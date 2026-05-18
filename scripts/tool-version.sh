#!/bin/bash
# =================================================================
# tool-version.sh — Kiểm tra phiên bản & tình trạng cập nhật
# Chạy trên : continux-imac hoặc bất kỳ Ubuntu node nào trong cụm
# Mục đích  : So sánh phiên bản đã cài với latest stable
#             Hiển thị: ✓ cập nhật | ↑ lỗi thời | ✗ chưa cài | ? không lấy được
# Nguồn     : HTTP redirect (github.com/releases/latest), update.k3s.io, get.helm.sh
#             — không dùng GitHub API, không cần token
# =================================================================
set -o pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; ORANGE='\033[38;5;208m'; BOLD='\033[1m'; NC='\033[0m'

# ======================== HÀM TIỆN ÍCH ========================

# Lấy latest stable tag qua HTTP redirect header — không đụng GitHub API
# github.com/owner/repo/releases/latest → 302 → /releases/tag/vX.Y.Z
latest_gh() {
    local repo="$1"
    local tag
    tag=$(curl -sfI --max-time 8 "https://github.com/${repo}/releases/latest" 2>/dev/null \
        | grep -i '^location:' \
        | sed 's|.*/tag/||' \
        | tr -d '\r\n')
    echo "${tag:-N/A}"
}

# k3s: channel endpoint trả về HTML redirect, parse tag từ href
latest_k3s() {
    local ver
    ver=$(curl -sf --max-time 8 "https://update.k3s.io/v1-release/channels/stable" 2>/dev/null \
        | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+\+k3s[0-9]+' | head -1)
    echo "${ver:-N/A}"
}

# Helm: endpoint binary chính thức của Helm
latest_helm() {
    local ver
    ver=$(curl -sf --max-time 8 "https://get.helm.sh/helm-latest-version" 2>/dev/null | tr -d '\n')
    echo "${ver:-N/A}"
}

# Bỏ prefix v và build metadata
normalize_ver() {
    echo "$1" | sed 's/^v//; s/[+~].*//' | tr -d '[:space:]'
}

# Trả về 0 (true) nếu $1 < $2 theo semver
ver_lt() {
    local a b
    a=$(normalize_ver "$1"); b=$(normalize_ver "$2")
    [ "$a" != "$b" ] && [ "$(printf '%s\n%s' "$a" "$b" | sort -V | head -1)" = "$a" ]
}

# ======================== KIỂM TRA TỪNG TOOL ========================

check_tool() {
    local name="$1" installed="$2" stable="$3"

    local i_norm s_norm status_col
    i_norm=$(normalize_ver "$installed")
    s_norm=$(normalize_ver "$stable")

    if [ -z "$installed" ]; then
        status_col="${RED}✗ chưa cài${NC}"
    elif [ "$stable" = "N/A" ] || [ -z "$stable" ]; then
        status_col="${CYAN}? (không lấy được)${NC}"
    elif [ "$i_norm" = "$s_norm" ] || ver_lt "$stable" "$installed"; then
        status_col="${GREEN}✓ cập nhật${NC}"
    else
        status_col="${ORANGE}↑ lỗi thời → ${stable}${NC}"
    fi

    printf "  ${CYAN}%-16s${NC} %-30s %b\n" "${name}" "${installed:-(chưa cài)}" "$status_col"
}

# ======================== LẤY PHIÊN BẢN ĐÃ CÀI ========================

get_installed() {
    command -v "${1%% *}" >/dev/null 2>&1 || { echo ""; return; }
    eval "$1" 2>/dev/null | head -1 | tr -d '\n' || echo ""
}

ver_os()        { lsb_release -ds 2>/dev/null || grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2; }
ver_kernel()    { uname -r; }
ver_tailscale() { get_installed "tailscale version" | awk '{print $1}'; }
ver_k3s()       { get_installed "k3s --version" | sed 's/k3s version //; s/ (.*//' | xargs; }
ver_kubectl()   { command -v kubectl >/dev/null 2>&1 || { echo ""; return; }
                  kubectl version --client 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+[^ ]*' | head -1; }
ver_helm()      { get_installed "helm version --short" | sed 's/+.*//' | xargs; }
ver_argocd()    { get_installed "argocd version --client 2>/dev/null" | grep '^argocd:' | sed 's/argocd: //; s/+.*//' | xargs; }
ver_rpk()       { get_installed "rpk version" | grep '^rpk version' | sed 's/rpk version: //' | xargs; }
ver_mc()        { get_installed "mc --version" | sed 's/mc version //' | awk '{print $1}'; }
ver_psql()      { get_installed "psql --version" | sed 's/psql (PostgreSQL) //' | xargs; }

# ======================== MAIN ========================

echo -e "\n${BOLD}=== CONTINUX — KIỂM TRA PHIÊN BẢN CÔNG CỤ ===${NC}"
echo -e "${CYAN}$(date '+%Y-%m-%d %H:%M:%S') | $(hostname)${NC}"
echo ""

echo -e "${YELLOW}── Hệ điều hành ──────────────────────────────────────────${NC}"
printf "  ${CYAN}%-16s${NC} %s\n" "OS:" "$(ver_os)"
printf "  ${CYAN}%-16s${NC} %s\n" "Kernel:" "$(ver_kernel)"

APT_COUNT=$(apt list --upgradable 2>/dev/null | grep -c '\[upgradable' || true)
if [ "${APT_COUNT:-0}" -gt 0 ]; then
    printf "  ${CYAN}%-16s${NC} ${ORANGE}%s gói có thể nâng cấp (chạy: sudo apt upgrade)${NC}\n" "APT packages:" "$APT_COUNT"
else
    printf "  ${CYAN}%-16s${NC} ${GREEN}✓ Đã cập nhật${NC}\n" "APT packages:"
fi

echo ""
echo -e "${YELLOW}── CLI Tools ─────────────────────────────────────────────${NC}"
echo -e "  ${CYAN}(Đang kiểm tra phiên bản, vui lòng đợi...)${NC}"
echo ""

# Fetch tất cả song song, ghi vào file tạm
_tmp=$(mktemp -d)

{ latest_gh "tailscale/tailscale"    > "${_tmp}/ts";   } &
{ latest_k3s                         > "${_tmp}/k3s";  } &
{ latest_helm                        > "${_tmp}/helm"; } &
{ latest_gh "argoproj/argo-cd"       > "${_tmp}/argo"; } &
{ latest_gh "redpanda-data/redpanda" > "${_tmp}/rpk";  } &
{ latest_gh "minio/mc"               > "${_tmp}/mc";   } &
wait

_ts_stable=$(cat "${_tmp}/ts")
_k3s_stable=$(cat "${_tmp}/k3s")
_helm_stable=$(cat "${_tmp}/helm")
_argo_stable=$(cat "${_tmp}/argo")
_rpk_stable=$(cat "${_tmp}/rpk")
_mc_stable=$(cat "${_tmp}/mc")

rm -rf "${_tmp}"

check_tool "tailscale"  "$(ver_tailscale)" "${_ts_stable}"
check_tool "k3s"        "$(ver_k3s)"       "${_k3s_stable}"
check_tool "kubectl"    "$(ver_kubectl)"   "${_k3s_stable}"
check_tool "helm"       "$(ver_helm)"      "${_helm_stable}"
check_tool "argocd CLI" "$(ver_argocd)"    "${_argo_stable}"
check_tool "rpk"        "$(ver_rpk)"       "${_rpk_stable}"
check_tool "mc"         "$(ver_mc)"        "${_mc_stable}"

_psql_inst=$(ver_psql)
printf "  ${CYAN}%-16s${NC} %-30s ${CYAN}(APT — chạy apt upgrade để cập nhật)${NC}\n" \
    "psql" "${_psql_inst:-(chưa cài)}"

echo ""
echo -e "${YELLOW}── Ghi chú ───────────────────────────────────────────────${NC}"
echo -e "  ${ORANGE}↑${NC}  = có bản stable mới hơn → xem ${CYAN}SETUP.md mục 'Cập nhật phần mềm (Maintenance)'${NC}"
echo -e "  ${CYAN}?${NC}  = không lấy được phiên bản mới nhất (kiểm tra kết nối mạng)"
echo ""
