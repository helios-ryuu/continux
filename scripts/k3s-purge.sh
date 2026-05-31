#!/bin/bash
# =================================================================
# k3s-purge.sh
# Mặc định: đưa cluster đang chạy về trạng thái sạch sau khi cài K3s.
# --nuke : xóa dấu vết K3s khỏi node hiện tại.
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

usage() {
    cat <<'EOF'
Cú pháp:
  sudo bash scripts/k3s-purge.sh --nuke [--yes]
      Xóa K3s khỏi node hiện tại: service, binary, cấu hình và trạng thái CNI.
      Chạy trên từng K3s node khi cần xóa hoàn toàn dấu vết cluster.

  bash scripts/k3s-purge.sh [--yes]
      Đưa cluster đang chạy về trạng thái sạch sau khi cài K3s.
      Giữ K3s và node hoạt động, nhưng xóa workload, namespace ứng dụng,
      Helm release/repository, object PV/PVC, app Argo CD và CRD đã biết.
      Nếu có, script cũng dừng và disable redpanda.service trên host.

Tùy chọn:
  --nuke      Xóa dấu vết K3s khỏi node hiện tại.
  -y, --yes   Bỏ qua xác nhận tương tác.
  -h, --help  Hiển thị hướng dẫn này.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --nuke) MODE="purge-node" ;;
        -y|--yes) ASSUME_YES="true" ;;
        -h|--help) usage; exit 0 ;;
        *) die "Tùy chọn không hợp lệ: $1" ;;
    esac
    shift
done

confirm_or_exit() {
    local prompt="$1"
    local expected="$2"

    if [ "$ASSUME_YES" = "true" ]; then
        warn "Bỏ qua xác nhận vì đã truyền --yes."
        return
    fi

    echo -e "${YELLOW}${prompt}${NC}"
    read -r answer
    [ "$answer" = "$expected" ] || die "Nội dung xác nhận không khớp. Đã hủy."
}

kubectl_bin() {
    if command -v kubectl >/dev/null 2>&1; then
        command -v kubectl
    elif command -v k3s >/dev/null 2>&1; then
        echo "k3s kubectl"
    else
        return 1
    fi
}

run_privileged() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        if [ "$ASSUME_YES" = "true" ]; then
            sudo -n "$@"
        else
            sudo "$@"
        fi
    else
        return 1
    fi
}

stop_host_redpanda() {
    command -v systemctl >/dev/null 2>&1 || {
        warn "Không tìm thấy systemctl; bỏ qua bước dọn redpanda.service trên host."
        return 0
    }

    if ! systemctl list-unit-files redpanda.service --no-legend 2>/dev/null | grep -q '^redpanda\.service'; then
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
        for obj in $($KUBECTL -n kube-system get "$kind" -o name 2>/dev/null | grep -E "/(${project_name_pattern})" || true); do
            $KUBECTL -n kube-system delete "$obj" --ignore-not-found=true >/dev/null 2>&1 || true
        done
    done
}

purge_current_node() {
    [ "$(id -u)" -ne 0 ] && die "Hãy chạy bằng sudo: sudo bash scripts/k3s-purge.sh --nuke"

    confirm_or_exit \
        "Thao tác này chỉ xóa dấu vết K3s khỏi node hiện tại. Nhập NUKE để tiếp tục:" \
        "NUKE"

    info "Đang dừng service K3s..."
    systemctl stop k3s k3s-agent 2>/dev/null || true

    info "Đang chạy script killall và uninstall chính thức..."
    [ -f /usr/local/bin/k3s-killall.sh ] && /usr/local/bin/k3s-killall.sh 2>/dev/null || true
    [ -f /usr/local/bin/k3s-uninstall.sh ] && /usr/local/bin/k3s-uninstall.sh 2>/dev/null || true
    [ -f /usr/local/bin/k3s-agent-uninstall.sh ] && /usr/local/bin/k3s-agent-uninstall.sh 2>/dev/null || true

    info "Đang xóa thư mục và cấu hình..."
    rm -rf /etc/rancher /var/lib/rancher /var/lib/kubelet /run/k3s /var/lib/k3s
    rm -rf /etc/cni /opt/cni /var/lib/cni
    rm -rf /var/log/pods /var/log/containers

    info "Đang dọn systemd và binary..."
    rm -f /etc/systemd/system/k3s*
    systemctl daemon-reload
    rm -f /usr/local/bin/k3s /usr/local/bin/kubectl /usr/local/bin/crictl /usr/local/bin/ctr

    info "Đang dọn network interface..."
    ip link delete cni0 2>/dev/null || true
    ip link delete flannel.1 2>/dev/null || true
    rm -rf /var/run/netns/cni-*

    info "Xác minh:"
    command -v k3s >/dev/null 2>&1 || echo "- binary k3s: đã xóa"
    command -v kubectl >/dev/null 2>&1 || echo "- binary kubectl: đã xóa"
    pgrep -fa "k3s|containerd" >/dev/null 2>&1 || echo "- tiến trình K3s/containerd: đã xóa"

    ok "Đã xóa K3s khỏi node hiện tại."
}

reset_cluster() {
    KUBECTL="$(kubectl_bin)" || die "Không tìm thấy kubectl/k3s. Hãy chạy trên K3s server có quyền dùng kubeconfig."

    info "Đang dùng kubectl: ${KUBECTL}"
    $KUBECTL get nodes >/dev/null || die "Không kết nối được Kubernetes API."

    echo -e "${BOLD}Cluster sắp được đưa về trạng thái sạch:${NC}"
    $KUBECTL get nodes -o wide
    echo ""
    warn "Thao tác này giữ K3s nhưng xóa trạng thái ứng dụng khỏi cluster."
    warn "Script xóa Helm release, namespace ngoài hệ thống, object PV/PVC, app Argo CD và CRD đã biết."
    warn "Hãy sao lưu etcd, MinIO và dashboard Grafana trước khi tiếp tục."

    confirm_or_exit \
        "Nhập RESET để đưa cluster về trạng thái sạch sau khi cài K3s:" \
        "RESET"

    info "Đang scale workload ingest đã biết về 0 trước..."
    $KUBECTL -n pipeline scale deploy/vector --replicas=0 --ignore-not-found=true 2>/dev/null || true

    info "Đang xóa finalizer và Application của Argo CD..."
    if $KUBECTL get crd applications.argoproj.io >/dev/null 2>&1; then
        for app in $($KUBECTL -n argocd get applications.argoproj.io -o name 2>/dev/null || true); do
            $KUBECTL -n argocd patch "$app" --type=json \
                -p='[{"op":"remove","path":"/metadata/finalizers"}]' >/dev/null 2>&1 || true
            $KUBECTL -n argocd delete "$app" --ignore-not-found=true >/dev/null 2>&1 || true
        done
    fi

    if command -v helm >/dev/null 2>&1; then
        info "Đang uninstall Helm release..."
        while read -r namespace release; do
            [ -z "${namespace:-}" ] && continue
            [ -z "${release:-}" ] && continue
            helm uninstall "$release" -n "$namespace" >/dev/null 2>&1 || true
        done < <(helm list -A --no-headers 2>/dev/null | awk '{print $2, $1}')

        info "Đang xóa repository khỏi cấu hình Helm cục bộ..."
        while read -r repo; do
            [ -z "${repo:-}" ] && continue
            helm repo remove "$repo" >/dev/null 2>&1 || true
        done < <(helm repo list 2>/dev/null | awk 'NR > 1 {print $1}')
    else
        warn "Không tìm thấy helm; bỏ qua bước dọn Helm release/repository."
    fi

    stop_host_redpanda
    delete_project_leftovers_from_kube_system

    info "Đang xóa tài nguyên ứng dụng khỏi namespace default..."
    $KUBECTL -n default delete deploy,statefulset,daemonset,job,cronjob,pod,replicaset,rc,ingress,networkpolicy,pdb,configmap,secret,pvc,serviceaccount,role,rolebinding \
        --all --ignore-not-found=true --timeout=120s || true
    for svc in $($KUBECTL -n default get svc -o name 2>/dev/null | grep -v '^service/kubernetes$' || true); do
        $KUBECTL -n default delete "$svc" --ignore-not-found=true || true
    done

    info "Đang xóa namespace ngoài hệ thống..."
    for ns in $($KUBECTL get ns -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'); do
        case "$ns" in
            default|kube-system|kube-public|kube-node-lease) continue ;;
        esac
        $KUBECTL delete namespace "$ns" --ignore-not-found=true --timeout=180s || true
    done

    info "Đang xóa object persistent volume..."
    $KUBECTL delete pvc --all -A --ignore-not-found=true --timeout=180s || true
    $KUBECTL delete pv --all --ignore-not-found=true --timeout=180s || true

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
        for crd in $($KUBECTL get crd -o name 2>/dev/null | grep "$pattern" || true); do
            $KUBECTL delete "$crd" --ignore-not-found=true --timeout=120s || true
        done
    done

    info "Đang xóa tài nguyên cluster dự án còn sót..."
    for sc in $($KUBECTL get storageclass -o name 2>/dev/null | grep -E 'minio|risingwave|redpanda|victoria|grafana|argo|vector' || true); do
        $KUBECTL delete "$sc" --ignore-not-found=true || true
    done

    info "Trạng thái cluster cuối:"
    $KUBECTL get nodes -o wide
    $KUBECTL get ns
    ok "Đã đưa cluster về trạng thái sạch. K3s vẫn được cài đặt; hãy áp dụng lại bootstrap/GitOps theo docs/runbook/SETUP.md."
}

case "$MODE" in
    purge-node) purge_current_node ;;
    reset-cluster) reset_cluster ;;
esac
