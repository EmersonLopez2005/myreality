#!/usr/bin/env bash

# ==============================================================================
# Xray VLESS-Reality & Shadowsocks 2022 绠＄悊鑴氭湰 (x.sh)
# - 浜や簰閫昏緫閲嶆瀯 x.sh
# - 绉婚櫎鏃х増 x.sh 鐨勨€滃垎娴?YouTube/涓婃父SS鈥濈瓑鍔熻兘锛屼粎淇濈暀锛歊eality + SS2022
# - 淇濈暀蹇嵎閿叆鍙ｏ細alias xray='bash /root/x.sh'
# ==============================================================================

set -euo pipefail

# --- 鍏ㄥ眬甯搁噺 ---
readonly SCRIPT_VERSION="x.sh v3.0.3"
readonly SCRIPT_PATH="/root/x.sh"
readonly SCRIPT_UPDATE_URL="https://raw.githubusercontent.com/EmersonLopez2005/myreality/main/x.sh"

readonly xray_config_path="/usr/local/etc/xray/config.json"
readonly xray_binary_path="/usr/local/bin/xray"
readonly xray_install_script_url="https://github.com/XTLS/Xray-install/raw/main/install-release.sh"

# --- BBR / 缃戠粶浼樺寲 ---
readonly BBR_CONF_FILE="/etc/sysctl.d/99-bbr.conf"
readonly BBR_STATE_DIR="/var/lib/xray-menu"
readonly BBR_STATE_FILE="${BBR_STATE_DIR}/bbr-preapply.state"
readonly BBR_MODULE_VERSION="bbr-module v1.1.0"

# --- 蹇嵎鍛戒护 (alias/澶囩敤鍛戒护) ---
readonly MENU_BIN_SYMLINK="/usr/local/bin/xray-menu"

# --- 棰滆壊瀹氫箟 ---
readonly red='\e[91m' green='\e[92m' yellow='\e[93m'
readonly magenta='\e[95m' cyan='\e[96m' blue='\e[94m' none='\e[0m'

# --- 鍏ㄥ眬鍙橀噺 ---
xray_status_info=""
is_quiet=false

# Keep a mutable Xray binary path so runtime detection can override the default.
XRAY_BIN="${xray_binary_path}"

# --- 鑷畨瑁咃細淇濈暀 xray 蹇嵎閿叆鍙?---
install_self() {
    # Copy the currently running script into the canonical install path.
    local self_src="${BASH_SOURCE[0]}"
    if [[ "$self_src" != "$SCRIPT_PATH" ]]; then
        cp -f "$self_src" "$SCRIPT_PATH"
        chmod +x "$SCRIPT_PATH"
    else
        chmod +x "$SCRIPT_PATH" 2>/dev/null || true
    fi

    # 2) 鍐欏叆 alias锛堜粎鍐欎竴娆★級锛氭牴鎹綋鍓?shell 鍐欏叆 bashrc/zshrc
    # Alias changes take effect after reopening the shell or sourcing the rc file.
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

    # 3) 瀹夎涓€涓鐢ㄥ懡浠わ細/usr/local/bin/xray-menu
    # Install a fallback launcher even if the alias is not loaded.
    mkdir -p "$(dirname "$MENU_BIN_SYMLINK")"
    ln -sf "$SCRIPT_PATH" "$MENU_BIN_SYMLINK" 2>/dev/null || true
    chmod +x "$MENU_BIN_SYMLINK" 2>/dev/null || true

    # 4) 灏濊瘯缁欏綋鍓?shell 涓存椂鐢熸晥锛堜粎鏈浼氳瘽锛涗笉淇濊瘉鎵€鏈夌幆澧冩湁鏁堬級
    alias xray="bash ${SCRIPT_PATH}" 2>/dev/null || true
}

update_script() {
    info "姝ｅ湪浠庤繙绋嬫洿鏂拌剼鏈?.."
    if ! command -v curl &>/dev/null; then
        error "绯荤粺缂哄皯 curl锛屾棤娉曞湪绾挎洿鏂拌剼鏈€?"
        return 1
    fi
    local tmp="/tmp/x.sh.$$"
    if ! curl -fsSL "$SCRIPT_UPDATE_URL" -o "$tmp"; then
        error "涓嬭浇鑴氭湰澶辫触锛岃妫€鏌ョ綉缁滄垨鏇存柊鍦板潃銆?"
        return 1
    fi
    # 绠€鍗曟牎楠岋細鑷冲皯鍖呭惈 main_menu 瀛楁牱锛岄伩鍏嶄笅杞藉埌 HTML/404
    if ! grep -q "main_menu" "$tmp"; then
        rm -f "$tmp"
        error "涓嬭浇鍐呭寮傚父锛堟湭妫€娴嬪埌 main_menu锛夈€備负瀹夊叏璧疯宸茬粓姝㈡洿鏂般€?"
        return 1
    fi
    install -m 755 -o root -g root "$tmp" "$SCRIPT_PATH"
    rm -f "$tmp"
    success "鑴氭湰宸叉洿鏂板畬鎴愩€傝閲嶆柊杩愯锛歺ray"
}

# --- 杈呭姪鍑芥暟 ---
error() {
    echo -e "\n${red}[鉁朷 $1${none}\n" >&2
    case "$1" in
        *"缃戠粶"*|*"涓嬭浇"*) echo -e "${yellow}鎻愮ず: 妫€鏌ョ綉缁滆繛鎺ユ垨鏇存崲DNS${none}" >&2 ;;
        *"鏉冮檺"*|*"root"*) echo -e "${yellow}鎻愮ず: 璇蜂娇鐢?sudo 杩愯鑴氭湰${none}" >&2 ;;
        *"绔彛"*) echo -e "${yellow}鎻愮ず: 灏濊瘯浣跨敤鍏朵粬绔彛鍙?{none}" >&2 ;;
    esac
}

info() { [[ "$is_quiet" = false ]] && echo -e "\n${yellow}[!] $1${none}\n"; }
success() { [[ "$is_quiet" = false ]] && echo -e "\n${green}[鉁擼 $1${none}\n"; }
warning() { [[ "$is_quiet" = false ]] && echo -e "\n${yellow}[鈿燷 $1${none}\n"; }

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

# --- 棰勬鏌ヤ笌鐜璁剧疆 ---
pre_check() {
    [[ "$(id -u)" != 0 ]] && error "閿欒: 鎮ㄥ繀椤讳互root鐢ㄦ埛韬唤杩愯姝よ剼鏈?" && exit 1
    if [[ ! -f /etc/debian_version ]]; then
        error "閿欒: 姝よ剼鏈粎鏀寔 Debian/Ubuntu 鍙婂叾琛嶇敓绯荤粺銆?" && exit 1
    fi
    if ! command -v jq &>/dev/null || ! command -v curl &>/dev/null || ! command -v openssl &>/dev/null; then
        info "妫€娴嬪埌缂哄け渚濊禆 (jq/curl/openssl)锛屾鍦ㄥ皾璇曡嚜鍔ㄥ畨瑁?.."
        (DEBIAN_FRONTEND=noninteractive apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y jq curl openssl) &>/dev/null &
        spinner $!
        if ! command -v jq &>/dev/null || ! command -v curl &>/dev/null || ! command -v openssl &>/dev/null; then
            error "渚濊禆鑷姩瀹夎澶辫触銆傝鎵嬪姩杩愯: apt update && apt install -y jq curl openssl" && exit 1
        fi
        success "渚濊禆宸叉垚鍔熷畨瑁呫€?"
    fi
}

detect_xray_binary() {
    # Use type -P so aliases/functions named xray do not mask the real binary.
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
        xray_status_info=" Xray 鐘舵€? ${red}鏈畨瑁?{none}"
        return
    fi
    local xray_version service_status
    # Ignore the exit status here because some environments still print a version on non-zero exit.
    xray_version=$("$XRAY_BIN" version 2>/dev/null | head -n 1 | awk '{print $2}' || true)
    xray_version=$(echo -n "$xray_version" | tr -d '\r\n')
    [[ -z "$xray_version" ]] && xray_version="鏈煡"
    if systemctl is-active --quiet xray 2>/dev/null; then
        service_status="${green}杩愯涓?{none}"
    else
        service_status="${yellow}鏈繍琛?{none}"
    fi
    xray_status_info=" Xray 鐘舵€? ${green}宸插畨瑁?{none} | ${service_status} | 鐗堟湰: ${cyan}${xray_version}${none}"
}

quick_status() {
    detect_xray_binary >/dev/null 2>&1 || true
    if [[ ! -f "$XRAY_BIN" ]]; then
        echo -e " ${red}鈼?{none} 鏈畨瑁?"
        return
    fi
    local status_icon
    if systemctl is-active --quiet xray 2>/dev/null; then status_icon="${green}鈼?{none}"; else status_icon="${red}鈼?{none}"; fi
    echo -e " $status_icon Xray $(systemctl is-active xray 2>/dev/null || echo "inactive")"
}

generate_reality_keypair() {
    # 杈撳嚭涓よ锛歱rivate_key\npublic_key
    detect_xray_binary >/dev/null 2>&1 || true
    if [[ ! -x "$XRAY_BIN" ]]; then
        error "閿欒: 鏈壘鍒?xray 鍙墽琛屾枃浠讹紙鏈熸湜: $XRAY_BIN锛夈€?"
        return 1
    fi

    local out private_key reality_client_key
    out=$("$XRAY_BIN" x25519 2>&1 || true)

    # 鍏煎澶氱杈撳嚭鏍煎紡锛堜笉鍚?xray 鐗堟湰鍙兘杩斿洖涓嶅悓瀛楁鍚嶏級锛?    # - Private key: xxx
    # - Public key:  xxx
    # - PrivateKey: xxx
    # - PublicKey:  xxx
    # - Hash32:     xxx   (閮ㄥ垎鐗堟湰鐢?Hash32 浣滀负鍙敤浜?Reality 鐨勫叕閽?鎸囩汗瀛楁)
    private_key=$(echo "$out" | awk -F':' 'tolower($1) ~ /private/ {gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2; exit}')

    # publicKey 浼樺厛锛屽叾娆?Hash32
    reality_client_key=$(echo "$out" | awk -F':' 'tolower($1) ~ /(password|public[[:space:]]*key)/ {gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2; exit}')

    if [[ -z "$private_key" || -z "$reality_client_key" ]]; then
        error "鐢熸垚 Reality 瀵嗛挜瀵瑰け璐ワ細鏃犳硶浠?xray x25519 杈撳嚭瑙ｆ瀽瀵嗛挜銆?"
        {
            echo -e "${yellow}--- xray x25519 鍘熷杈撳嚭锛堜究浜庢帓鏌ワ級---${none}"
            echo "$out" | sed 's/^/  /'
            echo -e "${yellow}----------------------------------------${none}"
        } >&2
        return 1
    fi

    printf "%s\n%s\n" "$private_key" "$reality_client_key"
}

# --- Reality shortId (shortkey) 闅忔満鐢熸垚 ---
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
    # Reality shortIds are typically 8 hex characters (4 bytes).
    local sid
    sid=$(openssl rand -hex 4 2>/dev/null || true)
    if [[ -z "$sid" ]]; then
        sid=$(head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \n')
    fi
    echo "$sid"
}

# --- 鏍稿績閰嶇疆鐢熸垚鍑芥暟 ---
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
            info "瀹歌弓璐熼幃銊ф晸閹存劙娈㈤張鍝勭槕闁? ${cyan}${ss_pass_ref}${none}"
            return 0
        fi

        if is_valid_ss2022_password "$ss_pass_ref"; then
            return 0
        fi

        error "Invalid SS2022 key. Enter a 16-byte Base64 key, or leave it blank to auto-generate one."
    done
}

# ==============================================================================
# BBR / Linux 缃戠粶鍙傛暟鏅鸿兘浼樺寲锛堣瀺鍚?script.sh 鐨勯€昏緫锛屽鍔犲彲鍥炴粴/鍙煡鐪嬬姸鎬侊級
# ==============================================================================

# --- BBR 鍏ㄥ眬鍙橀噺锛堢粺涓€浣跨敤 BBR_ 鍓嶇紑锛岄伩鍏嶄笌涓昏剼鏈彉閲忓啿绐侊級 ---
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

# 杩愯鏃堕€夋嫨鐨勪紭鍖栫瓥鐣ワ紙鍧囪　/楂樺苟鍙?鐪佸唴瀛橈級
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
    # Scale kernel networking limits by RAM tier so smaller VPSes do not overcommit.
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
        BBR_CONNTRACK_MAX="1048576" # 100涓囪繛鎺ラ€氬父瓒冲
    fi
}

bbr_pre_flight_checks() {
    [[ $(id -u) -ne 0 ]] && error "鉂?閿欒: 蹇呴』 root 鏉冮檺銆?" && return 1
    # 灏濊瘯鍔犺浇蹇呰鍐呮牳妯″潡锛堝け璐ヤ笉鑷村懡锛氬鍣ㄧ幆澧冩垨绮剧畝鍐呮牳鍙兘涓嶅厑璁革級
    modprobe nf_conntrack >/dev/null 2>&1 || true
    modprobe tcp_bbr >/dev/null 2>&1 || true
    return 0
}

bbr_add_conf() {
    # 鐢ㄦ硶: bbr_add_conf <file> <key> <value> <comment>
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
        # Keep the three most recent backups.
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
    # Adjust base limits for the selected optimization profile.
    local profile="$1"

    case "$profile" in
        high_concurrency)
            # Favor larger connection and queue limits for busy proxy nodes.
            BBR_SOMAXCONN=$(bbr_scale_int "$BBR_SOMAXCONN" 2 1)
            BBR_FILE_MAX=$(bbr_scale_int "$BBR_FILE_MAX" 2 1)
            BBR_CONNTRACK_MAX=$(bbr_scale_int "$BBR_CONNTRACK_MAX" 2 1)

            # Increase socket buffer ceilings moderately without going extreme.
            BBR_RMEM_MAX=$(bbr_scale_int "$BBR_RMEM_MAX" 3 2)
            BBR_WMEM_MAX=$(bbr_scale_int "$BBR_WMEM_MAX" 3 2)
            BBR_TCP_MEM_MAX=$(bbr_scale_int "$BBR_TCP_MEM_MAX" 3 2)
            ;;
        memory_saving)
            # Use more conservative queue, conntrack, and buffer limits.
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

    # Keep limits within sane floors and ceilings.
    BBR_SOMAXCONN=$(bbr_clamp_int "$BBR_SOMAXCONN" 4096 262144)
    BBR_FILE_MAX=$(bbr_clamp_int "$BBR_FILE_MAX" 65535 8388608)
    BBR_CONNTRACK_MAX=$(bbr_clamp_int "$BBR_CONNTRACK_MAX" 65536 2097152)

    # Prevent oversized per-socket buffers from consuming too much RAM.
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
    # Generate the sysctl file in a temp path and print that path to stdout.
    local profile="$1" tw_reuse="$2"
    bbr_get_system_info
    bbr_apply_profile_tuning "$profile"

    local tmp
    tmp=$(mktemp "${BBR_CONF_FILE}.tmp.XXXXXX")

    cat >> "$tmp" << EOF
# ==========================================================
# Linux Network Tuning (Proxy/Forwarding Optimized)
# 鐢熸垚鏃堕棿: $(date)
# 纭欢鐜: ${BBR_TOTAL_MEM}MB RAM, ${BBR_CPU_CORES} CPU
# 铏氭嫙鍖? : ${BBR_VIRT_TYPE}
# 妗ｄ綅    : ${BBR_VM_TIER}
# 妯″紡    : $(bbr_profile_label "$profile") (${profile})
# 妯″潡鐗堟湰: ${BBR_MODULE_VERSION}
# ==========================================================
EOF

    # Capability check: warn when BBR is unavailable, but still write the config.
    local available_cc
    available_cc=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)
    if ! echo " $available_cc " | grep -q " bbr "; then
        warning "绯荤粺鏈娴嬪埌鍙敤鐨?BBR 鎷ュ绠楁硶锛坅vailable: ${available_cc:-鏈煡}锛夈€備粛浼氬啓鍏ラ厤缃紝浣嗗彲鑳戒笉浼氱敓鏁堛€?"
    fi

    # 1) Congestion control and qdisc.
    bbr_add_conf "$tmp" "net.core.default_qdisc" "fq" "FQ 闃熷垪绠楁硶 (BBR 甯哥敤鎼厤)"
    bbr_add_conf "$tmp" "net.ipv4.tcp_congestion_control" "bbr" "寮€鍚?BBR"

    # 2) 缂撳啿鍖轰紭鍖?(TCP & UDP)
    bbr_add_conf "$tmp" "net.core.rmem_max" "$BBR_RMEM_MAX" "绯荤粺鏈€澶ф帴鏀剁紦瀛?"
    bbr_add_conf "$tmp" "net.core.wmem_max" "$BBR_WMEM_MAX" "绯荤粺鏈€澶у彂閫佺紦瀛?"
    bbr_add_conf "$tmp" "net.core.rmem_default" "262144" "榛樿鎺ユ敹缂撳瓨 (256k)"
    bbr_add_conf "$tmp" "net.core.wmem_default" "262144" "榛樿鍙戦€佺紦瀛?(256k)"
    bbr_add_conf "$tmp" "net.ipv4.tcp_rmem" "8192 262144 $BBR_TCP_MEM_MAX" "TCP璇荤紦瀛?(min default max)"
    bbr_add_conf "$tmp" "net.ipv4.tcp_wmem" "8192 262144 $BBR_TCP_MEM_MAX" "TCP鍐欑紦瀛?(min default max)"
    bbr_add_conf "$tmp" "net.ipv4.udp_rmem_min" "16384" "UDP璇荤紦瀛樹笅闄?(浼樺寲QUIC)"
    bbr_add_conf "$tmp" "net.ipv4.udp_wmem_min" "16384" "UDP鍐欑紦瀛樹笅闄?(浼樺寲QUIC)"

    # 3) Queue and backlog limits.
    bbr_add_conf "$tmp" "net.core.somaxconn" "$BBR_SOMAXCONN" "鏈€澶х洃鍚槦鍒?"
    bbr_add_conf "$tmp" "net.core.netdev_max_backlog" "$BBR_SOMAXCONN" "缃戝崱绉帇闃熷垪"
    bbr_add_conf "$tmp" "net.ipv4.tcp_max_syn_backlog" "$BBR_SOMAXCONN" "SYN鍗婅繛鎺ラ槦鍒?"
    bbr_add_conf "$tmp" "net.ipv4.tcp_notsent_lowat" "16384" "闄嶄綆鏈彂閫佹暟鎹槇鍊?(闄嶄綆寤惰繜)"

    # 4) TIME_WAIT 涓?绔彛澶嶇敤
    bbr_add_conf "$tmp" "net.ipv4.tcp_tw_reuse" "$tw_reuse" "寮€鍚?TIME_WAIT 澶嶇敤 (楂樺苟鍙戜紭鍖栵紝鍙寜闇€鍏抽棴)"
    bbr_add_conf "$tmp" "net.ipv4.tcp_timestamps" "1" "寮€鍚椂闂存埑 (閰嶅悎 reuse)"
    bbr_add_conf "$tmp" "net.ipv4.tcp_fin_timeout" "30" "缂╃煭 FIN_WAIT 鏃堕棿"
    bbr_add_conf "$tmp" "net.ipv4.ip_local_port_range" "10000 65535" "鎵╁ぇ鏈湴绔彛鑼冨洿"
    bbr_add_conf "$tmp" "net.ipv4.tcp_max_tw_buckets" "500000" "鍏佽鏇村 TIME_WAIT socket"

    # 5) TCP Keepalive
    bbr_add_conf "$tmp" "net.ipv4.tcp_keepalive_time" "600" "TCP淇濇椿鏃堕棿 (10鍒嗛挓)"
    bbr_add_conf "$tmp" "net.ipv4.tcp_keepalive_intvl" "15" "鎺㈡祴闂撮殧"
    bbr_add_conf "$tmp" "net.ipv4.tcp_keepalive_probes" "5" "鎺㈡祴娆℃暟"

    # 6) Conntrack
    bbr_add_conf "$tmp" "net.netfilter.nf_conntrack_max" "$BBR_CONNTRACK_MAX" "鏈€澶ц繛鎺ヨ窡韪暟 (杩囧ぇ鍙兘鍚冨唴瀛?"
    bbr_add_conf "$tmp" "net.netfilter.nf_conntrack_tcp_timeout_established" "7200" "杩炴帴璺熻釜瓒呮椂 (2灏忔椂)"
    bbr_add_conf "$tmp" "net.netfilter.nf_conntrack_tcp_timeout_time_wait" "120" "鍑忓皯 TIME_WAIT 璺熻釜鏃堕棿"

    # 7) Other system-level tuning.
    bbr_add_conf "$tmp" "fs.file-max" "$BBR_FILE_MAX" "鏈€澶ф枃浠跺彞鏌?"
    bbr_add_conf "$tmp" "vm.swappiness" "10" "鍑忓皯 Swap 浣跨敤"
    bbr_add_conf "$tmp" "net.ipv4.tcp_mtu_probing" "1" "寮€鍚?MTU 鎺㈡祴"
    bbr_add_conf "$tmp" "net.ipv4.tcp_syncookies" "1" "闃?SYN Flood"

    echo "$tmp"
}

bbr_apply_sysctl_from_file() {
    # 閫愰」搴旂敤骞舵眹鎬荤粨鏋滐紝閬垮厤鏌愪釜鍙傛暟澶辫触瀵艰嚧鍏ㄩ儴澶辫触
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
                # Classify the failure so the summary is actionable.
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
    # Write detailed failures to stderr so interactive runs still show them.
    if ((${#failed_lines[@]} > 0)); then
        {
            echo -e "\n${yellow}浠ヤ笅鍙傛暟鏈兘鎴愬姛搴旂敤锛堜笉涓€瀹氬奖鍝嶆牳蹇冨姛鑳斤級锛?{none}"
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
    # 鏂伴€昏緫锛氬師瀛愬啓鍏?+ 閫愰」 sysctl 搴旂敤 + 姹囨€诲け璐ラ」 + 鏀寔 profile
    local profile="$1" tw_reuse="$2"

    bbr_get_system_info
    bbr_apply_profile_tuning "$profile"

    [[ "$is_quiet" = false ]] && {
        echo -e "${cyan}>>> 绯荤粺淇℃伅妫€娴嬶細${none}"
        echo -e "鍐呭瓨澶у皬   : ${yellow}${BBR_TOTAL_MEM}MB${none}"
        echo -e "CPU鏍稿績鏁? : ${yellow}${BBR_CPU_CORES}${none}"
        echo -e "铏氭嫙鍖栫被鍨?: ${yellow}${BBR_VIRT_TYPE}${none}"
        echo -e "鐩爣妗ｄ綅   : ${yellow}${BBR_VM_TIER}${none}"
        echo -e "浼樺寲妯″紡   : ${yellow}$(bbr_profile_label "$profile")${none}"
    }

    info "鐢熸垚骞跺簲鐢ㄧ綉缁滀紭鍖栭厤缃?(${BBR_VM_TIER} / $(bbr_profile_label "$profile"))..."
    mkdir -p "$(dirname "$BBR_CONF_FILE")"

    # 鍘熷瓙鍐欙細鍏堝啓 tmp锛屽啀 mv 瑕嗙洊
    local tmp
    tmp=$(bbr_build_conf_file "$profile" "$tw_reuse")
    bbr_capture_runtime_state "$tmp"
    chmod 644 "$tmp" 2>/dev/null || true
    mv -f "$tmp" "$BBR_CONF_FILE"

    info "姝ｅ湪閫愰」搴旂敤 sysctl 鍙傛暟锛堝彲璺宠繃涓嶆敮鎸佺殑閿級..."
    local summary ok missing denied invalid cc qdisc reuse iface tcq
    summary=$(bbr_apply_sysctl_from_file "$BBR_CONF_FILE")
    ok=${summary%%|*}; summary=${summary#*|}
    missing=${summary%%|*}; summary=${summary#*|}
    denied=${summary%%|*}; invalid=${summary#*|}

    cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "鏈煡")
    qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "鏈煡")
    reuse=$(sysctl -n net.ipv4.tcp_tw_reuse 2>/dev/null || echo "鏈煡")

    iface=$(bbr_detect_primary_iface || true)
    if command -v tc >/dev/null 2>&1 && [[ -n "$iface" ]]; then
        tcq=$(tc qdisc show dev "$iface" 2>/dev/null | head -n 1 || true)
    else
        tcq=""
    fi

    success "缃戠粶浼樺寲瀹屾垚锛?"
    echo -e "宸插簲鐢? ${green}${ok}${none} 椤?| 涓嶅瓨鍦? ${yellow}${missing}${none} 椤?| 鏉冮檺/鍙楅檺: ${yellow}${denied}${none} 椤?| 鍏跺畠澶辫触: ${yellow}${invalid}${none} 椤?"
    echo -e "鎷ュ鎺у埗: ${cyan}${cc}${none} | 闃熷垪绠楁硶: ${cyan}${qdisc}${none} | tcp_tw_reuse: ${cyan}${reuse}${none}"
    [[ -n "$tcq" ]] && echo -e "缃戝崱闃熷垪(tc): ${cyan}${tcq}${none}"
}

bbr_apply_and_verify() {
    # Compatibility shim for older call sites.
    :
}

bbr_uninstall() {
    if [[ ! -f "$BBR_CONF_FILE" ]]; then
        warning "鏈彂鐜?$BBR_CONF_FILE锛屾棤闇€鍗歌浇銆?"
        return 0
    fi

    info "姝ｅ湪鍗歌浇/鍥炴粴 BBR 缃戠粶浼樺寲閰嶇疆..."
    mv -f "$BBR_CONF_FILE" "$BBR_CONF_FILE.removed_$(date +%F_%H-%M-%S)"
    # 閲嶈浇鎵€鏈?sysctl.d锛堢‘淇濆垹闄ゅ悗鐢熸晥锛?    sysctl --system >/dev/null 2>&1 || true
    success "宸茬Щ闄や紭鍖栭厤缃紙宸蹭繚鐣?removed 澶囦唤锛夈€?"
}

bbr_uninstall() {
    if [[ ! -f "$BBR_CONF_FILE" ]]; then
        warning "鏈彂鐜?$BBR_CONF_FILE锛屾棤闇€鍗歌浇銆?"
        return 0
    fi

    info "姝ｅ湪鍗歌浇/鍥炴粴 BBR 缃戠粶浼樺寲閰嶇疆..."
    mv -f "$BBR_CONF_FILE" "$BBR_CONF_FILE.removed_$(date +%F_%H-%M-%S)"

    local restore_summary restored failed
    sysctl --system >/dev/null 2>&1 || true
    if [[ -f "$BBR_STATE_FILE" ]]; then
        restore_summary=$(bbr_restore_runtime_state "$BBR_STATE_FILE")
        restored=${restore_summary%%|*}
        failed=${restore_summary#*|}
        rm -f "$BBR_STATE_FILE"
        success "宸茬Щ闄や紭鍖栭厤缃紝骞跺皾璇曟仮澶?${restored} 椤瑰師濮?sysctl 鍊笺€?"
        if [[ "$failed" != "0" ]]; then
            warning "浠嶆湁 ${failed} 椤?sysctl 鏈兘鎭㈠鍒板簲鐢ㄥ墠鐘舵€侊紝濡傛湁寮傚父鍙噸鍚湇鍔″櫒銆?"
        fi
    else
        success "宸茬Щ闄や紭鍖栭厤缃紙鏈壘鍒板師濮?sysctl 澶囦唤锛屽鏈夋畫鐣欏彲閲嶅惎鏈嶅姟鍣級銆?"
    fi
}

bbr_status() {
    draw_menu_header
    echo -e "${cyan} BBR/缃戠粶浼樺寲鐘舵€?{none}"
    draw_divider
    printf "  %-24s %s\n" "閰嶇疆鏂囦欢" "${BBR_CONF_FILE}"
    if [[ -f "$BBR_CONF_FILE" ]]; then
        printf "  %-24s %b\n" "鏄惁瀛樺湪" "${green}鏄?{none}"
    else
        printf "  %-24s %b\n" "鏄惁瀛樺湪" "${red}鍚?{none}"
    fi

    local cc qdisc available
    cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "鏈煡")
    qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "鏈煡")
    available=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || echo "鏈煡")

    printf "  %-24s %s\n" "褰撳墠鎷ュ鎺у埗" "${cc}"
    printf "  %-24s %s\n" "鍙敤鎷ュ鎺у埗" "${available}"
    printf "  %-24s %s\n" "褰撳墠 qdisc" "${qdisc}"

    # 灞曠ず鐢ㄦ埛甯哥敤鐨勨€淏BR 鏄惁鐢熸晥鈥濇帓鏌ラ」锛堝彲閫夐」锛屽敖鍔涜緭鍑猴級
    echo ""
    echo "  甯哥敤楠岃瘉锛堝彲閫夛級锛?"

    if command -v lsmod >/dev/null 2>&1; then
        local mod_line
        # Some minimal/container systems make lsmod fail, so keep this best-effort.
        mod_line=$(lsmod 2>/dev/null | awk '$1=="tcp_bbr"{print; exit}' || true)
        if [[ -n "$mod_line" ]]; then
            printf "  %-24s %s\n" "tcp_bbr 妯″潡" "宸插姞杞?(lsmod 鍙)"
        else
            printf "  %-24s %s\n" "tcp_bbr 妯″潡" "lsmod 鏈樉绀猴紙鍙兘鏈姞杞?鎴栧凡缂栬瘧杩涘唴鏍革級"
        fi
    else
        printf "  %-24s %s\n" "tcp_bbr 妯″潡" "鏃犳硶妫€鏌ワ紙绯荤粺缂哄皯 lsmod锛?"
    fi

    local iface tcq
    iface=$(bbr_detect_primary_iface || true)
    if [[ -n "$iface" ]]; then
        printf "  %-24s %s\n" "榛樿鍑哄彛缃戝崱" "${iface}"
        if command -v tc >/dev/null 2>&1; then
            tcq=$(tc qdisc show dev "$iface" 2>/dev/null | head -n 1 || true)
            [[ -n "$tcq" ]] && printf "  %-24s %s\n" "tc qdisc(缃戝崱)" "${tcq}"
        else
            printf "  %-24s %s\n" "tc qdisc(缃戝崱)" "鏃犳硶妫€鏌ワ紙绯荤粺缂哄皯 tc 鍛戒护锛?"
        fi
    else
        printf "  %-24s %s\n" "榛樿鍑哄彛缃戝崱" "鏃犳硶璇嗗埆锛坕p route 鏃?default锛?"
    fi
    echo ""
    echo "  鍏抽敭鍙傛暟锛?"
    sysctl net.ipv4.tcp_tw_reuse net.ipv4.tcp_timestamps net.core.somaxconn 2>/dev/null | sed 's/^/  /' || true
    draw_divider
}

bbr_menu() {
    while true; do
        draw_menu_header
        echo -e "${cyan} BBR / 缃戠粶鏅鸿兘浼樺寲 (${BBR_MODULE_VERSION})${none}"
        draw_divider
        printf "  ${green}%-2s${none} %-35s\n" "1." "涓€閿紑鍚?鏅鸿兘浼樺寲 (鍐欏叆骞跺簲鐢?sysctl)"
        printf "  ${yellow}%-2s${none} %-35s\n" "2." "鏌ョ湅褰撳墠鐘舵€?鏄惁鐢熸晥"
        printf "  ${red}%-2s${none} %-35s\n" "3." "鍗歌浇/鍥炴粴 (绉婚櫎閰嶇疆鏂囦欢)"
        draw_divider
        printf "  ${magenta}%-2s${none} %-35s\n" "0." "杩斿洖涓昏彍鍗?"
        draw_divider
        read -r -p " 璇疯緭鍏ラ€夐」 [0-3]: " choice || true
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
            *) error "鏃犳晥閫夐」銆?"; press_any_key_to_continue ;;
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
        error "鐢熸垚鐨勯厤缃枃浠舵牸寮忛敊璇紒"
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
        error "涓嬭浇 Xray 瀹樻柟瀹夎鑴氭湰澶辫触鎴栧唴瀹瑰紓甯革紒璇锋鏌ョ綉缁滆繛鎺ャ€?"
        return 1
    fi
    echo "$script_content" | bash -s -- $args &>/dev/null &
    spinner $!
    if ! wait $!; then return 1; fi
}

run_core_install() {
    info "姝ｅ湪涓嬭浇骞跺畨瑁?Xray 鏍稿績..."
    if ! execute_official_script "install"; then
        error "Xray 鏍稿績瀹夎澶辫触锛?"
        return 1
    fi
    info "姝ｅ湪鏇存柊 GeoIP 鍜?GeoSite 鏁版嵁鏂囦欢..."
    if ! execute_official_script "install-geodata"; then
        warning "Geo-data 鏇存柊澶辫触锛堥€氬父涓嶅奖鍝嶆牳蹇冨姛鑳斤紝鍙◢鍚庡啀璇曪級銆?"
    fi
    success "Xray 鏍稿績鍙婃暟鎹枃浠跺凡鍑嗗灏辩华銆?"
}

# --- 杈撳叆楠岃瘉涓庝氦浜掑嚱鏁?---
is_valid_port() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] && [[ "$port" -ge 1 && "$port" -le 65535 ]]
}

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
        warning "绔彛 $port 宸茶 ${proto} 鍗犵敤锛屽缓璁€夋嫨鍏朵粬绔彛"
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
        read -r -p "$(echo -e " -> 璇疯緭鍏?VLESS 绔彛 (榛樿: ${cyan}${default_port}${none}): ")" p_port || true
        [[ -z "$p_port" ]] && p_port="$default_port"
        if is_port_available "$p_port"; then break; fi
    done
    info "VLESS 绔彛灏嗕娇鐢? ${cyan}${p_port}${none}"

    read -r -p "$(echo -e " -> 璇疯緭鍏UID (鐣欑┖灏嗚嚜鍔ㄧ敓鎴?: ")" p_uuid || true
    if [[ -z "$p_uuid" ]]; then
        p_uuid=$(cat /proc/sys/kernel/random/uuid)
        info "宸蹭负鎮ㄧ敓鎴愰殢鏈篣UID: ${cyan}${p_uuid}${none}"
    fi

    while true; do
        read -r -p "$(echo -e " -> 璇疯緭鍏NI鍩熷悕 (榛樿: ${cyan}learn.microsoft.com${none}): ")" p_sni || true
        [[ -z "$p_sni" ]] && p_sni="learn.microsoft.com"
        if is_valid_domain "$p_sni"; then break; else error "鍩熷悕鏍煎紡鏃犳晥锛岃閲嶆柊杈撳叆銆?"; fi
    done
    info "SNI 鍩熷悕灏嗕娇鐢? ${cyan}${p_sni}${none}"
}

prompt_for_ss_config() {
    local -n p_port="$1" p_pass="$2"
    local default_port="${3:-8388}"

    while true; do
        read -r -p "$(echo -e " -> 璇疯緭鍏?Shadowsocks 绔彛 (榛樿: ${cyan}${default_port}${none}): ")" p_port || true
        [[ -z "$p_port" ]] && p_port="$default_port"
        if is_port_available "$p_port"; then break; fi
    done
    info "Shadowsocks 绔彛灏嗕娇鐢? ${cyan}${p_port}${none}"

    read -r -p "$(echo -e " -> 璇疯緭鍏?Shadowsocks 瀵嗛挜 (鐣欑┖灏嗚嚜鍔ㄧ敓鎴?: ")" p_pass || true
    if [[ -z "$p_pass" ]]; then
        p_pass=$(generate_ss_key)
        info "宸蹭负鎮ㄧ敓鎴愰殢鏈哄瘑閽? ${cyan}${p_pass}${none}"
    fi
}

# --- 鑿滃崟鍔熻兘鍑芥暟 ---
draw_divider() { printf "%0.s鈹€" {1..48}; printf "\n"; }

draw_menu_header() {
    clear
    echo -e "${cyan} Xray VLESS-Reality & Shadowsocks-2022 绠＄悊鑴氭湰${none}"
    echo -e "${yellow} Version: ${SCRIPT_VERSION}${none}"
    draw_divider
    check_xray_status
    echo -e "${xray_status_info}"
    quick_status
    draw_divider
}

press_any_key_to_continue() {
    echo ""
    read -n 1 -s -r -p " 鎸変换鎰忛敭杩斿洖涓昏彍鍗?.." || true
}

install_menu() {
    local vless_exists="" ss_exists=""
    if [[ -f "$xray_config_path" ]]; then
        vless_exists=$(jq '.inbounds[] | select(.protocol == "vless")' "$xray_config_path" 2>/dev/null || true)
        ss_exists=$(jq '.inbounds[] | select(.protocol == "shadowsocks")' "$xray_config_path" 2>/dev/null || true)
    fi

    draw_menu_header
    if [[ -n "$vless_exists" && -n "$ss_exists" ]]; then
        success "鎮ㄥ凡瀹夎 VLESS-Reality + Shadowsocks-2022 鍙屽崗璁€?"
        info "濡傞渶淇敼锛岃浣跨敤涓昏彍鍗曠殑鈥滀慨鏀归厤缃€濄€俓n濡傞渶閲嶈锛岃鍏堚€滃嵏杞解€濆悗鍐嶉噸鏂扳€滃畨瑁呪€濄€?"
        return
    elif [[ -n "$vless_exists" && -z "$ss_exists" ]]; then
        info "妫€娴嬪埌鎮ㄥ凡瀹夎 VLESS-Reality"
        echo -e "${cyan} 璇烽€夋嫨涓嬩竴姝ユ搷浣?{none}"
        draw_divider
        printf "  ${green}%-2s${none} %-35s\n" "1." "杩藉姞瀹夎 Shadowsocks-2022 (缁勬垚鍙屽崗璁?"
        printf "  ${red}%-2s${none} %-35s\n" "2." "瑕嗙洊閲嶈 VLESS-Reality"
        draw_divider
        printf "  ${yellow}%-2s${none} %-35s\n" "0." "杩斿洖涓昏彍鍗?"
        draw_divider
        read -r -p " 璇疯緭鍏ラ€夐」 [0-2]: " choice || true
        case "$choice" in
            1) add_ss_to_vless ;;
            2) install_vless_only ;;
            0) return ;;
            *) error "鏃犳晥閫夐」銆? ";;
        esac
    elif [[ -z "$vless_exists" && -n "$ss_exists" ]]; then
        info "妫€娴嬪埌鎮ㄥ凡瀹夎 Shadowsocks-2022"
        echo -e "${cyan} 璇烽€夋嫨涓嬩竴姝ユ搷浣?{none}"
        draw_divider
        printf "  ${green}%-2s${none} %-35s\n" "1." "杩藉姞瀹夎 VLESS-Reality (缁勬垚鍙屽崗璁?"
        printf "  ${red}%-2s${none} %-35s\n" "2." "瑕嗙洊閲嶈 Shadowsocks-2022"
        draw_divider
        printf "  ${yellow}%-2s${none} %-35s\n" "0." "杩斿洖涓昏彍鍗?"
        draw_divider
        read -r -p " 璇疯緭鍏ラ€夐」 [0-2]: " choice || true
        case "$choice" in
            1) add_vless_to_ss ;;
            2) install_ss_only ;;
            0) return ;;
            *) error "鏃犳晥閫夐」銆? ";;
        esac
    else
        clean_install_menu
    fi
}

clean_install_menu() {
    draw_menu_header
    echo -e "${cyan} 璇烽€夋嫨瑕佸畨瑁呯殑鍗忚绫诲瀷${none}"
    draw_divider
    printf "  ${green}%-2s${none} %-35s\n" "1." "浠?VLESS-Reality"
    printf "  ${cyan}%-2s${none} %-35s\n" "2." "浠?Shadowsocks-2022"
    printf "  ${yellow}%-2s${none} %-35s\n" "3." "VLESS-Reality + Shadowsocks-2022 (鍙屽崗璁?"
    draw_divider
    printf "  ${magenta}%-2s${none} %-35s\n" "0." "杩斿洖涓昏彍鍗?"
    draw_divider
    read -r -p " 璇疯緭鍏ラ€夐」 [0-3]: " choice || true
    case "$choice" in
        1) install_vless_only ;;
        2) install_ss_only ;;
        3) install_dual ;;
        0) return ;;
        *) error "鏃犳晥閫夐」銆? ";;
    esac
}

add_ss_to_vless() {
    info "寮€濮嬭拷鍔犲畨瑁?Shadowsocks-2022..."
    if [[ -z "$(get_public_ip)" ]]; then
        error "鏃犳硶鑾峰彇鍏綉 IP 鍦板潃锛屾搷浣滀腑姝€傝妫€鏌ユ偍鐨勭綉缁滆繛鎺ャ€?"
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

    success "杩藉姞瀹夎鎴愬姛锛?"
    view_all_info
}

add_vless_to_ss() {
    info "寮€濮嬭拷鍔犲畨瑁?VLESS-Reality..."
    if [[ -z "$(get_public_ip)" ]]; then
        error "鏃犳硶鑾峰彇鍏綉 IP 鍦板潃锛屾搷浣滀腑姝€傝妫€鏌ユ偍鐨勭綉缁滆繛鎺ャ€?"
        return 1
    fi
    local ss_inbound ss_port default_vless_port vless_port vless_uuid vless_domain key_pair private_key public_key shortid vless_inbound
    ss_inbound=$(jq '.inbounds[] | select(.protocol == "shadowsocks")' "$xray_config_path")
    ss_port=$(echo "$ss_inbound" | jq -r '.port')
    default_vless_port=$([[ "$ss_port" == "8388" ]] && echo "443" || echo "$((ss_port - 1))")

    prompt_for_vless_config vless_port vless_uuid vless_domain "$default_vless_port"

    info "姝ｅ湪鐢熸垚 Reality 瀵嗛挜瀵?.."
    key_pair=$(generate_reality_keypair) || return 1
    private_key=$(echo "$key_pair" | sed -n '1p')
    public_key=$(echo "$key_pair" | sed -n '2p')
    shortid=$(generate_shortid)

    if [[ -z "$private_key" || -z "$public_key" ]]; then
        error "鐢熸垚 Reality 瀵嗛挜瀵瑰け璐ワ紒璇锋鏌?Xray 鏍稿績鏄惁姝ｅ父锛屾垨灏濊瘯鍗歌浇鍚庨噸瑁呫€?"
        return 1
    fi

    vless_inbound=$(build_vless_inbound "$vless_port" "$vless_uuid" "$vless_domain" "$private_key" "$public_key" "$shortid")
    write_config "[$vless_inbound, $ss_inbound]"
    if ! restart_xray; then return 1; fi

    success "杩藉姞瀹夎鎴愬姛锛?"
    view_all_info
}

install_vless_only() {
    info "寮€濮嬮厤缃?VLESS-Reality..."
    local port uuid domain
    prompt_for_vless_config port uuid domain
    run_install_vless "$port" "$uuid" "$domain"
}

install_ss_only() {
    info "寮€濮嬮厤缃?Shadowsocks-2022..."
    local port password
    prompt_for_ss_config port password
    run_install_ss "$port" "$password"
}

install_dual() {
    info "寮€濮嬮厤缃弻鍗忚 (VLESS-Reality + Shadowsocks-2022)..."
    local vless_port vless_uuid vless_domain ss_port ss_password
    prompt_for_vless_config vless_port vless_uuid vless_domain

    local default_ss_port
    if [[ "$vless_port" == "443" ]]; then default_ss_port=8388; else default_ss_port=$((vless_port + 1)); fi
    prompt_for_ss_config ss_port ss_password "$default_ss_port"

    run_install_dual "$vless_port" "$vless_uuid" "$vless_domain" "$ss_port" "$ss_password"
}

update_xray() {
    detect_xray_binary >/dev/null 2>&1 || true
    if [[ ! -f "$XRAY_BIN" ]]; then error "閿欒: Xray 鏈畨瑁呫€?" && return; fi
    info "姝ｅ湪妫€鏌ユ渶鏂扮増鏈?.."
    local current_version latest_version yn
    current_version=$("$XRAY_BIN" version 2>/dev/null | head -n 1 | awk '{print $2}' || true)
    current_version=$(echo -n "$current_version" | tr -d '\r\n')
    [[ -z "$current_version" ]] && current_version="鏈煡"

    latest_version=$(curl -fsSL --max-time 8 https://api.github.com/repos/XTLS/Xray-core/releases/latest 2>/dev/null \
        | jq -r '.tag_name' 2>/dev/null \
        | sed 's/^v//' || true)

    if [[ -z "$latest_version" || "$latest_version" == "null" ]]; then
        warning "鑾峰彇鏈€鏂扮増鏈彿澶辫触锛堝彲鑳芥槸缃戠粶/DNS 鎴?GitHub API 闄愭祦锛夈€?"
        echo -e "  褰撳墠鐗堟湰: ${cyan}${current_version}${none}"
        read -r -p "  鏄惁浠嶇劧灏濊瘯鎵ц瀹樻柟鏇存柊鑴氭湰锛焄Y/n]: " yn || true
        if [[ "$yn" =~ ^[nN]$ ]]; then
            info "宸插彇娑堟洿鏂般€?"
            return 0
        fi
        info "寮€濮嬫墽琛屽畼鏂规洿鏂拌剼鏈紙涓嶄緷璧?GitHub API 鐗堟湰鍙锋煡璇級..."
        if ! run_core_install; then
            error "Xray 鏇存柊澶辫触锛? "
            return 1
        fi
        restart_xray || return 1
        success "Xray 鏇存柊娴佺▼宸叉墽琛屽畬鎴愶紙鐗堟湰鍙疯鍥炲埌涓昏彍鍗曟煡鐪嬶級銆?"
        return 0
    fi
    info "褰撳墠鐗堟湰: ${cyan}${current_version}${none}锛屾渶鏂扮増鏈? ${cyan}${latest_version}${none}"
    if [[ "$current_version" == "$latest_version" ]]; then success "鎮ㄧ殑 Xray 宸叉槸鏈€鏂扮増鏈€?" && return; fi
    info "鍙戠幇鏂扮増鏈紝寮€濮嬫洿鏂?.."
    if ! run_core_install; then
        error "Xray 鏇存柊澶辫触锛? "
        return 1
    fi
    if ! restart_xray; then return 1; fi
    success "Xray 鏇存柊鎴愬姛锛?"
}

uninstall_xray() {
    detect_xray_binary >/dev/null 2>&1 || true
    if [[ ! -f "$XRAY_BIN" ]]; then error "閿欒: Xray 鏈畨瑁呫€?" && return; fi
    read -r -p "$(echo -e "${yellow}鎮ㄧ‘瀹氳鍗歌浇 Xray 鍚楋紵杩欏皢鍒犻櫎鎵€鏈夐厤缃紒[Y/n]: ${none}")" confirm || true
    if [[ "$confirm" =~ ^[nN]$ ]]; then info "鎿嶄綔宸插彇娑堛€?"; return; fi
    info "姝ｅ湪鍗歌浇 Xray..."
    if ! execute_official_script "remove --purge"; then
        error "Xray 鍗歌浇澶辫触锛?"
        return 1
    fi
    rm -f ~/xray_subscription_info.txt
    success "Xray 宸叉垚鍔熷嵏杞姐€?"
}

modify_config_menu() {
    if [[ ! -f "$xray_config_path" ]]; then error "閿欒: Xray 鏈畨瑁呫€?" && return; fi

    local vless_exists="" ss_exists=""
    vless_exists=$(jq '.inbounds[] | select(.protocol == "vless")' "$xray_config_path" 2>/dev/null || true)
    ss_exists=$(jq '.inbounds[] | select(.protocol == "shadowsocks")' "$xray_config_path" 2>/dev/null || true)

    if [[ -n "$vless_exists" && -n "$ss_exists" ]]; then
        draw_menu_header
        echo -e "${cyan} 璇烽€夋嫨瑕佷慨鏀圭殑鍗忚閰嶇疆${none}"
        draw_divider
        printf "  ${green}%-2s${none} %-35s\n" "1." "VLESS-Reality"
        printf "  ${cyan}%-2s${none} %-35s\n" "2." "Shadowsocks-2022"
        draw_divider
        printf "  ${yellow}%-2s${none} %-35s\n" "0." "杩斿洖涓昏彍鍗?"
        draw_divider
        read -r -p " 璇疯緭鍏ラ€夐」 [0-2]: " choice || true
        case "$choice" in
            1) modify_vless_config ;;
            2) modify_ss_config ;;
            0) return ;;
            *) error "鏃犳晥閫夐」銆? ";;
        esac
    elif [[ -n "$vless_exists" ]]; then
        modify_vless_config
    elif [[ -n "$ss_exists" ]]; then
        modify_ss_config
    else
        error "鏈壘鍒板彲淇敼鐨勫崗璁厤缃€?"
    fi
}

modify_vless_config() {
    info "寮€濮嬩慨鏀?VLESS-Reality 閰嶇疆..."
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
        read -r -p "$(echo -e " -> 鏂扮鍙?(褰撳墠: ${cyan}${current_port}${none}, 鐣欑┖涓嶆敼): ")" port || true
        [[ -z "$port" ]] && port="$current_port"
        if is_port_available "$port" || [[ "$port" == "$current_port" ]]; then break; fi
    done

    read -r -p "$(echo -e " -> 鏂癠UID (褰撳墠: ${cyan}${current_uuid}${none}, 鐣欑┖涓嶆敼): ")" uuid || true
    [[ -z "$uuid" ]] && uuid="$current_uuid"

    while true; do
        read -r -p "$(echo -e " -> 鏂癝NI鍩熷悕 (褰撳墠: ${cyan}${current_domain}${none}, 鐣欑┖涓嶆敼): ")" domain || true
        [[ -z "$domain" ]] && domain="$current_domain"
        if is_valid_domain "$domain"; then break; else error "鍩熷悕鏍煎紡鏃犳晥锛岃閲嶆柊杈撳叆銆?"; fi
    done

    read -r -p "$(echo -e " -> 鏄惁閲嶆柊鐢熸垚 shortId (褰撳墠: ${cyan}${shortid}${none})? [y/N]: ")" regenerate || true
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
    success "閰嶇疆淇敼鎴愬姛锛?"
    view_all_info
}

modify_ss_config() {
    info "寮€濮嬩慨鏀?Shadowsocks-2022 閰嶇疆..."
    local ss_inbound current_port current_password port password new_ss_inbound vless_inbound new_inbounds
    ss_inbound=$(jq '.inbounds[] | select(.protocol == "shadowsocks")' "$xray_config_path")
    current_port=$(echo "$ss_inbound" | jq -r '.port')
    current_password=$(echo "$ss_inbound" | jq -r '.settings.password')

    while true; do
        read -r -p "$(echo -e " -> 鏂扮鍙?(褰撳墠: ${cyan}${current_port}${none}, 鐣欑┖涓嶆敼): ")" port || true
        [[ -z "$port" ]] && port="$current_port"
        if is_port_available "$port" || [[ "$port" == "$current_port" ]]; then break; fi
    done

    read -r -p "$(echo -e " -> 鏂板瘑閽?(褰撳墠: ${cyan}${current_password}${none}, 鐣欑┖涓嶆敼): ")" password || true
    [[ -z "$password" ]] && password="$current_password"

    new_ss_inbound=$(build_ss_inbound "$port" "$password")
    vless_inbound=$(jq '.inbounds[] | select(.protocol == "vless")' "$xray_config_path" 2>/dev/null || true)
    new_inbounds="[$new_ss_inbound]"
    [[ -n "$vless_inbound" ]] && new_inbounds="[$vless_inbound, $new_ss_inbound]"

    write_config "$new_inbounds"
    if ! restart_xray; then return 1; fi
    success "閰嶇疆淇敼鎴愬姛锛?"
    view_all_info
}

restart_xray() {
    detect_xray_binary >/dev/null 2>&1 || true
    if [[ ! -f "$XRAY_BIN" ]]; then error "閿欒: Xray 鏈畨瑁呫€?" && return 1; fi
    info "姝ｅ湪閲嶅惎 Xray 鏈嶅姟..."
    if ! systemctl restart xray; then
        error "灏濊瘯閲嶅惎 Xray 鏈嶅姟澶辫触锛?"
        echo -e "\n${yellow}閿欒璇︽儏:${none}"
        systemctl status xray --no-pager -l | tail -5
        return 1
    fi
    sleep 2
    if systemctl is-active --quiet xray; then
        success "Xray 鏈嶅姟宸叉垚鍔熼噸鍚紒"
    else
        error "鏈嶅姟鍚姩澶辫触锛岃缁嗕俊鎭?"
        systemctl status xray --no-pager -l | tail -5
        return 1
    fi
}

view_xray_log() {
    detect_xray_binary >/dev/null 2>&1 || true
    if [[ ! -f "$XRAY_BIN" ]]; then error "閿欒: Xray 鏈畨瑁呫€?" && return; fi
    info "姝ｅ湪鏄剧ず Xray 瀹炴椂鏃ュ織... 鎸?Ctrl+C 閫€鍑恒€?"
    journalctl -u xray -f --no-pager
}

view_all_info() {
    if [[ ! -f "$xray_config_path" ]]; then
        [[ "$is_quiet" = true ]] && return
        error "閿欒: 閰嶇疆鏂囦欢涓嶅瓨鍦ㄣ€?"
        return
    fi

    [[ "$is_quiet" = false ]] && clear && echo -e "${cyan} Xray 閰嶇疆鍙婅闃呬俊鎭?{none}" && draw_divider

    local ip host
    ip=$(get_public_ip)
    if [[ -z "$ip" ]]; then
        [[ "$is_quiet" = false ]] && error "鏃犳硶鑾峰彇鍏綉 IP 鍦板潃銆?"
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
            echo -e "${green} [ VLESS-Reality 閰嶇疆 ]${none}"
            printf "    %s: ${cyan}%s${none}\n" "鑺傜偣鍚嶇О" "$link_name_raw"
            printf "    %s: ${cyan}%s${none}\n" "鏈嶅姟鍣ㄥ湴鍧€" "$ip"
            printf "    %s: ${cyan}%s${none}\n" "绔彛" "$port"
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
            echo -e "${green} [ Shadowsocks-2022 閰嶇疆 ]${none}"
            printf "    %s: ${cyan}%s${none}\n" "鑺傜偣鍚嶇О" "$link_name_raw"
            printf "    %s: ${cyan}%s${none}\n" "鏈嶅姟鍣ㄥ湴鍧€" "$ip"
            printf "    %s: ${cyan}%s${none}\n" "绔彛" "$port"
            printf "    %s: ${cyan}%s${none}\n" "鍔犲瘑鏂瑰紡" "$method"
            printf "    %s: ${cyan}%s${none}\n" "瀵嗙爜" "$password"
        fi
    fi

    if [[ ${#links_array[@]} -gt 0 ]]; then
        if [[ "$is_quiet" = true ]]; then
            printf "%s\n" "${links_array[@]}"
        else
            draw_divider
            printf "%s\n" "${links_array[@]}" > ~/xray_subscription_info.txt
            success "鎵€鏈夎闃呴摼鎺ュ凡姹囨€讳繚瀛樺埌: ~/xray_subscription_info.txt"
            echo -e "\n${yellow} --- 瀹㈡埛绔彲鐩存帴瀵煎叆浠ヤ笅閾炬帴 --- ${none}\n"
            for link in "${links_array[@]}"; do
                echo -e "${cyan}${link}${none}\n"
            done
            draw_divider
        fi
    elif [[ "$is_quiet" = false ]]; then
        info "褰撳墠鏈畨瑁呬换浣曞崗璁紝鏃犺闃呬俊鎭彲鏄剧ず銆?"
    fi
}

# --- 鏍稿績瀹夎閫昏緫鍑芥暟 ---
run_install_vless() {
    local port="$1" uuid="$2" domain="$3"
    if [[ -z "$(get_public_ip)" ]]; then
        error "鏃犳硶鑾峰彇鍏綉 IP 鍦板潃锛屽畨瑁呬腑姝€傝妫€鏌ユ偍鐨勭綉缁滆繛鎺ャ€?"
        exit 1
    fi
    run_core_install || exit 1

    info "姝ｅ湪鐢熸垚 Reality 瀵嗛挜瀵?.."
    local key_pair private_key public_key shortid vless_inbound
    key_pair=$(generate_reality_keypair) || exit 1
    private_key=$(echo "$key_pair" | sed -n '1p')
    public_key=$(echo "$key_pair" | sed -n '2p')
    shortid=$(generate_shortid)

    if [[ -z "$private_key" || -z "$public_key" ]]; then
        error "鐢熸垚 Reality 瀵嗛挜瀵瑰け璐ワ紒璇锋鏌?Xray 鏍稿績鏄惁姝ｅ父锛屾垨灏濊瘯鍗歌浇鍚庨噸瑁呫€?"
        exit 1
    fi

    vless_inbound=$(build_vless_inbound "$port" "$uuid" "$domain" "$private_key" "$public_key" "$shortid")
    write_config "[$vless_inbound]"
    if ! restart_xray; then exit 1; fi

    success "VLESS-Reality 瀹夎鎴愬姛锛侊紙shortId 宸查殢鏈虹敓鎴愶級"
    view_all_info
}

run_install_ss() {
    local port="$1" password="$2"
    if [[ -z "$(get_public_ip)" ]]; then
        error "鏃犳硶鑾峰彇鍏綉 IP 鍦板潃锛屽畨瑁呬腑姝€傝妫€鏌ユ偍鐨勭綉缁滆繛鎺ャ€?"
        exit 1
    fi
    run_core_install || exit 1

    local ss_inbound
    ss_inbound=$(build_ss_inbound "$port" "$password")
    write_config "[$ss_inbound]"
    if ! restart_xray; then exit 1; fi

    success "Shadowsocks-2022 瀹夎鎴愬姛锛?"
    view_all_info
}

run_install_dual() {
    local vless_port="$1" vless_uuid="$2" vless_domain="$3" ss_port="$4" ss_password="$5"
    if [[ -z "$(get_public_ip)" ]]; then
        error "鏃犳硶鑾峰彇鍏綉 IP 鍦板潃锛屽畨瑁呬腑姝€傝妫€鏌ユ偍鐨勭綉缁滆繛鎺ャ€?"
        exit 1
    fi
    run_core_install || exit 1

    info "姝ｅ湪鐢熸垚 Reality 瀵嗛挜瀵?.."
    local key_pair private_key public_key shortid vless_inbound ss_inbound
    key_pair=$(generate_reality_keypair) || exit 1
    private_key=$(echo "$key_pair" | sed -n '1p')
    public_key=$(echo "$key_pair" | sed -n '2p')
    shortid=$(generate_shortid)

    if [[ -z "$private_key" || -z "$public_key" ]]; then
        error "鐢熸垚 Reality 瀵嗛挜瀵瑰け璐ワ紒璇锋鏌?Xray 鏍稿績鏄惁姝ｅ父锛屾垨灏濊瘯鍗歌浇鍚庨噸瑁呫€?"
        exit 1
    fi

    vless_inbound=$(build_vless_inbound "$vless_port" "$vless_uuid" "$vless_domain" "$private_key" "$public_key" "$shortid")
    ss_inbound=$(build_ss_inbound "$ss_port" "$ss_password")
    write_config "[$vless_inbound, $ss_inbound]"
    if ! restart_xray; then exit 1; fi

    success "鍙屽崗璁畨瑁呮垚鍔燂紒锛圧eality shortId 宸查殢鏈虹敓鎴愶級"
    view_all_info
}

# --- 涓昏彍鍗曚笌鑴氭湰鍏ュ彛 ---
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
        warning "绔彛 $port 宸茶 ${proto} 鍗犵敤锛屽缓璁€夋嫨鍏朵粬绔彛"
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
        read -r -p "$(echo -e " -> 璇疯緭鍏?Shadowsocks 绔彛 (榛樿: ${cyan}${default_port}${none}): ")" p_port || true
        [[ -z "$p_port" ]] && p_port="$default_port"
        if is_port_available "$p_port"; then break; fi
    done
    info "Shadowsocks 绔彛灏嗕娇鐢?${cyan}${p_port}${none}"

    prompt_for_ss_password p_pass "" "$(echo -e " -> 璇疯緭鍏?Shadowsocks 瀵嗛挜 (鐣欑┖灏嗚嚜鍔ㄧ敓鎴?: ")"
}

modify_ss_config() {
    info "寮€濮嬩慨鏀?Shadowsocks-2022 閰嶇疆..."
    local ss_inbound current_port current_password port password new_ss_inbound vless_inbound new_inbounds
    ss_inbound=$(jq '.inbounds[] | select(.protocol == "shadowsocks")' "$xray_config_path")
    current_port=$(echo "$ss_inbound" | jq -r '.port')
    current_password=$(echo "$ss_inbound" | jq -r '.settings.password')

    while true; do
        read -r -p "$(echo -e " -> 鏂扮鍙?(褰撳墠: ${cyan}${current_port}${none}, 鐣欑┖涓嶆敼): ")" port || true
        [[ -z "$port" ]] && port="$current_port"
        if is_port_available "$port" || [[ "$port" == "$current_port" ]]; then break; fi
    done

    prompt_for_ss_password password "$current_password" "$(echo -e " -> 鏂板瘑閽?(褰撳墠: ${cyan}${current_password}${none}, 鐣欑┖涓嶆敼): ")"

    new_ss_inbound=$(build_ss_inbound "$port" "$password")
    vless_inbound=$(jq '.inbounds[] | select(.protocol == "vless")' "$xray_config_path" 2>/dev/null || true)
    new_inbounds="[$new_ss_inbound]"
    [[ -n "$vless_inbound" ]] && new_inbounds="[$vless_inbound, $new_ss_inbound]"

    write_config "$new_inbounds"
    if ! restart_xray; then return 1; fi
    success "閰嶇疆淇敼鎴愬姛锛?"
    view_all_info
}

execute_official_script() {
    local args="$1" script_content="" curl_rc=0 pid
    script_content=$(curl -fsSL "$xray_install_script_url" 2>/dev/null) || curl_rc=$?
    if [[ "$curl_rc" -ne 0 || -z "$script_content" || ! "$script_content" =~ install-release ]]; then
        error "涓嬭浇 Xray 瀹樻柟瀹夎鑴氭湰澶辫触鎴栧唴瀹瑰紓甯革紒璇锋鏌ョ綉缁滆繛鎺ャ€?"
        return 1
    fi

    echo "$script_content" | bash -s -- $args &>/dev/null &
    pid=$!
    spinner "$pid"
    if ! wait "$pid"; then return 1; fi
}

update_xray() {
    detect_xray_binary >/dev/null 2>&1 || true
    if [[ ! -f "$XRAY_BIN" ]]; then error "閿欒: Xray 鏈畨瑁呫€?" && return; fi
    info "姝ｅ湪妫€鏌ユ渶鏂扮増鏈?.."

    local current_version latest_version yn
    current_version=$("$XRAY_BIN" version 2>/dev/null | head -n 1 | awk '{print $2}' || true)
    current_version=$(echo -n "$current_version" | tr -d '\r\n')
    [[ -z "$current_version" ]] && current_version="鏈煡"

    latest_version=$(curl -fsSL --max-time 8 https://api.github.com/repos/XTLS/Xray-core/releases/latest 2>/dev/null \
        | jq -r '.tag_name' 2>/dev/null \
        | sed 's/^v//' || true)

    if [[ -z "$latest_version" || "$latest_version" == "null" ]]; then
        warning "鑾峰彇鏈€鏂扮増鏈彿澶辫触锛堝彲鑳芥槸缃戠粶/DNS 鎴?GitHub API 闄愭祦锛夈€?"
        echo -e "  褰撳墠鐗堟湰: ${cyan}${current_version}${none}"
        read -r -p "  鏄惁浠嶇劧灏濊瘯鎵ц瀹樻柟鏇存柊鑴氭湰锛焄Y/n]: " yn || true
        if [[ "$yn" =~ ^[nN]$ ]]; then
            info "宸插彇娑堟洿鏂般€?"
            return 0
        fi
        info "寮€濮嬫墽琛屽畼鏂规洿鏂拌剼鏈?.."
        if ! run_core_install; then return 1; fi
        restart_xray || return 1
        success "Xray 鏇存柊娴佺▼宸叉墽琛屽畬鎴愶紙鐗堟湰鍙疯鍥炲埌涓昏彍鍗曟煡鐪嬶級銆?"
        return 0
    fi

    info "褰撳墠鐗堟湰: ${cyan}${current_version}${none}锛屾渶鏂扮増鏈? ${cyan}${latest_version}${none}"
    if [[ "$current_version" == "$latest_version" ]]; then
        success "鎮ㄧ殑 Xray 宸叉槸鏈€鏂扮増鏈€?"
        return 0
    fi

    info "鍙戠幇鏂扮増鏈紝寮€濮嬫洿鏂?.."
    if ! run_core_install; then return 1; fi
    if ! restart_xray; then return 1; fi
    success "Xray 鏇存柊鎴愬姛锛?"
}

main_menu() {
    while true; do
        draw_menu_header
        printf "  ${green}%-2s${none} %-35s\n" "1." "瀹夎 Xray (VLESS/Shadowsocks)"
        printf "  ${cyan}%-2s${none} %-35s\n" "2." "鏇存柊 Xray"
        printf "  ${red}%-2s${none} %-35s\n" "3." "鍗歌浇 Xray"
        draw_divider
        printf "  ${yellow}%-2s${none} %-35s\n" "4." "淇敼閰嶇疆"
        printf "  ${cyan}%-2s${none} %-35s\n" "5." "閲嶅惎 Xray"
        printf "  ${magenta}%-2s${none} %-35s\n" "6." "鏌ョ湅 Xray 鏃ュ織"
        printf "  ${green}%-2s${none} %-35s\n" "7." "鏌ョ湅璁㈤槄淇℃伅"
        draw_divider
        printf "  ${cyan}%-2s${none} %-35s\n" "8." "鏇存柊鑴氭湰 (x.sh)"
        printf "  ${blue}%-2s${none} %-35s\n" "9." "BBR/缃戠粶鏅鸿兘浼樺寲"
        printf "  ${yellow}%-2s${none} %-35s\n" "0." "閫€鍑鸿剼鏈?"
        draw_divider

        read -r -p " 璇疯緭鍏ラ€夐」 [0-9]: " choice || true
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
            0) success "鎰熻阿浣跨敤锛?"; exit 0 ;;
            *) error "鏃犳晥閫夐」銆傝杈撳叆0鍒?涔嬮棿鐨勬暟瀛椼€? ";;
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
