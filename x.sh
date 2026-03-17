#!/usr/bin/env bash

# ==============================================================================
# Xray VLESS-Reality & Shadowsocks 2022 管理脚本 (x.sh)
# - 基于 install.sh (Final v2.9.2) 的交互逻辑重构 x.sh
# - 移除旧版 x.sh 的“分流/YouTube/上游SS”等功能，仅保留：Reality + SS2022
# - 保留快捷键入口：alias xray='bash /root/x.sh'
# - 修复/增强：Reality shortId(你说的 shortkey) 每次创建/重装时随机生成
# ==============================================================================

set -euo pipefail

# --- 全局常量 ---
readonly SCRIPT_VERSION="x.sh v3.0.0"
readonly SCRIPT_PATH="/root/x.sh"
readonly SCRIPT_UPDATE_URL="https://raw.githubusercontent.com/EmersonLopez2005/myreality/main/x.sh"

readonly xray_config_path="/usr/local/etc/xray/config.json"
readonly xray_binary_path="/usr/local/bin/xray"
readonly xray_install_script_url="https://github.com/XTLS/Xray-install/raw/main/install-release.sh"

# --- 颜色定义 ---
readonly red='\e[91m' green='\e[92m' yellow='\e[93m'
readonly magenta='\e[95m' cyan='\e[96m' none='\e[0m'

# --- 全局变量 ---
xray_status_info=""
is_quiet=false

# 允许自动探测 xray 实际路径（不同安装环境可能不在 /usr/local/bin/xray）
XRAY_BIN="${xray_binary_path}"

# --- 自安装：保留 xray 快捷键入口 ---
install_self() {
    # 1) 确保脚本在 /root/x.sh（允许你从任意路径执行一次后“固定”到 /root/x.sh）
    local self_src="${BASH_SOURCE[0]}"
    if [[ "$self_src" != "$SCRIPT_PATH" ]]; then
        cp -f "$self_src" "$SCRIPT_PATH"
        chmod +x "$SCRIPT_PATH"
    else
        chmod +x "$SCRIPT_PATH" 2>/dev/null || true
    fi

    # 2) 写入 alias（仅写一次）
    if ! grep -qs "alias xray='bash ${SCRIPT_PATH}'" ~/.bashrc; then
        echo "alias xray='bash ${SCRIPT_PATH}'" >> ~/.bashrc
    fi
    # 尝试给当前 shell 生效（非关键）
    alias xray="bash ${SCRIPT_PATH}" 2>/dev/null || true
}

update_script() {
    info "正在从远程更新脚本..."
    if ! command -v curl &>/dev/null; then
        error "系统缺少 curl，无法在线更新脚本。"
        return 1
    fi
    local tmp="/tmp/x.sh.$$"
    if ! curl -fsSL "$SCRIPT_UPDATE_URL" -o "$tmp"; then
        error "下载脚本失败，请检查网络或更新地址。"
        return 1
    fi
    # 简单校验：至少包含 main_menu 字样，避免下载到 HTML/404
    if ! grep -q "main_menu" "$tmp"; then
        rm -f "$tmp"
        error "下载内容异常（未检测到 main_menu）。为安全起见已终止更新。"
        return 1
    fi
    install -m 755 -o root -g root "$tmp" "$SCRIPT_PATH"
    rm -f "$tmp"
    success "脚本已更新完成。请重新运行：xray"
}

# --- 辅助函数 ---
error() {
    echo -e "\n${red}[✖] $1${none}\n" >&2
    case "$1" in
        *"网络"*|*"下载"*) echo -e "${yellow}提示: 检查网络连接或更换DNS${none}" >&2 ;;
        *"权限"*|*"root"*) echo -e "${yellow}提示: 请使用 sudo 运行脚本${none}" >&2 ;;
        *"端口"*) echo -e "${yellow}提示: 尝试使用其他端口号${none}" >&2 ;;
    esac
}

info() { [[ "$is_quiet" = false ]] && echo -e "\n${yellow}[!] $1${none}\n"; }
success() { [[ "$is_quiet" = false ]] && echo -e "\n${green}[✔] $1${none}\n"; }
warning() { [[ "$is_quiet" = false ]] && echo -e "\n${yellow}[⚠] $1${none}\n"; }

spinner() {
    local pid="$1"
    local spinstr='|/-\\'
    if [[ "$is_quiet" = true ]]; then
        wait "$pid"
        return
    fi
    while ps -p "$pid" >/dev/null 2>&1; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        spinstr=$temp${spinstr%"$temp"}
        sleep 0.1
        printf "\r"
    done
    printf "    \r"
}

get_public_ip() {
    local ip attempts=0 max_attempts=2
    while [[ $attempts -lt $max_attempts ]]; do
        for cmd in "curl -4s --max-time 5" "wget -4qO- --timeout=5"; do
            for url in "https://api.ipify.org" "https://ip.sb" "https://checkip.amazonaws.com"; do
                ip=$($cmd "$url" 2>/dev/null) && [[ -n "$ip" ]] && echo "$ip" && return
            done
        done
        ((attempts++))
        [[ $attempts -lt $max_attempts ]] && sleep 1
    done
    for cmd in "curl -6s --max-time 5" "wget -6qO- --timeout=5"; do
        for url in "https://api64.ipify.org" "https://ip.sb"; do
            ip=$($cmd "$url" 2>/dev/null) && [[ -n "$ip" ]] && echo "$ip" && return
        done
    done
}

# --- 预检查与环境设置 ---
pre_check() {
    [[ "$(id -u)" != 0 ]] && error "错误: 您必须以root用户身份运行此脚本" && exit 1
    if [[ ! -f /etc/debian_version ]]; then
        error "错误: 此脚本仅支持 Debian/Ubuntu 及其衍生系统。" && exit 1
    fi
    if ! command -v jq &>/dev/null || ! command -v curl &>/dev/null || ! command -v openssl &>/dev/null; then
        info "检测到缺失依赖 (jq/curl/openssl)，正在尝试自动安装..."
        (DEBIAN_FRONTEND=noninteractive apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y jq curl openssl) &>/dev/null &
        spinner $!
        if ! command -v jq &>/dev/null || ! command -v curl &>/dev/null || ! command -v openssl &>/dev/null; then
            error "依赖自动安装失败。请手动运行: apt update && apt install -y jq curl openssl" && exit 1
        fi
        success "依赖已成功安装。"
    fi
}

detect_xray_binary() {
    # 优先使用 command -v，其次 fallback 到默认路径
    if command -v xray &>/dev/null; then
        XRAY_BIN="$(command -v xray)"
        return 0
    fi
    if [[ -x "$xray_binary_path" ]]; then
        XRAY_BIN="$xray_binary_path"
        return 0
    fi
    XRAY_BIN="$xray_binary_path"
    return 1
}

check_xray_status() {
    detect_xray_binary >/dev/null 2>&1 || true
    if [[ ! -f "$XRAY_BIN" || ! -x "$XRAY_BIN" ]]; then
        xray_status_info=" Xray 状态: ${red}未安装${none}"
        return
    fi
    local xray_version service_status
    xray_version=$("$XRAY_BIN" version 2>/dev/null | head -n 1 | awk '{print $2}' || echo "未知")
    if systemctl is-active --quiet xray 2>/dev/null; then
        service_status="${green}运行中${none}"
    else
        service_status="${yellow}未运行${none}"
    fi
    xray_status_info=" Xray 状态: ${green}已安装${none} | ${service_status} | 版本: ${cyan}${xray_version}${none}"
}

quick_status() {
    detect_xray_binary >/dev/null 2>&1 || true
    if [[ ! -f "$XRAY_BIN" ]]; then
        echo -e " ${red}●${none} 未安装"
        return
    fi
    local status_icon
    if systemctl is-active --quiet xray 2>/dev/null; then status_icon="${green}●${none}"; else status_icon="${red}●${none}"; fi
    echo -e " $status_icon Xray $(systemctl is-active xray 2>/dev/null || echo "inactive")"
}

generate_reality_keypair() {
    # 输出两行：private_key\npublic_key
    detect_xray_binary >/dev/null 2>&1 || true
    if [[ ! -x "$XRAY_BIN" ]]; then
        error "错误: 未找到 xray 可执行文件（期望: $XRAY_BIN）。"
        return 1
    fi

    local out private_key public_key
    out=$("$XRAY_BIN" x25519 2>&1 || true)

    # 兼容多种输出格式：
    # - Private key: xxx
    # - Public key:  xxx
    # - PrivateKey: xxx
    # - PublicKey:  xxx
    private_key=$(echo "$out" | awk -F':' 'tolower($1) ~ /private/ {gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2; exit}')
    public_key=$(echo "$out" | awk -F':' 'tolower($1) ~ /public/  {gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2; exit}')

    if [[ -z "$private_key" || -z "$public_key" ]]; then
        error "生成 Reality 密钥对失败：无法从 xray x25519 输出解析密钥。"
        echo -e "${yellow}--- xray x25519 原始输出（便于排查）---${none}"
        echo "$out" | sed 's/^/  /'
        echo -e "${yellow}----------------------------------------${none}"
        return 1
    fi

    printf "%s\n%s\n" "$private_key" "$public_key"
}

# --- Reality shortId (shortkey) 随机生成 ---
generate_shortid() {
    # Reality shortId 推荐使用 8 个 hex 字符（4字节）
    local sid
    sid=$(openssl rand -hex 4 2>/dev/null || true)
    if [[ -z "$sid" ]]; then
        sid=$(head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \n')
    fi
    echo "$sid"
}

# --- 核心配置生成函数 ---
generate_ss_key() {
    openssl rand -base64 16
}

build_vless_inbound() {
    local port="$1" uuid="$2" domain="$3" private_key="$4" public_key="$5" shortid="$6"
    jq -n \
        --argjson port "$port" \
        --arg uuid "$uuid" \
        --arg domain "$domain" \
        --arg private_key "$private_key" \
        --arg public_key "$public_key" \
        --arg shortid "$shortid" \
        '{
            "listen": "0.0.0.0",
            "port": $port,
            "protocol": "vless",
            "settings": {
                "clients": [{"id": $uuid, "flow": "xtls-rprx-vision"}],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "show": false,
                    "dest": ($domain + ":443"),
                    "xver": 0,
                    "serverNames": [$domain],
                    "privateKey": $private_key,
                    "publicKey": $public_key,
                    "shortIds": [$shortid]
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": ["http", "tls", "quic"]
            }
        }'
}

build_ss_inbound() {
    local port="$1" password="$2"
    jq -n --argjson port "$port" --arg password "$password" \
        '{ "listen": "0.0.0.0", "port": $port, "protocol": "shadowsocks", "settings": {"method": "2022-blake3-aes-128-gcm", "password": $password} }'
}

write_config() {
    local inbounds_json="$1"
    local config_content
    config_content=$(jq -n --argjson inbounds "$inbounds_json" \
        '{
          "log": {"loglevel": "warning"},
          "inbounds": $inbounds,
          "outbounds": [
            {
              "protocol": "freedom",
              "settings": {"domainStrategy": "UseIPv4v6"}
            }
          ]
        }')

    if ! echo "$config_content" | jq . >/dev/null 2>&1; then
        error "生成的配置文件格式错误！"
        return 1
    fi

    echo "$config_content" > "$xray_config_path"
    chmod 644 "$xray_config_path"
    chown root:root "$xray_config_path"
}

execute_official_script() {
    local args="$1" script_content
    script_content=$(curl -L "$xray_install_script_url")
    if [[ -z "$script_content" || ! "$script_content" =~ "install-release" ]]; then
        error "下载 Xray 官方安装脚本失败或内容异常！请检查网络连接。"
        return 1
    fi
    echo "$script_content" | bash -s -- $args &>/dev/null &
    spinner $!
    if ! wait $!; then return 1; fi
}

run_core_install() {
    info "正在下载并安装 Xray 核心..."
    if ! execute_official_script "install"; then
        error "Xray 核心安装失败！"
        return 1
    fi
    info "正在更新 GeoIP 和 GeoSite 数据文件..."
    if ! execute_official_script "install-geodata"; then
        warning "Geo-data 更新失败（通常不影响核心功能，可稍后再试）。"
    fi
    success "Xray 核心及数据文件已准备就绪。"
}

# --- 输入验证与交互函数 ---
is_valid_port() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] && [[ "$port" -ge 1 && "$port" -le 65535 ]]
}

is_port_available() {
    local port="$1"
    is_valid_port "$port" || return 1
    if ss -tlpn 2>/dev/null | grep -q ":$port "; then
        warning "端口 $port 已被占用，建议选择其他端口"
        return 1
    fi
    return 0
}

is_valid_domain() {
    local domain="$1"
    [[ "$domain" =~ ^[a-zA-Z0-9-]{1,63}(\.[a-zA-Z0-9-]{1,63})+$ ]] && [[ "$domain" != *--* ]]
}

prompt_for_vless_config() {
    local -n p_port="$1" p_uuid="$2" p_sni="$3"
    local default_port="${4:-443}"

    while true; do
        read -r -p "$(echo -e " -> 请输入 VLESS 端口 (默认: ${cyan}${default_port}${none}): ")" p_port || true
        [[ -z "$p_port" ]] && p_port="$default_port"
        if is_port_available "$p_port"; then break; fi
    done
    info "VLESS 端口将使用: ${cyan}${p_port}${none}"

    read -r -p "$(echo -e " -> 请输入UUID (留空将自动生成): ")" p_uuid || true
    if [[ -z "$p_uuid" ]]; then
        p_uuid=$(cat /proc/sys/kernel/random/uuid)
        info "已为您生成随机UUID: ${cyan}${p_uuid}${none}"
    fi

    while true; do
        read -r -p "$(echo -e " -> 请输入SNI域名 (默认: ${cyan}learn.microsoft.com${none}): ")" p_sni || true
        [[ -z "$p_sni" ]] && p_sni="learn.microsoft.com"
        if is_valid_domain "$p_sni"; then break; else error "域名格式无效，请重新输入。"; fi
    done
    info "SNI 域名将使用: ${cyan}${p_sni}${none}"
}

prompt_for_ss_config() {
    local -n p_port="$1" p_pass="$2"
    local default_port="${3:-8388}"

    while true; do
        read -r -p "$(echo -e " -> 请输入 Shadowsocks 端口 (默认: ${cyan}${default_port}${none}): ")" p_port || true
        [[ -z "$p_port" ]] && p_port="$default_port"
        if is_port_available "$p_port"; then break; fi
    done
    info "Shadowsocks 端口将使用: ${cyan}${p_port}${none}"

    read -r -p "$(echo -e " -> 请输入 Shadowsocks 密钥 (留空将自动生成): ")" p_pass || true
    if [[ -z "$p_pass" ]]; then
        p_pass=$(generate_ss_key)
        info "已为您生成随机密钥: ${cyan}${p_pass}${none}"
    fi
}

# --- 菜单功能函数 ---
draw_divider() { printf "%0.s─" {1..48}; printf "\n"; }

draw_menu_header() {
    clear
    echo -e "${cyan} Xray VLESS-Reality & Shadowsocks-2022 管理脚本${none}"
    echo -e "${yellow} Version: ${SCRIPT_VERSION}${none}"
    draw_divider
    check_xray_status
    echo -e "${xray_status_info}"
    quick_status
    draw_divider
}

press_any_key_to_continue() {
    echo ""
    read -n 1 -s -r -p " 按任意键返回主菜单..." || true
}

install_menu() {
    local vless_exists="" ss_exists=""
    if [[ -f "$xray_config_path" ]]; then
        vless_exists=$(jq '.inbounds[] | select(.protocol == "vless")' "$xray_config_path" 2>/dev/null || true)
        ss_exists=$(jq '.inbounds[] | select(.protocol == "shadowsocks")' "$xray_config_path" 2>/dev/null || true)
    fi

    draw_menu_header
    if [[ -n "$vless_exists" && -n "$ss_exists" ]]; then
        success "您已安装 VLESS-Reality + Shadowsocks-2022 双协议。"
        info "如需修改，请使用主菜单的“修改配置”。\n如需重装，请先“卸载”后再重新“安装”。"
        return
    elif [[ -n "$vless_exists" && -z "$ss_exists" ]]; then
        info "检测到您已安装 VLESS-Reality"
        echo -e "${cyan} 请选择下一步操作${none}"
        draw_divider
        printf "  ${green}%-2s${none} %-35s\n" "1." "追加安装 Shadowsocks-2022 (组成双协议)"
        printf "  ${red}%-2s${none} %-35s\n" "2." "覆盖重装 VLESS-Reality"
        draw_divider
        printf "  ${yellow}%-2s${none} %-35s\n" "0." "返回主菜单"
        draw_divider
        read -r -p " 请输入选项 [0-2]: " choice || true
        case "$choice" in
            1) add_ss_to_vless ;;
            2) install_vless_only ;;
            0) return ;;
            *) error "无效选项。" ;;
        esac
    elif [[ -z "$vless_exists" && -n "$ss_exists" ]]; then
        info "检测到您已安装 Shadowsocks-2022"
        echo -e "${cyan} 请选择下一步操作${none}"
        draw_divider
        printf "  ${green}%-2s${none} %-35s\n" "1." "追加安装 VLESS-Reality (组成双协议)"
        printf "  ${red}%-2s${none} %-35s\n" "2." "覆盖重装 Shadowsocks-2022"
        draw_divider
        printf "  ${yellow}%-2s${none} %-35s\n" "0." "返回主菜单"
        draw_divider
        read -r -p " 请输入选项 [0-2]: " choice || true
        case "$choice" in
            1) add_vless_to_ss ;;
            2) install_ss_only ;;
            0) return ;;
            *) error "无效选项。" ;;
        esac
    else
        clean_install_menu
    fi
}

clean_install_menu() {
    draw_menu_header
    echo -e "${cyan} 请选择要安装的协议类型${none}"
    draw_divider
    printf "  ${green}%-2s${none} %-35s\n" "1." "仅 VLESS-Reality"
    printf "  ${cyan}%-2s${none} %-35s\n" "2." "仅 Shadowsocks-2022"
    printf "  ${yellow}%-2s${none} %-35s\n" "3." "VLESS-Reality + Shadowsocks-2022 (双协议)"
    draw_divider
    printf "  ${magenta}%-2s${none} %-35s\n" "0." "返回主菜单"
    draw_divider
    read -r -p " 请输入选项 [0-3]: " choice || true
    case "$choice" in
        1) install_vless_only ;;
        2) install_ss_only ;;
        3) install_dual ;;
        0) return ;;
        *) error "无效选项。" ;;
    esac
}

add_ss_to_vless() {
    info "开始追加安装 Shadowsocks-2022..."
    if [[ -z "$(get_public_ip)" ]]; then
        error "无法获取公网 IP 地址，操作中止。请检查您的网络连接。"
        return 1
    fi
    local vless_inbound vless_port default_ss_port ss_port ss_password ss_inbound
    vless_inbound=$(jq '.inbounds[] | select(.protocol == "vless")' "$xray_config_path")
    vless_port=$(echo "$vless_inbound" | jq -r '.port')
    default_ss_port=$([[ "$vless_port" == "443" ]] && echo "8388" || echo "$((vless_port + 1))")

    prompt_for_ss_config ss_port ss_password "$default_ss_port"
    ss_inbound=$(build_ss_inbound "$ss_port" "$ss_password")
    write_config "[$vless_inbound, $ss_inbound]"
    if ! restart_xray; then return 1; fi

    success "追加安装成功！"
    view_all_info
}

add_vless_to_ss() {
    info "开始追加安装 VLESS-Reality..."
    if [[ -z "$(get_public_ip)" ]]; then
        error "无法获取公网 IP 地址，操作中止。请检查您的网络连接。"
        return 1
    fi
    local ss_inbound ss_port default_vless_port vless_port vless_uuid vless_domain key_pair private_key public_key shortid vless_inbound
    ss_inbound=$(jq '.inbounds[] | select(.protocol == "shadowsocks")' "$xray_config_path")
    ss_port=$(echo "$ss_inbound" | jq -r '.port')
    default_vless_port=$([[ "$ss_port" == "8388" ]] && echo "443" || echo "$((ss_port - 1))")

    prompt_for_vless_config vless_port vless_uuid vless_domain "$default_vless_port"

    info "正在生成 Reality 密钥对..."
    key_pair=$(generate_reality_keypair) || return 1
    private_key=$(echo "$key_pair" | sed -n '1p')
    public_key=$(echo "$key_pair" | sed -n '2p')
    shortid=$(generate_shortid)

    if [[ -z "$private_key" || -z "$public_key" ]]; then
        error "生成 Reality 密钥对失败！请检查 Xray 核心是否正常，或尝试卸载后重装。"
        return 1
    fi

    vless_inbound=$(build_vless_inbound "$vless_port" "$vless_uuid" "$vless_domain" "$private_key" "$public_key" "$shortid")
    write_config "[$vless_inbound, $ss_inbound]"
    if ! restart_xray; then return 1; fi

    success "追加安装成功！"
    view_all_info
}

install_vless_only() {
    info "开始配置 VLESS-Reality..."
    local port uuid domain
    prompt_for_vless_config port uuid domain
    run_install_vless "$port" "$uuid" "$domain"
}

install_ss_only() {
    info "开始配置 Shadowsocks-2022..."
    local port password
    prompt_for_ss_config port password
    run_install_ss "$port" "$password"
}

install_dual() {
    info "开始配置双协议 (VLESS-Reality + Shadowsocks-2022)..."
    local vless_port vless_uuid vless_domain ss_port ss_password
    prompt_for_vless_config vless_port vless_uuid vless_domain

    local default_ss_port
    if [[ "$vless_port" == "443" ]]; then default_ss_port=8388; else default_ss_port=$((vless_port + 1)); fi
    prompt_for_ss_config ss_port ss_password "$default_ss_port"

    run_install_dual "$vless_port" "$vless_uuid" "$vless_domain" "$ss_port" "$ss_password"
}

update_xray() {
    detect_xray_binary >/dev/null 2>&1 || true
    if [[ ! -f "$XRAY_BIN" ]]; then error "错误: Xray 未安装。" && return; fi
    info "正在检查最新版本..."
    local current_version latest_version
    current_version=$("$XRAY_BIN" version | head -n 1 | awk '{print $2}')
    latest_version=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r '.tag_name' | sed 's/v//' || echo "")
    [[ -z "$latest_version" ]] && error "获取最新版本号失败，请检查网络或稍后重试。" && return
    info "当前版本: ${cyan}${current_version}${none}，最新版本: ${cyan}${latest_version}${none}"
    if [[ "$current_version" == "$latest_version" ]]; then success "您的 Xray 已是最新版本。" && return; fi
    info "发现新版本，开始更新..."
    run_core_install
    if ! restart_xray; then return 1; fi
    success "Xray 更新成功！"
}

uninstall_xray() {
    detect_xray_binary >/dev/null 2>&1 || true
    if [[ ! -f "$XRAY_BIN" ]]; then error "错误: Xray 未安装。" && return; fi
    read -r -p "$(echo -e "${yellow}您确定要卸载 Xray 吗？这将删除所有配置！[Y/n]: ${none}")" confirm || true
    if [[ "$confirm" =~ ^[nN]$ ]]; then info "操作已取消。"; return; fi
    info "正在卸载 Xray..."
    if ! execute_official_script "remove --purge"; then
        error "Xray 卸载失败！"
        return 1
    fi
    rm -f ~/xray_subscription_info.txt
    success "Xray 已成功卸载。"
}

modify_config_menu() {
    if [[ ! -f "$xray_config_path" ]]; then error "错误: Xray 未安装。" && return; fi

    local vless_exists="" ss_exists=""
    vless_exists=$(jq '.inbounds[] | select(.protocol == "vless")' "$xray_config_path" 2>/dev/null || true)
    ss_exists=$(jq '.inbounds[] | select(.protocol == "shadowsocks")' "$xray_config_path" 2>/dev/null || true)

    if [[ -n "$vless_exists" && -n "$ss_exists" ]]; then
        draw_menu_header
        echo -e "${cyan} 请选择要修改的协议配置${none}"
        draw_divider
        printf "  ${green}%-2s${none} %-35s\n" "1." "VLESS-Reality"
        printf "  ${cyan}%-2s${none} %-35s\n" "2." "Shadowsocks-2022"
        draw_divider
        printf "  ${yellow}%-2s${none} %-35s\n" "0." "返回主菜单"
        draw_divider
        read -r -p " 请输入选项 [0-2]: " choice || true
        case "$choice" in
            1) modify_vless_config ;;
            2) modify_ss_config ;;
            0) return ;;
            *) error "无效选项。" ;;
        esac
    elif [[ -n "$vless_exists" ]]; then
        modify_vless_config
    elif [[ -n "$ss_exists" ]]; then
        modify_ss_config
    else
        error "未找到可修改的协议配置。"
    fi
}

modify_vless_config() {
    info "开始修改 VLESS-Reality 配置..."
    local vless_inbound current_port current_uuid current_domain private_key public_key shortid
    local port uuid domain regenerate new_shortid new_vless_inbound ss_inbound new_inbounds

    vless_inbound=$(jq '.inbounds[] | select(.protocol == "vless")' "$xray_config_path")
    current_port=$(echo "$vless_inbound" | jq -r '.port')
    current_uuid=$(echo "$vless_inbound" | jq -r '.settings.clients[0].id')
    current_domain=$(echo "$vless_inbound" | jq -r '.streamSettings.realitySettings.serverNames[0]')
    private_key=$(echo "$vless_inbound" | jq -r '.streamSettings.realitySettings.privateKey')
    public_key=$(echo "$vless_inbound" | jq -r '.streamSettings.realitySettings.publicKey')
    shortid=$(echo "$vless_inbound" | jq -r '.streamSettings.realitySettings.shortIds[0]')

    while true; do
        read -r -p "$(echo -e " -> 新端口 (当前: ${cyan}${current_port}${none}, 留空不改): ")" port || true
        [[ -z "$port" ]] && port="$current_port"
        if is_port_available "$port" || [[ "$port" == "$current_port" ]]; then break; fi
    done

    read -r -p "$(echo -e " -> 新UUID (当前: ${cyan}${current_uuid}${none}, 留空不改): ")" uuid || true
    [[ -z "$uuid" ]] && uuid="$current_uuid"

    while true; do
        read -r -p "$(echo -e " -> 新SNI域名 (当前: ${cyan}${current_domain}${none}, 留空不改): ")" domain || true
        [[ -z "$domain" ]] && domain="$current_domain"
        if is_valid_domain "$domain"; then break; else error "域名格式无效，请重新输入。"; fi
    done

    read -r -p "$(echo -e " -> 是否重新生成 shortId (当前: ${cyan}${shortid}${none})? [y/N]: ")" regenerate || true
    if [[ "$regenerate" =~ ^[yY]$ ]]; then
        new_shortid=$(generate_shortid)
    else
        new_shortid="$shortid"
    fi

    new_vless_inbound=$(build_vless_inbound "$port" "$uuid" "$domain" "$private_key" "$public_key" "$new_shortid")
    ss_inbound=$(jq '.inbounds[] | select(.protocol == "shadowsocks")' "$xray_config_path" 2>/dev/null || true)
    new_inbounds="[$new_vless_inbound]"
    [[ -n "$ss_inbound" ]] && new_inbounds="[$new_vless_inbound, $ss_inbound]"

    write_config "$new_inbounds"
    if ! restart_xray; then return 1; fi
    success "配置修改成功！"
    view_all_info
}

modify_ss_config() {
    info "开始修改 Shadowsocks-2022 配置..."
    local ss_inbound current_port current_password port password new_ss_inbound vless_inbound new_inbounds
    ss_inbound=$(jq '.inbounds[] | select(.protocol == "shadowsocks")' "$xray_config_path")
    current_port=$(echo "$ss_inbound" | jq -r '.port')
    current_password=$(echo "$ss_inbound" | jq -r '.settings.password')

    while true; do
        read -r -p "$(echo -e " -> 新端口 (当前: ${cyan}${current_port}${none}, 留空不改): ")" port || true
        [[ -z "$port" ]] && port="$current_port"
        if is_port_available "$port" || [[ "$port" == "$current_port" ]]; then break; fi
    done

    read -r -p "$(echo -e " -> 新密钥 (当前: ${cyan}${current_password}${none}, 留空不改): ")" password || true
    [[ -z "$password" ]] && password="$current_password"

    new_ss_inbound=$(build_ss_inbound "$port" "$password")
    vless_inbound=$(jq '.inbounds[] | select(.protocol == "vless")' "$xray_config_path" 2>/dev/null || true)
    new_inbounds="[$new_ss_inbound]"
    [[ -n "$vless_inbound" ]] && new_inbounds="[$vless_inbound, $new_ss_inbound]"

    write_config "$new_inbounds"
    if ! restart_xray; then return 1; fi
    success "配置修改成功！"
    view_all_info
}

restart_xray() {
    detect_xray_binary >/dev/null 2>&1 || true
    if [[ ! -f "$XRAY_BIN" ]]; then error "错误: Xray 未安装。" && return 1; fi
    info "正在重启 Xray 服务..."
    if ! systemctl restart xray; then
        error "尝试重启 Xray 服务失败！"
        echo -e "\n${yellow}错误详情:${none}"
        systemctl status xray --no-pager -l | tail -5
        return 1
    fi
    sleep 2
    if systemctl is-active --quiet xray; then
        success "Xray 服务已成功重启！"
    else
        error "服务启动失败，详细信息:"
        systemctl status xray --no-pager -l | tail -5
        return 1
    fi
}

view_xray_log() {
    detect_xray_binary >/dev/null 2>&1 || true
    if [[ ! -f "$XRAY_BIN" ]]; then error "错误: Xray 未安装。" && return; fi
    info "正在显示 Xray 实时日志... 按 Ctrl+C 退出。"
    journalctl -u xray -f --no-pager
}

view_all_info() {
    if [[ ! -f "$xray_config_path" ]]; then
        [[ "$is_quiet" = true ]] && return
        error "错误: 配置文件不存在。"
        return
    fi

    [[ "$is_quiet" = false ]] && clear && echo -e "${cyan} Xray 配置及订阅信息${none}" && draw_divider

    local ip host
    ip=$(get_public_ip)
    if [[ -z "$ip" ]]; then
        [[ "$is_quiet" = false ]] && error "无法获取公网 IP 地址。"
        return 1
    fi
    host=$(hostname)
    local links_array=()

    local vless_inbound
    vless_inbound=$(jq '.inbounds[] | select(.protocol == "vless")' "$xray_config_path" 2>/dev/null || true)
    if [[ -n "$vless_inbound" ]]; then
        local uuid port domain public_key shortid display_ip link_name_raw link_name_encoded vless_url
        uuid=$(echo "$vless_inbound" | jq -r '.settings.clients[0].id')
        port=$(echo "$vless_inbound" | jq -r '.port')
        domain=$(echo "$vless_inbound" | jq -r '.streamSettings.realitySettings.serverNames[0]')
        public_key=$(echo "$vless_inbound" | jq -r '.streamSettings.realitySettings.publicKey')
        shortid=$(echo "$vless_inbound" | jq -r '.streamSettings.realitySettings.shortIds[0]')

        display_ip=$ip && [[ $ip =~ ":" ]] && display_ip="[$ip]"
        link_name_raw="$host X-reality"
        link_name_encoded=$(echo "$link_name_raw" | sed 's/ /%20/g')
        vless_url="vless://${uuid}@${display_ip}:${port}?flow=xtls-rprx-vision&encryption=none&type=tcp&security=reality&sni=${domain}&fp=chrome&pbk=${public_key}&sid=${shortid}#${link_name_encoded}"
        links_array+=("$vless_url")

        if [[ "$is_quiet" = false ]]; then
            echo -e "${green} [ VLESS-Reality 配置 ]${none}"
            printf "    %s: ${cyan}%s${none}\n" "节点名称" "$link_name_raw"
            printf "    %s: ${cyan}%s${none}\n" "服务器地址" "$ip"
            printf "    %s: ${cyan}%s${none}\n" "端口" "$port"
            printf "    %s: ${cyan}%s${none}\n" "UUID" "$uuid"
            printf "    %s: ${cyan}%s${none}\n" "SNI" "$domain"
            printf "    %s: ${cyan}%s${none}\n" "PublicKey" "$public_key"
            printf "    %s: ${cyan}%s${none}\n" "ShortId" "$shortid"
        fi
    fi

    local ss_inbound
    ss_inbound=$(jq '.inbounds[] | select(.protocol == "shadowsocks")' "$xray_config_path" 2>/dev/null || true)
    if [[ -n "$ss_inbound" ]]; then
        local port method password link_name_raw user_info_base64 ss_url
        port=$(echo "$ss_inbound" | jq -r '.port')
        method=$(echo "$ss_inbound" | jq -r '.settings.method')
        password=$(echo "$ss_inbound" | jq -r '.settings.password')
        link_name_raw="$host X-ss2022"
        user_info_base64=$(echo -n "${method}:${password}" | base64 -w 0)
        ss_url="ss://${user_info_base64}@${ip}:${port}#${link_name_raw}"
        links_array+=("$ss_url")

        if [[ "$is_quiet" = false ]]; then
            echo ""
            echo -e "${green} [ Shadowsocks-2022 配置 ]${none}"
            printf "    %s: ${cyan}%s${none}\n" "节点名称" "$link_name_raw"
            printf "    %s: ${cyan}%s${none}\n" "服务器地址" "$ip"
            printf "    %s: ${cyan}%s${none}\n" "端口" "$port"
            printf "    %s: ${cyan}%s${none}\n" "加密方式" "$method"
            printf "    %s: ${cyan}%s${none}\n" "密码" "$password"
        fi
    fi

    if [[ ${#links_array[@]} -gt 0 ]]; then
        if [[ "$is_quiet" = true ]]; then
            printf "%s\n" "${links_array[@]}"
        else
            draw_divider
            printf "%s\n" "${links_array[@]}" > ~/xray_subscription_info.txt
            success "所有订阅链接已汇总保存到: ~/xray_subscription_info.txt"
            echo -e "\n${yellow} --- 客户端可直接导入以下链接 --- ${none}\n"
            for link in "${links_array[@]}"; do
                echo -e "${cyan}${link}${none}\n"
            done
            draw_divider
        fi
    elif [[ "$is_quiet" = false ]]; then
        info "当前未安装任何协议，无订阅信息可显示。"
    fi
}

# --- 核心安装逻辑函数 ---
run_install_vless() {
    local port="$1" uuid="$2" domain="$3"
    if [[ -z "$(get_public_ip)" ]]; then
        error "无法获取公网 IP 地址，安装中止。请检查您的网络连接。"
        exit 1
    fi
    run_core_install || exit 1

    info "正在生成 Reality 密钥对..."
    local key_pair private_key public_key shortid vless_inbound
    key_pair=$(generate_reality_keypair) || exit 1
    private_key=$(echo "$key_pair" | sed -n '1p')
    public_key=$(echo "$key_pair" | sed -n '2p')
    shortid=$(generate_shortid)

    if [[ -z "$private_key" || -z "$public_key" ]]; then
        error "生成 Reality 密钥对失败！请检查 Xray 核心是否正常，或尝试卸载后重装。"
        exit 1
    fi

    vless_inbound=$(build_vless_inbound "$port" "$uuid" "$domain" "$private_key" "$public_key" "$shortid")
    write_config "[$vless_inbound]"
    if ! restart_xray; then exit 1; fi

    success "VLESS-Reality 安装成功！（shortId 已随机生成）"
    view_all_info
}

run_install_ss() {
    local port="$1" password="$2"
    if [[ -z "$(get_public_ip)" ]]; then
        error "无法获取公网 IP 地址，安装中止。请检查您的网络连接。"
        exit 1
    fi
    run_core_install || exit 1

    local ss_inbound
    ss_inbound=$(build_ss_inbound "$port" "$password")
    write_config "[$ss_inbound]"
    if ! restart_xray; then exit 1; fi

    success "Shadowsocks-2022 安装成功！"
    view_all_info
}

run_install_dual() {
    local vless_port="$1" vless_uuid="$2" vless_domain="$3" ss_port="$4" ss_password="$5"
    if [[ -z "$(get_public_ip)" ]]; then
        error "无法获取公网 IP 地址，安装中止。请检查您的网络连接。"
        exit 1
    fi
    run_core_install || exit 1

    info "正在生成 Reality 密钥对..."
    local key_pair private_key public_key shortid vless_inbound ss_inbound
    key_pair=$(generate_reality_keypair) || exit 1
    private_key=$(echo "$key_pair" | sed -n '1p')
    public_key=$(echo "$key_pair" | sed -n '2p')
    shortid=$(generate_shortid)

    if [[ -z "$private_key" || -z "$public_key" ]]; then
        error "生成 Reality 密钥对失败！请检查 Xray 核心是否正常，或尝试卸载后重装。"
        exit 1
    fi

    vless_inbound=$(build_vless_inbound "$vless_port" "$vless_uuid" "$vless_domain" "$private_key" "$public_key" "$shortid")
    ss_inbound=$(build_ss_inbound "$ss_port" "$ss_password")
    write_config "[$vless_inbound, $ss_inbound]"
    if ! restart_xray; then exit 1; fi

    success "双协议安装成功！（Reality shortId 已随机生成）"
    view_all_info
}

# --- 主菜单与脚本入口 ---
main_menu() {
    while true; do
        draw_menu_header
        printf "  ${green}%-2s${none} %-35s\n" "1." "安装 Xray (VLESS/Shadowsocks)"
        printf "  ${cyan}%-2s${none} %-35s\n" "2." "更新 Xray"
        printf "  ${red}%-2s${none} %-35s\n" "3." "卸载 Xray"
        draw_divider
        printf "  ${yellow}%-2s${none} %-35s\n" "4." "修改配置"
        printf "  ${cyan}%-2s${none} %-35s\n" "5." "重启 Xray"
        printf "  ${magenta}%-2s${none} %-35s\n" "6." "查看 Xray 日志"
        printf "  ${green}%-2s${none} %-35s\n" "7." "查看订阅信息"
        draw_divider
        printf "  ${cyan}%-2s${none} %-35s\n" "8." "更新脚本 (x.sh)"
        printf "  ${yellow}%-2s${none} %-35s\n" "0." "退出脚本"
        draw_divider

        read -r -p " 请输入选项 [0-8]: " choice || true
        local needs_pause=true

        case "$choice" in
            1) install_menu ;;
            2) update_xray ;;
            3) uninstall_xray ;;
            4) modify_config_menu ;;
            5) restart_xray ;;
            6) view_xray_log; needs_pause=false ;;
            7) view_all_info ;;
            8) update_script ;;
            0) success "感谢使用！"; exit 0 ;;
            *) error "无效选项。请输入0到8之间的数字。" ;;
        esac

        if [[ "$needs_pause" = true ]]; then press_any_key_to_continue; fi
    done
}

main() {
    pre_check
    detect_xray_binary >/dev/null 2>&1 || true
    install_self
    main_menu
}

main "$@"