#!/usr/bin/env bash
set -u

# ==================================================
# Reality 管理脚本 v2.9 (Hybrid/混合模式版)
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

# --- 自我更新与安装机制 ---
install_self() {
    if [[ ! -f "$SCRIPT_PATH" ]]; then
        curl -o "$SCRIPT_PATH" -Ls "https://raw.githubusercontent.com/EmersonLopez2005/myreality/main/x.sh"
        chmod +x "$SCRIPT_PATH"
    fi
    if ! grep -q "alias xray=" ~/.bashrc; then
        echo "alias xray='bash $SCRIPT_PATH'" >> ~/.bashrc
        alias xray='bash $SCRIPT_PATH'
    fi
}

update_script() {
    green "正在从 GitHub 拉取最新脚本..."
    curl -o "$SCRIPT_PATH" -Ls "https://raw.githubusercontent.com/EmersonLopez2005/myreality/main/x.sh"
    chmod +x "$SCRIPT_PATH"
    green "脚本已更新！请重新运行 xray"
    exit 0
}

# --- 强力卸载 ---
uninstall_xray() {
    echo ""
    red "⚠️  警告：这将彻底删除 Xray 及其所有配置！"
    read -p "确定要卸载吗? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then echo "已取消"; return; fi

    systemctl stop xray >/dev/null 2>&1
    systemctl disable xray >/dev/null 2>&1
    rm -f /etc/systemd/system/xray.service
    systemctl daemon-reload
    rm -rf /usr/local/bin/xray /usr/local/etc/xray /etc/xray /usr/local/share/xray /var/log/xray
    
    sed -i '/alias xray=/d' ~/.bashrc
    rm -f "$SCRIPT_PATH"
    
    green "卸载完成！"
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

check_ss2022_server() {
    if [[ -f "$XRAY_CONF" ]]; then
        SS_INBOUND=$(jq -r '.inbounds[] | select(.protocol=="shadowsocks") | .port' "$XRAY_CONF" 2>/dev/null)
        [[ -n "$SS_INBOUND" && "$SS_INBOUND" != "null" ]] && return 0 || return 1
    fi
    return 1
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
    echo ""
    echo -e "\033[33m"
    echo "██████╗ ███████╗ █████╗ ██╗    ██╗████████╗██╗  ██╗"
    echo "██╔══██╗██╔════╝██╔══██╗██╗    ██║╚══██╔══╝╚██╗ ██╔╝"
    echo "██████╔╝█████╗  ███████║██╗    ██║   ██║    ╚████╔╝"
    echo "██╔══██╗██╔══╝  ██╔══██║██╗    ██║   ██║     ╚██╔╝ "
    echo "██║  ██║███████╗██║  ██║███████╗██║   ██║      ██║  "
    echo "╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚══════╝╚═╝   ╚═╝      ╚═╝  "
    echo -e "\033[0m"
    echo -e "\033[36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\033[32m            Reality 极简安装脚本 v2.9\033[0m"
    echo -e "\033[36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo ""
    
    read -p "$(yellow "请输入端口 [回车随机]: ") " input_port
    [[ -z "$input_port" ]] && PORT=$(shuf -i 10000-65535 -n 1) || PORT=$input_port

    read -p "$(yellow "请输入伪装域名 [回车默认 learn.microsoft.com]: ") " input_sni
    [[ -z "$input_sni" ]] && TARGET_SNI="learn.microsoft.com" || TARGET_SNI=$input_sni
    
    echo ""
    green "配置确认：端口 $PORT | SNI $TARGET_SNI"
    read -p "按回车继续.."
}

install_core() {
    green ">>> 安装 Xray 内核..."
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
}

# --- 核心：配置生成 ---
get_inbound_config() {
    local tag=$1
    local port=$2
    local protocol=$3
    local USE_SNI="${SNI:-learn.microsoft.com}"

    if [[ "$protocol" == "vless" ]]; then
        echo '{
            "tag": "'$tag'",
            "listen": "0.0.0.0",
            "port": '$port',
            "protocol": "vless",
            "settings": {
                "clients": [{ "id": "'$UUID'", "flow": "xtls-rprx-vision" }],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "show": false,
                    "dest": "'${USE_SNI}':443",
                    "serverNames": ["'${USE_SNI}'"],
                    "privateKey": "'$CURRENT_PK'",
                    "shortIds": ["'$SID'"],
                    "fingerprint": "chrome"
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": ["http", "tls", "quic"],
                "routeOnly": true
            }
        }'
    else
        echo '{
            "tag": "'$tag'",
            "listen": "0.0.0.0",
            "port": '$port',
            "protocol": "shadowsocks",
            "settings": {
                "method": "'$SS_METHOD'",
                "password": "'$SS_PASS'",
                "network": "tcp,udp",
                "ipLimit": 128,
                "clientIpLimit": 10
            },
            "sniffing": {
                "enabled": true,
                "destOverride": ["http", "tls", "quic"],
                "routeOnly": true
            }
        }'
    fi
}

generate_config() {
    mkdir -p /etc/xray
    UUID=$(cat /proc/sys/kernel/random/uuid)
    KEYS=$($XRAY_BIN x25519)
    PK=$(echo "$KEYS" | sed -n '1p' | awk -F: '{print $2}' | xargs)
    PUB=$(echo "$KEYS" | sed -n '2p' | awk -F: '{print $2}' | xargs)
    SHORT_ID=$(openssl rand -hex 4)
    CURRENT_PK=$PK

    cat > "$XRAY_CONF" <<JSON
{
  "log": { "access": "none", "loglevel": "warning" },
  "inbounds": [
    {
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
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "routeOnly": true
      }
    }
  ],
  "outbounds": [{ "protocol": "freedom", "tag": "direct" }]
}
JSON
    cat > "$ENV_FILE" <<ENV
UUID=$UUID
PORT=$PORT
SNI=$TARGET_SNI
PBK=$PUB
SID=$SHORT_ID
YOUTUBE_MODE=direct
ENV
    chmod 600 "$ENV_FILE"
}

setup_system() {
    systemctl enable xray >/dev/null 2>&1
    systemctl restart xray
}

# --- 创建 SS2022 服务器 ---
create_ss2022_server() {
    if [[ ! -f "$ENV_FILE" ]]; then red "未找到 Reality 配置，请先安装 Reality"; return; fi
    source "$ENV_FILE"
    
    CURRENT_PK=$(grep -oP '"privateKey": "\K[^"]+' "$XRAY_CONF")
    if [[ -z "$CURRENT_PK" ]]; then red "私钥读取失败"; return; fi
    
    clear
    echo ""
    echo -e "\033[36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\033[33m           🔐 创建 SS2022 服务器\033[0m"
    echo -e "\033[36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo ""
    
    if check_ss2022_server; then
        SS_PORT=$(jq -r '.inbounds[] | select(.protocol=="shadowsocks") | .port' "$XRAY_CONF")
        SS_METHOD=$(jq -r '.inbounds[] | select(.protocol=="shadowsocks") | .settings.method' "$XRAY_CONF")
        yellow "⚠️  检测到已存在 SS2022 服务器"
        echo -e "\033[33m端口:\033[0m $SS_PORT"
        echo -e "\033[33m加密:\033[0m $SS_METHOD"
        echo ""
        read -p "是否重新配置? (y/n) [n]: " reconfigure
        [[ "$reconfigure" != "y" ]] && return
    fi
    
    read -p "$(yellow "请输入 SS2022 端口 [回车随机]: ") " input_ss_port
    [[ -z "$input_ss_port" ]] && SS_PORT=$(shuf -i 10000-65535 -n 1) || SS_PORT=$input_ss_port
    
    echo ""
    echo "请选择 SS2022 加密方式:"
    echo "1) 2022-blake3-aes-128-gcm (推荐/默认)"
    echo "2) 2022-blake3-aes-256-gcm"
    read -p "选择 [1-2]: " method_choice
    
    if [[ "$method_choice" == "2" ]]; then
        SS_METHOD="2022-blake3-aes-256-gcm"
        SS_PASS=$(openssl rand -base64 32)
    else
        SS_METHOD="2022-blake3-aes-128-gcm"
        SS_PASS=$(openssl rand -base64 16)
    fi
    
    echo ""
    green "配置确认：端口 $SS_PORT | $SS_METHOD"
    read -p "按回车继续.."
    
    get_ss_status
    
    INBOUND_REALITY=$(get_inbound_config "reality-in" $PORT "vless")
    INBOUND_SS=$(get_inbound_config "ss-in" $SS_PORT "shadowsocks")

    if [[ -n "$SS_IP" && "$SS_IP" != "null" ]]; then
        US_ADDR=$(jq -r '.outbounds[] | select(.tag=="US_SS2022") | .settings.servers[0].address' "$XRAY_CONF")
        US_PORT=$(jq -r '.outbounds[] | select(.tag=="US_SS2022") | .settings.servers[0].port' "$XRAY_CONF")
        US_METHOD=$(jq -r '.outbounds[] | select(.tag=="US_SS2022") | .settings.servers[0].method' "$XRAY_CONF")
        US_PASS=$(jq -r '.outbounds[] | select(.tag=="US_SS2022") | .settings.servers[0].password' "$XRAY_CONF")
        
        # 恢复 YouTube 模式 (包含混合模式逻辑)
        YT_RULES=""
        CUR_MODE="${YOUTUBE_MODE:-direct}"
        if [[ "$CUR_MODE" == "proxy" ]]; then
             YT_RULES='{ "type": "field", "outboundTag": "US_SS2022", "domain": ["geosite:youtube","domain:googlevideo.com"] },'
        elif [[ "$CUR_MODE" == "hybrid" ]]; then
             YT_RULES='{ "type": "field", "outboundTag": "direct", "domain": ["domain:googlevideo.com","domain:ggpht.com"] }, { "type": "field", "outboundTag": "US_SS2022", "domain": ["geosite:youtube"] },'
        else
             YT_RULES='{ "type": "field", "outboundTag": "direct", "domain": ["geosite:youtube","domain:googlevideo.com"] },'
        fi
        
        cat > "$XRAY_CONF" <<JSON
{
  "log": { "access": "none", "loglevel": "warning" },
  "inbounds": [ $INBOUND_REALITY, $INBOUND_SS ],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" },
    {
      "tag": "US_SS2022",
      "protocol": "shadowsocks",
      "settings": {
        "servers": [{
          "address": "$US_ADDR",
          "port": $US_PORT,
          "method": "$US_METHOD",
          "password": "$US_PASS"
        }]
      },
      "streamSettings": { "sockopt": { "tcpKeepAliveIdle": 100, "tcpKeepAliveInterval": 30 } }
    },
    { "tag": "block", "protocol": "blackhole" }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      { "type": "field", "inboundTag": ["ss-in"], "outboundTag": "direct" },
      $YT_RULES
      { "type": "field", "outboundTag": "US_SS2022", "domain": ["geosite:openai","geosite:google","geosite:bing","domain:ai.com","regexp:ocsp."] },
      { "type": "field", "outboundTag": "block", "network": "udp", "port": "443", "domain": ["geosite:openai","geosite:bing"] },
      { "type": "field", "outboundTag": "direct", "network": "udp,tcp" }
    ]
  }
}
JSON
    else
        cat > "$XRAY_CONF" <<JSON
{
  "log": { "access": "none", "loglevel": "warning" },
  "inbounds": [ $INBOUND_REALITY, $INBOUND_SS ],
  "outbounds": [{ "protocol": "freedom", "tag": "direct" }]
}
JSON
    fi
    
    sed -i '/^SS_PORT=/d' "$ENV_FILE"
    sed -i '/^SS_METHOD=/d' "$ENV_FILE"
    sed -i '/^SS_PASS=/d' "$ENV_FILE"
    cat >> "$ENV_FILE" <<ENV
SS_PORT=$SS_PORT
SS_METHOD=$SS_METHOD
SS_PASS=$SS_PASS
ENV
    systemctl restart xray
    if systemctl is-active --quiet xray; then
        echo ""; green "✅ SS2022 服务器创建成功！"; echo ""; show_ss2022_info
    else
        echo ""; red "❌ [失败] 启动失败！"; 
    fi
}

show_ss2022_info() {
    if ! check_ss2022_server; then red "未创建 SS2022 服务器"; return; fi
    source "$ENV_FILE"
    CURRENT_IP=$(curl -s -4 https://api.ipify.org)
    [[ -z "$CURRENT_IP" ]] && CURRENT_IP=$(curl -s https://api.ipify.org)
    SS_LINK=$(echo -n "${SS_METHOD}:${SS_PASS}" | base64 -w 0)
    SS_URL="ss://${SS_LINK}@${CURRENT_IP}:${SS_PORT}#SS2022-$(hostname)"
    
    echo ""
    echo -e "\033[36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\033[32m           🔐 SS2022 服务器信息\033[0m"
    echo -e "\033[36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\033[33m服务器地址:\033[0m $CURRENT_IP"
    echo -e "\033[33m端口:\033[0m       $SS_PORT"
    echo -e "\033[33m加密方式:\033[0m   $SS_METHOD"
    echo -e "\033[33m密码:\033[0m       $SS_PASS"
    echo -e "\033[90m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo ""
    yellow "👇 复制下方链接 (Shadowrocket / V2RayN / NekoBox):"
    echo -e "\033[36m${SS_URL}\033[0m"
    echo ""
}

remove_ss2022_server() {
    if ! check_ss2022_server; then yellow "未检测到 SS2022"; return; fi
    source "$ENV_FILE"
    CURRENT_PK=$(grep -oP '"privateKey": "\K[^"]+' "$XRAY_CONF")
    INBOUND_REALITY=$(get_inbound_config "reality-in" $PORT "vless")
    
    get_ss_status
    if [[ -n "$SS_IP" && "$SS_IP" != "null" ]]; then
        US_ADDR=$(jq -r '.outbounds[] | select(.tag=="US_SS2022") | .settings.servers[0].address' "$XRAY_CONF")
        US_PORT=$(jq -r '.outbounds[] | select(.tag=="US_SS2022") | .settings.servers[0].port' "$XRAY_CONF")
        US_METHOD=$(jq -r '.outbounds[] | select(.tag=="US_SS2022") | .settings.servers[0].method' "$XRAY_CONF")
        US_PASS=$(jq -r '.outbounds[] | select(.tag=="US_SS2022") | .settings.servers[0].password' "$XRAY_CONF")

        # 检查当前 YouTube 模式，但既然删除了 SS2022，强制回退或仅保留直连
        YT_RULES='{ "type": "field", "outboundTag": "direct", "domain": ["geosite:youtube","domain:googlevideo.com"] },'

        cat > "$XRAY_CONF" <<JSON
{
  "log": { "access": "none", "loglevel": "warning" },
  "inbounds": [ $INBOUND_REALITY ],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" },
    {
      "tag": "US_SS2022",
      "protocol": "shadowsocks",
      "settings": {
        "servers": [{
          "address": "$US_ADDR",
          "port": $US_PORT,
          "method": "$US_METHOD",
          "password": "$US_PASS"
        }]
      },
      "streamSettings": { "sockopt": { "tcpKeepAliveIdle": 100, "tcpKeepAliveInterval": 30 } }
    },
    { "tag": "block", "protocol": "blackhole" }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      $YT_RULES
      { "type": "field", "outboundTag": "US_SS2022", "domain": ["geosite:openai","geosite:google","geosite:bing","regexp:ocsp."] },
      { "type": "field", "outboundTag": "block", "network": "udp", "port": "443", "domain": ["geosite:openai"] },
      { "type": "field", "outboundTag": "direct", "network": "udp,tcp" }
    ]
  }
}
JSON
    else
        cat > "$XRAY_CONF" <<JSON
{
  "log": { "access": "none", "loglevel": "warning" },
  "inbounds": [ $INBOUND_REALITY ],
  "outbounds": [{ "protocol": "freedom", "tag": "direct" }]
}
JSON
    fi
    sed -i '/^SS_PORT=/d' "$ENV_FILE"
    systemctl restart xray
    green "✅ SS2022 已删除"
}

setup_ai_routing_ss2022() {
    local mode="${1:-normal}" # 接受参数：normal(默认) 或 refresh(刷新)
    
    if [[ ! -f "$ENV_FILE" ]]; then red "未找到配置"; return; fi
    source "$ENV_FILE"
    
    # 默认 YouTube 模式
    if [[ -z "${YOUTUBE_MODE:-}" ]]; then
        echo "YOUTUBE_MODE=direct" >> "$ENV_FILE"
        YOUTUBE_MODE="direct"
    fi

    CURRENT_PK=$(grep -oP '"privateKey": "\K[^"]+' "$XRAY_CONF")
    get_ss_status
    
    # === 变量准备 ===
    if [[ "$mode" == "refresh" ]]; then
        # 刷新模式：从 JSON 读取现有配置，不询问用户
        us_addr=$(jq -r '.outbounds[] | select(.tag=="US_SS2022") | .settings.servers[0].address' "$XRAY_CONF")
        us_port=$(jq -r '.outbounds[] | select(.tag=="US_SS2022") | .settings.servers[0].port' "$XRAY_CONF")
        us_method=$(jq -r '.outbounds[] | select(.tag=="US_SS2022") | .settings.servers[0].method' "$XRAY_CONF")
        us_pass=$(jq -r '.outbounds[] | select(.tag=="US_SS2022") | .settings.servers[0].password' "$XRAY_CONF")
        DNS_STRATEGY="${DNS_STRATEGY:-UseIP}"
    else
        # 正常交互模式
        clear
        echo ""; echo -e "\033[33m       🌐 配置分流 (Gemini + ChatGPT -> US)\033[0m"; echo ""
        
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
        
        echo ""; echo "请选择 SS2022 加密方式:"
        echo "1) 2022-blake3-aes-128-gcm (推荐/默认)"; echo "2) 2022-blake3-aes-256-gcm"
        read -p "选择 [1-2]: " m
        [[ "$m" == "2" ]] && us_method="2022-blake3-aes-256-gcm" || us_method="2022-blake3-aes-128-gcm"
        
        echo ""; echo "请选择 DNS 查询策略:"
        echo "1) IPv4 优先 (默认)"; echo "2) IPv6 优先"; echo "3) 同时查询"
        read -p "选择 [1-3]: " dns_choice
        case "$dns_choice" in
            2) DNS_STRATEGY="UseIPv6" ;;
            3) DNS_STRATEGY="UseIP" ;;
            *) DNS_STRATEGY="UseIPv4" ;;
        esac
        # 【新增这里】：把你的选择永久保存到环境文件中！
        sed -i '/^DNS_STRATEGY=/d' "$ENV_FILE"
        echo "DNS_STRATEGY=$DNS_STRATEGY" >> "$ENV_FILE"
        export DNS_STRATEGY
    fi

    # === 构建 YouTube 规则 (混合模式核心) ===
    YT_RULES=""
    if [[ "$YOUTUBE_MODE" == "proxy" ]]; then
        # 全代理模式：所有 YouTube 相关域名都走 US
        YT_INFO="全代理 (US)"
        YT_RULES='{ "type": "field", "outboundTag": "US_SS2022", "domain": ["geosite:youtube","domain:googlevideo.com"] },'
        
    elif [[ "$YOUTUBE_MODE" == "hybrid" ]]; then
        # 混合模式：视频流直连，其他走 US (注意顺序：先匹配视频流)
        YT_INFO="混合 (界面US + 视频直连)"
        YT_RULES='
        { "type": "field", "outboundTag": "direct", "domain": ["domain:googlevideo.com", "domain:ggpht.com"] },
        { "type": "field", "outboundTag": "US_SS2022", "domain": ["geosite:youtube"] },'
        
    else
        # 直连模式
        YT_INFO="直连"
        YT_RULES='{ "type": "field", "outboundTag": "direct", "domain": ["geosite:youtube","domain:googlevideo.com"] },'
    fi

    if [[ "$mode" != "refresh" ]]; then green "正在写入规则..."; fi
    
    INBOUND_REALITY=$(get_inbound_config "reality-in" $PORT "vless")
    
    if check_ss2022_server && [[ -n "$SS_PORT" ]]; then
        INBOUND_SS=$(get_inbound_config "ss-in" $SS_PORT "shadowsocks")
        INBOUNDS_BLOCK="[ $INBOUND_REALITY, $INBOUND_SS ]"
        SS_RULE='{ "type": "field", "inboundTag": ["ss-in"], "outboundTag": "direct" },'
    else
        INBOUNDS_BLOCK="[ $INBOUND_REALITY ]"
        SS_RULE=""
    fi

    cat > "$XRAY_CONF" <<JSON
{
  "log": { "access": "none", "loglevel": "warning" },
  "dns": {
    "servers": [
      { "address": "https://1.1.1.1/dns-query", "domains": ["geosite:openai","geosite:google","geosite:bing"], "expectIPs": ["geoip:us"] },
      "localhost"
    ],
    "queryStrategy": "$DNS_STRATEGY",
    "disableCache": false,
    "disableFallback": true
  },
  "inbounds": $INBOUNDS_BLOCK,
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
      },
      "streamSettings": {
        "sockopt": {
          "tcpKeepAliveIdle": 100,
          "tcpKeepAliveInterval": 30
        }
      }
    },
    { "tag": "block", "protocol": "blackhole" }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      $SS_RULE
      $YT_RULES
      {
        "type": "field",
        "outboundTag": "US_SS2022",
        "domain": [
          "geosite:openai",
          "geosite:google",
          "geosite:bing",
          "domain:ai.com",
          "domain:openai.com",
          "domain:chatgpt.com",
          "domain:gemini.google.com",
          "domain:bard.google.com",
          "domain:accounts.google.com",
          "domain:googleapis.com",
          "domain:google.com",
          "regexp:ocsp.",
          "regexp:.digicert.com\$",
          "regexp:.letsencrypt.org\$",
          "regexp:.amazontrust.com\$"
        ]
      },
      { "type": "field", "outboundTag": "block", "network": "udp", "port": "443", "domain": ["geosite:openai"] },
      { "type": "field", "outboundTag": "direct", "network": "udp,tcp" }
    ]
  }
}
JSON
    systemctl restart xray
    if systemctl is-active --quiet xray; then
        echo ""
        if [[ "$mode" == "refresh" ]]; then
            green "✅ YouTube 路由已切换为: $YT_INFO"
        else
            green "✅ 分流配置成功 (安全+极速)"
            echo "   - AI 流量  -> 代理"
            echo "   - YouTube  -> $YT_INFO"
        fi
    else
        echo ""; red "❌ [失败] 启动失败";
    fi
}

toggle_youtube() {
    if [[ ! -f "$ENV_FILE" ]]; then red "未找到配置"; return; fi
    source "$ENV_FILE"
    
    # 检查是否已配置上游代理 (必须先有 US_SS2022 才能代理 YouTube)
    get_ss_status
    if [[ -z "$SS_IP" || "$SS_IP" == "null" ]]; then 
        red "❌ 必须先配置分流 (选项 6) 设定上游代理，才能切换 YouTube 路由！"
        read -p "按回车返回..."
        return
    fi

    # 循环切换状态: direct -> proxy -> hybrid -> direct
    case "${YOUTUBE_MODE:-direct}" in
        "direct")
            NEW_MODE="proxy"
            MSG="全代理 (US_SS2022)"
            ;;
        "proxy")
            NEW_MODE="hybrid"
            MSG="混合模式 (界面US + 视频直连)"
            ;;
        *)
            NEW_MODE="direct"
            MSG="直连"
            ;;
    esac

    sed -i '/^YOUTUBE_MODE=/d' "$ENV_FILE"
    echo "YOUTUBE_MODE=$NEW_MODE" >> "$ENV_FILE"
    export YOUTUBE_MODE="$NEW_MODE"
    
    echo ""
    green "🔄 正在切换: YouTube -> $MSG..."

    # 刷新配置
    setup_ai_routing_ss2022 "refresh"
    read -p "按回车返回..."
}

disable_routing() {
    if [[ ! -f "$ENV_FILE" ]]; then red "未找到配置"; return; fi
    source "$ENV_FILE"
    CURRENT_PK=$(grep -oP '"privateKey": "\K[^"]+' "$XRAY_CONF")
    INBOUND_REALITY=$(get_inbound_config "reality-in" $PORT "vless")
    
    if check_ss2022_server && [[ -n "$SS_PORT" ]]; then
        INBOUND_SS=$(get_inbound_config "ss-in" $SS_PORT "shadowsocks")
        INBOUNDS_BLOCK="[ $INBOUND_REALITY, $INBOUND_SS ]"
    else
        INBOUNDS_BLOCK="[ $INBOUND_REALITY ]"
    fi
    
    cat > "$XRAY_CONF" <<JSON
{
  "log": { "access": "none", "loglevel": "warning" },
  "inbounds": $INBOUNDS_BLOCK,
  "outbounds": [{ "protocol": "freedom", "tag": "direct" }]
}
JSON
    systemctl restart xray
    echo ""; green "✅ 分流已关闭"; echo ""
}

show_info() {
    if [[ ! -f "$ENV_FILE" ]]; then red "未找到配置"; return; fi
    source "$ENV_FILE"
    get_ss_status
    CURRENT_IP=$(curl -s -4 https://api.ipify.org)
    [[ -z "$CURRENT_IP" ]] && CURRENT_IP=$(curl -s https://api.ipify.org)
    REMARK="$(hostname)"
    
    LINK="vless://${UUID}@${CURRENT_IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=chrome&pbk=${PBK}&sid=${SID}&type=tcp#${REMARK}"
    
    echo ""
    echo -e "\033[36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\033[32m           📡 节点配置信息 (Reality)\033[0m"
    echo -e "\033[36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\033[33m地址 (Address):\033[0m     ${CURRENT_IP}"
    echo -e "\033[33m端口 (Port):\033[0m        ${PORT}"
    echo -e "\033[33m用户ID (UUID):\033[0m      ${UUID}"
    echo -e "\033[33m流控 (Flow):\033[0m        xtls-rprx-vision"
    echo -e "\033[33m传输 (Network):\033[0m     tcp"
    echo -e "\033[33m伪装域名 (SNI):\033[0m     ${SNI}"
    echo -e "\033[33m指纹 (Fingerprint):\033[0m chrome"
    echo -e "\033[33m公钥 (Public Key):\033[0m  ${PBK}"
    echo -e "\033[33mShortId:\033[0m            ${SID}"
    
    echo -e "\033[90m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    if [[ -n "$SS_IP" && "$SS_IP" != "null" ]]; then
        echo -e "\033[33m分流 (Route):\033[0m       \033[32m✅ 开启 (嗅探+保活)\033[0m"
    else
        echo -e "\033[33m分流 (Route):\033[0m       \033[31m⛔ 关闭\033[0m"
    fi
    echo -e "\033[90m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    
    echo ""
    yellow "👇 复制下方链接 (V2RayN / NekoBox / Shadowrocket):"
    echo -e "\033[36m${LINK}\033[0m"
    echo ""
}

menu() {
    clear
    install_jq
    install_self
    get_ss_status
    if [[ -f "$ENV_FILE" ]]; then source "$ENV_FILE"; fi
    
    if [[ -n "$SS_IP" && "$SS_IP" != "null" ]]; then
        AI_STATUS="[\033[32m开启\033[0m]"
    else
        AI_STATUS="[\033[31m关闭\033[0m]"
    fi
    
    if check_ss2022_server; then
        SS_SERVER_STATUS="[\033[32m已创建\033[0m]"
    else
        SS_SERVER_STATUS="[\033[31m未创建\033[0m]"
    fi

    # YouTube 状态显示
    case "${YOUTUBE_MODE:-direct}" in
        "proxy")  YT_STATUS="[\033[32m代理\033[0m]" ;;
        "hybrid") YT_STATUS="[\033[36m混合\033[0m]" ;;
        *)        YT_STATUS="[\033[33m直连\033[0m]" ;;
    esac
    
    echo ""
    echo -e "\033[33m"
    echo "██████╗ ███████╗ █████╗ ██╗    ██╗████████╗██╗  ██╗"
    echo "██╔══██╗██╔════╝██╔══██╗██╗    ██║╚══██╔══╝╚██╗ ██╔╝"
    echo "██████╔╝█████╗  ███████║██╗    ██║   ██║    ╚████╔╝"
    echo "██╔══██╗██╔══╝  ██╔══██║██╗    ██║   ██║     ╚██╔╝ "
    echo "██║  ██║███████╗██║  ██║███████╗██║   ██║      ██║  "
    echo "╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚══════╝╚═╝   ╚═╝      ╚═╝  "
    echo -e "\033[0m"
    echo -e "\033[36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\033[32m           Reality 管理面板 v2.9 (混合版)\033[0m"
    echo -e "\033[36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\033[36m  [1]\033[0m 查看 Reality 节点"
    echo -e "\033[36m  [2]\033[0m 更新内核"
    echo -e "\033[36m  [3]\033[0m 初始化/重置 Reality"
    echo -e "\033[36m  [4]\033[0m 重启服务"
    echo -e "\033[36m  [5]\033[0m 彻底卸载 (Uninstall & Clean)"
    echo -e "\033[90m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\033[36m  [6]\033[0m 配置/刷新分流 (Gemini+GPT)"
    echo -e "\033[36m  [y]\033[0m 切换 YouTube 路由 $YT_STATUS"
    echo -e "\033[36m  [a]\033[0m 关闭分流 (恢复直连)"
    echo -e "\033[90m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\033[36m  [8]\033[0m 创建 SS2022 服务器 $SS_SERVER_STATUS"
    echo -e "\033[36m  [9]\033[0m 查看 SS2022 信息"
    echo -e "\033[36m  [d]\033[0m 删除 SS2022 服务器"
    echo -e "\033[90m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\033[36m  [7]\033[0m 更新脚本 (Update Script)"
    echo -e "\033[36m  [0]\033[0m 退出"
    echo ""
    read -p "$(echo -e '\033[33m请选择:\033[0m ') " num
    case "$num" in
        1) show_info ;;
        2) install_core; systemctl restart xray ;;
        3) ask_config; install_core; generate_config; setup_system; show_info ;;
        4) systemctl restart xray; green "已重启" ;;
        5) uninstall_xray ;;
        6) setup_ai_routing_ss2022 ;;
        y|Y) toggle_youtube ;;
        a|A) disable_routing ;;
        7) update_script ;;
        8) create_ss2022_server ;;
        9) show_ss2022_info ;;
        d|D) remove_ss2022_server ;;
        0) exit 0 ;;
        *) red "无效选项" ;;
    esac
}

check_root=$( [[ $EUID -ne 0 ]] && echo "fail" )
if [[ "$check_root" == "fail" ]]; then red "请用 root 运行"; exit 1; fi

if [[ ! -f "$XRAY_CONF" ]]; then
    install_self
    ask_config; install_core; generate_config; setup_system
    show_info
    exec bash -l
else
    menu
fi
