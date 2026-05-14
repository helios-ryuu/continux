#!/bin/bash
# =================================================================
# k3s-install.sh — Cài K3s agent (worker) cho helios hoặc nammn
# Chạy trên : helios hoặc nammn (WSL2 Ubuntu 24.04, bước §5.5 SETUP.md)
# Mục đích  : Join máy phụ trợ vào cụm K3s làm worker khi cần burst
# Cú pháp   : sudo bash k3s-install.sh <tailscale-ip-imac> <token> [node-name]
#             node-name mặc định lấy từ $(hostname) nếu không truyền
# Gỡ worker : từ continux-imac chạy k3s-check.sh rồi drain + delete node
#           : trên node này chạy: sudo /usr/local/bin/k3s-agent-uninstall.sh
# =================================================================
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()   { echo -e "${RED}[FAIL]${NC}  $*" >&2; exit 1; }

# ======================== KIỂM TRA ĐIỀU KIỆN ========================
[ "$(id -u)" -ne 0 ] && die "Chạy với sudo: sudo bash $0 <imac-ip> <token> [node-name]"

command -v tailscale >/dev/null 2>&1 || {
    warn "Tailscale chưa cài. Đang cài Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
    info "Chạy 'sudo tailscale up' rồi chạy lại script này."
    exit 0
}

tailscale status >/dev/null 2>&1 || die "Tailscale chưa kết nối. Chạy: sudo tailscale up"

# ======================== ĐỌC THAM SỐ ========================
IMAC_IP="${1:-}"
K3S_TOKEN="${2:-}"
NODE_NAME="${3:-$(hostname)}"

if [ -z "$IMAC_IP" ]; then
    read -r -p "$(echo -e "${YELLOW}Tailscale IP của continux-imac (100.x.x.x): ${NC}")" IMAC_IP
fi
if [ -z "$K3S_TOKEN" ]; then
    read -r -p "$(echo -e "${YELLOW}Node join token: ${NC}")" K3S_TOKEN
fi

[[ -z "$IMAC_IP" || -z "$K3S_TOKEN" ]] && die "Thiếu IP hoặc token."

TAILSCALE_IP=$(tailscale ip -4 2>/dev/null)
[ -z "$TAILSCALE_IP" ] && die "Không lấy được IP Tailscale (IPv4)."

K3S_URL="https://${IMAC_IP}:6443"

echo -e "\n${BOLD}=== K3s Agent Join — ${NODE_NAME} (worker) ===${NC}"
info "Node name           : ${NODE_NAME}"
info "Tailscale IP local  : ${TAILSCALE_IP}"
info "K3s server (iMac)   : ${K3S_URL}"
echo ""
warn "Node này sẽ join cluster với label workload=heavy (cần gán từ continux-imac sau)."
echo ""
read -r -p "$(echo -e "${YELLOW}Tiếp tục? [y/N]${NC} ")" confirm
[[ "${confirm,,}" == "y" ]] || { info "Đã huỷ."; exit 0; }

# ======================== KIỂM TRA KẾT NỐI ========================
info "Kiểm tra ping đến continux-imac (${IMAC_IP})..."
ping -c 2 -W 3 "${IMAC_IP}" >/dev/null 2>&1 || die "Không ping được ${IMAC_IP}. Kiểm tra Tailscale."
ok "Ping OK"

# ======================== CÀI K3S AGENT ========================
info "Đang cài K3s agent (stable)..."

curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=stable sh -s - agent \
    --server="${K3S_URL}" \
    --token="${K3S_TOKEN}" \
    --node-name="${NODE_NAME}" \
    --node-ip="${TAILSCALE_IP}" \
    --flannel-iface=tailscale0

ok "K3s agent đã cài và đang chạy."

# ======================== HƯỚNG DẪN TIẾP THEO ========================
echo ""
echo -e "${BOLD}=================================================${NC}"
ok "Agent join thành công!"
echo ""
echo -e "${YELLOW}Bước tiếp theo — chạy trên continux-imac:${NC}"
echo -e "  kubectl label node ${NODE_NAME} workload=heavy role=data-plane"
echo -e "  kubectl get nodes -o wide"
echo ""
echo -e "${YELLOW}Khi không cần worker nữa — chạy trên continux-imac:${NC}"
echo -e "  kubectl drain ${NODE_NAME} --ignore-daemonsets --delete-emptydir-data"
echo -e "  kubectl delete node ${NODE_NAME}"
echo -e "${YELLOW}Sau đó trên máy này (WSL2):${NC}"
echo -e "  sudo /usr/local/bin/k3s-agent-uninstall.sh"
echo -e "${BOLD}=================================================${NC}"
