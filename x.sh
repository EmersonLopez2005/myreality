#!/usr/bin/env bash

# ==============================================================================
# Xray VLESS-Reality & Shadowsocks 2022 管理脚本 (x.sh)
# - 交互逻辑重构 x.sh
# - 移除旧版 x.sh 的“分流/YouTube/上游SS”等功能，仅保留：Reality + SS2022
# - 保留快捷键入口：alias xray='bash /root/x.sh'
# ==============================================================================

set -euo pipefail

# --- 全局常量 ---
readonly SCRIPT_VERSION="x.sh v3.0.3"
readonly SCRIPT_PATH="/root/x.sh"
readonly SCRIPT_UPDATE_URL="https://raw.githubusercontent.com/EmersonLopez2005/myreality/main/x.sh"

readonly xray_config_path="/usr/local/etc/xray/config.json"
readonly xray_binary_path="/usr/local/bin/xray"
readonly xray_install_script_url="https://github.com/XTLS/Xray-install/raw/main/install-release.sh"

# --- BBR / 网络优化 ---
readonly BBR_CONF_FILE="/etc/sysctl.d/99-bbr.conf"
readonly BBR_STATE_DIR="/var/lib/xray-menu"
readonly BBR_STATE_FILE="${BBR_STATE_DIR}/bbr-preapply.state"
readonly BBR_MODULE_VERSION="bbr-module v1.1.0"

# --- 快捷命令 (alias/备用命令) ---
readonly MENU_BIN_SYMLINK="/usr/local/bin/xray-menu"

# --- 颜色定义 ---
readonly red='\e[91m' green='\e[92m' yellow='\e[93m'
readonly magenta='\e[95m' cyan='\e[96m' blue='\e[94m' none='\e[0m'

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

    # 2) 写入 alias（仅写一次）：根据当前 shell 写入 bashrc/zshrc
    #    注意：alias 需要重新打开终端或 source 对应 rc 文件才能生效。
    local rc_file=""
    case "${SHELL:-}" in
        */zsh) rc_file="$HOME/.zshrc" ;;
        *)     rc_file="$HOME/.bashrc" ;;
    esac
    if [[ -n "$rc_file" ]]; then
        if ! grep -qs "alias xray='bash ${SCRIPT_PATH}'" "$rc_file" 2>/dev/null; then
            echo "alias xray='bash ${SCRIPT_PATH}'" >> "$rc_file"
        fi
    fi

    # 3) 安装一个备用命令：/usr/local/bin/xray-menu
    #    这样即使 alias 没加载，你也能直接输入 xray-menu 进入菜单。
    mkdir -p "$(dirname "$MENU_BIN_SYMLINK")"
    ln -sf "$SCRIPT_PATH" "$MENU_BIN_SYMLINK" 2>/dev/null || true
    chmod +x "$MENU_BIN_SYMLINK" 2>/dev/null || true

    # 4) 尝试给当前 shell 临时生效（仅本次会话；不保证所有环境有效）
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

warning() { [[ "$is_quiet" = false ]] && echo -e "\n${yellow}[!] $1${none}\n" >&2; }

warning_stderr() {
    local saved_quiet="$is_quiet"
    is_quiet=false
    warning "$1" >&2
    is_quiet="$saved_quiet"
}

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
    # 重要：不要用 `command -v xray`，因为它可能返回 alias/function（例如 alias xray='bash /root/x.sh'）
    # 这里用 `type -P` 只取真实二进制路径。
    local real
    real=$(type -P xray 2>/dev/null || true)
    if [[ -n "$real" ]]; then
        XRAY_BIN="$real"
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
    # 某些环境下 `xray version` 可能会输出版本但返回非 0。
    # 在 set -e 下会导致脚本提前退出，或版本字符串夹带换行/“未知”。
    # 这里忽略返回码，并做清洗。
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

    local out private_key reality_client_key
    out=$("$XRAY_BIN" x25519 2>&1 || true)

    # 兼容多种输出格式（不同 xray 版本可能返回不同字段名）：
    # - Private key: xxx
    # - Public key:  xxx
    # - PrivateKey: xxx
    # - PublicKey:  xxx
    # - Hash32:     xxx   (部分版本用 Hash32 作为可用于 Reality 的公钥/指纹字段)
    private_key=$(echo "$out" | awk -F':' 'tolower($1) ~ /private/ {gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2; exit}')

    # publicKey 优先，其次 Hash32
    reality_client_key=$(echo "$out" | awk -F':' 'tolower($1) ~ /(password|public[[:space:]]*key)/ {gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2; exit}')

    if [[ -z "$private_key" || -z "$reality_client_key" ]]; then
        error "生成 Reality 密钥对失败：无法从 xray x25519 输出解析密钥。"
        {
            echo -e "${yellow}--- xray x25519 原始输出（便于排查）---${none}"
            echo "$out" | sed 's/^/  /'
            echo -e "${yellow}----------------------------------------${none}"
        } >&2
        return 1
    fi

    printf "%s\n%s\n" "$private_key" "$reality_client_key"
}

# --- Reality shortId (shortkey) 随机生成 ---
derive_reality_client_key_from_private_key() {
    local private_key="$1"
    detect_xray_binary >/dev/null 2>&1 || true
    [[ -z "$private_key" || ! -x "$XRAY_BIN" ]] && return 1

    local out reality_client_key
    out=$("$XRAY_BIN" x25519 -i "$private_key" 2>&1 || true)
    reality_client_key=$(echo "$out" | awk -F':' 'tolower($1) ~ /(password|public[[:space:]]*key)/ {gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2; exit}')
    [[ -n "$reality_client_key" ]] || return 1
    printf "%s\n" "$reality_client_key"
}

get_reality_client_key_from_inbound() {
    local inbound_json="$1"
    local private_key stored_key

    private_key=$(echo "$inbound_json" | jq -r '.streamSettings.realitySettings.privateKey // empty')
    if [[ -n "$private_key" ]]; then
        stored_key=$(derive_reality_client_key_from_private_key "$private_key" || true)
        if [[ -n "$stored_key" ]]; then
            printf "%s\n" "$stored_key"
            return 0
        fi
    fi

    stored_key=$(echo "$inbound_json" | jq -r '.streamSettings.realitySettings.password // .streamSettings.realitySettings.publicKey // empty')
    [[ -n "$stored_key" ]] || return 1
    printf "%s\n" "$stored_key"
}

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
    openssl rand -base64 16 | tr -d '\r\n'
}

base64_encode_inline() {
    printf '%s' "$1" | openssl base64 -A
}

is_valid_ss2022_password() {
    local password="$1" decoded_len rc=0
    decoded_len=$(printf '%s' "$password" | openssl base64 -d -A 2>/dev/null | wc -c | tr -d '[:space:]') || rc=$?
    [[ "$rc" -eq 0 && "$decoded_len" == "16" ]]
}

prompt_for_ss_password() {
    local -n p_pass="$1"
    local current_pass="${2:-}"
    local prompt_text="$3"

    while true; do
        read -r -p "$prompt_text" p_pass || true
        if [[ -z "$p_pass" ]]; then
            if [[ -n "$current_pass" ]]; then
                p_pass="$current_pass"
                return 0
            fi
            p_pass=$(generate_ss_key)
            info "宸蹭负鎮ㄧ敓鎴愰殢鏈哄瘑閽? ${cyan}${p_pass}${none}"
            return 0
        fi

        if is_valid_ss2022_password "$p_pass"; then
            return 0
        fi

        error "Invalid SS2022 key. Enter a 16-byte Base64 key, or leave it blank to auto-generate one."
    done
}

# ==============================================================================
# BBR / Linux 网络参数智能优化（融合 script.sh 的逻辑，增加可回滚/可查看状态）
# ==============================================================================

# --- BBR 全局变量（统一使用 BBR_ 前缀，避免与主脚本变量冲突） ---
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

# 运行时选择的优化策略（均衡/高并发/省内存）
BBR_PROFILE="balanced"
BBR_TW_REUSE="1"

bbr_get_system_info() {
    BBR_TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}' | tr -d '\r')
    BBR_CPU_CORES=$(nproc | tr -d '\r')

    if command -v systemd-detect-virt >/dev/null 2>&1; then
        BBR_VIRT_TYPE=$(systemd-detect-virt)
    elif grep -q -i "hypervisor" /proc/cpuinfo; then
        BBR_VIRT_TYPE="KVM/VMware"
    else
        BBR_VIRT_TYPE="Physical/Unknown"
    fi

    bbr_calculate_parameters
}

bbr_calculate_parameters() {
    # 基础连接数设置 - 代理服务器通常需要更多连接跟踪
    if [[ "${BBR_TOTAL_MEM:-0}" -le 512 ]]; then
        BBR_VM_TIER="entry-level <=512MB"
        BBR_RMEM_MAX="16777216"   # 16MB
        BBR_WMEM_MAX="16777216"
        BBR_TCP_MEM_MAX="16777216"
        BBR_SOMAXCONN="4096"
        BBR_FILE_MAX="65535"
        BBR_CONNTRACK_MAX="65536"
    elif [[ "${BBR_TOTAL_MEM:-0}" -le 1024 ]]; then
        BBR_VM_TIER="basic 1GB"
        BBR_RMEM_MAX="33554432"   # 32MB
        BBR_WMEM_MAX="33554432"
        BBR_TCP_MEM_MAX="33554432"
        BBR_SOMAXCONN="16384"
        BBR_FILE_MAX="524288"
        BBR_CONNTRACK_MAX="262144"
    elif [[ "${BBR_TOTAL_MEM:-0}" -le 4096 ]]; then
        BBR_VM_TIER="advanced 2GB-4GB"
        BBR_RMEM_MAX="67108864"   # 64MB
        BBR_WMEM_MAX="67108864"
        BBR_TCP_MEM_MAX="67108864"
        BBR_SOMAXCONN="32768"
        BBR_FILE_MAX="1048576"
        BBR_CONNTRACK_MAX="524288"
    else
        BBR_VM_TIER="professional >4GB"
        # Limit per-socket buffer growth to avoid a few connections consuming all RAM.
        BBR_RMEM_MAX="134217728"  # 128MB
        BBR_WMEM_MAX="134217728"
        BBR_TCP_MEM_MAX="134217728"
        BBR_SOMAXCONN="65535"
        BBR_FILE_MAX="2097152"
        BBR_CONNTRACK_MAX="1048576" # 100万连接通常足够
    fi
}

bbr_pre_flight_checks() {
    [[ $(id -u) -ne 0 ]] && error "❌ 错误: 必须 root 权限。" && return 1
    # 尝试加载必要内核模块（失败不致命：容器环境或精简内核可能不允许）
    modprobe nf_conntrack >/dev/null 2>&1 || true
    modprobe tcp_bbr >/dev/null 2>&1 || true
    return 0
}

bbr_add_conf() {
    # 用法: bbr_add_conf <file> <key> <value> <comment>
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
        # 保留最近 3 个备份
        ls -t "$BBR_CONF_FILE.bak_"* 2>/dev/null | tail -n +4 | xargs -r rm
    fi
}

bbr_extract_keys_from_file() {
    local file="$1"
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        if [[ "$line" =~ ^[[:space:]]*([a-zA-Z0-9_.]+)[[:space:]]*= ]]; then
            printf "%s\n" "${BASH_REMATCH[1]}"
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
            printf "%s = %s\n" "$key" "$value" >> "$tmp"
        else
            printf "# missing %s\n" "$key" >> "$tmp"
        fi
    done < <(bbr_extract_keys_from_file "$conf_file")

    chmod 600 "$tmp" 2>/dev/null || true
    mv -f "$tmp" "$BBR_STATE_FILE"
}

bbr_restore_runtime_state() {
    local state_file="$1"
    [[ -f "$state_file" ]] || return 0

    local restored=0 failed=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        if [[ "$line" =~ ^[[:space:]]*([a-zA-Z0-9_.]+)[[:space:]]*=[[:space:]]*(.+)[[:space:]]*$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            if sysctl -w "${key}=${value}" >/dev/null 2>&1; then
                ((restored++))
            else
                ((failed++))
            fi
        fi
    done < "$state_file"

    echo "$restored|$failed"
}

bbr_clamp_int() {
    # bbr_clamp_int <val> <min> <max>
    local v="$1" min="$2" max="$3"
    [[ -z "$v" ]] && v=0
    if (( v < min )); then v="$min"; fi
    if (( v > max )); then v="$max"; fi
    echo "$v"
}

bbr_scale_int() {
    # bbr_scale_int <val> <num> <den>
    local v="$1" num="$2" den="$3"
    if [[ -z "$v" || -z "$num" || -z "$den" || "$den" == "0" ]]; then
        echo "$v"
        return
    fi
    echo $(( v * num / den ))
}

bbr_apply_profile_tuning() {
    # 根据选择的 profile 对基础参数做倍率调整，并做上下限保护。
    # profile:
    #   balanced        默认均衡
    #   high_concurrency 偏高并发（更多连接/队列/句柄/conntrack）
    #   memory_saving    偏省内存（更保守的 conntrack/缓冲区/队列）
    local profile="$1"

    case "$profile" in
        high_concurrency)
            # 连接/队列/句柄上调（但仍限制上限，避免夸张参数）
            BBR_SOMAXCONN=$(bbr_scale_int "$BBR_SOMAXCONN" 2 1)
            BBR_FILE_MAX=$(bbr_scale_int "$BBR_FILE_MAX" 2 1)
            BBR_CONNTRACK_MAX=$(bbr_scale_int "$BBR_CONNTRACK_MAX" 2 1)

            # 缓冲区轻微上调（避免极端占用内存）
            BBR_RMEM_MAX=$(bbr_scale_int "$BBR_RMEM_MAX" 3 2)
            BBR_WMEM_MAX=$(bbr_scale_int "$BBR_WMEM_MAX" 3 2)
            BBR_TCP_MEM_MAX=$(bbr_scale_int "$BBR_TCP_MEM_MAX" 3 2)
            ;;
        memory_saving)
            # 更保守：减少 conntrack / 队列 / 缓冲区，降低内存占用风险
            BBR_SOMAXCONN=$(bbr_scale_int "$BBR_SOMAXCONN" 1 2)
            BBR_FILE_MAX=$(bbr_scale_int "$BBR_FILE_MAX" 1 2)
            BBR_CONNTRACK_MAX=$(bbr_scale_int "$BBR_CONNTRACK_MAX" 1 2)
            BBR_RMEM_MAX=$(bbr_scale_int "$BBR_RMEM_MAX" 1 2)
            BBR_WMEM_MAX=$(bbr_scale_int "$BBR_WMEM_MAX" 1 2)
            BBR_TCP_MEM_MAX=$(bbr_scale_int "$BBR_TCP_MEM_MAX" 1 2)
            ;;
        *)
            : # balanced
            ;;
    esac

    # 下限保护：太小会影响基本可用性
    BBR_SOMAXCONN=$(bbr_clamp_int "$BBR_SOMAXCONN" 4096 262144)
    BBR_FILE_MAX=$(bbr_clamp_int "$BBR_FILE_MAX" 65535 8388608)
    BBR_CONNTRACK_MAX=$(bbr_clamp_int "$BBR_CONNTRACK_MAX" 65536 2097152)

    # 缓冲区保护：过大可能导致单连接/少量连接吃掉太多内存
    BBR_RMEM_MAX=$(bbr_clamp_int "$BBR_RMEM_MAX" 8388608 268435456)   # 8MB - 256MB
    BBR_WMEM_MAX=$(bbr_clamp_int "$BBR_WMEM_MAX" 8388608 268435456)
    BBR_TCP_MEM_MAX=$(bbr_clamp_int "$BBR_TCP_MEM_MAX" 8388608 268435456)
}

bbr_profile_label() {
    case "$1" in
        high_concurrency) echo "high-concurrency" ;;
        memory_saving) echo "memory-saving" ;;
        *) echo "balanced" ;;
    esac
}

bbr_prompt_profile() {
    local choice
    echo -e "${cyan}Choose optimization profile${none}"
    draw_divider
    printf "  ${green}%-2s${none} %-35s\n" "1." "balanced (recommended)"
    printf "  ${yellow}%-2s${none} %-35s\n" "2." "high concurrency"
    printf "  ${magenta}%-2s${none} %-35s\n" "3." "memory saving"
    draw_divider
    read -r -p " Select [1-3, default 1]: " choice || true
    case "$choice" in
        2) BBR_PROFILE="high_concurrency" ;;
        3) BBR_PROFILE="memory_saving" ;;
        *) BBR_PROFILE="balanced" ;;
    esac

    read -r -p "  Enable tcp_tw_reuse? [Y/n]: " choice || true
    if [[ "$choice" =~ ^[nN]$ ]]; then
        BBR_TW_REUSE="0"
    else
        BBR_TW_REUSE="1"
    fi
}

bbr_build_conf_file() {
    # 原子写入：生成临时文件，写完后由调用方 mv 覆盖。
    # 输出: 临时文件路径（echo）
    local profile="$1" tw_reuse="$2"
    bbr_get_system_info
    bbr_apply_profile_tuning "$profile"

    local tmp
    tmp=$(mktemp "${BBR_CONF_FILE}.tmp.XXXXXX")

    cat >> "$tmp" << EOF
# ==========================================================
# Linux Network Tuning (Proxy/Forwarding Optimized)
# 生成时间: $(date)
# 硬件环境: ${BBR_TOTAL_MEM}MB RAM, ${BBR_CPU_CORES} CPU
# 虚拟化  : ${BBR_VIRT_TYPE}
# 档位    : ${BBR_VM_TIER}
# 模式    : $(bbr_profile_label "$profile") (${profile})
# 模块版本: ${BBR_MODULE_VERSION}
# ==========================================================
EOF

    # 0) 能力探测（更友好）
    local available_cc
    available_cc=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)
    if ! echo " $available_cc " | grep -q " bbr "; then
        warning "系统未检测到可用的 BBR 拥塞算法（available: ${available_cc:-未知}）。仍会写入配置，但可能不会生效。"
    fi

    # 1) BBR 与队列算法
    bbr_add_conf "$tmp" "net.core.default_qdisc" "fq" "FQ 队列算法 (BBR 常用搭配)"
    bbr_add_conf "$tmp" "net.ipv4.tcp_congestion_control" "bbr" "开启 BBR"

    # 2) 缓冲区优化 (TCP & UDP)
    bbr_add_conf "$tmp" "net.core.rmem_max" "$BBR_RMEM_MAX" "系统最大接收缓存"
    bbr_add_conf "$tmp" "net.core.wmem_max" "$BBR_WMEM_MAX" "系统最大发送缓存"
    bbr_add_conf "$tmp" "net.core.rmem_default" "262144" "默认接收缓存 (256k)"
    bbr_add_conf "$tmp" "net.core.wmem_default" "262144" "默认发送缓存 (256k)"
    bbr_add_conf "$tmp" "net.ipv4.tcp_rmem" "8192 262144 $BBR_TCP_MEM_MAX" "TCP读缓存 (min default max)"
    bbr_add_conf "$tmp" "net.ipv4.tcp_wmem" "8192 262144 $BBR_TCP_MEM_MAX" "TCP写缓存 (min default max)"
    bbr_add_conf "$tmp" "net.ipv4.udp_rmem_min" "16384" "UDP读缓存下限 (优化QUIC)"
    bbr_add_conf "$tmp" "net.ipv4.udp_wmem_min" "16384" "UDP写缓存下限 (优化QUIC)"

    # 3) 连接与队列上限
    bbr_add_conf "$tmp" "net.core.somaxconn" "$BBR_SOMAXCONN" "最大监听队列"
    bbr_add_conf "$tmp" "net.core.netdev_max_backlog" "$BBR_SOMAXCONN" "网卡积压队列"
    bbr_add_conf "$tmp" "net.ipv4.tcp_max_syn_backlog" "$BBR_SOMAXCONN" "SYN半连接队列"
    bbr_add_conf "$tmp" "net.ipv4.tcp_notsent_lowat" "16384" "降低未发送数据阈值 (降低延迟)"

    # 4) TIME_WAIT 与 端口复用
    bbr_add_conf "$tmp" "net.ipv4.tcp_tw_reuse" "$tw_reuse" "开启 TIME_WAIT 复用 (高并发优化，可按需关闭)"
    bbr_add_conf "$tmp" "net.ipv4.tcp_timestamps" "1" "开启时间戳 (配合 reuse)"
    bbr_add_conf "$tmp" "net.ipv4.tcp_fin_timeout" "30" "缩短 FIN_WAIT 时间"
    bbr_add_conf "$tmp" "net.ipv4.ip_local_port_range" "10000 65535" "扩大本地端口范围"
    bbr_add_conf "$tmp" "net.ipv4.tcp_max_tw_buckets" "500000" "允许更多 TIME_WAIT socket"

    # 5) TCP Keepalive
    bbr_add_conf "$tmp" "net.ipv4.tcp_keepalive_time" "600" "TCP保活时间 (10分钟)"
    bbr_add_conf "$tmp" "net.ipv4.tcp_keepalive_intvl" "15" "探测间隔"
    bbr_add_conf "$tmp" "net.ipv4.tcp_keepalive_probes" "5" "探测次数"

    # 6) Conntrack
    bbr_add_conf "$tmp" "net.netfilter.nf_conntrack_max" "$BBR_CONNTRACK_MAX" "最大连接跟踪数 (过大可能吃内存)"
    bbr_add_conf "$tmp" "net.netfilter.nf_conntrack_tcp_timeout_established" "7200" "连接跟踪超时 (2小时)"
    bbr_add_conf "$tmp" "net.netfilter.nf_conntrack_tcp_timeout_time_wait" "120" "减少 TIME_WAIT 跟踪时间"

    # 7) 其他系统级优化
    bbr_add_conf "$tmp" "fs.file-max" "$BBR_FILE_MAX" "最大文件句柄"
    bbr_add_conf "$tmp" "vm.swappiness" "10" "减少 Swap 使用"
    bbr_add_conf "$tmp" "net.ipv4.tcp_mtu_probing" "1" "开启 MTU 探测"
    bbr_add_conf "$tmp" "net.ipv4.tcp_syncookies" "1" "防 SYN Flood"

    echo "$tmp"
}

bbr_apply_sysctl_from_file() {
    # 逐项应用并汇总结果，避免某个参数失败导致全部失败
    local file="$1"
    local ok=0 missing=0 denied=0 invalid=0
    local -a failed_lines=()
    local -a missing_keys=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        if [[ "$line" =~ ^[[:space:]]*([a-zA-Z0-9_.]+)[[:space:]]*=[[:space:]]*(.+)[[:space:]]*$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            local out rc

            out=$(sysctl -w "${key}=${value}" 2>&1) || rc=$?
            rc=${rc:-0}

            if [[ "$rc" -eq 0 ]]; then
                ((ok++))
            else
                # 分类统计（尽力而为）
                if echo "$out" | grep -qiE "No such file|not found"; then
                    ((missing++))
                    missing_keys+=("$key")
                elif echo "$out" | grep -qiE "permission denied|Operation not permitted"; then
                    ((denied++))
                elif echo "$out" | grep -qiE "Invalid argument"; then
                    ((invalid++))
                else
                    ((invalid++))
                fi
                failed_lines+=("$key=$value -> $out")
            fi
        fi
    done < "$file"

    echo "$ok|$missing|$denied|$invalid"
    # 将失败详情写到 stderr（交互模式下也能看到）
    if ((${#failed_lines[@]} > 0)); then
        {
            echo -e "\n${yellow}以下参数未能成功应用（不一定影响核心功能）：${none}"
            for l in "${failed_lines[@]}"; do
                echo "  - $l"
            done
        } >&2
    fi
}

bbr_detect_primary_iface() {
    ip route 2>/dev/null | awk '/default/ {print $5; exit}'
}

bbr_apply_optimizations() {
    # 新逻辑：原子写入 + 逐项 sysctl 应用 + 汇总失败项 + 支持 profile
    local profile="$1" tw_reuse="$2"

    bbr_get_system_info
    bbr_apply_profile_tuning "$profile"

    [[ "$is_quiet" = false ]] && {
        echo -e "${cyan}>>> 系统信息检测：${none}"
        echo -e "内存大小   : ${yellow}${BBR_TOTAL_MEM}MB${none}"
        echo -e "CPU核心数  : ${yellow}${BBR_CPU_CORES}${none}"
        echo -e "虚拟化类型 : ${yellow}${BBR_VIRT_TYPE}${none}"
        echo -e "目标档位   : ${yellow}${BBR_VM_TIER}${none}"
        echo -e "优化模式   : ${yellow}$(bbr_profile_label "$profile")${none}"
    }

    info "生成并应用网络优化配置 (${BBR_VM_TIER} / $(bbr_profile_label "$profile"))..."
    mkdir -p "$(dirname "$BBR_CONF_FILE")"

    # 原子写：先写 tmp，再 mv 覆盖
    local tmp
    tmp=$(bbr_build_conf_file "$profile" "$tw_reuse")
    bbr_capture_runtime_state "$tmp"
    chmod 644 "$tmp" 2>/dev/null || true
    mv -f "$tmp" "$BBR_CONF_FILE"

    info "正在逐项应用 sysctl 参数（可跳过不支持的键）..."
    local summary ok missing denied invalid cc qdisc reuse iface tcq
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

    success "网络优化完成！"
    echo -e "已应用: ${green}${ok}${none} 项 | 不存在: ${yellow}${missing}${none} 项 | 权限/受限: ${yellow}${denied}${none} 项 | 其它失败: ${yellow}${invalid}${none} 项"
    echo -e "拥塞控制: ${cyan}${cc}${none} | 队列算法: ${cyan}${qdisc}${none} | tcp_tw_reuse: ${cyan}${reuse}${none}"
    [[ -n "$tcq" ]] && echo -e "网卡队列(tc): ${cyan}${tcq}${none}"
}

bbr_apply_and_verify() {
    # 兼容旧调用点（保留函数名），实际逻辑已在 bbr_apply_optimizations 中完成
    :
}

bbr_uninstall() {
    if [[ ! -f "$BBR_CONF_FILE" ]]; then
        warning "未发现 $BBR_CONF_FILE，无需卸载。"
        return 0
    fi

    info "正在卸载/回滚 BBR 网络优化配置..."
    mv -f "$BBR_CONF_FILE" "$BBR_CONF_FILE.removed_$(date +%F_%H-%M-%S)"
    # 重载所有 sysctl.d（确保删除后生效）
    sysctl --system >/dev/null 2>&1 || true
    success "已移除优化配置（已保留 removed 备份）。"
}

bbr_uninstall() {
    if [[ ! -f "$BBR_CONF_FILE" ]]; then
        warning "未发现 $BBR_CONF_FILE，无需卸载。"
        return 0
    fi

    info "正在卸载/回滚 BBR 网络优化配置..."
    mv -f "$BBR_CONF_FILE" "$BBR_CONF_FILE.removed_$(date +%F_%H-%M-%S)"

    local restore_summary restored failed
    sysctl --system >/dev/null 2>&1 || true
    if [[ -f "$BBR_STATE_FILE" ]]; then
        restore_summary=$(bbr_restore_runtime_state "$BBR_STATE_FILE")
        restored=${restore_summary%%|*}
        failed=${restore_summary#*|}
        rm -f "$BBR_STATE_FILE"
        success "已移除优化配置，并尝试恢复 ${restored} 项原始 sysctl 值。"
        if [[ "$failed" != "0" ]]; then
            warning "仍有 ${failed} 项 sysctl 未能恢复到应用前状态，如有异常可重启服务器。"
        fi
    else
        success "已移除优化配置（未找到原始 sysctl 备份，如有残留可重启服务器）。"
    fi
}

bbr_status() {
    draw_menu_header
    echo -e "${cyan} BBR/网络优化状态${none}"
    draw_divider
    printf "  %-24s %s\n" "配置文件" "${BBR_CONF_FILE}"
    if [[ -f "$BBR_CONF_FILE" ]]; then
        printf "  %-24s %b\n" "是否存在" "${green}是${none}"
    else
        printf "  %-24s %b\n" "是否存在" "${red}否${none}"
    fi

    local cc qdisc available
    cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "未知")
    qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "未知")
    available=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || echo "未知")

    printf "  %-24s %s\n" "当前拥塞控制" "${cc}"
    printf "  %-24s %s\n" "可用拥塞控制" "${available}"
    printf "  %-24s %s\n" "当前 qdisc" "${qdisc}"

    # 展示用户常用的“BBR 是否生效”排查项（可选项，尽力输出）
    echo ""
    echo "  常用验证（可选）："

    if command -v lsmod >/dev/null 2>&1; then
        local mod_line
        # 注意：部分容器/精简系统中 lsmod 可能返回非 0（/proc/modules 不可用）。
        # 在 set -e 环境下这会导致函数提前退出，所以这里用 || true 保底。
        mod_line=$(lsmod 2>/dev/null | awk '$1=="tcp_bbr"{print; exit}' || true)
        if [[ -n "$mod_line" ]]; then
            printf "  %-24s %s\n" "tcp_bbr 模块" "已加载 (lsmod 可见)"
        else
            printf "  %-24s %s\n" "tcp_bbr 模块" "lsmod 未显示（可能未加载/或已编译进内核）"
        fi
    else
        printf "  %-24s %s\n" "tcp_bbr 模块" "无法检查（系统缺少 lsmod）"
    fi

    local iface tcq
    iface=$(bbr_detect_primary_iface || true)
    if [[ -n "$iface" ]]; then
        printf "  %-24s %s\n" "默认出口网卡" "${iface}"
        if command -v tc >/dev/null 2>&1; then
            tcq=$(tc qdisc show dev "$iface" 2>/dev/null | head -n 1 || true)
            [[ -n "$tcq" ]] && printf "  %-24s %s\n" "tc qdisc(网卡)" "${tcq}"
        else
            printf "  %-24s %s\n" "tc qdisc(网卡)" "无法检查（系统缺少 tc 命令）"
        fi
    else
        printf "  %-24s %s\n" "默认出口网卡" "无法识别（ip route 无 default）"
    fi
    echo ""
    echo "  关键参数："
    sysctl net.ipv4.tcp_tw_reuse net.ipv4.tcp_timestamps net.core.somaxconn 2>/dev/null | sed 's/^/  /' || true
    draw_divider
}

bbr_menu() {
    while true; do
        draw_menu_header
        echo -e "${cyan} BBR / 网络智能优化 (${BBR_MODULE_VERSION})${none}"
        draw_divider
        printf "  ${green}%-2s${none} %-35s\n" "1." "一键开启/智能优化 (写入并应用 sysctl)"
        printf "  ${yellow}%-2s${none} %-35s\n" "2." "查看当前状态/是否生效"
        printf "  ${red}%-2s${none} %-35s\n" "3." "卸载/回滚 (移除配置文件)"
        draw_divider
        printf "  ${magenta}%-2s${none} %-35s\n" "0." "返回主菜单"
        draw_divider
        read -r -p " 请输入选项 [0-3]: " choice || true
        case "$choice" in
            1)
                bbr_pre_flight_checks || { press_any_key_to_continue; continue; }
                bbr_manage_backups
                bbr_prompt_profile
                bbr_apply_optimizations "$BBR_PROFILE" "$BBR_TW_REUSE"
                press_any_key_to_continue
                ;;
            2)
                bbr_status
                press_any_key_to_continue
                ;;
            3)
                bbr_uninstall
                press_any_key_to_continue
                ;;
            0) return ;;
            *) error "无效选项。"; press_any_key_to_continue ;;
        esac
    done
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
                    "password": $public_key,
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
    # 同样忽略 version 的返回码，避免 set -e 直接退出
    current_version=$("$XRAY_BIN" version 2>/dev/null | head -n 1 | awk '{print $2}' || true)
    current_version=$(echo -n "$current_version" | tr -d '\r\n')
    [[ -z "$current_version" ]] && current_version="未知"

    # 获取最新版本可能因为网络/DNS/GitHub API 限流而失败。
    # 失败时给出明确提示，并允许用户选择“仍然尝试执行官方更新脚本”。
    latest_version=$(curl -fsSL --max-time 8 https://api.github.com/repos/XTLS/Xray-core/releases/latest 2>/dev/null \
        | jq -r '.tag_name' 2>/dev/null \
        | sed 's/^v//' || true)

    if [[ -z "$latest_version" || "$latest_version" == "null" ]]; then
        warning "获取最新版本号失败（可能是网络/DNS 或 GitHub API 限流）。"
        echo -e "  当前版本: ${cyan}${current_version}${none}"
        read -r -p "  是否仍然尝试执行官方更新脚本？[Y/n]: " yn || true
        if [[ "$yn" =~ ^[nN]$ ]]; then
            info "已取消更新。"
            return 0
        fi
        info "开始执行官方更新脚本（不依赖 GitHub API 版本号查询）..."
        run_core_install
        restart_xray || return 1
        success "Xray 更新流程已执行完成（版本号请回到主菜单查看）。"
        return 0
    fi
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
    public_key=$(get_reality_client_key_from_inbound "$vless_inbound" || true)
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
        public_key=$(get_reality_client_key_from_inbound "$vless_inbound" || true)
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
            printf "    %s: ${cyan}%s${none}\n" "Password(pbk)" "$public_key"
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
is_port_available() {
    local port="$1"
    is_valid_port "$port" || return 1

    local tcp_in_use=false udp_in_use=false
    if ss -H -ltn 2>/dev/null | awk -v p=":$port" '$4 ~ p"$" {found=1; exit} END{exit !found}'; then tcp_in_use=true; fi
    if ss -H -lun 2>/dev/null | awk -v p=":$port" '($4 ~ p"$") || ($5 ~ p"$") {found=1; exit} END{exit !found}'; then udp_in_use=true; fi

    if [[ "$tcp_in_use" = true || "$udp_in_use" = true ]]; then
        local proto="TCP/UDP"
        [[ "$tcp_in_use" = true && "$udp_in_use" = false ]] && proto="TCP"
        [[ "$tcp_in_use" = false && "$udp_in_use" = true ]] && proto="UDP"
        warning "端口 $port 已被 ${proto} 占用，建议选择其他端口"
        return 1
    fi

    return 0
}

is_valid_domain() {
    local domain="$1"
    [[ "$domain" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]]
}

prompt_for_ss_config() {
    local -n p_port="$1" p_pass="$2"
    local default_port="${3:-8388}"

    while true; do
        read -r -p "$(echo -e " -> 请输入 Shadowsocks 端口 (默认: ${cyan}${default_port}${none}): ")" p_port || true
        [[ -z "$p_port" ]] && p_port="$default_port"
        if is_port_available "$p_port"; then break; fi
    done
    info "Shadowsocks 端口将使用 ${cyan}${p_port}${none}"

    prompt_for_ss_password p_pass "" "$(echo -e " -> 请输入 Shadowsocks 密钥 (留空将自动生成): ")"
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

    prompt_for_ss_password password "$current_password" "$(echo -e " -> 新密钥 (当前: ${cyan}${current_password}${none}, 留空不改): ")"

    new_ss_inbound=$(build_ss_inbound "$port" "$password")
    vless_inbound=$(jq '.inbounds[] | select(.protocol == "vless")' "$xray_config_path" 2>/dev/null || true)
    new_inbounds="[$new_ss_inbound]"
    [[ -n "$vless_inbound" ]] && new_inbounds="[$vless_inbound, $new_ss_inbound]"

    write_config "$new_inbounds"
    if ! restart_xray; then return 1; fi
    success "配置修改成功！"
    view_all_info
}

execute_official_script() {
    local args="$1" script_content="" curl_rc=0 pid
    script_content=$(curl -fsSL "$xray_install_script_url" 2>/dev/null) || curl_rc=$?
    if [[ "$curl_rc" -ne 0 || -z "$script_content" || ! "$script_content" =~ install-release ]]; then
        error "下载 Xray 官方安装脚本失败或内容异常！请检查网络连接。"
        return 1
    fi

    echo "$script_content" | bash -s -- $args &>/dev/null &
    pid=$!
    spinner "$pid"
    if ! wait "$pid"; then return 1; fi
}

update_xray() {
    detect_xray_binary >/dev/null 2>&1 || true
    if [[ ! -f "$XRAY_BIN" ]]; then error "错误: Xray 未安装。" && return; fi
    info "正在检查最新版本..."

    local current_version latest_version yn
    current_version=$("$XRAY_BIN" version 2>/dev/null | head -n 1 | awk '{print $2}' || true)
    current_version=$(echo -n "$current_version" | tr -d '\r\n')
    [[ -z "$current_version" ]] && current_version="未知"

    latest_version=$(curl -fsSL --max-time 8 https://api.github.com/repos/XTLS/Xray-core/releases/latest 2>/dev/null \
        | jq -r '.tag_name' 2>/dev/null \
        | sed 's/^v//' || true)

    if [[ -z "$latest_version" || "$latest_version" == "null" ]]; then
        warning "获取最新版本号失败（可能是网络/DNS 或 GitHub API 限流）。"
        echo -e "  当前版本: ${cyan}${current_version}${none}"
        read -r -p "  是否仍然尝试执行官方更新脚本？[Y/n]: " yn || true
        if [[ "$yn" =~ ^[nN]$ ]]; then
            info "已取消更新。"
            return 0
        fi
        info "开始执行官方更新脚本..."
        if ! run_core_install; then return 1; fi
        restart_xray || return 1
        success "Xray 更新流程已执行完成（版本号请回到主菜单查看）。"
        return 0
    fi

    info "当前版本: ${cyan}${current_version}${none}，最新版本: ${cyan}${latest_version}${none}"
    if [[ "$current_version" == "$latest_version" ]]; then
        success "您的 Xray 已是最新版本。"
        return 0
    fi

    info "发现新版本，开始更新..."
    if ! run_core_install; then return 1; fi
    if ! restart_xray; then return 1; fi
    success "Xray 更新成功！"
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
        printf "  ${blue}%-2s${none} %-35s\n" "9." "BBR/网络智能优化"
        printf "  ${yellow}%-2s${none} %-35s\n" "0." "退出脚本"
        draw_divider

        read -r -p " 请输入选项 [0-9]: " choice || true
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
            9) bbr_menu; needs_pause=false ;;
            0) success "感谢使用！"; exit 0 ;;
            *) error "无效选项。请输入0到9之间的数字。" ;;
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
