#!/bin/bash
# =================================================================
# In token dùng để join K3s server.
# Chạy trên: imac sau khi khởi tạo server số 1.
# =================================================================
set -euo pipefail

TOKEN_FILE="/var/lib/rancher/k3s/server/node-token"

usage() {
    cat <<'EOF'
Cú pháp:
  bash scripts/k3s-token.sh

In token join K3s server từ /var/lib/rancher/k3s/server/node-token.
Chạy trên imac sau khi khởi tạo server số 1.
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
        echo "Tham số không hợp lệ: $1" >&2
        usage >&2
        exit 1
        ;;
esac

if [ -r "$TOKEN_FILE" ]; then
    cat "$TOKEN_FILE"
    echo
    exit 0
fi

if command -v sudo >/dev/null 2>&1; then
    sudo cat "$TOKEN_FILE"
    echo
    exit 0
fi

echo "Không đọc được ${TOKEN_FILE}. Hãy chạy bằng sudo trên K3s server." >&2
exit 1
