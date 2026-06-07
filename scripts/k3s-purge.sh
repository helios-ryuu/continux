#!/bin/bash
# =================================================================
# k3s-purge.sh
# Mặc định: đưa cluster đang chạy về trạng thái sạch sau khi cài K3s.
# --nuke/--local-uninstall: xóa dấu vết K3s khỏi node hiện tại, không cần API.
# =================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info() { echo -e "${CYAN}[THÔNG TIN]${NC} $*"; }
ok()   { echo -e "${GREEN}[HOÀN TẤT]${NC} $*"; }
warn() { echo -e "${YELLOW}[LƯU Ý]${NC} $*"; }
die()  { echo -e "${RED}[LỖI]${NC} $*" >&2; exit 1; }

MODE="reset-cluster"
ASSUME_YES="false"
DRY_RUN="false"
KUBECTL=()

usage() {
    cat <<'EOF'
Cú pháp:
  sudo bash scripts/k3s-purge.sh --nuke [--yes] [--dry-run]
  sudo bash scripts/k3s-purge.sh --local-uninstall [--yes] [--dry-run]
      Xóa K3s khỏi node hiện tại: service, binary, cấu hình và trạng thái CNI.
      Chế độ này không cần giao tiếp Kubernetes API và chạy script uninstall
      chính thức nếu còn tồn tại trên host.

  bash scripts/k3s-purge.sh [--yes] [--dry-run]
      Đưa cluster đang chạy về trạng thái sạch sau khi cài K3s.
      Giữ K3s và node hoạt động, nhưng xóa workload, namespace ứng dụng,
      Helm release/repository, object PV/PVC, app Argo CD và CRD đã biết.
      Chế độ này cần Kubernetes API còn phản hồi.

Tùy chọn:
  --nuke, --local-uninstall  Xóa dấu vết K3s khỏi node hiện tại, không cần API.
  -n, --dry-run              Chỉ in thao tác sẽ chạy, không thay đổi hệ thống.
  -y, --yes                  Bỏ qua xác nhận tương tác.
  -h, --help                 Hiển thị hướng dẫn này.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --nuke|--local-uninstall) MODE="purge-node" ;;
        -n|--dry-run) DRY_RUN="true" ;;
        -y|--yes) ASSUME_YES="true" ;;
        -h|--help) usage; exit 0 ;;
        *) die "Tùy chọn không hợp lệ: $1" ;;
    esac
    shift
done

quote_command() {
    local quoted=""
    printf -v quoted '%q ' "$@"
    printf '%s\n' "${quoted% }"
}

planned() {
    if [ "${DRY_RUN}" = "true" ]; then
        echo "DRY-RUN: $(quote_command "$@")"
    else
        info "$(quote_command "$@")"
    fi
}

run_cmd() {
    planned "$@"
    if [ "${DRY_RUN}" = "true" ]; then
        return 0
    fi
    "$@"
}

try_run() {
    run_cmd "$@" || warn "Lệnh lỗi, tiếp tục: $(quote_command "$@")"
}

path_exists() {
    [ -e "$1" ] || [ -L "$1" ]
}

rm_path() {
    local path="$1"
    if ! path_exists "${path}"; then
        info "Không tồn tại, bỏ qua: ${path}"
        return 0
    fi
    try_run rm -rf -- "${path}"
}

rm_file() {
    local path="$1"
    if ! path_exists "${path}"; then
        info "Không tồn tại, bỏ qua: ${path}"
        return 0
    fi
    try_run rm -f -- "${path}"
}

rm_matching() {
    local pattern="$1"
    local matches path
    matches="$(compgen -G "${pattern}" || true)"
    if [ -z "${matches}" ]; then
        info "Không tồn tại, bỏ qua: ${pattern}"
        return 0
    fi
    while IFS= read -r path; do
        [ -n "${path}" ] || continue
        rm_path "${path}"
    done <<< "${matches}"
}

confirm_or_exit() {
    local prompt="$1"
    local expected="$2"

    if [ "${DRY_RUN}" = "true" ]; then
        warn "Dry-run: bỏ qua xác nhận vì sẽ không thay đổi hệ thống."
        return
    fi
    if [ "$ASSUME_YES" = "true" ]; then
        warn "Bỏ qua xác nhận vì đã truyền --yes."
        return
    fi

    echo -e "${YELLOW}${prompt}${NC}"
    read -r answer
    [ "$answer" = "$expected" ] || die "Nội dung xác nhận không khớp. Đã hủy."
}

set_kubectl_cmd() {
    if command -v kubectl >/dev/null 2>&1; then
        KUBECTL=("$(command -v kubectl)")
    elif command -v k3s >/dev/null 2>&1; then
        KUBECTL=("$(command -v k3s)" kubectl)
    else
        return 1
    fi
}

kube_api_available() {
    "${KUBECTL[@]}" get nodes >/dev/null 2>&1
}

run_privileged() {
    if [ "$(id -u)" -eq 0 ]; then
        run_cmd "$@"
    elif command -v sudo >/dev/null 2>&1; then
        if [ "$ASSUME_YES" = "true" ]; then
            run_cmd sudo -n "$@"
        else
            run_cmd sudo "$@"
        fi
    else
        return 1
    fi
}

systemctl_available() {
    command -v systemctl >/dev/null 2>&1
}

stop_host_redpanda() {
    systemctl_available || {
        warn "Không tìm thấy systemctl; bỏ qua bước dọn redpanda.service trên host."
        return 0
    }

    if ! systemctl list-unit-files redpanda.service --no-legend 2>/dev/null | grep -q '^redpanda\.service'; then
        info "Không thấy redpanda.service trên host; bỏ qua."
        return 0
    fi

    info "Đang dừng và disable redpanda.service trên host..."
    if run_privileged systemctl stop redpanda.service; then
        ok "Đã dừng redpanda.service."
    else
        warn "Không dừng được redpanda.service; hãy dừng thủ công nếu service vẫn chạy."
    fi

    if run_privileged systemctl disable redpanda.service; then
        ok "Đã disable redpanda.service."
    else
        warn "Không disable được redpanda.service; hãy xử lý thủ công nếu cần."
    fi
}

delete_project_leftovers_from_kube_system() {
    local kind obj
    local project_name_pattern='argocd|cloudflared|grafana|minio|redpanda|risingwave|vector|victoria|vmagent|vmalert|vmsingle'

    info "Đang xóa tài nguyên dự án còn sót trong kube-system..."
    for kind in service endpoints endpointslice configmap secret serviceaccount role rolebinding; do
        for obj in $("${KUBECTL[@]}" -n kube-system get "$kind" -o name 2>/dev/null | grep -E "/(${project_name_pattern})" || true); do
            try_run "${KUBECTL[@]}" -n kube-system delete "$obj" --ignore-not-found=true
        done
    done
}

run_official_uninstall_scripts() {
    info "Đang chạy script killall và uninstall chính thức nếu còn tồn tại..."
    if [ -f /usr/local/bin/k3s-killall.sh ]; then
        try_run /usr/local/bin/k3s-killall.sh
    else
        info "Không tồn tại, bỏ qua: /usr/local/bin/k3s-killall.sh"
    fi
    if [ -f /usr/local/bin/k3s-uninstall.sh ]; then
        try_run /usr/local/bin/k3s-uninstall.sh
    else
        info "Không tồn tại, bỏ qua: /usr/local/bin/k3s-uninstall.sh"
    fi
    if [ -f /usr/local/bin/k3s-agent-uninstall.sh ]; then
        try_run /usr/local/bin/k3s-agent-uninstall.sh
    else
        info "Không tồn tại, bỏ qua: /usr/local/bin/k3s-agent-uninstall.sh"
    fi
}

purge_current_node() {
    if [ "$(id -u)" -ne 0 ] && [ "${DRY_RUN}" != "true" ]; then
        die "Hãy chạy bằng sudo: sudo bash scripts/k3s-purge.sh --nuke"
    fi

    confirm_or_exit \
        "Thao tác này chỉ xóa dấu vết K3s khỏi node hiện tại. Nhập NUKE để tiếp tục:" \
        "NUKE"

    if systemctl_available; then
        info "Đang dừng service K3s..."
        try_run systemctl stop k3s k3s-agent
    else
        warn "Không tìm thấy systemctl; bỏ qua bước dừng service K3s."
    fi

    run_official_uninstall_scripts

    info "Đang xóa thư mục và cấu hình còn sót..."
    rm_path /etc/rancher
    rm_path /var/lib/rancher
    rm_path /var/lib/kubelet
    rm_path /run/k3s
    rm_path /var/lib/k3s
    rm_path /etc/cni
    rm_path /opt/cni
    rm_path /var/lib/cni
    rm_path /var/log/pods
    rm_path /var/log/containers
    rm_matching "/var/run/netns/cni-*"

    info "Đang dọn systemd và binary còn sót..."
    rm_matching "/etc/systemd/system/k3s*"
    if systemctl_available; then
        try_run systemctl daemon-reload
    fi
    rm_file /usr/local/bin/k3s
    rm_file /usr/local/bin/kubectl
    rm_file /usr/local/bin/crictl
    rm_file /usr/local/bin/ctr
    rm_file /usr/local/bin/k3s-killall.sh
    rm_file /usr/local/bin/k3s-uninstall.sh
    rm_file /usr/local/bin/k3s-agent-uninstall.sh

    info "Đang dọn network interface..."
    if command -v ip >/dev/null 2>&1; then
        try_run ip link delete cni0
        try_run ip link delete flannel.1
    else
        warn "Không tìm thấy lệnh ip; bỏ qua bước xóa network interface."
    fi

    if [ "${DRY_RUN}" = "true" ]; then
        ok "Dry-run hoàn tất; chưa xóa K3s khỏi node hiện tại."
        return
    fi

    info "Xác minh:"
    command -v k3s >/dev/null 2>&1 || echo "- binary k3s: đã xóa"
    command -v kubectl >/dev/null 2>&1 || echo "- binary kubectl: đã xóa"
    pgrep -fa "k3s|containerd" >/dev/null 2>&1 || echo "- tiến trình K3s/containerd: đã xóa"

    ok "Đã xóa K3s khỏi node hiện tại."
}

print_reset_dry_run_without_api() {
    warn "Dry-run không giao tiếp được Kubernetes API; chỉ in kế hoạch reset tổng quát."
    warn "Nếu API thật sự đã chết và mục tiêu là uninstall host, dùng: sudo bash scripts/k3s-purge.sh --nuke"
    echo "DRY-RUN: kubectl -n pipeline scale deploy/vector --replicas=0 --ignore-not-found=true"
    echo "DRY-RUN: remove Argo CD Application finalizers and Applications"
    echo "DRY-RUN: helm uninstall all releases and remove local Helm repos"
    echo "DRY-RUN: delete app resources from default namespace"
    echo "DRY-RUN: delete non-system namespaces"
    echo "DRY-RUN: delete PVC/PV objects"
    echo "DRY-RUN: delete known project CRDs and storage classes"
}

reset_cluster() {
    if ! set_kubectl_cmd; then
        if [ "${DRY_RUN}" = "true" ]; then
            print_reset_dry_run_without_api
            return
        fi
        die "Không tìm thấy kubectl/k3s. Nếu muốn uninstall local, chạy: sudo bash scripts/k3s-purge.sh --nuke"
    fi

    info "Đang dùng kubectl: $(quote_command "${KUBECTL[@]}")"
    if ! kube_api_available; then
        if [ "${DRY_RUN}" = "true" ]; then
            print_reset_dry_run_without_api
            return
        fi
        die "Không kết nối được Kubernetes API. Reset cluster cần API; nếu muốn uninstall local, chạy: sudo bash scripts/k3s-purge.sh --nuke"
    fi

    echo -e "${BOLD}Cluster sắp được đưa về trạng thái sạch:${NC}"
    "${KUBECTL[@]}" get nodes -o wide
    echo ""
    warn "Thao tác này giữ K3s nhưng xóa trạng thái ứng dụng khỏi cluster."
    warn "Script xóa Helm release, namespace ngoài hệ thống, object PV/PVC, app Argo CD và CRD đã biết."
    warn "Hãy sao lưu etcd, MinIO và dashboard Grafana trước khi tiếp tục."

    confirm_or_exit \
        "Nhập RESET để đưa cluster về trạng thái sạch sau khi cài K3s:" \
        "RESET"

    info "Đang scale workload ingest đã biết về 0 trước..."
    try_run "${KUBECTL[@]}" -n pipeline scale deploy/vector --replicas=0 --ignore-not-found=true

    info "Đang xóa finalizer và Application của Argo CD..."
    if "${KUBECTL[@]}" get crd applications.argoproj.io >/dev/null 2>&1; then
        for app in $("${KUBECTL[@]}" -n argocd get applications.argoproj.io -o name 2>/dev/null || true); do
            try_run "${KUBECTL[@]}" -n argocd patch "$app" --type=json \
                -p='[{"op":"remove","path":"/metadata/finalizers"}]'
            try_run "${KUBECTL[@]}" -n argocd delete "$app" --ignore-not-found=true
        done
    fi

    if command -v helm >/dev/null 2>&1; then
        info "Đang uninstall Helm release..."
        while read -r namespace release; do
            [ -z "${namespace:-}" ] && continue
            [ -z "${release:-}" ] && continue
            try_run helm uninstall "$release" -n "$namespace"
        done < <(helm list -A --no-headers 2>/dev/null | awk '{print $2, $1}')

        info "Đang xóa repository khỏi cấu hình Helm cục bộ..."
        while read -r repo; do
            [ -z "${repo:-}" ] && continue
            try_run helm repo remove "$repo"
        done < <(helm repo list 2>/dev/null | awk 'NR > 1 {print $1}')
    else
        warn "Không tìm thấy helm; bỏ qua bước dọn Helm release/repository."
    fi

    stop_host_redpanda
    delete_project_leftovers_from_kube_system

    info "Đang xóa tài nguyên ứng dụng khỏi namespace default..."
    try_run "${KUBECTL[@]}" -n default delete deploy,statefulset,daemonset,job,cronjob,pod,replicaset,rc,ingress,networkpolicy,pdb,configmap,secret,pvc,serviceaccount,role,rolebinding \
        --all --ignore-not-found=true --timeout=120s
    for svc in $("${KUBECTL[@]}" -n default get svc -o name 2>/dev/null | grep -v '^service/kubernetes$' || true); do
        try_run "${KUBECTL[@]}" -n default delete "$svc" --ignore-not-found=true
    done

    info "Đang xóa namespace ngoài hệ thống..."
    for ns in $("${KUBECTL[@]}" get ns -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'); do
        case "$ns" in
            default|kube-system|kube-public|kube-node-lease) continue ;;
        esac
        try_run "${KUBECTL[@]}" delete namespace "$ns" --ignore-not-found=true --timeout=180s
    done

    info "Đang xóa object persistent volume..."
    try_run "${KUBECTL[@]}" delete pvc --all -A --ignore-not-found=true --timeout=180s
    try_run "${KUBECTL[@]}" delete pv --all --ignore-not-found=true --timeout=180s

    info "Đang xóa CRD của stack đã biết..."
    for pattern in \
        'argoproj.io' \
        'operator.victoriametrics.com' \
        'victoriametrics.com' \
        'redpanda.com' \
        'vectorized.io' \
        'risingwave.com' \
        'risingwavelabs.com' \
        'cert-manager.io'
    do
        for crd in $("${KUBECTL[@]}" get crd -o name 2>/dev/null | grep "$pattern" || true); do
            try_run "${KUBECTL[@]}" delete "$crd" --ignore-not-found=true --timeout=120s
        done
    done

    info "Đang xóa tài nguyên cluster dự án còn sót..."
    for sc in $("${KUBECTL[@]}" get storageclass -o name 2>/dev/null | grep -E 'minio|risingwave|redpanda|victoria|grafana|argo|vector' || true); do
        try_run "${KUBECTL[@]}" delete "$sc" --ignore-not-found=true
    done

    if [ "${DRY_RUN}" = "true" ]; then
        ok "Dry-run reset cluster hoàn tất; chưa thay đổi cluster."
        return
    fi

    info "Trạng thái cluster cuối:"
    "${KUBECTL[@]}" get nodes -o wide
    "${KUBECTL[@]}" get ns
    ok "Đã đưa cluster về trạng thái sạch. K3s vẫn được cài đặt; hãy áp dụng lại bootstrap/GitOps theo docs/runbook/SETUP.md."
}

case "$MODE" in
    purge-node) purge_current_node ;;
    reset-cluster) reset_cluster ;;
esac
