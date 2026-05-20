#!/bin/bash
# =================================================================
# k3s-install-server.sh — Join thêm K3s server vào cluster hiện có
# Chạy trên : continux-vps hoặc helios-wsl Ubuntu 24.04 (SETUP.md §5)
# Mục đích  : Tạo cụm embedded etcd 3 server: imac + vps + helios-wsl
# Cú pháp   : sudo bash k3s-install-server.sh <tailscale-ip-imac> <token> [node-name] [profile]
# Profile   : edge | quorum
# =================================================================
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
die()   { echo -e "${RED}[FAIL]${NC}  $*" >&2; exit 1; }

# ======================== KIỂM TRA ĐIỀU KIỆN ========================
[ "$(id -u)" -ne 0 ] && die "Chạy với sudo: sudo bash $0 <imac-ip> <token> [node-name] [profile]"

command -v tailscale >/dev/null 2>&1 || die "Tailscale chưa cài. Xem SETUP.md §4."
tailscale status >/dev/null 2>&1    || die "Tailscale chưa kết nối. Chạy: sudo tailscale up"

# ======================== ĐỌC THAM SỐ ========================
IMAC_IP="${1:-}"
K3S_TOKEN="${2:-}"
NODE_NAME="${3:-$(hostname)}"
PROFILE="${4:-}"

if [ -z "$IMAC_IP" ]; then
    read -r -p "$(echo -e "${YELLOW}Tailscale IP của continux-imac (100.x.x.x): ${NC}")" IMAC_IP
fi
if [ -z "$K3S_TOKEN" ]; then
    read -r -p "$(echo -e "${YELLOW}Node join token (từ k3s-install-server-init.sh): ${NC}")" K3S_TOKEN
fi
if [ -z "$NODE_NAME" ]; then
    read -r -p "$(echo -e "${YELLOW}Node name (vd: continux-vps hoặc helios-wsl): ${NC}")" NODE_NAME
fi

[[ -z "$IMAC_IP" || -z "$K3S_TOKEN" || -z "$NODE_NAME" ]] && die "Thiếu IP, token hoặc node-name."

if [ -z "$PROFILE" ]; then
    case "$NODE_NAME" in
        continux-vps) PROFILE="edge" ;;
        *) PROFILE="quorum" ;;
    esac
fi

case "$PROFILE" in
    edge|quorum) ;;
    *) die "Profile không hợp lệ: ${PROFILE}. Chỉ dùng edge hoặc quorum." ;;
esac

TAILSCALE_IP=$(tailscale ip -4 2>/dev/null)
[ -z "$TAILSCALE_IP" ] && die "Không lấy được IP Tailscale (IPv4)."

K3S_URL="https://${IMAC_IP}:6443"

echo -e "\n${BOLD}=== K3s Server Join — ${NODE_NAME} ===${NC}"
info "Tailscale IP local  : ${TAILSCALE_IP}"
info "Tailscale IP iMac   : ${IMAC_IP}"
info "K3s URL             : ${K3S_URL}"
info "Node name           : ${NODE_NAME}"
info "Profile             : ${PROFILE}"
echo ""
read -r -p "$(echo -e "${YELLOW}Tiếp tục cài đặt? [y/N]${NC} ")" confirm
[[ "${confirm,,}" == "y" ]] || { info "Đã huỷ."; exit 0; }

# ======================== KIỂM TRA KẾT NỐI ========================
info "Kiểm tra ping đến continux-imac..."
ping -c 2 -W 3 "${IMAC_IP}" >/dev/null 2>&1 || die "Không ping được ${IMAC_IP}. Kiểm tra Tailscale."
ok "Ping OK"

# ======================== CÀI K3S ========================
info "Đang tải và cài K3s (stable)..."

curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=stable sh -s - server \
    --server="${K3S_URL}" \
    --token="${K3S_TOKEN}" \
    --write-kubeconfig-mode=644 \
    --disable=traefik \
    --disable=servicelb \
    --disable=local-storage \
    --disable=metrics-server \
    --node-name="${NODE_NAME}" \
    --node-ip="${TAILSCALE_IP}" \
    --advertise-address="${TAILSCALE_IP}" \
    --flannel-iface=tailscale0 \
    --tls-san="${TAILSCALE_IP}" \
    --etcd-expose-metrics=true

# ======================== GÁN LABEL + TAINT ========================
info "Đợi node ${NODE_NAME} xuất hiện trong cluster..."
for i in $(seq 1 30); do
    kubectl get node "${NODE_NAME}" >/dev/null 2>&1 && break
    sleep 3
    [ "$i" -eq 30 ] && die "Node ${NODE_NAME} không xuất hiện sau 90s."
done

info "Gán label và taint cho ${NODE_NAME}..."
if [ "$PROFILE" = "edge" ]; then
    kubectl label node "${NODE_NAME}" workload=light role=control-plane --overwrite
    kubectl taint node "${NODE_NAME}" dedicated=edge:NoSchedule --overwrite
    ok "Label: workload=light, role=control-plane | Taint: dedicated=edge:NoSchedule"
else
    kubectl label node "${NODE_NAME}" workload=quorum role=quorum --overwrite
    kubectl taint node "${NODE_NAME}" dedicated=quorum:NoSchedule --overwrite
    ok "Label: workload=quorum, role=quorum | Taint: dedicated=quorum:NoSchedule"
fi

echo ""
echo -e "${BOLD}=================================================${NC}"
ok "Cài đặt hoàn tất!"
echo -e "${BOLD}=================================================${NC}"

kubectl get nodes -o wide
