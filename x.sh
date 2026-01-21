#!/usr/bin/env bash
set -u

# ==================================================
# Reality 管理脚本
# ==================================================

# --- 全局变量 ---
ENV_FILE="/etc/xray/reality.env"
XRAY_CONF="/usr/local/etc/xray/config.json"
XRAY_BIN="/usr/local/bin/xray"
SCRIPT_PATH="/root/x.sh"

# --- 颜色定义 ---
red() { echo -e "\033[31m$1\033[0m"; }
green() { echo -e "\033[32m$1\033[0m"; }
yellow() { echo -e "\033[33m$1\033[0m"; }
blue() { echo -e "\033[36m$1\033[0m"; }

# --- 自我更新机制 ---
self_check() {
    if [[ ! -f "$SCRIPT_PATH" ]] || [[ "${BASH_SOURCE[0]}" != "$SCRIPT_PATH" ]]; then
        curl -o "$SCRIPT_PATH" -Ls "https://raw.githubusercontent.com/EmersonLopez2005/myreality/main/x.sh"
        chmod +x "$SCRIPT_PATH"
    fi
    if ! grep -q "alias xray=" ~/.bashrc; then
        echo "alias xray='bash $SCRIPT_PATH'" >> ~/.bashrc
        source ~/.bashrc
    fi
}

update_script() {
    green "正在从 GitHub 拉取最新脚本..."
    curl -o "$SCRIPT_PATH" -Ls "https://raw.githubusercontent.com/EmersonLopez2005/myreality/main/x.sh"
    chmod +x "$SCRIPT_PATH"
    green "脚本已更新！请重新运行 xray"
    exit 0
}

# --- 辅助函数 ---
get_ss_status() {
    if [[ -f "$XRAY_CONF" ]]; then
        SS_IP=$(jq -r '.outbounds[] | select(.tag=="US_SS2022") | .settings.servers[0].address' "$XRAY_CONF" 2>/dev/null)
    else
        SS_IP=""
    fi
}

install_jq() {
    if ! command -v jq &> /dev/null; then
        apt-get update -y >/dev/null 2>&1
        apt-get install -y jq >/dev/null 2>&1
    fi
}

# --- 1. 基础安装 ---
ask_config() {
    clear
    echo "################################################"
    echo "      Reality 极简安装脚本"
    echo "################################################"
    
    read -p "$(yellow "请输入端口 [回车随机]: ") " input_port
    [[ -z "$input_port" ]] && PORT=$(shuf -i 10000-65535 -n 1) || PORT=$input_port

    read -p "$(yellow "请输入伪装域名 [回车默认 learn.microsoft.com]: ") " input_sni
    [[ -z "$input_sni" ]] && TARGET_SNI="learn.microsoft.com" || TARGET_SNI=$input_sni
    
    echo ""
    green "配置确认：端口 $PORT | SNI $TARGET_SNI"
    read -p "按回车继续..."
}

install_core() {
    green ">>> 安装 Xray 内核..."
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
}

generate_config() {
    mkdir -p /etc/xray
    UUID=$(cat /proc/sys/kernel/random/uuid)
    KEYS=$($XRAY_BIN x25519)
    PK=$(echo "$KEYS" | sed -n '1p' | awk -F: '{print $2}' | xargs)
    PUB=$(echo "$KEYS" | sed -n '2p' | awk -F: '{print $2}' | xargs)
    SHORT_ID=$(openssl rand -hex 4)

    cat > "$XRAY_CONF" <<JSON
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "listen": "0.0.0.0",
    "port": $PORT,
    "protocol": "vless",
    "settings": {
      "clients": [{ "id": "$UUID", "flow": "xtls-rprx-vision" }],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "show": false,
        "dest": "${TARGET_SNI}:443",
        "serverNames": ["${TARGET_SNI}"],
        "privateKey": "$PK",
        "shortIds": ["$SHORT_ID"],
        "fingerprint": "chrome"
      }
    }
  }],
  "outbounds": [{ "protocol": "freedom", "tag": "direct" }]
}
JSON
    cat > "$ENV_FILE" <<ENV
UUID=$UUID
PORT=$PORT
SNI=$TARGET_SNI
PBK=$PUB
SID=$SHORT_ID
ENV
    chmod 600 "$ENV_FILE"
}

setup_system() {
    systemctl enable xray >/dev/null 2>&1
    systemctl restart xray
}

# --- 核心：智能分流 (Gemini + ChatGPT) ---
setup_ai_routing_ss2022() {
    if [[ ! -f "$ENV_FILE" ]]; then red "未找到配置"; return; fi
    source "$ENV_FILE"
    
    CURRENT_PK=$(grep -oP '"privateKey": "\K[^"]+' "$XRAY_CONF")
    if [[ -z "$CURRENT_PK" ]]; then red "私钥读取失败"; return; fi

    get_ss_status
    clear
    echo "################################################"
    echo "       配置分流 (Gemini + ChatGPT -> US)"
    echo "################################################"
    
    if [[ -n "$SS_IP" && "$SS_IP" != "null" ]]; then
        green "当前 US 目标: $SS_IP"
        read -p "是否修改? (y/n) [n]: " modify
        [[ "$modify" != "y" ]] && return
    fi
    
    read -p "$(yellow "1. US IP地址: ") " us_addr
    [[ -z "$us_addr" ]] && return
    read -p "$(yellow "2. US 端口: ") " us_port
    [[ -z "$us_port" ]] && return
    read -p "$(yellow "3. SS2022 密钥: ") " us_pass
    [[ -z "$us_pass" ]] && return
    
    echo "加密: 1) aes-128-gcm (默认)"
    read -p "选择: " m
    [[ "$m" == "2" ]] && us_method="2022-blake3-aes-256-gcm" || us_method="2022-blake3-aes-128-gcm"

    green "正在写入路由规则..."
    
    # 策略解释：
    # 1. YouTube -> 直连 (HK)。
    # 2. Gemini/ChatGPT + UDP -> Block (防泄露)。
    # 3. Gemini/ChatGPT + TCP -> US Proxy。
    
    cat > "$XRAY_CONF" <<JSON
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "listen": "0.0.0.0",
    "port": $PORT,
    "protocol": "vless",
    "settings": {
      "clients": [{ "id": "$UUID", "flow": "xtls-rprx-vision" }],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "show": false,
        "dest": "${SNI}:443",
        "serverNames": ["${SNI}"],
        "privateKey": "$CURRENT_PK",
        "shortIds": ["$SID"],
        "fingerprint": "chrome"
      }
    }
  }],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" },
    {
      "tag": "US_SS2022",
      "protocol": "shadowsocks",
      "settings": {
        "servers": [{
          "address": "$us_addr",
          "port": $us_port,
          "method": "$us_method",
          "password": "$us_pass"
        }]
      }
    },
    { "tag": "block", "protocol": "blackhole" }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "outboundTag": "direct",
        "domain": [
          "geosite:youtube",
          "domain:googlevideo.com",
          "domain:youtube.com",
          "domain:ytimg.com",
          "domain:ggpht.com"
        ]
      },
      {
        "type": "field",
        "outboundTag": "block",
        "network": "udp",
        "port": "443",
        "domain": [
          "geosite:openai",
          "geosite:chatgpt",
          "geosite:gemini",
          "geosite:bard",
          "geosite:bing",
          "domain:ai.com",
          "domain:openai.com",
          "domain:chatgpt.com",
          "domain:accounts.google.com",
          "domain:googleapis.com",
          "domain:gstatic.com",
          "domain:googleusercontent.com",
          "domain:gemini.google.com",
          "domain:bard.google.com",
          "domain:makersuite.google.com"
        ]
      },
      {
        "type": "field",
        "outboundTag": "US_SS2022",
        "domain": [
          "geosite:openai",
          "geosite:chatgpt",
          "geosite:gemini",
          "geosite:bard",
          "geosite:bing",
          "domain:ai.com",
          "domain:openai.com",
          "domain:chatgpt.com",
          "domain:accounts.google.com",
          "domain:googleapis.com",
          "domain:gstatic.com",
          "domain:googleusercontent.com",
          "domain:gemini.google.com",
          "domain:bard.google.com",
          "domain:makersuite.google.com"
        ]
      },
      {
        "type": "field",
        "outboundTag": "direct",
        "network": "udp,tcp"
      }
    ]
  }
}
JSON
    systemctl restart xray
    if systemctl is-active --quiet xray; then
        echo ""
        green "✅ 智能分流配置成功！"
    else
        echo ""
        red "❌ 启动失败，请检查端口/密钥！"
    fi
}

show_info() {
    if [[ ! -f "$ENV_FILE" ]]; then red "未找到配置"; return; fi
    source "$ENV_FILE"
    get_ss_status
    CURRENT_IP=$(curl -s -4 https://api.ipify.org)
    [[ -z "$CURRENT_IP" ]] && CURRENT_IP=$(curl -s https://api.ipify.org)
    
    LINK="vless://${UUID}@${CURRENT_IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=chrome&pbk=${PBK}&sid=${SID}&type=tcp#$(hostname)"
    
    echo ""
    green "=== 节点信息 ==="
    echo "地址: ${CURRENT_IP}"
    echo "端口: ${PORT}"
    echo "UUID: ${UUID}"
    if [[ -n "$SS_IP" && "$SS_IP" != "null" ]]; then
        green "分流: ✅ 开启 (Gemini/GPT -> US | YT -> HK)"
    else
        red "分流: ❌ 关闭"
    fi
    yellow "👇 链接:"
    echo "${LINK}"
    echo ""
}

menu() {
    clear
    install_jq
    self_check
    
    echo "################################################"
    echo "      Reality 管理面板"
    echo "################################################"
    echo "1. 查看节点 (Info)"
    echo "2. 更新内核"
    echo "3. 初始化/重置 (Re-Install)"
    echo "4. 重启服务"
    echo "5. 卸载脚本"
    echo "--------------------------------"
    echo "6. 配置分流 (Gemini+GPT -> US)"
    echo "7. 更新脚本 (Update Script)"
    echo "--------------------------------"
    echo "0. 退出"
    read -p "选择: " num
    case "$num" in
        1) show_info ;;
        2) install_core; systemctl restart xray ;;
        3) ask_config; install_core; generate_config; setup_system; show_info ;;
        4) systemctl restart xray; green "已重启" ;;
        5) systemctl stop xray; rm -f /root/x.sh; green "已卸载";;
        6) setup_ai_routing_ss2022 ;;
        7) update_script ;;
        0) exit 0 ;;
        *) red "无效选项" ;;
    esac
}

check_root=$( [[ $EUID -ne 0 ]] && echo "fail" )
if [[ "$check_root" == "fail" ]]; then red "请用 root 运行"; exit 1; fi

if [[ ! -f "$XRAY_CONF" ]]; then
    self_check
    ask_config; install_core; generate_config; setup_system
    show_info
    exec bash -l
else
    menu
fi
