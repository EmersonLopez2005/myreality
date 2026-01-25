#!/usr/bin/env bash
set -u

# ==================================================
# Reality 管理脚本 v2.3 
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
    # 修复快捷键
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
    echo -e "\033[32m            Reality 极简安装脚本 v2.3\033[0m"
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
    
    # 检查是否已存在
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
    
    # 输入配置
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
    green "配置确认："
    echo -e "\033[33m端口:\033[0m $SS_PORT"
    echo -e "\033[33m加密:\033[0m $SS_METHOD"
    echo -e "\033[33m密钥:\033[0m $SS_PASS"
    echo ""
    read -p "按回车继续.."
    
    # 检查是否存在分流配置
    get_ss_status
    
    # 生成配置（Reality + SS2022，保留分流）
    if [[ -n "$SS_IP" && "$SS_IP" != "null" ]]; then
        # 有分流配置，保留规则，并添加 SS 白名单
        US_ADDR=$(jq -r '.outbounds[] | select(.tag=="US_SS2022") | .settings.servers[0].address' "$XRAY_CONF")
        US_PORT=$(jq -r '.outbounds[] | select(.tag=="US_SS2022") | .settings.servers[0].port' "$XRAY_CONF")
        US_METHOD=$(jq -r '.outbounds[] | select(.tag=="US_SS2022") | .settings.servers[0].method' "$XRAY_CONF")
        US_PASS=$(jq -r '.outbounds[] | select(.tag=="US_SS2022") | .settings.servers[0].password' "$XRAY_CONF")
        
        # 注意：这里也需要加上 sockopt，以防用户先创建SS再开分流
        cat > "$XRAY_CONF" <<JSON
{
  "log": { "loglevel": "warning" },
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
          "dest": "${SNI}:443",
          "serverNames": ["${SNI}"],
          "privateKey": "$CURRENT_PK",
          "shortIds": ["$SID"],
          "fingerprint": "chrome"
        }
      }
    },
    {
      "tag": "ss-in",
      "listen": "0.0.0.0",
      "port": $SS_PORT,
      "protocol": "shadowsocks",
      "settings": {
        "method": "$SS_METHOD",
        "password": "$SS_PASS",
        "network": "tcp,udp"
      }
    }
  ],
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
      {
        "type": "field",
        "inboundTag": ["ss-in"],
        "outboundTag": "direct"
      },
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
      {
        "type": "field",
        "outboundTag": "block",
        "network": "udp",
        "port": "443",
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
          "domain:google.com"
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
    else
        # 没有分流，只有 Reality + SS2022 服务器
        cat > "$XRAY_CONF" <<JSON
{
  "log": { "loglevel": "warning" },
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
          "dest": "${SNI}:443",
          "serverNames": ["${SNI}"],
          "privateKey": "$CURRENT_PK",
          "shortIds": ["$SID"],
          "fingerprint": "chrome"
        }
      }
    },
    {
      "tag": "ss-in",
      "listen": "0.0.0.0",
      "port": $SS_PORT,
      "protocol": "shadowsocks",
      "settings": {
        "method": "$SS_METHOD",
        "password": "$SS_PASS",
        "network": "tcp,udp"
      }
    }
  ],
  "outbounds": [{ "protocol": "freedom", "tag": "direct" }]
}
JSON
    fi
    
    # 保存 SS2022 信息到 ENV
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
        echo ""
        green "✅ SS2022 服务器创建成功！"
        echo ""
        show_ss2022_info
    else
        echo ""
        red "❌ [失败] 启动失败，请检查配置！"
    fi
}

# --- 显示 SS2022 信息 ---
show_ss2022_info() {
    if ! check_ss2022_server; then
        red "未创建 SS2022 服务器"
        return
    fi
    
    source "$ENV_FILE"
    CURRENT_IP=$(curl -s -4 https://api.ipify.org)
    [[ -z "$CURRENT_IP" ]] && CURRENT_IP=$(curl -s https://api.ipify.org)
    
    # 生成 SS2022 链接
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

# --- 删除 SS2022 服务器 ---
remove_ss2022_server() {
    if ! check_ss2022_server; then
        yellow "未检测到 SS2022 服务器"
        return
    fi
    
    if [[ ! -f "$ENV_FILE" ]]; then red "未找到配置"; return; fi
    source "$ENV_FILE"
    
    clear
    echo ""
    echo -e "\033[36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\033[31m           🗑️ 删除 SS2022 服务器\033[0m"
    echo -e "\033[36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo ""
    red "⚠️  警告：这将删除 SS2022 服务器配置"
    echo -e "\033[33m端口:\033[0m $SS_PORT"
    echo ""
    get_ss_status
    if [[ -n "$SS_IP" && "$SS_IP" != "null" ]]; then
        green "✅ [保留] 分流配置将被保留"
    else
        yellow "注意：当前没有分流配置"
    fi
    echo ""
    read -p "确定要删除 SS2022 服务器吗? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then 
        echo "已取消"
        return
    fi
    
    CURRENT_PK=$(grep -oP '"privateKey": "\K[^"]+' "$XRAY_CONF")
    if [[ -z "$CURRENT_PK" ]]; then red "私钥读取失败"; return; fi
    
    # 检查是否有分流配置
    if [[ -n "$SS_IP" && "$SS_IP" != "null" ]]; then
        # 有分流，保留分流配置
        US_ADDR=$(jq -r '.outbounds[] | select(.tag=="US_SS2022") | .settings.servers[0].address' "$XRAY_CONF")
        US_PORT=$(jq -r '.outbounds[] | select(.tag=="US_SS2022") | .settings.servers[0].port' "$XRAY_CONF")
        US_METHOD=$(jq -r '.outbounds[] | select(.tag=="US_SS2022") | .settings.servers[0].method' "$XRAY_CONF")
        US_PASS=$(jq -r '.outbounds[] | select(.tag=="US_SS2022") | .settings.servers[0].password' "$XRAY_CONF")
        
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
          "address": "$US_ADDR",
          "port": $US_PORT,
          "method": "$US_METHOD",
          "password": "$US_PASS"
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
          "geosite:google",
          "geosite:bing",
          "domain:ai.com",
          "domain:openai.com",
          "domain:chatgpt.com",
          "domain:gemini.google.com",
          "domain:bard.google.com",
          "domain:accounts.google.com",
          "domain:googleapis.com",
          "domain:google.com"
        ]
      },
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
      {
        "type": "field",
        "outboundTag": "direct",
        "network": "udp,tcp"
      }
    ]
  }
}
JSON
    else
        # 没有分流，只保留 Reality
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
  "outbounds": [{ "protocol": "freedom", "tag": "direct" }]
}
JSON
    fi
    
    # 删除 ENV 中的 SS2022 配置
    sed -i '/^SS_PORT=/d' "$ENV_FILE"
    sed -i '/^SS_METHOD=/d' "$ENV_FILE"
    sed -i '/^SS_PASS=/d' "$ENV_FILE"
    
    systemctl restart xray
    
    if systemctl is-active --quiet xray; then
        echo ""
        green "✅ [成功] SS2022 服务器已删除"
        if [[ -n "$SS_IP" && "$SS_IP" != "null" ]]; then
            green "✅ [保留] 分流配置已保留"
        fi
    else
        echo ""
        red "❌ [失败] 重启失败"
    fi
}

# --- 核心：智能分流 (修复 IPv6 泄露 + SS直连优化 + HK-US保活) ---
setup_ai_routing_ss2022() {
    if [[ ! -f "$ENV_FILE" ]]; then red "未找到配置"; return; fi
    source "$ENV_FILE"
    
    CURRENT_PK=$(grep -oP '"privateKey": "\K[^"]+' "$XRAY_CONF")
    if [[ -z "$CURRENT_PK" ]]; then red "私钥读取失败"; return; fi

    get_ss_status
    clear
    echo ""
    echo -e "\033[36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\033[33m       🌐 配置分流 (Gemini + ChatGPT -> US)\033[0m"
    echo -e "\033[36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo ""
    
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
    
    echo ""
    echo "请选择 SS2022 加密方式:"
    echo "1) 2022-blake3-aes-128-gcm (推荐/默认)"
    echo "2) 2022-blake3-aes-256-gcm"
    read -p "选择 [1-2]: " m
    [[ "$m" == "2" ]] && us_method="2022-blake3-aes-256-gcm" || us_method="2022-blake3-aes-128-gcm"
    
    echo ""
    echo "请选择 DNS 查询策略:"
    echo "1) IPv4 优先 (默认，稳定性好)"
    echo "2) IPv6 优先 (US VPS 有 IPv6 优势时选择)"
    echo "3) 同时查询 IPv4 和 IPv6"
    read -p "选择 [1-3]: " dns_choice
    case "$dns_choice" in
        2) DNS_STRATEGY="UseIPv6" ;;
        3) DNS_STRATEGY="UseIP" ;;
        *) DNS_STRATEGY="UseIPv4" ;;
    esac

    green "正在写入强力路由规则..."
    green "DNS 策略: $DNS_STRATEGY"
    green "启用 HK-US 链路心跳保活 (100s)"
    
    # 策略解释 :
    # 1. [BYPASS]   SS2022 入站流量 (ss-in) -> 强制直连 (Direct)。避免 SS 流量被劫持到 US。
    # 2. [PRIORITY] YouTube -> 直连 (HK)
    # 3. [BLOCK]    UDP 443 -> 针对 Google/OpenAI 拦截。强制 TCP，防止 IPv6/QUIC 绕过
    # 4. [PROXY]    Google全家桶/OpenAI/OCSP/Cert -> US Proxy。
    # 5. [ALIVE]    sockopt.tcpKeepAliveIdle: 100 -> 保持 HK-US 链路活跃
    
    # 检查是否存在 SS2022 服务器
    if check_ss2022_server && [[ -n "$SS_PORT" ]] && [[ -n "$SS_METHOD" ]] && [[ -n "$SS_PASS" ]]; then
        # 保留 SS2022 服务器配置，并添加 ss-in 标签
        cat > "$XRAY_CONF" <<JSON
{
  "log": { "loglevel": "warning" },
  "dns": {
    "servers": [
      {
        "address": "https://1.1.1.1/dns-query",
        "domains": ["geosite:openai", "geosite:google", "geosite:bing"],
        "expectIPs": ["geoip:us"]
      },
      "localhost"
    ],
    "queryStrategy": "$DNS_STRATEGY",
    "disableCache": false,
    "disableFallback": true
  },
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
          "dest": "${SNI}:443",
          "serverNames": ["${SNI}"],
          "privateKey": "$CURRENT_PK",
          "shortIds": ["$SID"],
          "fingerprint": "chrome"
        }
      }
    },
    {
      "tag": "ss-in",
      "listen": "0.0.0.0",
      "port": $SS_PORT,
      "protocol": "shadowsocks",
      "settings": {
        "method": "$SS_METHOD",
        "password": "$SS_PASS",
        "network": "tcp,udp"
      }
    }
  ],
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
      {
        "type": "field",
        "inboundTag": ["ss-in"],
        "outboundTag": "direct"
      },
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
      {
        "type": "field",
        "outboundTag": "block",
        "network": "udp",
        "port": "443",
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
          "domain:google.com"
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
    else
        # 没有 SS2022 服务器，只有 Reality
        cat > "$XRAY_CONF" <<JSON
{
  "log": { "loglevel": "warning" },
  "dns": {
    "servers": [
      {
        "address": "https://1.1.1.1/dns-query",
        "domains": ["geosite:openai", "geosite:google", "geosite:bing"],
        "expectIPs": ["geoip:us"]
      },
      "localhost"
    ],
    "queryStrategy": "$DNS_STRATEGY",
    "disableCache": false,
    "disableFallback": true
  },
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
      {
        "type": "field",
        "outboundTag": "block",
        "network": "udp",
        "port": "443",
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
          "domain:google.com"
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
    fi
    systemctl restart xray
    if systemctl is-active --quiet xray; then
        echo ""
        green "✅ [保留] 分流配置成功 (Policy + HK-US 保活优化已应用)"
    else
        echo ""
        red "❌ [失败] 启动失败，请检查端口或密钥"
    fi
}

# --- 关闭分流（保留 SS2022 服务器）---
disable_routing() {
    if [[ ! -f "$ENV_FILE" ]]; then red "未找到配置"; return; fi
    source "$ENV_FILE"
    
    get_ss_status
    if [[ -z "$SS_IP" || "$SS_IP" == "null" ]]; then
        yellow "分流已经是关闭状态"
        return
    fi
    
    CURRENT_PK=$(grep -oP '"privateKey": "\K[^"]+' "$XRAY_CONF")
    if [[ -z "$CURRENT_PK" ]]; then red "私钥读取失败"; return; fi
    
    clear
    echo ""
    echo -e "\033[36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\033[33m           ⛔ 关闭分流功能\033[0m"
    echo -e "\033[36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo ""
    yellow "将关闭分流，所有流量恢复直连"
    if check_ss2022_server && [[ -n "$SS_PORT" ]]; then
        green "✅ 将保留 SS2022 服务器配置"
    fi
    echo ""
    read -p "确认关闭? (y/n) [n]: " confirm
    [[ "$confirm" != "y" ]] && return
    
    # 检查是否有 SS2022 服务器
    if check_ss2022_server && [[ -n "$SS_PORT" ]] && [[ -n "$SS_METHOD" ]] && [[ -n "$SS_PASS" ]]; then
        # 保留 SS2022 服务器，添加标签
        cat > "$XRAY_CONF" <<JSON
{
  "log": { "loglevel": "warning" },
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
          "dest": "${SNI}:443",
          "serverNames": ["${SNI}"],
          "privateKey": "$CURRENT_PK",
          "shortIds": ["$SID"],
          "fingerprint": "chrome"
        }
      }
    },
    {
      "tag": "ss-in",
      "listen": "0.0.0.0",
      "port": $SS_PORT,
      "protocol": "shadowsocks",
      "settings": {
        "method": "$SS_METHOD",
        "password": "$SS_PASS",
        "network": "tcp,udp"
      }
    }
  ],
  "outbounds": [{ "protocol": "freedom", "tag": "direct" }]
}
JSON
    else
        # 只有 Reality
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
  "outbounds": [{ "protocol": "freedom", "tag": "direct" }]
}
JSON
    fi
    
    systemctl restart xray
    if systemctl is-active --quiet xray; then
        echo ""
        green "✅ [成功] 分流已关闭，流量恢复直连"
    else
        echo ""
        red "❌ [失败] 重启失败"
    fi
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
        echo -e "\033[33m分流状态 (Route):\033[0m    \033[32m✅ 已启用 (SS2022)\033[0m"
        echo -e "\033[33mGemini/GPT (Target):\033[0m $SS_IP"
        echo -e "\033[33mSS直连策略 (Policy):\033[0m \033[32m✅ 已豁免 (强制直连)\033[0m"
        echo -e "\033[33mHK-US保活 (KeepAlive):\033[0m \033[32m✅ 已启用 (100s)\033[0m"
    else
        echo -e "\033[33m分流状态 (Route):\033[0m    \033[31m⛔ 未启用 (全部直连)\033[0m"
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
    echo -e "\033[32m              Reality 管理面板 v2.3\033[0m"
    echo -e "\033[36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo ""
    echo -e "\033[36m  [1]\033[0m 查看 Reality 节点"
    echo -e "\033[36m  [2]\033[0m 更新内核"
    echo -e "\033[36m  [3]\033[0m 初始化/重置 Reality"
    echo -e "\033[36m  [4]\033[0m 重启服务"
    echo -e "\033[36m  [5]\033[0m 彻底卸载 (Uninstall & Clean)"
    echo -e "\033[90m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\033[36m  [6]\033[0m 开启分流 (Gemini+GPT -> US) $AI_STATUS"
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
