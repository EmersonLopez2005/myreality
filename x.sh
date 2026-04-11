#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_VERSION="x.sh v3.0.4"
readonly SCRIPT_PATH="/root/x.sh"
readonly SCRIPT_UPDATE_URL="https://raw.githubusercontent.com/EmersonLopez2005/myreality/main/x.sh"

readonly xray_config_path="/usr/local/etc/xray/config.json"
readonly xray_binary_path="/usr/local/bin/xray"
readonly xray_install_script_url="https://github.com/XTLS/Xray-install/raw/main/install-release.sh"

readonly BBR_CONF_FILE="/etc/sysctl.d/99-bbr.conf"
readonly BBR_STATE_DIR="/var/lib/xray-menu"
readonly BBR_STATE_FILE="${BBR_STATE_DIR}/bbr-preapply.state"
readonly BBR_MODULE_VERSION="bbr-module v1.1.0"

readonly MENU_BIN_SYMLINK="/usr/local/bin/xray-menu"
readonly XRAY_ALIAS_PROFILE="/etc/profile.d/xray-shortcut.sh"

readonly red='\e[91m'
readonly green='\e[92m'
readonly yellow='\e[93m'
readonly magenta='\e[95m'
readonly cyan='\e[96m'
readonly blue='\e[94m'
readonly none='\e[0m'

xray_status_info=""
is_quiet=false
XRAY_BIN="${xray_binary_path}"

BBR_TOTAL_MEM=""
BBR_CPU_CORES=""
BBR_VIRT_TYPE=""
BBR_VM_TIER=""
BBR_RMEM_MAX=""
BBR_WMEM_MAX=""
BBR_TCP_MEM_MAX=""
BBR_SOMAXCONN=""
BBR_FILE_MAX=""
BBR_CONNTRACK_MAX=""
BBR_PROFILE="balanced"
BBR_TW_REUSE="1"

error() {
    echo -e "\n${red}[ERROR] $1${none}\n" >&2
}

info() {
    [[ "$is_quiet" = false ]] && echo -e "\n${yellow}[INFO] $1${none}\n"
}

success() {
    [[ "$is_quiet" = false ]] && echo -e "\n${green}[OK] $1${none}\n"
}

warning() {
    [[ "$is_quiet" = false ]] && echo -e "\n${yellow}[WARN] $1${none}\n" >&2
}

draw_divider() {
    printf '%0.s-' {1..56}
    printf '\n'
}

spinner() {
    local pid="$1"
    local spinstr='|/-\'

    [[ "$is_quiet" = true ]] && return 0

    while kill -0 "$pid" >/dev/null 2>&1; do
        local temp=${spinstr#?}
        printf " [%c]  \r" "$spinstr"
        spinstr=$temp${spinstr%"$temp"}
        sleep 0.1
    done
    printf "      \r"
}

get_public_ip() {
    local ip url

    for url in "https://api.ipify.org" "https://ip.sb" "https://checkip.amazonaws.com"; do
        ip=$(curl -4fsS --max-time 5 "$url" 2>/dev/null | tr -d '[:space:]' || true)
        [[ -n "$ip" ]] && printf '%s\n' "$ip" && return 0
    done

    for url in "https://api64.ipify.org" "https://ip.sb"; do
        ip=$(curl -6fsS --max-time 5 "$url" 2>/dev/null | tr -d '[:space:]' || true)
        [[ -n "$ip" ]] && printf '%s\n' "$ip" && return 0
    done

    return 1
}

install_self() {
    local self_src="${BASH_SOURCE[0]}"
    if [[ "$self_src" != "$SCRIPT_PATH" ]]; then
        cp -f "$self_src" "$SCRIPT_PATH"
        chmod +x "$SCRIPT_PATH"
    else
        chmod +x "$SCRIPT_PATH" 2>/dev/null || true
    fi

    local rc_file=""
    case "${SHELL:-}" in
        */zsh) rc_file="$HOME/.zshrc" ;;
        *) rc_file="$HOME/.bashrc" ;;
    esac

    local alias_line="alias xray='bash ${SCRIPT_PATH}'"

    if [[ -n "$rc_file" ]] && ! grep -qsF "$alias_line" "$rc_file" 2>/dev/null; then
        echo "$alias_line" >> "$rc_file"
    fi

    cat > "$XRAY_ALIAS_PROFILE" <<EOF_ALIAS
#!/usr/bin/env bash
$alias_line
EOF_ALIAS
    chmod 644 "$XRAY_ALIAS_PROFILE" 2>/dev/null || true

    mkdir -p "$(dirname "$MENU_BIN_SYMLINK")"
    ln -sf "$SCRIPT_PATH" "$MENU_BIN_SYMLINK" 2>/dev/null || true
    chmod +x "$MENU_BIN_SYMLINK" 2>/dev/null || true
    alias xray="bash ${SCRIPT_PATH}" 2>/dev/null || true
}

update_script() {
    info "正在从远程更新脚本..."
    if ! command -v curl >/dev/null 2>&1; then
        error "系统缺少 curl，无法在线更新脚本。"
        return 1
    fi

    local tmp_raw tmp_clean
    tmp_raw=$(mktemp /tmp/xray-menu.raw.XXXXXX)
    tmp_clean=$(mktemp /tmp/xray-menu.clean.XXXXXX)

    if ! curl -fsSL "$SCRIPT_UPDATE_URL" -o "$tmp_raw"; then
        rm -f "$tmp_raw" "$tmp_clean"
        error "下载脚本失败，请检查网络连接或更新地址。"
        return 1
    fi

    sed $'1s/^\xef\xbb\xbf//; s/\r$//' "$tmp_raw" > "$tmp_clean"
    rm -f "$tmp_raw"

    if ! grep -q 'main_menu' "$tmp_clean"; then
        rm -f "$tmp_clean"
        error "下载内容异常，未检测到有效脚本结构，已取消更新。"
        return 1
    fi

    install -m 755 -o root -g root "$tmp_clean" "$SCRIPT_PATH"
    rm -f "$tmp_clean"
    success "脚本更新完成，请重新运行: xray"
}

pre_check() {
    [[ "$(id -u)" != 0 ]] && error "请以 root 用户运行此脚本。" && exit 1

    if ! grep -Eq 'debian|ubuntu' /etc/os-release 2>/dev/null; then
        error "当前仅支持 Debian / Ubuntu 及其衍生系统。"
        exit 1
    fi

    if ! command -v jq >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1 || ! command -v openssl >/dev/null 2>&1 || ! command -v ss >/dev/null 2>&1; then
        info "检测到缺少依赖，正在尝试自动安装 jq / curl / openssl / iproute2 ..."
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y >/dev/null 2>&1
        apt-get install -y jq curl openssl ca-certificates iproute2 >/dev/null 2>&1 || {
            error "依赖安装失败，请先手动安装 jq、curl、openssl、iproute2 后再运行。"
            exit 1
        }
        success "依赖安装完成。"
    fi
}

detect_xray_binary() {
    local real
    real=$(type -P xray 2>/dev/null || true)
    if [[ -n "$real" ]]; then
        XRAY_BIN="$real"
        return 0
    fi
    XRAY_BIN="$xray_binary_path"
    [[ -x "$XRAY_BIN" ]]
}

check_xray_status() {
    detect_xray_binary >/dev/null 2>&1 || true
    if [[ ! -x "$XRAY_BIN" ]]; then
        xray_status_info=" Xray 状态: ${red}未安装${none}"
        return
    fi

    local xray_version service_status
    xray_version=$("$XRAY_BIN" version 2>/dev/null | head -n 1 | awk '{print $2}' || true)
    xray_version=$(echo -n "$xray_version" | tr -d '\r\n')
    [[ -z "$xray_version" ]] && xray_version="未知"

    if systemctl is-active --quiet xray 2>/dev/null; then
        service_status="${green}运行中${none}"
    else
        service_status="${yellow}未运行${none}"
    fi

    xray_status_info=" Xray 状态: ${green}已安装${none} | ${service_status} | 版本: ${cyan}${xray_version}${none}"
}

quick_status() {
    detect_xray_binary >/dev/null 2>&1 || true
    if [[ ! -x "$XRAY_BIN" ]]; then
        echo -e " * ${red}未安装${none}"
        return
    fi

    if systemctl is-active --quiet xray 2>/dev/null; then
        echo -e " * ${green}Xray 运行中${none}"
    else
        echo -e " * ${yellow}Xray 未运行${none}"
    fi
}

generate_reality_keypair() {
    detect_xray_binary >/dev/null 2>&1 || true
    if [[ ! -x "$XRAY_BIN" ]]; then
        error "未找到可执行的 xray 核心: $XRAY_BIN"
        return 1
    fi

    local out private_key reality_client_key
    out=$("$XRAY_BIN" x25519 2>&1 || true)
    private_key=$(echo "$out" | awk -F':' 'tolower($1) ~ /private/ {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit}')
    reality_client_key=$(echo "$out" | awk -F':' 'tolower($1) ~ /(password|public[[:space:]]*key)/ {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit}')

    if [[ -z "$private_key" || -z "$reality_client_key" ]]; then
        error "生成 Reality 密钥对失败，无法从 xray x25519 输出中解析密钥。"
        {
            echo -e "${yellow}--- xray x25519 原始输出 ---${none}"
            echo "$out" | sed 's/^/  /'
            echo -e "${yellow}---------------------------${none}"
        } >&2
        return 1
    fi

    printf '%s\n%s\n' "$private_key" "$reality_client_key"
}

derive_reality_client_key_from_private_key() {
    local private_key="$1"
    detect_xray_binary >/dev/null 2>&1 || true
    [[ -z "$private_key" || ! -x "$XRAY_BIN" ]] && return 1

    local out reality_client_key
    out=$("$XRAY_BIN" x25519 -i "$private_key" 2>&1 || true)
    reality_client_key=$(echo "$out" | awk -F':' 'tolower($1) ~ /(password|public[[:space:]]*key)/ {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit}')
    [[ -n "$reality_client_key" ]] || return 1
    printf '%s\n' "$reality_client_key"
}

get_reality_client_key_from_inbound() {
    local inbound_json="$1"
    local private_key stored_key

    private_key=$(echo "$inbound_json" | jq -r '.streamSettings.realitySettings.privateKey // empty')
    if [[ -n "$private_key" ]]; then
        stored_key=$(derive_reality_client_key_from_private_key "$private_key" || true)
        [[ -n "$stored_key" ]] && printf '%s\n' "$stored_key" && return 0
    fi

    stored_key=$(echo "$inbound_json" | jq -r '.streamSettings.realitySettings.password // .streamSettings.realitySettings.publicKey // empty')
    [[ -n "$stored_key" ]] || return 1
    printf '%s\n' "$stored_key"
}

generate_shortid() {
    local sid
    sid=$(openssl rand -hex 4 2>/dev/null || true)
    if [[ -z "$sid" ]]; then
        sid=$(head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \n')
    fi
    printf '%s\n' "$sid"
}

generate_ss_key() {
    openssl rand -base64 16 | tr -d '\r\n'
}

base64_encode_inline() {
    printf '%s' "$1" | openssl base64 -A
}

url_encode() {
    jq -rn --arg v "$1" '$v|@uri'
}

is_valid_uuid() {
    [[ "$1" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]
}

is_valid_ss2022_password() {
    local password="$1" decoded_len rc=0
    decoded_len=$(printf '%s' "$password" | openssl base64 -d -A 2>/dev/null | wc -c | tr -d '[:space:]') || rc=$?
    [[ "$rc" -eq 0 && "$decoded_len" == "16" ]]
}

prompt_for_ss_password() {
    local -n ss_pass_ref="$1"
    local current_pass="${2:-}"
    local prompt_text="$3"

    while true; do
        read -r -p "$prompt_text" ss_pass_ref || true
        if [[ -z "$ss_pass_ref" ]]; then
            if [[ -n "$current_pass" ]]; then
                ss_pass_ref="$current_pass"
                return 0
            fi
            ss_pass_ref=$(generate_ss_key)
            info "已为您自动生成 Shadowsocks 密钥: ${cyan}${ss_pass_ref}${none}"
            return 0
        fi

        if is_valid_ss2022_password "$ss_pass_ref"; then
            return 0
        fi

        error "SS2022 密钥格式无效。请输入合法的 16-byte Base64 密钥，或留空自动生成。"
    done
}
bbr_get_system_info() {
    BBR_TOTAL_MEM=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' | tr -d '\r' || echo 0)
    BBR_CPU_CORES=$(nproc 2>/dev/null | tr -d '\r' || echo 1)

    if command -v systemd-detect-virt >/dev/null 2>&1; then
        BBR_VIRT_TYPE=$(systemd-detect-virt 2>/dev/null || true)
        [[ -z "$BBR_VIRT_TYPE" ]] && BBR_VIRT_TYPE="unknown"
    elif grep -qi hypervisor /proc/cpuinfo 2>/dev/null; then
        BBR_VIRT_TYPE="kvm/vmware"
    else
        BBR_VIRT_TYPE="physical/unknown"
    fi

    bbr_calculate_parameters
}

bbr_calculate_parameters() {
    if [[ "${BBR_TOTAL_MEM:-0}" -le 512 ]]; then
        BBR_VM_TIER="入门型 <=512MB"
        BBR_RMEM_MAX="16777216"
        BBR_WMEM_MAX="16777216"
        BBR_TCP_MEM_MAX="16777216"
        BBR_SOMAXCONN="4096"
        BBR_FILE_MAX="65535"
        BBR_CONNTRACK_MAX="65536"
    elif [[ "${BBR_TOTAL_MEM:-0}" -le 1024 ]]; then
        BBR_VM_TIER="基础型 1GB"
        BBR_RMEM_MAX="33554432"
        BBR_WMEM_MAX="33554432"
        BBR_TCP_MEM_MAX="33554432"
        BBR_SOMAXCONN="16384"
        BBR_FILE_MAX="524288"
        BBR_CONNTRACK_MAX="262144"
    elif [[ "${BBR_TOTAL_MEM:-0}" -le 4096 ]]; then
        BBR_VM_TIER="进阶型 2GB-4GB"
        BBR_RMEM_MAX="67108864"
        BBR_WMEM_MAX="67108864"
        BBR_TCP_MEM_MAX="67108864"
        BBR_SOMAXCONN="32768"
        BBR_FILE_MAX="1048576"
        BBR_CONNTRACK_MAX="524288"
    else
        BBR_VM_TIER="专业型 >4GB"
        BBR_RMEM_MAX="134217728"
        BBR_WMEM_MAX="134217728"
        BBR_TCP_MEM_MAX="134217728"
        BBR_SOMAXCONN="65535"
        BBR_FILE_MAX="2097152"
        BBR_CONNTRACK_MAX="1048576"
    fi
}

bbr_pre_flight_checks() {
    [[ $(id -u) -ne 0 ]] && error "必须使用 root 权限执行 BBR 优化。" && return 1
    modprobe nf_conntrack >/dev/null 2>&1 || true
    modprobe tcp_bbr >/dev/null 2>&1 || true
    return 0
}

bbr_add_conf() {
    local file="$1" key="$2" value="$3" comment="$4"
    {
        echo "# $comment"
        echo "$key = $value"
        echo ""
    } >> "$file"
}

bbr_manage_backups() {
    if [[ -f "$BBR_CONF_FILE" ]]; then
        cp "$BBR_CONF_FILE" "$BBR_CONF_FILE.bak_$(date +%F_%H-%M-%S)"
        find "$(dirname "$BBR_CONF_FILE")" -maxdepth 1 -type f -name "$(basename "$BBR_CONF_FILE").bak_*" -printf '%T@ %p\n' 2>/dev/null \
            | sort -nr \
            | awk 'NR>3 {print $2}' \
            | xargs -r rm -f
    fi
}

bbr_extract_keys_from_file() {
    local file="$1"
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        if [[ "$line" =~ ^[[:space:]]*([a-zA-Z0-9_.]+)[[:space:]]*= ]]; then
            printf '%s\n' "${BASH_REMATCH[1]}"
        fi
    done < "$file"
}

bbr_capture_runtime_state() {
    local conf_file="$1"
    mkdir -p "$BBR_STATE_DIR"

    local tmp key value
    tmp=$(mktemp "${BBR_STATE_FILE}.tmp.XXXXXX")

    {
        echo "# Captured before applying ${BBR_CONF_FILE}"
        echo "# $(date)"
    } > "$tmp"

    while IFS= read -r key || [[ -n "$key" ]]; do
        [[ -z "$key" ]] && continue
        value=$(sysctl -n "$key" 2>/dev/null || true)
        if [[ -n "$value" ]]; then
            printf '%s = %s\n' "$key" "$value" >> "$tmp"
        else
            printf '# missing %s\n' "$key" >> "$tmp"
        fi
    done < <(bbr_extract_keys_from_file "$conf_file")

    mv -f "$tmp" "$BBR_STATE_FILE"
}

bbr_restore_runtime_state() {
    local state_file="$1"
    [[ -f "$state_file" ]] || return 0

    local restored=0 failed=0
    local line key value
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        if [[ "$line" =~ ^[[:space:]]*([a-zA-Z0-9_.]+)[[:space:]]*=[[:space:]]*(.+)[[:space:]]*$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            if sysctl -w "${key}=${value}" >/dev/null 2>&1; then
                ((restored++))
            else
                ((failed++))
            fi
        fi
    done < "$state_file"

    printf '%s|%s\n' "$restored" "$failed"
}

bbr_clamp_int() {
    local v="$1" min="$2" max="$3"
    [[ -z "$v" ]] && v=0
    (( v < min )) && v="$min"
    (( v > max )) && v="$max"
    printf '%s\n' "$v"
}

bbr_scale_int() {
    local v="$1" num="$2" den="$3"
    if [[ -z "$v" || -z "$num" || -z "$den" || "$den" == "0" ]]; then
        printf '%s\n' "$v"
        return
    fi
    printf '%s\n' $(( v * num / den ))
}

bbr_apply_profile_tuning() {
    local profile="$1"

    case "$profile" in
        high_concurrency)
            BBR_SOMAXCONN=$(bbr_scale_int "$BBR_SOMAXCONN" 2 1)
            BBR_FILE_MAX=$(bbr_scale_int "$BBR_FILE_MAX" 2 1)
            BBR_CONNTRACK_MAX=$(bbr_scale_int "$BBR_CONNTRACK_MAX" 2 1)
            BBR_RMEM_MAX=$(bbr_scale_int "$BBR_RMEM_MAX" 3 2)
            BBR_WMEM_MAX=$(bbr_scale_int "$BBR_WMEM_MAX" 3 2)
            BBR_TCP_MEM_MAX=$(bbr_scale_int "$BBR_TCP_MEM_MAX" 3 2)
            ;;
        memory_saving)
            BBR_SOMAXCONN=$(bbr_scale_int "$BBR_SOMAXCONN" 1 2)
            BBR_FILE_MAX=$(bbr_scale_int "$BBR_FILE_MAX" 1 2)
            BBR_CONNTRACK_MAX=$(bbr_scale_int "$BBR_CONNTRACK_MAX" 1 2)
            BBR_RMEM_MAX=$(bbr_scale_int "$BBR_RMEM_MAX" 1 2)
            BBR_WMEM_MAX=$(bbr_scale_int "$BBR_WMEM_MAX" 1 2)
            BBR_TCP_MEM_MAX=$(bbr_scale_int "$BBR_TCP_MEM_MAX" 1 2)
            ;;
        *)
            ;;
    esac

    BBR_SOMAXCONN=$(bbr_clamp_int "$BBR_SOMAXCONN" 4096 262144)
    BBR_FILE_MAX=$(bbr_clamp_int "$BBR_FILE_MAX" 65535 8388608)
    BBR_CONNTRACK_MAX=$(bbr_clamp_int "$BBR_CONNTRACK_MAX" 65536 2097152)
    BBR_RMEM_MAX=$(bbr_clamp_int "$BBR_RMEM_MAX" 8388608 268435456)
    BBR_WMEM_MAX=$(bbr_clamp_int "$BBR_WMEM_MAX" 8388608 268435456)
    BBR_TCP_MEM_MAX=$(bbr_clamp_int "$BBR_TCP_MEM_MAX" 8388608 268435456)
}

bbr_profile_label() {
    case "$1" in
        high_concurrency) echo "高并发" ;;
        memory_saving) echo "省内存" ;;
        *) echo "均衡" ;;
    esac
}

bbr_prompt_profile() {
    local choice
    echo -e "${cyan} 请选择 BBR 优化模式${none}"
    draw_divider
    printf "  ${green}%-2s${none} %-35s\n" "1." "均衡模式 (推荐)"
    printf "  ${yellow}%-2s${none} %-35s\n" "2." "高并发模式"
    printf "  ${magenta}%-2s${none} %-35s\n" "3." "省内存模式"
    draw_divider
    read -r -p " 请选择 [1-3，默认 1]: " choice || true
    case "$choice" in
        2) BBR_PROFILE="high_concurrency" ;;
        3) BBR_PROFILE="memory_saving" ;;
        *) BBR_PROFILE="balanced" ;;
    esac

    read -r -p " 是否启用 tcp_tw_reuse [Y/n]: " choice || true
    if [[ "$choice" =~ ^[nN]$ ]]; then
        BBR_TW_REUSE="0"
    else
        BBR_TW_REUSE="1"
    fi
}

bbr_build_conf_file() {
    local profile="$1" tw_reuse="$2"
    local tmp available_cc

    tmp=$(mktemp "${BBR_CONF_FILE}.tmp.XXXXXX")
    cat > "$tmp" <<EOF
# Generated by x.sh
# Time: $(date)
# Memory: ${BBR_TOTAL_MEM}MB
# CPU: ${BBR_CPU_CORES}
# Virtualization: ${BBR_VIRT_TYPE}
# Tier: ${BBR_VM_TIER}
# Profile: $(bbr_profile_label "$profile")
# Module: ${BBR_MODULE_VERSION}
EOF

    available_cc=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)
    if ! echo " $available_cc " | grep -q ' bbr '; then
        warning "系统未检测到可用的 BBR 拥塞控制，但仍会写入配置。"
    fi

    bbr_add_conf "$tmp" "net.core.default_qdisc" "fq" "fq qdisc"
    bbr_add_conf "$tmp" "net.ipv4.tcp_congestion_control" "bbr" "enable bbr"
    bbr_add_conf "$tmp" "net.core.rmem_max" "$BBR_RMEM_MAX" "rmem max"
    bbr_add_conf "$tmp" "net.core.wmem_max" "$BBR_WMEM_MAX" "wmem max"
    bbr_add_conf "$tmp" "net.core.rmem_default" "262144" "rmem default"
    bbr_add_conf "$tmp" "net.core.wmem_default" "262144" "wmem default"
    bbr_add_conf "$tmp" "net.ipv4.tcp_rmem" "8192 262144 $BBR_TCP_MEM_MAX" "tcp rmem"
    bbr_add_conf "$tmp" "net.ipv4.tcp_wmem" "8192 262144 $BBR_TCP_MEM_MAX" "tcp wmem"
    bbr_add_conf "$tmp" "net.ipv4.udp_rmem_min" "16384" "udp rmem min"
    bbr_add_conf "$tmp" "net.ipv4.udp_wmem_min" "16384" "udp wmem min"
    bbr_add_conf "$tmp" "net.core.somaxconn" "$BBR_SOMAXCONN" "somaxconn"
    bbr_add_conf "$tmp" "net.core.netdev_max_backlog" "$BBR_SOMAXCONN" "netdev backlog"
    bbr_add_conf "$tmp" "net.ipv4.tcp_max_syn_backlog" "$BBR_SOMAXCONN" "syn backlog"
    bbr_add_conf "$tmp" "net.ipv4.tcp_notsent_lowat" "16384" "notsent lowat"
    bbr_add_conf "$tmp" "net.ipv4.tcp_tw_reuse" "$tw_reuse" "tcp_tw_reuse"
    bbr_add_conf "$tmp" "net.ipv4.tcp_timestamps" "1" "tcp timestamps"
    bbr_add_conf "$tmp" "net.ipv4.tcp_fin_timeout" "30" "fin timeout"
    bbr_add_conf "$tmp" "net.ipv4.ip_local_port_range" "10000 65535" "local port range"
    bbr_add_conf "$tmp" "net.ipv4.tcp_max_tw_buckets" "500000" "time wait buckets"
    bbr_add_conf "$tmp" "net.ipv4.tcp_keepalive_time" "600" "keepalive time"
    bbr_add_conf "$tmp" "net.ipv4.tcp_keepalive_intvl" "15" "keepalive interval"
    bbr_add_conf "$tmp" "net.ipv4.tcp_keepalive_probes" "5" "keepalive probes"
    bbr_add_conf "$tmp" "net.netfilter.nf_conntrack_max" "$BBR_CONNTRACK_MAX" "conntrack max"
    bbr_add_conf "$tmp" "net.netfilter.nf_conntrack_tcp_timeout_established" "7200" "conntrack established"
    bbr_add_conf "$tmp" "net.netfilter.nf_conntrack_tcp_timeout_time_wait" "120" "conntrack time wait"
    bbr_add_conf "$tmp" "fs.file-max" "$BBR_FILE_MAX" "file max"
    bbr_add_conf "$tmp" "vm.swappiness" "10" "swappiness"
    bbr_add_conf "$tmp" "net.ipv4.tcp_mtu_probing" "1" "mtu probing"
    bbr_add_conf "$tmp" "net.ipv4.tcp_syncookies" "1" "syncookies"

    printf '%s\n' "$tmp"
}

bbr_apply_sysctl_from_file() {
    local file="$1"
    local ok=0 missing=0 denied=0 invalid=0
    local -a failed_lines=()
    local line key value out rc

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        if [[ "$line" =~ ^[[:space:]]*([a-zA-Z0-9_.]+)[[:space:]]*=[[:space:]]*(.+)[[:space:]]*$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            out=$(sysctl -w "${key}=${value}" 2>&1) || rc=$?
            rc=${rc:-0}

            if [[ "$rc" -eq 0 ]]; then
                ((ok++))
            else
                if echo "$out" | grep -qiE 'No such file|not found'; then
                    ((missing++))
                elif echo "$out" | grep -qiE 'permission denied|Operation not permitted'; then
                    ((denied++))
                else
                    ((invalid++))
                fi
                failed_lines+=("$key=$value -> $out")
            fi
            rc=0
        fi
    done < "$file"

    printf '%s|%s|%s|%s\n' "$ok" "$missing" "$denied" "$invalid"

    if ((${#failed_lines[@]} > 0)); then
        {
            echo -e "\n${yellow}以下 sysctl 项未能成功应用，不一定影响核心功能:${none}"
            for line in "${failed_lines[@]}"; do
                echo "  - $line"
            done
        } >&2
    fi
}

bbr_detect_primary_iface() {
    ip route show default 2>/dev/null | awk '/default/ {print $5; exit}'
}

bbr_apply_optimizations() {
    local profile="$1" tw_reuse="$2"
    local tmp summary ok missing denied invalid cc qdisc reuse iface tcq

    bbr_get_system_info
    bbr_apply_profile_tuning "$profile"

    [[ "$is_quiet" = false ]] && {
        echo -e "${cyan}>>> 系统信息检测${none}"
        echo -e "内存大小       : ${yellow}${BBR_TOTAL_MEM}MB${none}"
        echo -e "CPU 核心数     : ${yellow}${BBR_CPU_CORES}${none}"
        echo -e "虚拟化类型     : ${yellow}${BBR_VIRT_TYPE}${none}"
        echo -e "资源档位       : ${yellow}${BBR_VM_TIER}${none}"
        echo -e "优化模式       : ${yellow}$(bbr_profile_label "$profile")${none}"
    }

    info "正在生成并应用网络优化配置..."
    mkdir -p "$(dirname "$BBR_CONF_FILE")"

    tmp=$(bbr_build_conf_file "$profile" "$tw_reuse")
    bbr_capture_runtime_state "$tmp"
    chmod 644 "$tmp" 2>/dev/null || true
    mv -f "$tmp" "$BBR_CONF_FILE"

    info "正在应用 sysctl 参数..."
    summary=$(bbr_apply_sysctl_from_file "$BBR_CONF_FILE")
    ok=${summary%%|*}; summary=${summary#*|}
    missing=${summary%%|*}; summary=${summary#*|}
    denied=${summary%%|*}; invalid=${summary#*|}

    cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "未知")
    qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "未知")
    reuse=$(sysctl -n net.ipv4.tcp_tw_reuse 2>/dev/null || echo "未知")
    iface=$(bbr_detect_primary_iface || true)
    if command -v tc >/dev/null 2>&1 && [[ -n "$iface" ]]; then
        tcq=$(tc qdisc show dev "$iface" 2>/dev/null | head -n 1 || true)
    else
        tcq=""
    fi

    success "网络优化已完成。"
    echo -e "成功应用: ${green}${ok}${none} 项 | 不存在: ${yellow}${missing}${none} 项 | 权限受限: ${yellow}${denied}${none} 项 | 其他失败: ${yellow}${invalid}${none} 项"
    echo -e "拥塞控制: ${cyan}${cc}${none} | qdisc: ${cyan}${qdisc}${none} | tcp_tw_reuse: ${cyan}${reuse}${none}"
    [[ -n "$tcq" ]] && echo -e "网卡 qdisc: ${cyan}${tcq}${none}"
}

bbr_uninstall() {
    if [[ ! -f "$BBR_CONF_FILE" ]]; then
        warning "未发现 BBR 优化配置，无需卸载。"
        return 0
    fi

    info "正在卸载 / 回滚 BBR 网络优化配置..."
    mv -f "$BBR_CONF_FILE" "$BBR_CONF_FILE.removed_$(date +%F_%H-%M-%S)"

    local restore_summary restored failed
    sysctl --system >/dev/null 2>&1 || true
    if [[ -f "$BBR_STATE_FILE" ]]; then
        restore_summary=$(bbr_restore_runtime_state "$BBR_STATE_FILE")
        restored=${restore_summary%%|*}
        failed=${restore_summary#*|}
        rm -f "$BBR_STATE_FILE"
        success "已移除优化配置，并尝试恢复 ${restored} 项原始 sysctl。"
        if [[ "$failed" != "0" ]]; then
            warning "仍有 ${failed} 项 sysctl 未恢复，如有异常可重启服务器。"
        fi
    else
        success "已移除优化配置。未找到运行前备份，如有残留可重启服务器。"
    fi
}

bbr_status() {
    draw_menu_header
    echo -e "${cyan} BBR / 网络优化状态${none}"
    draw_divider
    printf "  %-24s %s\n" "配置文件" "$BBR_CONF_FILE"
    if [[ -f "$BBR_CONF_FILE" ]]; then
        printf "  %-24s %b\n" "是否存在" "${green}是${none}"
    else
        printf "  %-24s %b\n" "是否存在" "${red}否${none}"
    fi

    local cc qdisc available iface tcq mod_line
    cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "未知")
    qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "未知")
    available=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || echo "未知")

    printf "  %-24s %s\n" "当前拥塞控制" "$cc"
    printf "  %-24s %s\n" "可用拥塞控制" "$available"
    printf "  %-24s %s\n" "当前 qdisc" "$qdisc"

    echo ""
    echo "  常用验证:"
    if command -v lsmod >/dev/null 2>&1; then
        mod_line=$(lsmod 2>/dev/null | awk '$1=="tcp_bbr"{print; exit}' || true)
        if [[ -n "$mod_line" ]]; then
            printf "  %-24s %s\n" "tcp_bbr 模块" "已加载"
        else
            printf "  %-24s %s\n" "tcp_bbr 模块" "未显示 (可能已内置或未加载)"
        fi
    else
        printf "  %-24s %s\n" "tcp_bbr 模块" "无法检测 (缺少 lsmod)"
    fi

    iface=$(bbr_detect_primary_iface || true)
    if [[ -n "$iface" ]]; then
        printf "  %-24s %s\n" "默认出口网卡" "$iface"
        if command -v tc >/dev/null 2>&1; then
            tcq=$(tc qdisc show dev "$iface" 2>/dev/null | head -n 1 || true)
            [[ -n "$tcq" ]] && printf "  %-24s %s\n" "tc qdisc" "$tcq"
        else
            printf "  %-24s %s\n" "tc qdisc" "无法检测 (缺少 tc)"
        fi
    else
        printf "  %-24s %s\n" "默认出口网卡" "无法识别"
    fi

    echo ""
    echo "  关键参数:"
    sysctl net.ipv4.tcp_tw_reuse net.ipv4.tcp_timestamps net.core.somaxconn 2>/dev/null | sed 's/^/  /' || true
    draw_divider
}

bbr_menu() {
    while true; do
        draw_menu_header
        echo -e "${cyan} BBR / 网络智能优化 (${BBR_MODULE_VERSION})${none}"
        draw_divider
        printf "  ${green}%-2s${none} %-35s\n" "1." "一键开启优化"
        printf "  ${yellow}%-2s${none} %-35s\n" "2." "查看当前状态"
        printf "  ${red}%-2s${none} %-35s\n" "3." "卸载 / 回滚优化"
        draw_divider
        printf "  ${magenta}%-2s${none} %-35s\n" "0." "返回主菜单"
        draw_divider
        read -r -p " 请输入选项 [0-3]: " choice || true
        case "$choice" in
            1)
                bbr_pre_flight_checks || { press_any_key_to_continue; continue; }
                bbr_manage_backups
                bbr_prompt_profile
                bbr_apply_optimizations "$BBR_PROFILE" "$BBR_TW_REUSE" || true
                press_any_key_to_continue
                ;;
            2)
                bbr_status || true
                press_any_key_to_continue
                ;;
            3)
                bbr_uninstall || true
                press_any_key_to_continue
                ;;
            0) return ;;
            *) error "无效选项。"; press_any_key_to_continue ;;
        esac
    done
}
build_vless_inbound() {
    local port="$1" uuid="$2" domain="$3" private_key="$4" shortid="$5"
    jq -n \
        --argjson port "$port" \
        --arg uuid "$uuid" \
        --arg domain "$domain" \
        --arg private_key "$private_key" \
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
                    "shortIds": [$shortid]
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": ["http", "tls", "quic"]
            }
        }'
}

build_xhttp_inbound() {
    local port="$1" uuid="$2" domain="$3" private_key="$4" shortid="$5" path="$6" host="$7"
    jq -n \
        --argjson port "$port" \
        --arg uuid "$uuid" \
        --arg domain "$domain" \
        --arg private_key "$private_key" \
        --arg shortid "$shortid" \
        --arg path "$path" \
        --arg host "$host" \
        '{
            "listen": "0.0.0.0",
            "port": $port,
            "protocol": "vless",
            "settings": {
                "clients": [{"id": $uuid}],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "xhttp",
                "security": "reality",
                "realitySettings": {
                    "show": false,
                    "target": ($domain + ":443"),
                    "dest": ($domain + ":443"),
                    "xver": 0,
                    "serverNames": [$domain],
                    "privateKey": $private_key,
                    "shortIds": [$shortid]
                },
                "xhttpSettings": {
                    "host": $host,
                    "path": $path,
                    "mode": "auto"
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
        '{
            "listen": "0.0.0.0",
            "port": $port,
            "protocol": "shadowsocks",
            "settings": {
                "method": "2022-blake3-aes-128-gcm",
                "password": $password
            }
        }'
}

write_config() {
    local inbounds_json="$1"
    local config_content
    mkdir -p "$(dirname "$xray_config_path")"

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
        error "生成的配置文件格式错误。"
        return 1
    fi

    echo "$config_content" > "$xray_config_path"
    chmod 644 "$xray_config_path"
    chown root:root "$xray_config_path"
}

execute_official_script() {
    local script_content="" curl_rc=0 pid
    script_content=$(curl -fsSL "$xray_install_script_url" 2>/dev/null) || curl_rc=$?
    if [[ "$curl_rc" -ne 0 || -z "$script_content" || ! "$script_content" =~ install-release ]]; then
        error "下载 Xray 官方安装脚本失败或内容异常，请检查网络连接。"
        return 1
    fi

    {
        printf '%s' "$script_content" | bash -s -- "$@" >/dev/null 2>&1
    } &
    pid=$!
    spinner "$pid"
    if ! wait "$pid"; then
        return 1
    fi
}

run_core_install() {
    info "正在安装 / 更新 Xray 核心..."
    if ! execute_official_script install; then
        error "Xray 核心安装失败。"
        return 1
    fi

    info "正在更新 GeoIP / GeoSite 数据..."
    if ! execute_official_script install-geodata; then
        warning "Geo 数据更新失败，但通常不会影响核心功能，可稍后重试。"
    fi

    detect_xray_binary >/dev/null 2>&1 || true
    success "Xray 核心和数据文件已准备完成。"
}

is_valid_port() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] && [[ "$port" -ge 1 && "$port" -le 65535 ]]
}

is_port_available() {
    local port="$1"
    is_valid_port "$port" || return 1

    local tcp_in_use=false udp_in_use=false proto="TCP/UDP"
    if ss -H -ltn 2>/dev/null | awk -v p=":$port" '$4 ~ p"$" {found=1; exit} END{exit !found}'; then tcp_in_use=true; fi
    if ss -H -lun 2>/dev/null | awk -v p=":$port" '($4 ~ p"$") || ($5 ~ p"$") {found=1; exit} END{exit !found}'; then udp_in_use=true; fi

    if [[ "$tcp_in_use" = true || "$udp_in_use" = true ]]; then
        [[ "$tcp_in_use" = true && "$udp_in_use" = false ]] && proto="TCP"
        [[ "$tcp_in_use" = false && "$udp_in_use" = true ]] && proto="UDP"
        warning "端口 $port 已被 ${proto} 占用，请更换端口。"
        return 1
    fi
    return 0
}

is_valid_domain() {
    local domain="$1"
    [[ "$domain" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]]
}

prompt_for_vless_config() {
    local -n p_port="$1" p_uuid="$2" p_sni="$3"
    local default_port="${4:-443}"

    while true; do
        read -r -p " -> 请输入 VLESS 端口 (默认: ${default_port}): " p_port || true
        [[ -z "$p_port" ]] && p_port="$default_port"
        if is_port_available "$p_port"; then
            break
        fi
        error "端口不可用，请重新输入。"
    done
    info "VLESS 端口将使用: ${cyan}${p_port}${none}"

    while true; do
        read -r -p " -> 请输入 UUID (留空将自动生成): " p_uuid || true
        if [[ -z "$p_uuid" ]]; then
            p_uuid=$(cat /proc/sys/kernel/random/uuid)
            info "已为您生成随机 UUID: ${cyan}${p_uuid}${none}"
            break
        fi
        if is_valid_uuid "$p_uuid"; then
            break
        fi
        error "UUID 格式无效，请重新输入。"
    done

    while true; do
        read -r -p " -> 请输入 SNI 域名 (默认: learn.microsoft.com): " p_sni || true
        [[ -z "$p_sni" ]] && p_sni="learn.microsoft.com"
        if is_valid_domain "$p_sni"; then
            break
        fi
        error "域名格式无效，请重新输入。"
    done
    info "SNI 域名将使用: ${cyan}${p_sni}${none}"
}

prompt_for_xhttp_config() {
    local -n p_port="$1" p_uuid="$2" p_sni="$3" p_path="$4" p_host="$5"
    local default_port="${6:-443}"

    prompt_for_vless_config p_port p_uuid p_sni "$default_port"

    while true; do
        read -r -p " -> 请输入 XHTTP 路径 (默认: /xhttp): " p_path || true
        [[ -z "$p_path" ]] && p_path="/xhttp"
        [[ "$p_path" != /* ]] && p_path="/${p_path}"
        if [[ "$p_path" == /* && "$p_path" != *[[:space:]]* && "$p_path" != *\"* ]]; then
            break
        fi
        error "XHTTP 路径格式无效，请重新输入。"
    done
    info "XHTTP 路径将使用: ${cyan}${p_path}${none}"

    read -r -p " -> 请输入 XHTTP Host (留空则不设置): " p_host || true
    if [[ -n "$p_host" ]] && ! is_valid_domain "$p_host"; then
        error "Host 域名格式无效，已自动清空。"
        p_host=""
    fi
    [[ -n "$p_host" ]] && info "XHTTP Host 将使用: ${cyan}${p_host}${none}"
}

prompt_for_ss_config() {
    local -n p_port="$1" p_pass="$2"
    local default_port="${3:-8388}"

    while true; do
        read -r -p " -> 请输入 Shadowsocks 端口 (默认: ${default_port}): " p_port || true
        [[ -z "$p_port" ]] && p_port="$default_port"
        if is_port_available "$p_port"; then
            break
        fi
        error "端口不可用，请重新输入。"
    done
    info "Shadowsocks 端口将使用: ${cyan}${p_port}${none}"

    prompt_for_ss_password p_pass "" " -> 请输入 Shadowsocks 密钥 (留空将自动生成): "
}

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
    read -n 1 -s -r -p " 按任意键返回菜单..." || true
}

clean_install_menu() {
    draw_menu_header
    echo -e "${cyan} 请选择要安装的协议类型${none}"
    draw_divider
    printf "  ${green}%-2s${none} %-35s\n" "1." "仅 VLESS-Reality"
    printf "  ${blue}%-2s${none} %-35s\n" "2." "仅 VLESS-XHTTP-REALITY"
    printf "  ${cyan}%-2s${none} %-35s\n" "3." "仅 Shadowsocks-2022"
    printf "  ${yellow}%-2s${none} %-35s\n" "4." "VLESS-Reality + Shadowsocks-2022 (双协议)"
    printf "  ${magenta}%-2s${none} %-35s\n" "5." "VLESS-XHTTP-REALITY + Shadowsocks-2022 (双协议)"
    draw_divider
    printf "  ${magenta}%-2s${none} %-35s\n" "0." "返回主菜单"
    draw_divider
    read -r -p " 请输入选项 [0-5]: " choice || true
    case "$choice" in
        1) install_vless_only || true ;;
        2) install_xhttp_only || true ;;
        3) install_ss_only || true ;;
        4) install_dual || true ;;
        5) install_xhttp_dual || true ;;
        0) return ;;
        *) error "无效选项。" ;;
    esac
}

install_menu() {
    local vless_exists="" ss_exists="" vless_network="tcp"
    local current_vless_label="VLESS-Reality" reinstall_func="install_vless_only"
    if [[ -f "$xray_config_path" ]]; then
        vless_exists=$(jq '.inbounds[] | select(.protocol == "vless")' "$xray_config_path" 2>/dev/null || true)
        ss_exists=$(jq '.inbounds[] | select(.protocol == "shadowsocks")' "$xray_config_path" 2>/dev/null || true)
        if [[ -n "$vless_exists" ]]; then
            vless_network=$(echo "$vless_exists" | jq -r '.streamSettings.network // "tcp"')
            if [[ "$vless_network" == "xhttp" ]]; then
                current_vless_label="VLESS-XHTTP-REALITY"
                reinstall_func="install_xhttp_only"
            fi
        fi
    fi

    draw_menu_header
    if [[ -n "$vless_exists" && -n "$ss_exists" ]]; then
        success "当前已安装 ${current_vless_label} + Shadowsocks-2022 双协议。"
        info "如需修改，请使用“修改配置”；如需重装，请先卸载后再安装。"
        return
    elif [[ -n "$vless_exists" && -z "$ss_exists" ]]; then
        info "当前仅安装了 ${current_vless_label}。"
        echo -e "${cyan} 请选择下一步操作${none}"
        draw_divider
        printf "  ${green}%-2s${none} %-35s\n" "1." "追加安装 Shadowsocks-2022"
        printf "  ${red}%-2s${none} %-35s\n" "2." "覆盖重装 ${current_vless_label}"
        draw_divider
        printf "  ${yellow}%-2s${none} %-35s\n" "0." "返回主菜单"
        draw_divider
        read -r -p " 请输入选项 [0-2]: " choice || true
        case "$choice" in
            1) add_ss_to_vless || true ;;
            2) ${reinstall_func} || true ;;
            0) return ;;
            *) error "无效选项。" ;;
        esac
    elif [[ -z "$vless_exists" && -n "$ss_exists" ]]; then
        info "当前仅安装了 Shadowsocks-2022。"
        echo -e "${cyan} 请选择下一步操作${none}"
        draw_divider
        printf "  ${green}%-2s${none} %-35s\n" "1." "追加安装 VLESS-Reality"
        printf "  ${blue}%-2s${none} %-35s\n" "2." "追加安装 VLESS-XHTTP-REALITY"
        printf "  ${red}%-2s${none} %-35s\n" "3." "覆盖重装 Shadowsocks-2022"
        draw_divider
        printf "  ${yellow}%-2s${none} %-35s\n" "0." "返回主菜单"
        draw_divider
        read -r -p " 请输入选项 [0-3]: " choice || true
        case "$choice" in
            1) add_vless_to_ss || true ;;
            2) install_xhttp_dual || true ;;
            3) install_ss_only || true ;;
            0) return ;;
            *) error "无效选项。" ;;
        esac
    else
        clean_install_menu
    fi
}

add_ss_to_vless() {
    info "开始追加安装 Shadowsocks-2022..."
    if [[ -z "$(get_public_ip || true)" ]]; then
        error "无法获取公网 IP，操作中止，请检查网络连接。"
        return 1
    fi

    local vless_inbound vless_port default_ss_port ss_port ss_password ss_inbound
    vless_inbound=$(jq '.inbounds[] | select(.protocol == "vless")' "$xray_config_path" 2>/dev/null || true)
    vless_port=$(echo "$vless_inbound" | jq -r '.port')
    default_ss_port=$([[ "$vless_port" == "443" ]] && echo 8388 || echo $((vless_port + 1)))

    prompt_for_ss_config ss_port ss_password "$default_ss_port"
    ss_inbound=$(build_ss_inbound "$ss_port" "$ss_password")
    write_config "[$vless_inbound, $ss_inbound]"
    restart_xray || return 1
    success "Shadowsocks-2022 已追加安装完成。"
    view_all_info
}

add_vless_to_ss() {
    info "开始追加安装 VLESS-Reality..."
    if [[ -z "$(get_public_ip || true)" ]]; then
        error "无法获取公网 IP，操作中止，请检查网络连接。"
        return 1
    fi

    local ss_inbound ss_port default_vless_port vless_port vless_uuid vless_domain
    local key_pair private_key public_key shortid vless_inbound

    ss_inbound=$(jq '.inbounds[] | select(.protocol == "shadowsocks")' "$xray_config_path" 2>/dev/null || true)
    ss_port=$(echo "$ss_inbound" | jq -r '.port')
    default_vless_port=$([[ "$ss_port" == "8388" ]] && echo 443 || echo $((ss_port - 1)))

    prompt_for_vless_config vless_port vless_uuid vless_domain "$default_vless_port"
    info "正在生成 Reality 密钥对..."
    key_pair=$(generate_reality_keypair) || return 1
    private_key=$(echo "$key_pair" | sed -n '1p')
    public_key=$(echo "$key_pair" | sed -n '2p')
    shortid=$(generate_shortid)

    if [[ -z "$private_key" || -z "$public_key" ]]; then
        error "生成 Reality 密钥对失败，请检查 Xray 核心是否正常。"
        return 1
    fi

    vless_inbound=$(build_vless_inbound "$vless_port" "$vless_uuid" "$vless_domain" "$private_key" "$shortid")
    write_config "[$vless_inbound, $ss_inbound]"
    restart_xray || return 1
    success "VLESS-Reality 已追加安装完成。"
    view_all_info
}

install_xhttp_only() {
    info "开始配置 VLESS-XHTTP-REALITY..."
    local port uuid domain path host
    prompt_for_xhttp_config port uuid domain path host
    run_install_xhttp "$port" "$uuid" "$domain" "$path" "$host"
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
    local vless_port vless_uuid vless_domain ss_port ss_password default_ss_port
    prompt_for_vless_config vless_port vless_uuid vless_domain
    default_ss_port=$([[ "$vless_port" == "443" ]] && echo 8388 || echo $((vless_port + 1)))
    prompt_for_ss_config ss_port ss_password "$default_ss_port"
    run_install_dual "$vless_port" "$vless_uuid" "$vless_domain" "$ss_port" "$ss_password"
}

install_xhttp_dual() {
    info "开始配置双协议 (VLESS-XHTTP-REALITY + Shadowsocks-2022)..."
    local xhttp_port xhttp_uuid xhttp_domain xhttp_path xhttp_host ss_port ss_password default_ss_port
    prompt_for_xhttp_config xhttp_port xhttp_uuid xhttp_domain xhttp_path xhttp_host
    default_ss_port=$([[ "$xhttp_port" == "443" ]] && echo 8388 || echo $((xhttp_port + 1)))
    prompt_for_ss_config ss_port ss_password "$default_ss_port"
    run_install_xhttp_dual "$xhttp_port" "$xhttp_uuid" "$xhttp_domain" "$xhttp_path" "$xhttp_host" "$ss_port" "$ss_password"
}

run_install_vless() {
    local port="$1" uuid="$2" domain="$3"
    if [[ -z "$(get_public_ip || true)" ]]; then
        error "无法获取公网 IP，安装中止。请检查网络连接。"
        return 1
    fi
    run_core_install || return 1

    info "正在生成 Reality 密钥对..."
    local key_pair private_key public_key shortid vless_inbound
    key_pair=$(generate_reality_keypair) || return 1
    private_key=$(echo "$key_pair" | sed -n '1p')
    public_key=$(echo "$key_pair" | sed -n '2p')
    shortid=$(generate_shortid)

    if [[ -z "$private_key" || -z "$public_key" ]]; then
        error "生成 Reality 密钥对失败，请检查 Xray 核心是否正常。"
        return 1
    fi

    vless_inbound=$(build_vless_inbound "$port" "$uuid" "$domain" "$private_key" "$shortid")
    write_config "[$vless_inbound]"
    restart_xray || return 1

    success "VLESS-Reality 安装成功。"
    view_all_info
}

run_install_ss() {
    local port="$1" password="$2"
    if [[ -z "$(get_public_ip || true)" ]]; then
        error "无法获取公网 IP，安装中止。请检查网络连接。"
        return 1
    fi
    run_core_install || return 1

    local ss_inbound
    ss_inbound=$(build_ss_inbound "$port" "$password")
    write_config "[$ss_inbound]"
    restart_xray || return 1

    success "Shadowsocks-2022 安装成功。"
    view_all_info
}

run_install_xhttp() {
    local port="$1" uuid="$2" domain="$3" path="$4" host="$5"
    if [[ -z "$(get_public_ip || true)" ]]; then
        error "无法获取公网 IP，安装中止。请检查网络连接。"
        return 1
    fi
    run_core_install || return 1

    info "正在生成 Reality 密钥对..."
    local key_pair private_key public_key shortid xhttp_inbound
    key_pair=$(generate_reality_keypair) || return 1
    private_key=$(echo "$key_pair" | sed -n '1p')
    public_key=$(echo "$key_pair" | sed -n '2p')
    shortid=$(generate_shortid)

    if [[ -z "$private_key" || -z "$public_key" ]]; then
        error "生成 Reality 密钥对失败，请检查 Xray 核心是否正常。"
        return 1
    fi

    xhttp_inbound=$(build_xhttp_inbound "$port" "$uuid" "$domain" "$private_key" "$shortid" "$path" "$host")
    write_config "[$xhttp_inbound]"
    restart_xray || return 1

    success "VLESS-XHTTP-REALITY 安装成功。"
    view_all_info
}

run_install_dual() {
    local vless_port="$1" vless_uuid="$2" vless_domain="$3" ss_port="$4" ss_password="$5"
    if [[ -z "$(get_public_ip || true)" ]]; then
        error "无法获取公网 IP，安装中止。请检查网络连接。"
        return 1
    fi
    run_core_install || return 1

    info "正在生成 Reality 密钥对..."
    local key_pair private_key public_key shortid vless_inbound ss_inbound
    key_pair=$(generate_reality_keypair) || return 1
    private_key=$(echo "$key_pair" | sed -n '1p')
    public_key=$(echo "$key_pair" | sed -n '2p')
    shortid=$(generate_shortid)

    if [[ -z "$private_key" || -z "$public_key" ]]; then
        error "生成 Reality 密钥对失败，请检查 Xray 核心是否正常。"
        return 1
    fi

    vless_inbound=$(build_vless_inbound "$vless_port" "$vless_uuid" "$vless_domain" "$private_key" "$shortid")
    ss_inbound=$(build_ss_inbound "$ss_port" "$ss_password")
    write_config "[$vless_inbound, $ss_inbound]"
    restart_xray || return 1

    success "双协议安装成功。"
    view_all_info
}

run_install_xhttp_dual() {
    local xhttp_port="$1" xhttp_uuid="$2" xhttp_domain="$3" xhttp_path="$4" xhttp_host="$5" ss_port="$6" ss_password="$7"
    if [[ -z "$(get_public_ip || true)" ]]; then
        error "无法获取公网 IP，安装中止。请检查网络连接。"
        return 1
    fi
    run_core_install || return 1

    info "正在生成 Reality 密钥对..."
    local key_pair private_key public_key shortid xhttp_inbound ss_inbound
    key_pair=$(generate_reality_keypair) || return 1
    private_key=$(echo "$key_pair" | sed -n '1p')
    public_key=$(echo "$key_pair" | sed -n '2p')
    shortid=$(generate_shortid)

    if [[ -z "$private_key" || -z "$public_key" ]]; then
        error "生成 Reality 密钥对失败，请检查 Xray 核心是否正常。"
        return 1
    fi

    xhttp_inbound=$(build_xhttp_inbound "$xhttp_port" "$xhttp_uuid" "$xhttp_domain" "$private_key" "$shortid" "$xhttp_path" "$xhttp_host")
    ss_inbound=$(build_ss_inbound "$ss_port" "$ss_password")
    write_config "[$xhttp_inbound, $ss_inbound]"
    restart_xray || return 1

    success "VLESS-XHTTP-REALITY + Shadowsocks-2022 双协议安装成功。"
    view_all_info
}
update_xray() {
    detect_xray_binary >/dev/null 2>&1 || true
    if [[ ! -x "$XRAY_BIN" ]]; then
        error "Xray 未安装。"
        return 1
    fi

    info "正在检查最新版本..."
    local current_version latest_version yn
    current_version=$("$XRAY_BIN" version 2>/dev/null | head -n 1 | awk '{print $2}' || true)
    current_version=$(echo -n "$current_version" | tr -d '\r\n')
    [[ -z "$current_version" ]] && current_version="未知"

    latest_version=$(curl -fsSL --max-time 8 https://api.github.com/repos/XTLS/Xray-core/releases/latest 2>/dev/null \
        | jq -r '.tag_name' 2>/dev/null \
        | sed 's/^v//' || true)

    if [[ -z "$latest_version" || "$latest_version" == "null" ]]; then
        warning "获取最新版本号失败，可能是网络、DNS 或 GitHub API 限流导致。"
        echo -e " 当前版本: ${cyan}${current_version}${none}"
        read -r -p " 是否仍然尝试执行官方更新脚本 [Y/n]: " yn || true
        if [[ "$yn" =~ ^[nN]$ ]]; then
            info "已取消更新。"
            return 0
        fi
        info "开始执行官方更新脚本..."
        run_core_install || return 1
        restart_xray || return 1
        success "Xray 更新流程已执行完成。"
        return 0
    fi

    info "当前版本: ${cyan}${current_version}${none}，最新版本: ${cyan}${latest_version}${none}"
    if [[ "$current_version" == "$latest_version" ]]; then
        success "当前已经是最新版本。"
        return 0
    fi

    info "发现新版本，开始更新..."
    run_core_install || return 1
    restart_xray || return 1
    success "Xray 更新成功。"
}

uninstall_xray() {
    detect_xray_binary >/dev/null 2>&1 || true
    if [[ ! -x "$XRAY_BIN" ]]; then
        error "Xray 未安装。"
        return 1
    fi

    read -r -p "您确定要卸载 Xray 吗？这将删除所有配置 [Y/n]: " confirm || true
    if [[ "$confirm" =~ ^[nN]$ ]]; then
        info "操作已取消。"
        return 0
    fi

    info "正在卸载 Xray..."
    if ! execute_official_script remove --purge; then
        error "Xray 卸载失败。"
        return 1
    fi

    rm -f ~/xray_subscription_info.txt
    success "Xray 已成功卸载。"
}

modify_config_menu() {
    if [[ ! -f "$xray_config_path" ]]; then
        error "未找到 Xray 配置文件。"
        return 1
    fi

    local vless_exists="" ss_exists="" vless_label="VLESS-Reality"
    vless_exists=$(jq '.inbounds[] | select(.protocol == "vless")' "$xray_config_path" 2>/dev/null || true)
    ss_exists=$(jq '.inbounds[] | select(.protocol == "shadowsocks")' "$xray_config_path" 2>/dev/null || true)
    if [[ -n "$vless_exists" ]]; then
        local vless_network
        vless_network=$(echo "$vless_exists" | jq -r '.streamSettings.network // "tcp"')
        [[ "$vless_network" == "xhttp" ]] && vless_label="VLESS-XHTTP-REALITY"
    fi

    if [[ -n "$vless_exists" && -n "$ss_exists" ]]; then
        draw_menu_header
        echo -e "${cyan} 请选择要修改的协议配置${none}"
        draw_divider
        printf "  ${green}%-2s${none} %-35s\n" "1." "$vless_label"
        printf "  ${cyan}%-2s${none} %-35s\n" "2." "Shadowsocks-2022"
        draw_divider
        printf "  ${yellow}%-2s${none} %-35s\n" "0." "返回主菜单"
        draw_divider
        read -r -p " 请输入选项 [0-2]: " choice || true
        case "$choice" in
            1) modify_vless_config || true ;;
            2) modify_ss_config || true ;;
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
    local vless_inbound current_port current_uuid current_domain private_key shortid current_network current_path current_host
    local port uuid domain regenerate new_shortid new_vless_inbound ss_inbound new_inbounds path host

    vless_inbound=$(jq '.inbounds[] | select(.protocol == "vless")' "$xray_config_path" 2>/dev/null || true)
    current_port=$(echo "$vless_inbound" | jq -r '.port')
    current_uuid=$(echo "$vless_inbound" | jq -r '.settings.clients[0].id')
    current_domain=$(echo "$vless_inbound" | jq -r '.streamSettings.realitySettings.serverNames[0]')
    private_key=$(echo "$vless_inbound" | jq -r '.streamSettings.realitySettings.privateKey')
    shortid=$(echo "$vless_inbound" | jq -r '.streamSettings.realitySettings.shortIds[0]')
    current_network=$(echo "$vless_inbound" | jq -r '.streamSettings.network // "tcp"')
    current_path=$(echo "$vless_inbound" | jq -r '.streamSettings.xhttpSettings.path // empty')
    current_host=$(echo "$vless_inbound" | jq -r '.streamSettings.xhttpSettings.host // empty')

    if [[ "$current_network" == "xhttp" ]]; then
        info "开始修改 VLESS-XHTTP-REALITY 配置..."
    else
        info "开始修改 VLESS-Reality 配置..."
    fi

    while true; do
        read -r -p " -> 新端口 (当前: ${current_port}，留空不改): " port || true
        [[ -z "$port" ]] && port="$current_port"
        if [[ "$port" == "$current_port" ]] || is_port_available "$port"; then
            break
        fi
        error "端口不可用，请重新输入。"
    done

    while true; do
        read -r -p " -> 新 UUID (当前: ${current_uuid}，留空不改): " uuid || true
        [[ -z "$uuid" ]] && uuid="$current_uuid"
        if is_valid_uuid "$uuid"; then
            break
        fi
        error "UUID 格式无效，请重新输入。"
    done

    while true; do
        read -r -p " -> 新 SNI 域名 (当前: ${current_domain}，留空不改): " domain || true
        [[ -z "$domain" ]] && domain="$current_domain"
        if is_valid_domain "$domain"; then
            break
        fi
        error "域名格式无效，请重新输入。"
    done

    if [[ "$current_network" == "xhttp" ]]; then
        while true; do
            read -r -p " -> 新 XHTTP 路径 (当前: ${current_path}，留空不改): " path || true
            [[ -z "$path" ]] && path="$current_path"
            [[ "$path" != /* ]] && path="/${path}"
            if [[ "$path" == /* && "$path" != *[[:space:]]* && "$path" != *\"* ]]; then
                break
            fi
            error "XHTTP 路径格式无效，请重新输入。"
        done

        read -r -p " -> 新 XHTTP Host (当前: ${current_host:-未设置}，留空不改；输入 none 清空): " host || true
        [[ -z "$host" ]] && host="$current_host"
        [[ "$host" == "none" ]] && host=""
        if [[ -n "$host" ]] && ! is_valid_domain "$host"; then
            error "Host 域名格式无效。"
            return 1
        fi
    fi

    read -r -p " -> 是否重新生成 shortId (当前: ${shortid}) [y/N]: " regenerate || true
    if [[ "$regenerate" =~ ^[yY]$ ]]; then
        new_shortid=$(generate_shortid)
    else
        new_shortid="$shortid"
    fi

    if [[ "$current_network" == "xhttp" ]]; then
        new_vless_inbound=$(build_xhttp_inbound "$port" "$uuid" "$domain" "$private_key" "$new_shortid" "$path" "$host")
    else
        new_vless_inbound=$(build_vless_inbound "$port" "$uuid" "$domain" "$private_key" "$new_shortid")
    fi
    ss_inbound=$(jq '.inbounds[] | select(.protocol == "shadowsocks")' "$xray_config_path" 2>/dev/null || true)
    new_inbounds="[$new_vless_inbound]"
    [[ -n "$ss_inbound" ]] && new_inbounds="[$new_vless_inbound, $ss_inbound]"

    write_config "$new_inbounds"
    restart_xray || return 1
    if [[ "$current_network" == "xhttp" ]]; then
        success "VLESS-XHTTP-REALITY 配置修改成功。"
    else
        success "VLESS-Reality 配置修改成功。"
    fi
    view_all_info
}

modify_ss_config() {
    info "开始修改 Shadowsocks-2022 配置..."
    local ss_inbound current_port current_password port password new_ss_inbound vless_inbound new_inbounds
    ss_inbound=$(jq '.inbounds[] | select(.protocol == "shadowsocks")' "$xray_config_path" 2>/dev/null || true)
    current_port=$(echo "$ss_inbound" | jq -r '.port')
    current_password=$(echo "$ss_inbound" | jq -r '.settings.password')

    while true; do
        read -r -p " -> 新端口 (当前: ${current_port}，留空不改): " port || true
        [[ -z "$port" ]] && port="$current_port"
        if [[ "$port" == "$current_port" ]] || is_port_available "$port"; then
            break
        fi
        error "端口不可用，请重新输入。"
    done

    prompt_for_ss_password password "$current_password" " -> 新密钥 (当前: ${current_password}，留空不改): "

    new_ss_inbound=$(build_ss_inbound "$port" "$password")
    vless_inbound=$(jq '.inbounds[] | select(.protocol == "vless")' "$xray_config_path" 2>/dev/null || true)
    new_inbounds="[$new_ss_inbound]"
    [[ -n "$vless_inbound" ]] && new_inbounds="[$vless_inbound, $new_ss_inbound]"

    write_config "$new_inbounds"
    restart_xray || return 1
    success "Shadowsocks-2022 配置修改成功。"
    view_all_info
}

restart_xray() {
    detect_xray_binary >/dev/null 2>&1 || true
    if [[ ! -x "$XRAY_BIN" ]]; then
        error "Xray 未安装。"
        return 1
    fi

    info "正在重启 Xray 服务..."
    systemctl daemon-reload >/dev/null 2>&1 || true
    if ! systemctl restart xray; then
        error "尝试重启 Xray 服务失败。"
        echo -e "\n${yellow}最近状态:${none}"
        systemctl status xray --no-pager -l | tail -n 8
        return 1
    fi

    sleep 2
    if systemctl is-active --quiet xray; then
        success "Xray 服务已成功重启。"
    else
        error "服务启动失败，请查看日志。"
        systemctl status xray --no-pager -l | tail -n 8
        return 1
    fi
}

view_xray_log() {
    detect_xray_binary >/dev/null 2>&1 || true
    if [[ ! -x "$XRAY_BIN" ]]; then
        error "Xray 未安装。"
        return 1
    fi

    info "正在显示 Xray 实时日志，按 Ctrl+C 退出。"
    journalctl -u xray -f --no-pager
}

view_all_info() {
    if [[ ! -f "$xray_config_path" ]]; then
        [[ "$is_quiet" = true ]] && return 0
        error "配置文件不存在。"
        return 1
    fi

    if [[ "$is_quiet" = false ]]; then
        clear
        echo -e "${cyan} Xray 配置与订阅信息${none}"
        draw_divider
    fi

    local ip host display_ip
    ip=$(get_public_ip || true)
    if [[ -z "$ip" ]]; then
        [[ "$is_quiet" = false ]] && error "无法获取公网 IP 地址。"
        return 1
    fi
    host=$(hostname)
    display_ip="$ip"
    [[ "$ip" == *:* ]] && display_ip="[$ip]"

    local -a links_array=()

    local vless_inbound
    vless_inbound=$(jq '.inbounds[] | select(.protocol == "vless")' "$xray_config_path" 2>/dev/null || true)
    if [[ -n "$vless_inbound" ]]; then
        local uuid port domain public_key shortid link_name_raw link_name_encoded vless_url network xhttp_path xhttp_host
        uuid=$(echo "$vless_inbound" | jq -r '.settings.clients[0].id')
        port=$(echo "$vless_inbound" | jq -r '.port')
        domain=$(echo "$vless_inbound" | jq -r '.streamSettings.realitySettings.serverNames[0]')
        public_key=$(get_reality_client_key_from_inbound "$vless_inbound" || true)
        shortid=$(echo "$vless_inbound" | jq -r '.streamSettings.realitySettings.shortIds[0]')
        network=$(echo "$vless_inbound" | jq -r '.streamSettings.network // "tcp"')
        xhttp_path=$(echo "$vless_inbound" | jq -r '.streamSettings.xhttpSettings.path // empty')
        xhttp_host=$(echo "$vless_inbound" | jq -r '.streamSettings.xhttpSettings.host // empty')

        if [[ "$network" == "xhttp" ]]; then
            link_name_raw="$host X-XHTTP-Reality"
            link_name_encoded=$(url_encode "$link_name_raw")
            vless_url="vless://${uuid}@${display_ip}:${port}?encryption=none&type=xhttp&security=reality&sni=${domain}&fp=chrome&pbk=${public_key}&sid=${shortid}&path=$(url_encode "$xhttp_path")"
            [[ -n "$xhttp_host" ]] && vless_url+="&host=$(url_encode "$xhttp_host")"
            vless_url+="#${link_name_encoded}"
            links_array+=("$vless_url")

            if [[ "$is_quiet" = false ]]; then
                echo -e "${green}[ VLESS-XHTTP-REALITY ]${none}"
                printf "  节点名称      ${cyan}%s${none}\n" "$link_name_raw"
                printf "  服务器地址    ${cyan}%s${none}\n" "$ip"
                printf "  端口          ${cyan}%s${none}\n" "$port"
                printf "  UUID          ${cyan}%s${none}\n" "$uuid"
                printf "  SNI           ${cyan}%s${none}\n" "$domain"
                printf "  PublicKey     ${cyan}%s${none}\n" "$public_key"
                printf "  ShortId       ${cyan}%s${none}\n" "$shortid"
                printf "  Path          ${cyan}%s${none}\n" "$xhttp_path"
                [[ -n "$xhttp_host" ]] && printf "  Host          ${cyan}%s${none}\n" "$xhttp_host"
            fi
        else
            link_name_raw="$host X-Reality"
            link_name_encoded=$(url_encode "$link_name_raw")
            vless_url="vless://${uuid}@${display_ip}:${port}?flow=xtls-rprx-vision&encryption=none&type=tcp&security=reality&sni=${domain}&fp=chrome&pbk=${public_key}&sid=${shortid}#${link_name_encoded}"
            links_array+=("$vless_url")

            if [[ "$is_quiet" = false ]]; then
                echo -e "${green}[ VLESS-Reality ]${none}"
                printf "  节点名称      ${cyan}%s${none}\n" "$link_name_raw"
                printf "  服务器地址    ${cyan}%s${none}\n" "$ip"
                printf "  端口          ${cyan}%s${none}\n" "$port"
                printf "  UUID          ${cyan}%s${none}\n" "$uuid"
                printf "  SNI           ${cyan}%s${none}\n" "$domain"
                printf "  PublicKey     ${cyan}%s${none}\n" "$public_key"
                printf "  ShortId       ${cyan}%s${none}\n" "$shortid"
            fi
        fi
    fi

    local ss_inbound
    ss_inbound=$(jq '.inbounds[] | select(.protocol == "shadowsocks")' "$xray_config_path" 2>/dev/null || true)
    if [[ -n "$ss_inbound" ]]; then
        local port method password link_name_raw link_name_encoded user_info_base64 ss_url
        port=$(echo "$ss_inbound" | jq -r '.port')
        method=$(echo "$ss_inbound" | jq -r '.settings.method')
        password=$(echo "$ss_inbound" | jq -r '.settings.password')
        link_name_raw="$host X-SS2022"
        link_name_encoded=$(url_encode "$link_name_raw")
        user_info_base64=$(base64_encode_inline "${method}:${password}")
        ss_url="ss://${user_info_base64}@${display_ip}:${port}#${link_name_encoded}"
        links_array+=("$ss_url")

        if [[ "$is_quiet" = false ]]; then
            echo ""
            echo -e "${green}[ Shadowsocks-2022 ]${none}"
            printf "  节点名称      ${cyan}%s${none}\n" "$link_name_raw"
            printf "  服务器地址    ${cyan}%s${none}\n" "$ip"
            printf "  端口          ${cyan}%s${none}\n" "$port"
            printf "  加密方式      ${cyan}%s${none}\n" "$method"
            printf "  密钥          ${cyan}%s${none}\n" "$password"
        fi
    fi

    if [[ ${#links_array[@]} -gt 0 ]]; then
        if [[ "$is_quiet" = true ]]; then
            printf '%s\n' "${links_array[@]}"
        else
            draw_divider
            printf '%s\n' "${links_array[@]}" > ~/xray_subscription_info.txt
            success "所有订阅链接已保存到: ~/xray_subscription_info.txt"
            echo -e "\n${yellow}--- 可直接导入客户端的链接 ---${none}\n"
            for link in "${links_array[@]}"; do
                echo -e "${cyan}${link}${none}\n"
            done
            draw_divider
        fi
    elif [[ "$is_quiet" = false ]]; then
        info "当前未安装任何协议，暂无订阅信息可显示。"
    fi
}

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
        printf "  ${blue}%-2s${none} %-35s\n" "9." "BBR / 网络智能优化"
        printf "  ${yellow}%-2s${none} %-35s\n" "0." "退出脚本"
        draw_divider

        read -r -p " 请输入选项 [0-9]: " choice || true
        local needs_pause=true

        case "$choice" in
            1) install_menu || true ;;
            2) update_xray || true ;;
            3) uninstall_xray || true ;;
            4) modify_config_menu || true ;;
            5) restart_xray || true ;;
            6) view_xray_log || true; needs_pause=false ;;
            7) view_all_info || true ;;
            8) update_script || true ;;
            9) bbr_menu || true; needs_pause=false ;;
            0) success "感谢使用。"; exit 0 ;;
            *) error "无效选项，请输入 0 到 9。" ;;
        esac

        if [[ "$needs_pause" = true ]]; then
            press_any_key_to_continue
        fi
    done
}

main() {
    pre_check
    detect_xray_binary >/dev/null 2>&1 || true
    install_self
    main_menu
}

main "$@"