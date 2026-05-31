#!/usr/bin/env bash
# Kiểm tra phiên bản công cụ theo vai trò host trong cụm Continux.
set -o pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; ORANGE='\033[38;5;208m'; GRAY='\033[0;90m'
BOLD='\033[1m'; NC='\033[0m'

usage() {
    cat <<'EOF'
Cú pháp:
  bash scripts/tool-version.sh [--profile admin|server|wsl-server]

Vai trò:
  admin       Node quản trị imac: kiểm tra đầy đủ CLI vận hành.
  server      K3s server Linux: chỉ bắt buộc CLI nền của K3s.
  wsl-server  K3s server WSL: giống server và kiểm tra kubectl đi kèm K3s.

Nếu không truyền --profile, script tự suy ra vai trò từ hostname và kernel.
EOF
}

detect_profile() {
    if [ "$(hostname | tr '[:upper:]' '[:lower:]')" = "imac" ]; then
        printf 'admin'
    elif uname -r | grep -qi microsoft; then
        printf 'wsl-server'
    else
        printf 'server'
    fi
}

PROFILE=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --profile)
            PROFILE="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Tham số không hợp lệ: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done
PROFILE="${PROFILE:-$(detect_profile)}"
case "${PROFILE}" in
    admin|server|wsl-server) ;;
    *)
        echo "Vai trò không hợp lệ: ${PROFILE}" >&2
        exit 1
        ;;
esac

latest_gh() {
    local repo="$1"
    local tag
    tag="$(curl -sfI --max-time 8 "https://github.com/${repo}/releases/latest" 2>/dev/null |
        grep -i '^location:' |
        sed 's|.*/tag/||' |
        tr -d '\r\n')"
    echo "${tag:-N/A}"
}

latest_k3s_stable() {
    local version
    version="$(curl -sf --max-time 8 \
        https://update.k3s.io/v1-release/channels/stable 2>/dev/null |
        grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+\+k3s[0-9]+' |
        head -1)"
    echo "${version:-N/A}"
}

latest_helm() {
    local version
    version="$(curl -sf --max-time 8 \
        https://get.helm.sh/helm-latest-version 2>/dev/null |
        tr -d '\n')"
    echo "${version:-N/A}"
}

latest_apt_candidate() {
    local package="$1"
    local version
    version="$(apt-cache policy "${package}" 2>/dev/null |
        sed -n 's/^  Candidate: //p' |
        head -1)"
    [ "${version}" != "(none)" ] || version=""
    echo "${version:-N/A}"
}

normalize_ver() {
    echo "$1" |
        sed 's/^v//; s/[+~].*//; s/-[0-9][0-9]*$//' |
        tr -d '[:space:]'
}

ver_lt() {
    local first second
    first="$(normalize_ver "$1")"
    second="$(normalize_ver "$2")"
    [ "${first}" != "${second}" ] &&
        [ "$(printf '%s\n%s' "${first}" "${second}" | sort -V | head -1)" = "${first}" ]
}

check_tool() {
    local name="$1"
    local installed="$2"
    local published="$3"
    local requirement="$4"
    local note="${5:-}"
    local installed_norm published_norm status

    installed_norm="$(normalize_ver "${installed}")"
    published_norm="$(normalize_ver "${published}")"

    if [ -z "${installed}" ] && [ "${requirement}" = "optional" ]; then
        status="${GRAY}- không bắt buộc trên node này${NC}"
    elif [ -z "${installed}" ]; then
        status="${RED}✗ chưa cài${NC}"
    elif [ "${published}" = "N/A" ] || [ -z "${published}" ]; then
        status="${CYAN}? không lấy được phiên bản công bố${NC}"
    elif [ "${installed_norm}" = "${published_norm}" ]; then
        status="${GREEN}✓ phiên bản mới nhất${NC}"
    elif ver_lt "${published}" "${installed}"; then
        status="${GREEN}✓ mới hơn bản công bố ${published}${NC}"
    else
        status="${ORANGE}↑ cần nâng cấp → ${published}${NC}"
    fi

    printf "  ${CYAN}%-16s${NC} %-30s %b" \
        "${name}" "${installed:-(chưa cài)}" "${status}"
    [ -z "${note}" ] || printf " ${GRAY}(%s)${NC}" "${note}"
    printf '\n'
}

get_installed() {
    command -v "${1%% *}" >/dev/null 2>&1 || return
    eval "$1" 2>/dev/null | head -1 | tr -d '\n'
}

ver_os()        { lsb_release -ds 2>/dev/null || grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2; }
ver_kernel()    { uname -r; }
ver_tailscale() { get_installed "tailscale version" | awk '{print $1}'; }
ver_k3s()       { get_installed "k3s --version" | sed 's/k3s version //; s/ (.*//' | xargs; }
ver_kubectl()   { command -v kubectl >/dev/null 2>&1 || return
                  kubectl version --client 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+[^ ]*' | head -1; }
ver_helm()      { get_installed "helm version --short" | sed 's/+.*//' | xargs; }
ver_argocd()    { get_installed "argocd version --client" | grep '^argocd:' | sed 's/argocd: //; s/+.*//' | xargs; }
ver_rpk()       { get_installed "rpk version" | grep '^rpk version' | sed 's/rpk version: //' | xargs; }
ver_mc()        { get_installed "mc --version" | sed 's/mc version //' | awk '{print $1}'; }
ver_psql()      { get_installed "psql --version" | sed 's/psql (PostgreSQL) //' | xargs; }

echo -e "\n${BOLD}=== CONTINUX - KIỂM TRA PHIÊN BẢN CÔNG CỤ ===${NC}"
echo -e "${CYAN}$(date '+%Y-%m-%d %H:%M:%S') | $(hostname) | vai trò: ${PROFILE}${NC}"
echo ""

echo -e "${YELLOW}-- Hệ điều hành ------------------------------------------------${NC}"
printf "  ${CYAN}%-16s${NC} %s\n" "Hệ điều hành:" "$(ver_os)"
printf "  ${CYAN}%-16s${NC} %s\n" "Kernel:" "$(ver_kernel)"

APT_COUNT="$(apt list --upgradable 2>/dev/null | grep -c '\[upgradable' || true)"
if [ "${APT_COUNT:-0}" -gt 0 ]; then
    printf "  ${CYAN}%-16s${NC} ${ORANGE}%s gói có thể nâng cấp (chạy: sudo apt upgrade)${NC}\n" \
        "Gói APT:" "${APT_COUNT}"
else
    printf "  ${CYAN}%-16s${NC} ${GREEN}✓ phiên bản mới nhất${NC}\n" "Gói APT:"
fi

echo ""
echo -e "${YELLOW}-- Công cụ CLI -------------------------------------------------${NC}"
echo -e "  ${CYAN}(Đang kiểm tra phiên bản công bố, vui lòng đợi...)${NC}"
echo ""

TMP_DIR="$(mktemp -d)"
trap 'rm -rf -- "${TMP_DIR}"' EXIT
{ latest_apt_candidate tailscale           > "${TMP_DIR}/tailscale"; } &
{ latest_k3s_stable                        > "${TMP_DIR}/k3s"; } &
{ latest_helm                              > "${TMP_DIR}/helm"; } &
{ latest_gh argoproj/argo-cd               > "${TMP_DIR}/argocd"; } &
{ latest_gh redpanda-data/redpanda         > "${TMP_DIR}/rpk"; } &
{ latest_gh minio/mc                       > "${TMP_DIR}/mc"; } &
wait

TAILSCALE_LATEST="$(cat "${TMP_DIR}/tailscale")"
K3S_STABLE="$(cat "${TMP_DIR}/k3s")"
HELM_LATEST="$(cat "${TMP_DIR}/helm")"
ARGOCD_LATEST="$(cat "${TMP_DIR}/argocd")"
RPK_LATEST="$(cat "${TMP_DIR}/rpk")"
MC_LATEST="$(cat "${TMP_DIR}/mc")"

check_tool "tailscale"  "$(ver_tailscale)" "${TAILSCALE_LATEST}" required
check_tool "k3s"        "$(ver_k3s)"       "${K3S_STABLE}"      required "kênh stable"
check_tool "kubectl"    "$(ver_kubectl)"   "${K3S_STABLE}"      required "đi kèm K3s"

if [ "${PROFILE}" = "admin" ]; then
    check_tool "helm"       "$(ver_helm)"   "${HELM_LATEST}"   required
    check_tool "argocd CLI" "$(ver_argocd)" "${ARGOCD_LATEST}" required
    check_tool "rpk"        "$(ver_rpk)"    "${RPK_LATEST}"    required
    check_tool "mc"         "$(ver_mc)"     "${MC_LATEST}"     required
    check_tool "psql"       "$(ver_psql)"   "$(ver_psql)"      required "quản lý bằng APT"
else
    check_tool "helm"       "$(ver_helm)"   "${HELM_LATEST}"   optional
    check_tool "argocd CLI" "$(ver_argocd)" "${ARGOCD_LATEST}" optional
    check_tool "rpk"        "$(ver_rpk)"    "${RPK_LATEST}"    optional
    check_tool "mc"         "$(ver_mc)"     "${MC_LATEST}"     optional
    check_tool "psql"       "$(ver_psql)"   "$(ver_psql)"      optional
fi

echo ""
echo -e "${YELLOW}-- Ghi chú ------------------------------------------------------${NC}"
echo -e "  ${ORANGE}↑${NC}  = có phiên bản công bố mới hơn; xem docs/runbook/SETUP.md mục 'Phiên Bản Chuẩn Của Stack'."
echo -e "  ${CYAN}?${NC}  = không lấy được phiên bản công bố; kiểm tra kết nối mạng."
echo -e "  ${GRAY}-${NC}  = công cụ không bắt buộc trên vai trò host hiện tại."
echo ""
