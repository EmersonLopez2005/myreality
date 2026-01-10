cat > /root/x.sh <<'EOF'
#!/usr/bin/env bash
set -u

# ==================================================
# 极简 Reality 交互版
# ==================================================

# --- 全局变量 ---
ENV_FILE="/etc/xray/reality.env"
XRAY_CONF="/usr/local/etc/xray/config.json"
XRAY_BIN="/usr/local/bin/xray"

# --- 辅助颜色 ---
red() { echo -e "\033[31m$1\033[0m"; }
green() { echo -e "\033[32m$1\033[0m"; }
yellow() { echo -e "\033[33m$1\033[0m"; }
blue() { echo -e "\033[36m$1\033[0m"; }

check_root() { [[ $EUID -ne 0 ]] && red "请使用 root 权限运行" && exit 1; }

# --- 1. 安装前交互 ---
ask_config() {
    clear
    echo "################################################"
    echo "      Reality 极简安装脚本 "
    echo "################################################"
    echo ""
    
    # 1. 设置端口
    read -p "$(yellow "请输入端口 [回车随机 10000-65535]: ") " input_port
    if [[ -z "$input_port" ]]; then
        PORT=$(shuf -i 10000-65535 -n 1)
        blue "  -> 使用随机端口: $PORT"
    else
        PORT=$input_port
        blue "  -> 使用自定义端口: $PORT"
    fi
    echo ""

    # 2. 设置 SNI
    read -p "$(yellow "请输入伪装域名 (SNI) [回车默认 learn.microsoft.com]: ") " input_sni
    if [[ -z "$input_sni" ]]; then
        TARGET_SNI="learn.microsoft.com"
        blue "  -> 使用默认 SNI: $TARGET_SNI"
    else
        TARGET_SNI=$input_sni
        blue "  -> 使用自定义 SNI: $TARGET_SNI"
    fi
    echo ""

    # 3. 确认配置
    echo "--------------------------------"
    green "即将安装，配置确认："
    echo "端口 (Port):      $PORT"
    echo "域名 (SNI):       $TARGET_SNI"
    echo "指纹 (FP):        chrome"
    echo "备注 (Remark):    $(hostname)"
    echo "--------------------------------"
    read -p "按回车继续，或按 Ctrl+C 取消..."
}

install_deps() {
    green ">>> 1/4 安装依赖..."
    apt-get update -y >/dev/null 2>&1
    apt-get install -y curl unzip openssl jq >/dev/null 2>&1
}

install_core() {
    green ">>> 2/4 安装/更新 Xray 内核..."
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
}

generate_config() {
    green ">>> 3/4 生成配置文件..."
    mkdir -p /etc/xray
    
    # --- 适配新版 Xray 输出逻辑 ---
    UUID=$(cat /proc/sys/kernel/random/uuid)
    
    if [[ ! -x "$XRAY_BIN" ]]; then
        red "错误：未找到 Xray 内核！"
        exit 1
    fi

    KEYS=$($XRAY_BIN x25519)
    
    # 强制按行提取，不再依赖 label 名字 (适配 v25+ 版本)
    # 第一行通常是 PrivateKey
    PK=$(echo "$KEYS" | sed -n '1p' | awk -F: '{print $2}' | xargs)
    # 第二行通常是 PublicKey (或者新版显示的 Password)
    PUB=$(echo "$KEYS" | sed -n '2p' | awk -F: '{print $2}' | xargs)

    # 最终检查
    if [[ -z "$PUB" ]]; then
        red "密钥抓取失败。以下为原始输出，请截图反馈："
        echo "$KEYS"
        exit 1
    fi

    SHORT_ID=$(openssl rand -hex 4)
    SERVER_IP=$(curl -s https://api.ipify.org)

    # 写入 config.json
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
  "outbounds": [{ "protocol": "freedom" }]
}
JSON

    # 保存环境变量
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
    green ">>> 4/4 设置服务..."
    if ! grep -q "alias xray=" ~/.bashrc; then
        echo "alias xray='bash /root/x.sh'" >> ~/.bashrc
        alias xray='bash /root/x.sh'
    fi
    systemctl enable xray >/dev/null 2>&1
    systemctl restart xray
}

# --- 菜单功能 ---

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
    echo "      极简 Reality 管理面板 (V2.5 适配版)"
    echo "      Xray 版本: $($XRAY_BIN version | head -n 1 | awk '{print $2}')"
    echo "################################################"
    echo "1. 查看详细节点配置 (Info)"
    echo "2. 更新 Xray 内核 (Update Core)"
    echo "3. 修改端口/SNI/重置密钥 (Re-Install)"
    echo "4. 重启服务 (Restart)"
    echo "5. 卸载脚本 (Uninstall)"
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
            systemctl disable xray
            rm -rf /usr/local/bin/xray /usr/local/etc/xray /etc/xray /root/x.sh
            sed -i '/alias xray=/d' ~/.bashrc
            green "已卸载，干干净净。" 
            ;;
        0) exit 0 ;;
        *) red "无效选项" ;;
    esac
}

# --- 入口逻辑 ---
check_root

if [[ ! -f "$XRAY_CONF" ]]; then
    ask_config
    install_deps
    install_core
    generate_config
    setup_system
    green ">>> 安装完成！输入 'xray' 可调出菜单。"
    show_info
else
    menu
fi
EOF
chmod +x /root/x.sh && bash /root/x.sh
