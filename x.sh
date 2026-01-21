#!/usr/bin/env bash
set -u

# ==================================================
# Reality 管理脚本 (Gemini修复版 | YouTube不分流)
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
cyan() { echo -e "\033[36m$1\033[0m"; }

check_root() { [[ $EUID -ne 0 ]] && red "请使用 root 权限运行" && exit 1; }

# --- 辅助函数：获取分流状态 ---
get_ss_status() {
    if [[ -f "$XRAY_CONF" ]]; then
        # 尝试读取 SS2022 出站配置
        SS_IP=$(jq -r '.outbounds[] | select(.tag=="US_SS2022") | .settings.servers[0].address' "$XRAY_CONF" 2>/dev/null)
        SS_PORT=$(jq -r '.outbounds[] | select(.tag=="US_SS2022") | .settings.servers[0].port' "$XRAY_CONF" 2>/dev/null)
        SS_METHOD=$(jq -r '.outbounds[] | select(.tag=="US_SS2022") | .settings.servers[0].method' "$XRAY_CONF" 2>/dev/null)
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

install_core() {
    green ">>> 安装/更新 Xray 内核..."
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

# --- 核心修改：分流逻辑 (Gemini去US，YouTube留HK) ---
setup_ai_routing_ss2022() {
    if [[ ! -f "$ENV_FILE" ]]; then red "未找到配置文件，请先安装节点"; return; fi
    source "$ENV_FILE"

    # 抢救 PrivateKey
    CURRENT_PK=$(grep -oP '"privateKey": "\K[^"]+' "$XRAY_CONF")
    if [[ -z "$CURRENT_PK" ]]; then
        red "错误：无法读取 PrivateKey！请先执行选项 3 初始化配置。"
        return
    fi

    get_ss_status

    clear
    echo "################################################"
    echo "       配置 Gemini 分流 (修复 a!=b 报错)"
    echo "################################################"
    echo "说明: Gemini/OpenAI/账号登录 -> 转发至 US"
    echo "      YouTube/Google搜索     -> 保持 HK 直连 (速度优先)"
    echo "------------------------------------------------"
    
    if [[ -n "$SS_IP" && "$SS_IP" != "null" ]]; then
        green "⚠️  检测到当前已配置分流指向: $SS_IP"
        read -p "是否要修改配置？(y/n) [默认 n]: " modify
        if [[ "$modify" != "y" ]]; then
            echo "已取消。"
            return
        fi
        echo ""
    fi
    
    read -p "$(yellow "1. US 节点 IP地址/域名: ") " us_addr
    [[ -z "$us_addr" ]] && red "不能为空" && return

    read -p "$(yellow "2. US 节点 端口: ") " us_port
    [[ -z "$us_port" ]] && red "不能为空" && return

    read -p "$(yellow "3. SS2022 密钥 (Password/Key): ") " us_pass
    [[ -z "$us_pass" ]] && red "不能为空" && return

    echo ""
    echo "请选择加密方式 (Method):"
    echo "1) 2022-blake3-aes-128-gcm (默认)"
    echo "2) 2022-blake3-aes-256-gcm"
    read -p "选择 [1-2, 默认1]: " method_select
    
    case "$method_select" in
        2) us_method="2022-blake3-aes-256-gcm" ;;
        *) us_method="2022-blake3-aes-128-gcm" ;;
    esac
    blue "  -> 已选: $us_method"
    echo ""

    green "正在写入新配置 (已优化 YouTube 直连)..."
    
    # 写入带分流的配置
    # 注意：rules 列表中不包含 youtube.com，确保视频走直连
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
          "domain:openai.com",
          "domain:chatgpt.com",
          "domain:ai.com",
          "domain:gemini.google.com",
          "domain:bard.google.com",
          "domain:makersuite.google.com",
          "domain:alkalimakersuite-pa.clients6.google.com",
          "domain:generativelanguage.googleapis.com",
          "domain:proactivebackend-pa.googleapis.com",
          "domain:accounts.google.com",
          "domain:myaccount.google.com",
          "domain:googleapis.com",
          "domain:deepmind.com",
          "domain:deepmind.google",
          "domain:anthropic.com",
          "domain:claude.ai",
          "domain:bing.com"
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
    if systemctl is-active --quiet xray; then
        echo ""
        green "✅ 分流配置成功！"
        echo "Gemini/GPT -> US ($us_addr)"
        echo "YouTube    -> HK (直连)"
    else
        echo ""
        red "⚠️ 服务启动失败！"
        red "请运行 '/usr/local/bin/xray run -test -c /usr/local/etc/xray/config.json' 查看详情"
    fi
}

show_info() {
    if [[ ! -f "$ENV_FILE" ]]; then red "未找到配置文件"; return; fi
    source "$ENV_FILE"
    
    get_ss_status
    CURRENT_IP=$(curl -s -4 https://api.ipify.org)
    [[ -z "$CURRENT_IP" ]] && CURRENT_IP=$(curl -s https://api.ipify.org)
    
    REMARK="$(hostname)"
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
    echo "公钥 (Public Key):  ${PBK}"
    echo "ShortId:            ${SID}"
    
    echo "----------------------------------"
    if [[ -n "$SS_IP" && "$SS_IP" != "null" ]]; then
        echo -e "分流状态 (Route):    \033[32m✅ 已启用\033[0m"
        echo -e "Gemini/账号 (Target): $SS_IP (US)"
        echo -e "YouTube (Target):     本地直连 (HK)"
    else
        echo -e "分流状态 (Route):    \033[31m❌ 未启用 (全部直连)\033[0m"
    fi
    echo "----------------------------------"
    
    yellow "👇 复制下方链接 (V2RayN / NekoBox / Shadowrocket):"
    echo "${LINK}"
    echo ""
}

menu() {
    clear
    install_jq
    get_ss_status
    if [[ -n "$SS_IP" && "$SS_IP" != "null" ]]; then
        AI_STATUS="[\033[32m开启\033[0m]"
    else
        AI_STATUS="[\033[31m关闭\033[0m]"
    fi

    echo "################################################"
    echo "      Reality 管理面板 (修复版)"
    echo "      Xray 版本: $($XRAY_BIN version | head -n 1 | awk '{print $2}')"
    echo "################################################"
    echo "1. 查看节点配置 (Info)"
    echo "2. 更新/安装 内核 (Update Core)"
    echo "3. 修改端口/重置 (Re-Install)"
    echo "4. 重启服务 (Restart)"
    echo "5. 卸载脚本 (Uninstall)"
    echo "------------------------------------------------"
    echo -e "6. 配置 Gemini 分流 $AI_STATUS"
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
    # 第一次运行，自动修复 alias 并进入安装
    if ! grep -q "alias xray=" ~/.bashrc; then
        echo "alias xray='bash /root/x.sh'" >> ~/.bashrc
    fi
    ask_config; install_core; generate_config; setup_system
    green ">>> 安装完成！输入 'xray' 调出菜单。"
    show_info
    exec bash -l
else
    # 修复 alias 防止命令丢失
    if ! grep -q "alias xray=" ~/.bashrc; then
        echo "alias xray='bash /root/x.sh'" >> ~/.bashrc
    fi
    alias xray='bash /root/x.sh'
    menu
fi
