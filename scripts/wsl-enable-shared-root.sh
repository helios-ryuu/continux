#!/bin/bash
# =================================================================
# wsl-enable-shared-root.sh - Enable shared root mount propagation on WSL.
# Run on: helios-pc WSL node.
# Purpose: allow Kubernetes hostPath mounts with HostToContainer propagation,
#          such as prometheus-node-exporter mounting / as /host/root.
# =================================================================
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'

info() { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()  { echo -e "${RED}[FAIL]${NC}  $*" >&2; exit 1; }

[ "$(id -u)" -ne 0 ] && die "Chạy với sudo: sudo bash $0"

if ! grep -qi microsoft /proc/version 2>/dev/null; then
    warn "Kernel hiện tại không giống WSL. Script này chỉ cần cho node WSL; vẫn tiếp tục nếu bạn chủ động chạy."
fi

if ! command -v systemctl >/dev/null 2>&1; then
    die "Không tìm thấy systemctl. Bật systemd trong /etc/wsl.conf trước."
fi

info "Chuyển root mount / sang rshared cho phiên hiện tại..."
mount --make-rshared /
ok "Root mount hiện tại đã là shared/rshared."

info "Tạo systemd service để áp dụng lại sau mỗi lần WSL boot..."
cat >/etc/systemd/system/wsl-shared-root.service <<'EOF'
[Unit]
Description=Make WSL root mount shared for Kubernetes mount propagation
DefaultDependencies=no
After=local-fs.target
Before=k3s.service

[Service]
Type=oneshot
ExecStart=/usr/bin/mount --make-rshared /
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now wsl-shared-root.service
ok "wsl-shared-root.service đã bật."

if systemctl list-unit-files k3s.service >/dev/null 2>&1; then
    info "Thêm ordering để k3s luôn chạy sau wsl-shared-root.service..."
    mkdir -p /etc/systemd/system/k3s.service.d
    cat >/etc/systemd/system/k3s.service.d/10-wsl-shared-root.conf <<'EOF'
[Unit]
Requires=wsl-shared-root.service
After=wsl-shared-root.service
EOF
    systemctl daemon-reload
    systemctl restart k3s
    ok "k3s đã restart sau khi root mount được chuyển sang rshared."
else
    warn "Chưa thấy k3s.service. Hãy chạy lại script này sau khi cài K3s, hoặc tự thêm drop-in ordering."
fi

echo ""
findmnt -no TARGET,PROPAGATION /
