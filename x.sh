#!/usr/bin/env bash
set -u

# ==================================================
# 极简 Reality 管理脚本
# ==================================================

# --- 全局变量 ---
ENV_FILE="/etc/xray/reality.env"
XRAY_CONF="/usr/local/etc/xray/config.json"
XRAY_BIN="/usr/local/bin/xray"
GEO_DIR="/usr/local/share/xray"

# --- 辅助颜色 ---
red() { echo -e "\033[31m$1\033[0m"; }
green() { echo -e "\033[32m$1\033[0m"; }
yellow() { echo -e "\033[33m$1\033[0m"; }
blue() { echo -e "\033[36m$1\033[0m"; }

check_root() { [[ $EUID -ne 0 ]] && red "请使用 root 权限运行" && exit 1; }

# --- 1. 基础安装逻辑 ---
ask_config() {
    clear
    echo "################################################"
    echo "      Reality 极简安装脚本 "
    echo "################################################"
    
    read -p "$(yellow "请输入端口 [回车随机 10000-65535]: ") " input_port
    if [[ -z "$input_port" ]]; then
        PORT=$(shuf -i 10000-65535 -n 1)
        blue "  -> 使用随机端口: $PORT"
    else
        PORT=$input_port
        blue "  -> 使用自定义端口: $PORT"
    fi
    echo ""

    read -p "$(yellow "请输入伪装域名 (SNI) [回车默认 learn.microsoft.com]: ") " input_sni
    if [[ -z "$input_sni" ]]; then
        TARGET_SNI="learn.microsoft.com"
        blue "  -> 使用默认 SNI: $TARGET_SNI"
    else
        TARGET_SNI=$input_sni
        blue "  -> 使用自定义 SNI: $TARGET_SNI"
    fi
    echo ""

    green "配置确认：端口 $PORT | SNI $TARGET_SNI"
    read -p "按回车继续..."
}

install_deps() {
    green ">>> 安装依赖..."
    apt-get update -y >/dev/null 2>&1
    apt-get install -y curl unzip openssl jq >/dev/null 2>&1
}

install_core() {
    green ">>> 安装 Xray 内核..."
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
}

generate_config() {
    green ">>> 生成基础配置..."
    mkdir -p /etc/xray
    
    UUID=$(cat /proc/sys/kernel/random/uuid)
    if [[ ! -x "$XRAY_BIN" ]]; then red "未找到 Xray 内核"; exit 1; fi

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
    green ">>> 设置服务..."
    if ! grep -q "alias xray=" ~/.bashrc; then
        echo "alias xray='bash /root/x.sh'" >> ~/.bashrc
        alias xray='bash /root/x.sh'
    fi
    systemctl enable xray >/dev/null 2>&1
    systemctl restart xray
}

# --- 核心修改：SS2022 分流逻辑 ---
setup_ai_routing_ss2022() {
    if [[ ! -f "$ENV_FILE" ]]; then red "未找到配置文件，请先安装节点"; return; fi
    source "$ENV_FILE"

    # 1. 抢救 PrivateKey (非常重要)
    CURRENT_PK=$(grep -oP '"privateKey": "\K[^"]+' "$XRAY_CONF")
    if [[ -z "$CURRENT_PK" ]]; then
        red "错误：无法从现配置中读取 PrivateKey！操作中止。"
        return
    fi

    clear
    echo "################################################"
    echo "       配置 SS2022 前置分流 (Gemini -> US)"
    echo "################################################"
    echo "请准备好你的 US 节点 SS2022 信息。"
    echo ""
    
    # 2. 收集 SS2022 信息
    read -p "$(yellow "1. US 节点 IP地址/域名: ") " us_addr
    [[ -z "$us_addr" ]] && red "不能为空" && return

    read -p "$(yellow "2. US 节点 端口: ") " us_port
    [[ -z "$us_port" ]] && red "不能为空" && return

    read -p "$(yellow "3. SS2022 密钥 (Password/Key): ") " us_pass
    [[ -z "$us_pass" ]] && red "不能为空" && return

    echo ""
    echo "请选择加密方式 (Method):"
    echo "1) 2022-blake3-aes-128-gcm (推荐)"
    echo "2) 2022-blake3-aes-256-gcm"
    read -p "选择 [1-2, 默认1]: " method_select
    
    case "$method_select" in
        2) us_method="2022-blake3-aes-256-gcm" ;;
        *) us_method="2022-blake3-aes-128-gcm" ;;
    esac
    blue "  -> 已选: $us_method"
    echo ""

    green "正在下载 Geosite 规则库..."
    mkdir -p "$GEO_DIR"
    curl -L -o "$GEO_DIR/geosite.dat" "https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat"

    green "正在写入分流配置..."
    
    # 3. 写入带 SS2022 出站的配置
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
    { 
      "protocol": "freedom", 
      "tag": "direct" 
    },
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
        "outboundTag": "US_SS2022",
        "domain": [
          "geosite:openai",
          "geosite:gemini",
          "geosite:bard",
          "geosite:anthropic",
          "geosite:bing",
          "domain:alkalimakersuite-pa.clients6.google.com"
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

    green "重启服务..."
    systemctl restart xray
    echo ""
    green "✅ 分流已配置！"
    echo "现在访问 Gemini/GPT 将自动转发至 -> $us_addr ($us_method)"
}

# --- 恢复原版详细信息显示 ---
show_info() {
    if [[ ! -f "$ENV_FILE" ]]; then red "未找到配置文件"; return; fi
    source "$ENV_FILE"
    CURRENT_IP=$(curl -s https://api.ipify.org)
    HOST_NAME=$(hostname)
    
    REMARK="${HOST_NAME}"
    LINK="vless://${UUID}@${CURRENT_IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=chrome&pbk=${PBK}&sid=${SID}&type=tcp#${REMARK}"
    
    echo ""
    green "=================================="
    green "       节点配置信息 (VLESS)       "
    green "=================================="
    echo "地址 (Address):     ${CURRENT_IP}"
    echo "端口 (Port):        ${PORT}"
    echo "协议 (Protocol):    VLESS"
    echo "用户ID (UUID):      ${UUID}"
    echo "流控 (Flow):        xtls-rprx-vision"
    echo "传输 (Network):     tcp"
    echo "SNI (ServerName):   ${SNI}"
    echo "指纹 (Fingerprint): chrome"
    echo "公钥 (Public Key):  ${PBK}"
    echo "ShortId:            ${SID}"
    echo ""
    yellow "👇 复制下方链接 (V2RayN / NekoBox / Shadowrocket):"
    echo "${LINK}"
    echo ""
}

menu() {
    clear
    echo "################################################"
    echo "      极简 Reality 管理面板"
    echo "      Xray 版本: $($XRAY_BIN version | head -n 1 | awk '{print $2}')"
    echo "################################################"
    echo "1. 查看详细节点配置 (Info)"
    echo "2. 更新 Xray 内核 (Update Core)"
    echo "3. 修改端口/SNI/重置密钥 (Re-Install)"
    echo "4. 重启服务 (Restart)"
    echo "5. 卸载脚本 (Uninstall)"
    echo "------------------------------------------------"
    echo "6. 配置 AI 分流 (Gemini -> US SS2022) 🔥"
    echo "------------------------------------------------"
    echo "0. 退出"
    echo "################################################"
    read -p "请选择: " num
    case "$num" in
        1) show_info ;;
        2) install_core; systemctl restart xray; green "内核已更新" ;;
        3) ask_config; generate_config; systemctl restart xray; show_info ;;
        4) systemctl restart xray; green "服务已重启" ;;
        5) 
            systemctl stop xray
            rm -rf /usr/local/bin/xray /usr/local/etc/xray /etc/xray /root/x.sh
            sed -i '/alias xray=/d' ~/.bashrc
            green "已卸载" 
            ;;
        6) setup_ai_routing_ss2022 ;;
        0) exit 0 ;;
        *) red "无效选项" ;;
    esac
}

# --- 入口 ---
check_root
if [[ ! -f "$XRAY_CONF" ]]; then
    ask_config; install_deps; install_core; generate_config; setup_system
    green ">>> 安装完成！输入 'xray' 调出菜单。"
    show_info
    exec bash -l
else
    menu
fi
