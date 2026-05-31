#!/usr/bin/env bash
# Cập nhật công cụ host theo vai trò mà không cài lại hoặc khởi động lại K3s.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K3S_STABLE_VERSION="v1.35.5+k3s1"
HELM_VERSION="v4.2.0"
ARGOCD_VERSION="v3.4.3"
TAILSCALE_VERSION="1.98.4"
RPK_VERSION="26.1.9"
MC_VERSION="RELEASE.2025-08-13T08-35-41Z"
ADMIN_TMP_DIR=""

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'

info() { echo -e "${CYAN}[THÔNG TIN]${NC} $*"; }
ok()   { echo -e "${GREEN}[HOÀN TẤT]${NC} $*"; }
warn() { echo -e "${YELLOW}[LƯU Ý]${NC} $*"; }
die()  { echo -e "${RED}[LỖI]${NC} $*" >&2; exit 1; }

usage() {
    cat <<'EOF'
Cú pháp:
  sudo bash scripts/host-update.sh <admin|server|wsl-server>

Vai trò:
  admin       Cập nhật APT và CLI quản trị trên imac.
  server      Chuẩn hóa symlink CLI K3s trên server Linux.
  wsl-server  Chuẩn hóa symlink CLI K3s và kiểm tra shared root trên WSL.

Script không cài lại hoặc khởi động lại K3s.
EOF
}

require_root() {
    [ "$(id -u)" -eq 0 ] || die "Hãy chạy bằng sudo."
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Không tìm thấy lệnh bắt buộc: $1"
}

k3s_version() {
    k3s --version | sed -n '1s/^k3s version \([^ ]*\).*/\1/p'
}

verify_k3s_stable() {
    require_command k3s
    local installed
    installed="$(k3s_version)"
    [ "${installed}" = "${K3S_STABLE_VERSION}" ] ||
        die "K3s đang là ${installed:-không xác định}; release này yêu cầu ${K3S_STABLE_VERSION} thuộc kênh stable."
    ok "K3s đúng phiên bản stable ${installed}; service K3s không bị khởi động lại."
}

force_k3s_symlinks() {
    local command_name resolved
    for command_name in kubectl crictl ctr; do
        ln -sfn k3s "/usr/local/bin/${command_name}"
        resolved="$(readlink -f "/usr/local/bin/${command_name}")"
        [ "${resolved}" = "/usr/local/bin/k3s" ] ||
            die "Symlink /usr/local/bin/${command_name} chưa trỏ về /usr/local/bin/k3s."
    done
    ok "kubectl, crictl và ctr đã trỏ về binary K3s."
}

install_admin_tools() {
    local tailscale_package_version redpanda_package_version
    ADMIN_TMP_DIR="$(mktemp -d)"
    trap cleanup_admin_tmp EXIT

    info "Cập nhật danh sách gói APT và nâng các gói đã cài..."
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get -y upgrade
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        curl wget git ca-certificates jq netcat-openbsd unzip \
        postgresql-client python3-venv

    tailscale_package_version="$(apt_package_version tailscale "${TAILSCALE_VERSION}")"
    DEBIAN_FRONTEND=noninteractive apt-get install -y "tailscale=${tailscale_package_version}"

    info "Đăng ký repository Redpanda chính thức và cập nhật rpk..."
    curl -1sLf 'https://dl.redpanda.com/nzc4ZYQK3WRGd9sy/redpanda/cfg/setup/bash.deb.sh' |
        bash
    apt-get update
    redpanda_package_version="$(apt_package_version redpanda "${RPK_VERSION}")"
    DEBIAN_FRONTEND=noninteractive apt-get install -y "redpanda=${redpanda_package_version}"
    if systemctl list-unit-files redpanda.service --no-legend 2>/dev/null |
        grep -q '^redpanda\.service'; then
        systemctl disable --now redpanda.service >/dev/null 2>&1 || true
        ok "Đã tắt redpanda.service trên host; thực nghiệm chỉ dùng Redpanda trong Kubernetes."
    fi

    info "Cài Helm ${HELM_VERSION} bằng installer chính thức..."
    curl -fsSL \
        https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \
        -o "${ADMIN_TMP_DIR}/get-helm.sh"
    chmod 700 "${ADMIN_TMP_DIR}/get-helm.sh"
    DESIRED_VERSION="${HELM_VERSION}" "${ADMIN_TMP_DIR}/get-helm.sh"

    info "Cài Argo CD CLI ${ARGOCD_VERSION}..."
    curl -fsSL \
        "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64" \
        -o "${ADMIN_TMP_DIR}/argocd"
    install -m 755 "${ADMIN_TMP_DIR}/argocd" /usr/local/bin/argocd

    info "Cài MinIO Client từ kênh phát hành chính thức..."
    curl -fsSL \
        "https://dl.min.io/client/mc/release/linux-amd64/archive/mc.${MC_VERSION}" \
        -o "${ADMIN_TMP_DIR}/mc"
    install -m 755 "${ADMIN_TMP_DIR}/mc" /usr/local/bin/mc
}

cleanup_admin_tmp() {
    [ -z "${ADMIN_TMP_DIR:-}" ] || rm -rf -- "${ADMIN_TMP_DIR}"
}

apt_package_version() {
    local package_name="$1"
    local wanted_version="$2"
    local package_version
    package_version="$(
        apt-cache madison "${package_name}" |
            awk -v wanted="${wanted_version}" '$3 ~ ("^" wanted "([.+~-]|$)") { print $3; exit }'
    )"
    [ -n "${package_version}" ] ||
        die "APT không có ${package_name} phiên bản ${wanted_version}."
    printf '%s\n' "${package_version}"
}

verify_shared_root() {
    require_command findmnt
    local propagation
    propagation="$(findmnt -no PROPAGATION /)"
    [ "${propagation}" = "shared" ] ||
        die "Root mount của WSL đang là ${propagation:-không xác định}; hãy chạy scripts/wsl-enable-shared-root.sh."
    ok "Root mount của WSL đang ở chế độ shared."
}

main() {
    local profile="${1:-}"
    case "${profile}" in
        -h|--help)
            usage
            return
            ;;
        admin|server|wsl-server) ;;
        *)
            usage >&2
            die "Vai trò không hợp lệ: ${profile:-trống}"
            ;;
    esac

    require_root
    verify_k3s_stable
    force_k3s_symlinks

    case "${profile}" in
        admin)
            install_admin_tools
            ;;
        wsl-server)
            verify_shared_root
            ;;
    esac

    ok "Đã cập nhật host theo vai trò ${profile}."
    bash "${SCRIPT_DIR}/tool-version.sh" --profile "${profile}"
}

main "$@"
