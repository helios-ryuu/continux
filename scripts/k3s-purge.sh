#!/bin/bash
# =================================================================
# k3s-purge.sh
# Default : reset the running cluster to a clean post-K3s-install state.
# --nuke  : remove K3s traces from the current node.
# =================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info() { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()  { echo -e "${RED}[FAIL]${NC}  $*" >&2; exit 1; }

MODE="reset-cluster"
ASSUME_YES="false"

usage() {
    cat <<'EOF'
Usage:
  sudo bash scripts/k3s-purge.sh --nuke [--yes]
      Remove K3s from the current node: services, binaries, configs, CNI state.
      Run this on every K3s node when you want no K3s cluster traces left.

  bash scripts/k3s-purge.sh [--yes]
      Reset the running cluster to a clean post-K3s-install state.
      Keeps K3s and nodes running, but deletes workloads, app namespaces,
      Helm releases/repositories, PV/PVC objects, ArgoCD apps, and known
      stack CRDs. If present, it also stops/disables host redpanda.service.

Options:
  --nuke      Remove K3s traces from the current node.
  -y, --yes   Skip interactive confirmation.
  -h, --help  Show this help.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --nuke) MODE="purge-node" ;;
        -y|--yes) ASSUME_YES="true" ;;
        -h|--help) usage; exit 0 ;;
        *) die "Unknown option: $1" ;;
    esac
    shift
done

confirm_or_exit() {
    local prompt="$1"
    local expected="$2"

    if [ "$ASSUME_YES" = "true" ]; then
        warn "Skipping confirmation because --yes was provided."
        return
    fi

    echo -e "${YELLOW}${prompt}${NC}"
    read -r answer
    [ "$answer" = "$expected" ] || die "Confirmation mismatch. Aborted."
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
        warn "systemctl not found; skipping host redpanda.service cleanup."
        return 0
    }

    if ! systemctl list-unit-files redpanda.service --no-legend 2>/dev/null | grep -q '^redpanda\.service'; then
        return 0
    fi

    info "Stopping and disabling host redpanda.service..."
    if run_privileged systemctl stop redpanda.service; then
        ok "Stopped redpanda.service."
    else
        warn "Could not stop redpanda.service; stop it manually if it is still running."
    fi

    if run_privileged systemctl disable redpanda.service; then
        ok "Disabled redpanda.service."
    else
        warn "Could not disable redpanda.service; disable it manually if needed."
    fi
}

delete_project_leftovers_from_kube_system() {
    local kind obj
    local project_name_pattern='argocd|cloudflared|grafana|minio|redpanda|risingwave|vector|victoria|vmagent|vmalert|vmsingle'

    info "Deleting known project leftovers from kube-system..."
    for kind in service endpoints endpointslice configmap secret serviceaccount role rolebinding; do
        for obj in $($KUBECTL -n kube-system get "$kind" -o name 2>/dev/null | grep -E "/(${project_name_pattern})" || true); do
            $KUBECTL -n kube-system delete "$obj" --ignore-not-found=true >/dev/null 2>&1 || true
        done
    done
}

purge_current_node() {
    [ "$(id -u)" -ne 0 ] && die "Run with sudo: sudo bash scripts/k3s-purge.sh --nuke"

    confirm_or_exit \
        "This will remove K3s traces from ONLY this node. Type NUKE to continue:" \
        "NUKE"

    info "Stopping K3s services..."
    systemctl stop k3s k3s-agent 2>/dev/null || true

    info "Running official killall and uninstall scripts..."
    [ -f /usr/local/bin/k3s-killall.sh ] && /usr/local/bin/k3s-killall.sh 2>/dev/null || true
    [ -f /usr/local/bin/k3s-uninstall.sh ] && /usr/local/bin/k3s-uninstall.sh 2>/dev/null || true
    [ -f /usr/local/bin/k3s-agent-uninstall.sh ] && /usr/local/bin/k3s-agent-uninstall.sh 2>/dev/null || true

    info "Removing directories and configurations..."
    rm -rf /etc/rancher /var/lib/rancher /var/lib/kubelet /run/k3s /var/lib/k3s
    rm -rf /etc/cni /opt/cni /var/lib/cni
    rm -rf /var/log/pods /var/log/containers

    info "Cleaning up systemd and binaries..."
    rm -f /etc/systemd/system/k3s*
    systemctl daemon-reload
    rm -f /usr/local/bin/k3s /usr/local/bin/kubectl /usr/local/bin/crictl /usr/local/bin/ctr

    info "Cleaning up network interfaces..."
    ip link delete cni0 2>/dev/null || true
    ip link delete flannel.1 2>/dev/null || true
    rm -rf /var/run/netns/cni-*

    info "Verification:"
    command -v k3s >/dev/null 2>&1 || echo "- k3s binary: cleared"
    command -v kubectl >/dev/null 2>&1 || echo "- kubectl binary: cleared"
    pgrep -fa "k3s|containerd" >/dev/null 2>&1 || echo "- K3s/containerd processes: cleared"

    ok "K3s has been removed from this node."
}

reset_cluster() {
    KUBECTL="$(kubectl_bin)" || die "kubectl/k3s not found. Run this from a K3s server with kubeconfig access."

    info "Using kubectl: ${KUBECTL}"
    $KUBECTL get nodes >/dev/null || die "Cannot reach Kubernetes API."

    echo -e "${BOLD}Cluster that will be reset:${NC}"
    $KUBECTL get nodes -o wide
    echo ""
    warn "This keeps K3s installed, but deletes application state from the cluster."
    warn "It deletes Helm releases, non-system namespaces, PV/PVC objects, ArgoCD apps, and known stack CRDs."
    warn "Back up etcd, MinIO, and Grafana dashboards before continuing."

    confirm_or_exit \
        "Type RESET to reset this cluster to a clean post-K3s-install state:" \
        "RESET"

    info "Scaling known ingest workloads down first..."
    $KUBECTL -n pipeline scale deploy/vector --replicas=0 --ignore-not-found=true 2>/dev/null || true

    info "Removing ArgoCD Application finalizers and Applications..."
    if $KUBECTL get crd applications.argoproj.io >/dev/null 2>&1; then
        for app in $($KUBECTL -n argocd get applications.argoproj.io -o name 2>/dev/null || true); do
            $KUBECTL -n argocd patch "$app" --type=json \
                -p='[{"op":"remove","path":"/metadata/finalizers"}]' >/dev/null 2>&1 || true
            $KUBECTL -n argocd delete "$app" --ignore-not-found=true >/dev/null 2>&1 || true
        done
    fi

    if command -v helm >/dev/null 2>&1; then
        info "Uninstalling Helm releases..."
        while read -r namespace release; do
            [ -z "${namespace:-}" ] && continue
            [ -z "${release:-}" ] && continue
            helm uninstall "$release" -n "$namespace" >/dev/null 2>&1 || true
        done < <(helm list -A --no-headers 2>/dev/null | awk '{print $2, $1}')

        info "Removing Helm repositories from local Helm config..."
        while read -r repo; do
            [ -z "${repo:-}" ] && continue
            helm repo remove "$repo" >/dev/null 2>&1 || true
        done < <(helm repo list 2>/dev/null | awk 'NR > 1 {print $1}')
    else
        warn "helm not found; skipping Helm release/repository cleanup."
    fi

    stop_host_redpanda
    delete_project_leftovers_from_kube_system

    info "Deleting application resources from default namespace..."
    $KUBECTL -n default delete deploy,statefulset,daemonset,job,cronjob,pod,replicaset,rc,ingress,networkpolicy,pdb,configmap,secret,pvc,serviceaccount,role,rolebinding \
        --all --ignore-not-found=true --timeout=120s || true
    for svc in $($KUBECTL -n default get svc -o name 2>/dev/null | grep -v '^service/kubernetes$' || true); do
        $KUBECTL -n default delete "$svc" --ignore-not-found=true || true
    done

    info "Deleting non-system namespaces..."
    for ns in $($KUBECTL get ns -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'); do
        case "$ns" in
            default|kube-system|kube-public|kube-node-lease) continue ;;
        esac
        $KUBECTL delete namespace "$ns" --ignore-not-found=true --timeout=180s || true
    done

    info "Deleting persistent volume objects..."
    $KUBECTL delete pvc --all -A --ignore-not-found=true --timeout=180s || true
    $KUBECTL delete pv --all --ignore-not-found=true --timeout=180s || true

    info "Deleting known stack CRDs..."
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

    info "Deleting leftover project cluster resources..."
    for sc in $($KUBECTL get storageclass -o name 2>/dev/null | grep -E 'minio|risingwave|redpanda|victoria|grafana|argo|vector' || true); do
        $KUBECTL delete "$sc" --ignore-not-found=true || true
    done

    info "Final cluster state:"
    $KUBECTL get nodes -o wide
    $KUBECTL get ns
    ok "Đã reset cluster. K3s vẫn được cài đặt; hãy áp dụng lại bootstrap/GitOps theo docs/runbook/SETUP.md."
}

case "$MODE" in
    purge-node) purge_current_node ;;
    reset-cluster) reset_cluster ;;
esac
