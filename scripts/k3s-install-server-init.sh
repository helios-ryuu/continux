#!/bin/bash
# =================================================================
# Khởi tạo K3s server số 1 với --cluster-init.
# Chạy trên: imac.
# Mục đích: tạo cụm K3s embedded etcd qua Tailscale.
# =================================================================
set -euo pipefail

# ======================== MÀU HIỂN THỊ ========================
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()   { echo -e "${RED}[FAIL]${NC}  $*" >&2; exit 1; }

usage() {
    cat <<'EOF'
Cú pháp:
  sudo bash scripts/k3s-install-server-init.sh

Khởi tạo K3s server số 1 trên imac với embedded etcd qua Tailscale.
EOF
}

case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
    "")
        ;;
    *)
        die "Tham số không hợp lệ: $1"
        ;;
esac

# ======================== KIỂM TRA ĐIỀU KIỆN ========================
[ "$(id -u)" -ne 0 ] && die "Chạy với sudo: sudo bash $0"

command -v tailscale >/dev/null 2>&1 || die "Tailscale chưa cài. Xem docs/runbook/SETUP.md §2.2."
tailscale status >/dev/null 2>&1    || die "Tailscale chưa kết nối. Chạy: sudo tailscale up"

TAILSCALE_IP=$(tailscale ip -4 2>/dev/null)
[ -z "$TAILSCALE_IP" ] && die "Không lấy được IP Tailscale (IPv4)."

NODE_NAME="imac"

echo -e "\n${BOLD}=== K3s Server Init — ${NODE_NAME} ===${NC}"
info "Tailscale IP : ${TAILSCALE_IP}"
info "Node name    : ${NODE_NAME}"
info "Kênh K3s     : stable"
echo ""
read -r -p "$(echo -e "${YELLOW}Tiếp tục cài đặt? [y/N]${NC} ")" confirm
[[ "${confirm,,}" == "y" ]] || { info "Đã huỷ."; exit 0; }

# ======================== CÀI K3S ========================
info "Đang tải và cài K3s (stable)..."

curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=stable INSTALL_K3S_SYMLINK=force sh -s - server \
    --cluster-init \
    --write-kubeconfig-mode=644 \
    --disable=traefik \
    --disable=servicelb \
    --disable=metrics-server \
    --node-name="${NODE_NAME}" \
    --node-ip="${TAILSCALE_IP}" \
    --advertise-address="${TAILSCALE_IP}" \
    --flannel-iface=tailscale0 \
    --tls-san="${TAILSCALE_IP}" \
    --etcd-expose-metrics=true

# ======================== CHỜ API SERVER ========================
info "Đợi K3s API server sẵn sàng..."
for i in $(seq 1 30); do
    kubectl cluster-info >/dev/null 2>&1 && break
    sleep 2
    [ "$i" -eq 30 ] && die "K3s API không phản hồi sau 60s."
done
ok "K3s API server đã sẵn sàng."

# ======================== GÁN LABEL ========================
info "Gán label cho node ${NODE_NAME}..."
kubectl label node "${NODE_NAME}" workload=heavy role=data-plane --overwrite
ok "Label đã gán: workload=heavy, role=data-plane"

# ======================== HIỂN THỊ TOKEN ========================
NODE_TOKEN=$(cat /var/lib/rancher/k3s/server/node-token)

echo ""
echo -e "${BOLD}=================================================${NC}"
ok "Cài đặt hoàn tất!"
echo -e "${YELLOW}Token join node (dùng ở bước tiếp theo):${NC}"
echo -e "${CYAN}${NODE_TOKEN}${NC}"
echo ""
echo -e "${YELLOW}Join server số 2 trên continux-vps:${NC}"
echo -e "  sudo bash scripts/k3s-install-server.sh ${TAILSCALE_IP} <token> continux-vps edge"
echo -e "${YELLOW}Join server số 3 trên helios-pc:${NC}"
echo -e "  sudo bash scripts/k3s-install-server.sh ${TAILSCALE_IP} <token> helios-pc quorum"
echo -e "${BOLD}=================================================${NC}"

# ======================== VERIFY ========================
echo ""
info "Trạng thái cluster:"
kubectl get nodes -o wide
