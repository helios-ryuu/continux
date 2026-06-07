#!/usr/bin/env bash
# Destroy Continux state on the current host while preserving Tailscale.
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

EXECUTE="false"
ASSUME_YES="false"
K3S_PURGE_HELPER_USED="false"

info() { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()  { echo -e "${RED}[FAIL]${NC} $*" >&2; exit 1; }

usage() {
    cat <<'EOF'
Usage:
  bash scripts/nuke.sh
      Dry-run only. Print the host, target user/home, repo path and planned
      Continux removals. No files or services are changed.

  sudo bash scripts/nuke.sh --execute
      Destroy Continux state on the current host after typing NUKE-CONTINUX.

  sudo bash scripts/nuke.sh --execute --yes
      Destroy Continux state without the interactive confirmation. The
      --execute flag is still required.

This script runs locally per node. It does not SSH to other hosts.
It preserves Tailscale package, service, login state and data.
During dry-run it also invokes k3s-purge.sh --nuke --dry-run so the local
K3s uninstall plan is visible without contacting the Kubernetes API.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --execute)
            EXECUTE="true"
            ;;
        -y|--yes)
            ASSUME_YES="true"
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "Unknown option: $1"
            ;;
    esac
    shift
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [ "$(id -u)" -eq 0 ]; then
    TARGET_USER="${SUDO_USER:-root}"
else
    TARGET_USER="${USER:-$(id -un)}"
fi

target_home_for_user() {
    local user="$1"
    local home
    home="$(getent passwd "${user}" 2>/dev/null | cut -d: -f6 || true)"
    if [ -n "${home}" ]; then
        printf '%s\n' "${home}"
        return
    fi
    if [ "${user}" = "$(id -un)" ]; then
        printf '%s\n' "${HOME}"
        return
    fi
    return 1
}

TARGET_HOME="$(target_home_for_user "${TARGET_USER}")" ||
    die "Cannot determine home for user: ${TARGET_USER}"

quote_command() {
    local quoted=""
    printf -v quoted '%q ' "$@"
    printf '%s\n' "${quoted% }"
}

planned() {
    if [ "${EXECUTE}" = "true" ]; then
        info "$(quote_command "$@")"
    else
        echo "DRY-RUN: $(quote_command "$@")"
    fi
}

try_run() {
    planned "$@"
    if [ "${EXECUTE}" != "true" ]; then
        return 0
    fi
    "$@" || warn "Command failed: $(quote_command "$@")"
}

path_exists() {
    [ -e "$1" ] || [ -L "$1" ]
}

assert_safe_rm_target() {
    local path="$1"
    [ -n "${path}" ] || die "Refusing to remove an empty path."
    case "${path}" in
        /|/home|/home/|/root|/root/|/tmp|/tmp/|/usr|/usr/|/usr/local|/usr/local/|/usr/local/bin|/usr/local/bin/|/etc|/etc/|/var|/var/)
            die "Refusing to remove broad path: ${path}"
            ;;
    esac
}

rm_path() {
    local path="$1"
    assert_safe_rm_target "${path}"
    if ! path_exists "${path}"; then
        info "Missing, skip: ${path}"
        return 0
    fi
    planned rm -rf -- "${path}"
    if [ "${EXECUTE}" = "true" ]; then
        rm -rf -- "${path}" || warn "Could not remove: ${path}"
    fi
}

rm_file() {
    local path="$1"
    assert_safe_rm_target "${path}"
    if ! path_exists "${path}"; then
        info "Missing, skip: ${path}"
        return 0
    fi
    planned rm -f -- "${path}"
    if [ "${EXECUTE}" = "true" ]; then
        rm -f -- "${path}" || warn "Could not remove: ${path}"
    fi
}

rmdir_if_empty() {
    local path="$1"
    assert_safe_rm_target "${path}"
    planned rmdir --ignore-fail-on-non-empty "${path}"
    if [ "${EXECUTE}" = "true" ]; then
        rmdir --ignore-fail-on-non-empty "${path}" 2>/dev/null || true
    fi
}

remove_matching_paths() {
    local pattern="$1"
    local matches
    local path

    matches="$(compgen -G "${pattern}" || true)"
    if [ -z "${matches}" ]; then
        info "Missing, skip: ${pattern}"
        return 0
    fi

    while IFS= read -r path; do
        [ -n "${path}" ] || continue
        rm_path "${path}"
    done <<< "${matches}"
}

require_repo_markers() {
    local root="$1"
    [ -d "${root}" ] || return 1
    [ -f "${root}/VERSION" ] || return 1
    [ -f "${root}/docs/runbook/SETUP.md" ] || return 1
    [ -f "${root}/scripts/k3s-purge.sh" ] || return 1
}

remove_continux_repo() {
    local root="$1"
    local label="$2"
    if ! require_repo_markers "${root}"; then
        warn "Skip ${label}; Continux repo markers not found: ${root}"
        return 0
    fi
    rm_path "${root}"
}

confirm_execute() {
    if [ "${EXECUTE}" != "true" ]; then
        return 0
    fi
    [ "$(id -u)" -eq 0 ] || die "Execution requires sudo/root."
    if [ "${ASSUME_YES}" = "true" ]; then
        warn "Skipping interactive confirmation because --yes was provided."
        return 0
    fi
    echo -e "${YELLOW}This will remove Continux from this host and delete the repo/evidence. Tailscale is preserved.${NC}"
    read -r -p "Type NUKE-CONTINUX to continue: " answer
    [ "${answer}" = "NUKE-CONTINUX" ] || die "Confirmation did not match. Aborted."
}

systemctl_available() {
    command -v systemctl >/dev/null 2>&1
}

cleanup_systemd() {
    info "Cleaning Continux systemd units and drop-ins..."
    if systemctl_available; then
        if [ "${K3S_PURGE_HELPER_USED}" = "true" ]; then
            try_run systemctl stop redpanda.service wsl-shared-root.service
            try_run systemctl disable redpanda.service wsl-shared-root.service
        else
            try_run systemctl stop k3s k3s-agent redpanda.service wsl-shared-root.service
            try_run systemctl disable k3s k3s-agent redpanda.service wsl-shared-root.service
        fi
    else
        warn "systemctl not found; skipping service stop/disable."
    fi

    rm_file /etc/systemd/system/wsl-shared-root.service
    rm_file /etc/systemd/system/k3s.service.d/10-wsl-shared-root.conf
    rm_path /etc/systemd/system/k3s.service.d
    if [ "${K3S_PURGE_HELPER_USED}" != "true" ]; then
        remove_matching_paths "/etc/systemd/system/k3s*.service"
    fi

    if systemctl_available; then
        try_run systemctl daemon-reload
    fi
}

run_k3s_nuke() {
    info "Running K3s node purge helper if available..."
    if [ -f "${REPO_ROOT}/scripts/k3s-purge.sh" ]; then
        if [ "${EXECUTE}" = "true" ]; then
            planned bash "${REPO_ROOT}/scripts/k3s-purge.sh" --nuke --yes
            if bash "${REPO_ROOT}/scripts/k3s-purge.sh" --nuke --yes; then
                K3S_PURGE_HELPER_USED="true"
            else
                warn "k3s-purge failed; falling back to nuke local K3s cleanup."
            fi
        else
            if bash "${REPO_ROOT}/scripts/k3s-purge.sh" --nuke --yes --dry-run; then
                K3S_PURGE_HELPER_USED="true"
            else
                warn "k3s-purge dry-run failed; continuing with nuke dry-run."
            fi
        fi
    else
        warn "Missing ${REPO_ROOT}/scripts/k3s-purge.sh; using local cleanup steps only."
    fi
}

cleanup_k3s_leftovers() {
    if [ "${K3S_PURGE_HELPER_USED}" = "true" ]; then
        info "Removing K3s leftovers not covered by k3s-purge helper..."
        rm_file /etc/sysctl.d/99-k3s.conf
        return 0
    fi

    info "Removing K3s, kubelet, CNI and container log leftovers..."
    rm_path /etc/rancher
    rm_path /var/lib/rancher
    rm_path /var/lib/kubelet
    rm_path /run/k3s
    rm_path /var/lib/k3s
    rm_file /etc/sysctl.d/99-k3s.conf
    rm_path /etc/cni
    rm_path /opt/cni
    rm_path /var/lib/cni
    rm_path /var/log/pods
    rm_path /var/log/containers
    remove_matching_paths "/var/run/netns/cni-*"

    rm_file /usr/local/bin/k3s
    rm_file /usr/local/bin/k3s-killall.sh
    rm_file /usr/local/bin/k3s-uninstall.sh
    rm_file /usr/local/bin/k3s-agent-uninstall.sh
    rm_file /usr/local/bin/kubectl
    rm_file /usr/local/bin/crictl
    rm_file /usr/local/bin/ctr

    if command -v ip >/dev/null 2>&1; then
        try_run ip link delete cni0
        try_run ip link delete flannel.1
    else
        warn "ip command not found; skipping CNI interface deletion."
    fi
}

cleanup_ufw_rules() {
    info "Removing Continux/K3s UFW rules while keeping OpenSSH..."
    if ! command -v ufw >/dev/null 2>&1; then
        warn "ufw not found; skipping firewall cleanup."
        return 0
    fi

    try_run ufw --force delete allow from 100.64.0.0/10 to any port 6443 proto tcp
    try_run ufw --force delete allow from 100.64.0.0/10 to any port 2379:2380 proto tcp
    try_run ufw --force delete allow from 100.64.0.0/10 to any port 10250 proto tcp
    try_run ufw --force delete allow from 100.64.0.0/10 to any port 8472 proto udp
    try_run ufw --force delete allow from 10.42.0.0/16 to any
    try_run ufw --force delete allow from 10.43.0.0/16 to any
}

cleanup_project_cli() {
    info "Removing project CLI binaries and local CLI state..."
    rm_file /usr/local/bin/helm
    rm_file /usr/local/bin/argocd
    rm_file /usr/local/bin/mc

    rm_path "${TARGET_HOME}/.config/helm"
    rm_path "${TARGET_HOME}/.cache/helm"
    rm_path "${TARGET_HOME}/.local/share/helm"
    rm_path "${TARGET_HOME}/.argocd"
    rm_path "${TARGET_HOME}/.mc"
}

remove_shell_export_line() {
    local profile_file="${TARGET_HOME}/.bashrc"
    local pattern='^export KUBECONFIG=\$HOME/\.kube/config$'

    if ! path_exists "${profile_file}"; then
        info "Missing, skip: ${profile_file}"
        return 0
    fi
    if ! grep -Eq "${pattern}" "${profile_file}"; then
        info "No Continux KUBECONFIG export found in ${profile_file}"
        return 0
    fi

    if [ "$(id -u)" -eq 0 ] && [ "${TARGET_USER}" != "root" ] && command -v runuser >/dev/null 2>&1; then
        try_run runuser -u "${TARGET_USER}" -- sed -i "\\|${pattern}|d" "${profile_file}"
    else
        try_run sed -i "\\|${pattern}|d" "${profile_file}"
    fi
}

kubeconfig_is_project_generated() {
    local config="$1"
    [ -f "${config}" ] || return 1

    local cluster_count
    cluster_count="$(grep -c '^- cluster:' "${config}" 2>/dev/null || true)"
    [ "${cluster_count}" = "1" ] || return 1

    grep -Eq 'server: https://(127\.0\.0\.1|localhost|100\.[0-9]+\.[0-9]+\.[0-9]+):6443' "${config}"
}

cleanup_kube_user_state() {
    local kube_dir="${TARGET_HOME}/.kube"
    local kube_config="${kube_dir}/config"

    info "Removing project-generated kubeconfig when safe..."
    if kubeconfig_is_project_generated "${kube_config}"; then
        rm_file "${kube_config}"
        rm_path "${kube_dir}/cache"
        rmdir_if_empty "${kube_dir}"
    elif path_exists "${kube_config}"; then
        warn "Leaving ${kube_config}; it does not look like a single Continux/K3s kubeconfig."
    else
        info "Missing, skip: ${kube_config}"
    fi
}

purge_apt_packages() {
    info "Purging project CLI APT packages. Generic setup packages and Tailscale are preserved."
    if ! command -v apt-get >/dev/null 2>&1; then
        warn "apt-get not found; skipping APT purge."
        return 0
    fi

    if [ "${EXECUTE}" = "true" ]; then
        planned env DEBIAN_FRONTEND=noninteractive apt-get -y purge redpanda postgresql-client python3-venv
        env DEBIAN_FRONTEND=noninteractive apt-get -y purge redpanda postgresql-client python3-venv ||
            warn "APT purge failed; inspect package state manually."
    else
        planned env DEBIAN_FRONTEND=noninteractive apt-get -y purge redpanda postgresql-client python3-venv
    fi

    remove_matching_paths "/etc/apt/sources.list.d/redpanda*.list"
    remove_matching_paths "/etc/apt/trusted.gpg.d/redpanda*.gpg"
    remove_matching_paths "/etc/apt/keyrings/redpanda*.gpg"
    remove_matching_paths "/usr/share/keyrings/redpanda*.gpg"
}

cleanup_local_project_state() {
    info "Removing local Continux runtime state and evidence..."
    rm_path "${REPO_ROOT}/data/raw"
    rm_path "${REPO_ROOT}/.venv"
    rm_path "${REPO_ROOT}/scripts/k3s-check"
    rm_path "${REPO_ROOT}/scripts/__pycache__"
    rm_path "${REPO_ROOT}/dashboards/exports"
    rm_path "${REPO_ROOT}/evidence"
    rm_file "${REPO_ROOT}/experiments/results/current.env"
    remove_matching_paths "${REPO_ROOT}/experiments/results/[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]"
    rm_file "${REPO_ROOT}/data/zone/taxi_zone_lookup.csv"
    rm_file "${REPO_ROOT}/data/zone/taxi_zone_lookup_risingwave.csv"
    rm_file /tmp/continux-demo-env.sh
    rm_path "${TARGET_HOME}/continux-demo-evidence"
}

delete_repos_last() {
    info "Deleting Continux checkout(s) last..."
    cd /

    remove_continux_repo "${REPO_ROOT}" "current repo root"

    local home_checkout="${TARGET_HOME}/continux"
    if [ "${home_checkout}" != "${REPO_ROOT}" ]; then
        remove_continux_repo "${home_checkout}" "home checkout"
    fi
}

print_summary() {
    echo -e "${BOLD}=== CONTINUX NUKE ===${NC}"
    echo "Mode        : $([ "${EXECUTE}" = "true" ] && echo execute || echo dry-run)"
    echo "Host        : $(hostname)"
    echo "Target user : ${TARGET_USER}"
    echo "Target home : ${TARGET_HOME}"
    echo "Repo root   : ${REPO_ROOT}"
    echo "Preserved   : Tailscale package, service, login state and data"
    echo ""
}

main() {
    print_summary
    confirm_execute

    if [ "${EXECUTE}" != "true" ]; then
        warn "Dry-run only. Re-run with sudo bash scripts/nuke.sh --execute to delete."
    fi

    run_k3s_nuke
    cleanup_systemd
    cleanup_k3s_leftovers
    cleanup_ufw_rules
    cleanup_project_cli
    remove_shell_export_line
    cleanup_kube_user_state
    purge_apt_packages
    cleanup_local_project_state
    delete_repos_last

    if [ "${EXECUTE}" = "true" ]; then
        ok "Continux nuke completed on this host. Run the script separately on the other nodes."
    else
        ok "Dry-run completed. No changes were made."
    fi
}

main "$@"
