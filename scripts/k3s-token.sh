#!/bin/bash
# =================================================================
# k3s-token.sh - Print the K3s server join token.
# Run on: imac after server #1 is initialized.
# =================================================================
set -euo pipefail

TOKEN_FILE="/var/lib/rancher/k3s/server/node-token"

usage() {
    cat <<'EOF'
Usage:
  bash scripts/k3s-token.sh

Print the K3s server join token from /var/lib/rancher/k3s/server/node-token.
Run on imac after K3s server #1 is initialized.
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
        echo "Unknown option: $1" >&2
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

echo "Cannot read ${TOKEN_FILE}. Run with sudo on a K3s server." >&2
exit 1
