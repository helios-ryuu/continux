#!/bin/bash
# =================================================================
# k3s-check.sh — K3s Cluster Check
# Chạy trên : imac (node quản trị cluster)
# Mục đích  : Kiểm tra tổng thể cụm K3s: node, pod, PVC, workload,
#             image, Helm release/repo, secrets, tài nguyên hệ thống
# Cú pháp   : bash k3s-check.sh [-e|--explain] [section] [args]
# =================================================================

set -o pipefail
K3S_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CK_DIR="$K3S_DIR/k3s-check"
EXPLAIN=false

# ======================== COLORS ========================
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
ORANGE='\033[38;5;208m'
BOLD='\033[1m'
NC='\033[0m'

# ======================== CORE CHECKS ========================
check_dependencies() {
    local deps=("kubectl" "jq" "awk" "column" "ping")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            echo -e "${RED}✖ Lỗi: Không tìm thấy '$dep'. Vui lòng cài đặt trước khi chạy script.${NC}"
            exit 1
        fi
    done
}

check_k3s_connection() {
    if ! kubectl cluster-info >/dev/null 2>&1; then
        echo -e "${RED}✖ Lỗi: Không thể kết nối đến K3s API.${NC}"
        echo -e "${YELLOW}Gợi ý kiểm tra nhanh trên node hiện tại:${NC}"
        echo "  sudo systemctl status k3s --no-pager"
        echo "  sudo journalctl -u k3s -n 80 --no-pager"
        echo "  sudo cat /etc/systemd/system/k3s.service"
        echo "  sudo ss -lntp | grep 6443"
        echo "  kubectl config current-context"
        echo ""
        echo -e "${ORANGE}Nếu vừa chạy lệnh generic 'curl -sfL https://get.k3s.io | ... sh -', service có thể đã bị ghi đè thiếu flags Tailscale/etcd.${NC}"
        exit 1
    fi
}

strip_colors() {
    sed -r 's/\x1B\[[0-9;]*[mK]//g'
}

color_for_pct() {
    local pct="${1%.*}"
    [[ "$pct" =~ ^[0-9]+$ ]] || pct=0
    if [ "$pct" -lt 60 ]; then
        printf "%b" "$GREEN"
    elif [ "$pct" -lt 80 ]; then
        printf "%b" "$YELLOW"
    elif [ "$pct" -lt 90 ]; then
        printf "%b" "$ORANGE"
    else
        printf "%b" "$RED"
    fi
}

color_for_health_pct() {
    local pct="${1%.*}"
    [[ "$pct" =~ ^[0-9]+$ ]] || pct=0
    if [ "$pct" -ge 90 ]; then
        printf "%b" "$GREEN"
    elif [ "$pct" -ge 75 ]; then
        printf "%b" "$YELLOW"
    elif [ "$pct" -ge 60 ]; then
        printf "%b" "$ORANGE"
    else
        printf "%b" "$RED"
    fi
}

status_color() {
    case "$1" in
        Ready|Running|Bound|deployed|ok|healthy) printf "%b" "$GREEN" ;;
        Succeeded|Complete|completed) printf "%b" "$BLUE" ;;
        Pending|ContainerCreating|progressing|waiting) printf "%b" "$YELLOW" ;;
        Terminating|warning|stale) printf "%b" "$ORANGE" ;;
        *) printf "%b" "$RED" ;;
    esac
}

bar_pct() {
    local pct="${1%.*}"
    local width="${2:-24}"
    local mode="${3:-usage}"
    [[ "$pct" =~ ^[0-9]+$ ]] || pct=0
    [ "$pct" -lt 0 ] && pct=0
    [ "$pct" -gt 100 ] && pct=100
    local fill=$((pct * width / 100))
    local empty=$((width - fill))
    local color
    if [ "$mode" = "health" ]; then
        color=$(color_for_health_pct "$pct")
    else
        color=$(color_for_pct "$pct")
    fi

    printf "%b[" "$color"
    for ((i = 0; i < fill; i++)); do printf "█"; done
    for ((i = 0; i < empty; i++)); do printf "░"; done
    printf "]%b %3d%%" "$NC" "$pct"
}

bar_count() {
    local value="${1:-0}"
    local max="${2:-0}"
    local width="${3:-24}"
    local pct=0
    [[ "$value" =~ ^[0-9]+$ ]] || value=0
    [[ "$max" =~ ^[0-9]+$ ]] || max=0
    if [ "$max" -gt 0 ]; then
        pct=$((value * 100 / max))
    fi
    bar_pct "$pct" "$width"
}

section_header() {
    echo -e "\n${BLUE}${BOLD}--- [$1] $2 ---${NC}"
}

metric_ratio() {
    local label="$1"
    local good="$2"
    local total="$3"
    local suffix="$4"
    local pct=0
    [ "$total" -gt 0 ] && pct=$((good * 100 / total))
    printf "  ${CYAN}%-18s${NC} %b  %s/%s %s\n" "$label" "$(bar_pct "$pct" 22 health)" "$good" "$total" "$suffix"
}

print_ns_grouped_table() {
    local data="$1"
    local header="$2"
    local group_indent="${3:-     }"
    local row_indent="${4:-        }"
    local rows ns_list ns

    rows=$(printf "%b" "$data" | awk 'NF {print}')
    [ -z "$rows" ] && return

    ns_list=$(printf "%s\n" "$rows" | awk -F'\t' 'NF && $1 != "" {print $1}' | sort -u)
    while IFS= read -r ns; do
        [ -z "$ns" ] && continue
        echo -e "${group_indent}${ORANGE}>> $ns${NC}"
        (
            echo -e "${YELLOW}${header}${NC}"
            printf "%s\n" "$rows" | awk -F'\t' -v ns="$ns" 'BEGIN{OFS="\t"} $1 == ns {$1=""; sub(/^\t/, ""); print}'
        ) | column -t -s $'\t' | sed "s/^/${row_indent}/"
    done <<< "$ns_list"
}

# ======================== TIMING ========================
section_timed() {
    local start=$(date +%s%N)
    "$@"
    local ms=$(( ($(date +%s%N) - start) / 1000000 ))
    echo -e "  ${CYAN}(${ms}ms)${NC}"
}

# ======================== EXPLAIN MODE ========================
explain() {
    $EXPLAIN || return
    echo -e "  ${CYAN}ⓘ $*${NC}"
}

explain_item() {
    $EXPLAIN || return
    printf "  ${CYAN}%-12s${NC} %s\n" "$1" "$2"
}

explain_suffix() {
    $EXPLAIN && printf " ${CYAN}(%s)${NC}" "$1"
}

# ======================== CACHE ========================
_cache_loaded=false
load_cache() {
    [ "$_cache_loaded" = true ] && return

    RAW_NODES_JSON=$(kubectl get nodes -o json 2>/dev/null)
    RAW_PODS_JSON=$(kubectl get pods -A -o json 2>/dev/null)
    RAW_PVC_JSON=$(kubectl get pvc -A -o json 2>/dev/null)
    RAW_WORKLOADS_JSON=$(kubectl get deploy,sts,ds -A -o json 2>/dev/null)
    RAW_SVC_JSON=$(kubectl get svc -A -o json 2>/dev/null)
    RAW_SECRETS_JSON=$(kubectl get secrets -A -o json 2>/dev/null)
    RAW_HPA_JSON=$(kubectl get hpa -A -o json 2>/dev/null)

    # Validate API response
    if [ -z "$RAW_NODES_JSON" ] || ! echo "$RAW_NODES_JSON" | jq -e '.items' >/dev/null 2>&1; then
        echo -e "${RED}✖ K3s API không phản hồi hoặc dữ liệu rỗng. Kiểm tra: kubectl cluster-info${NC}"
        exit 1
    fi

    # Build Tailscale IP maps (both IP→IP and hostname→IP)
    declare -gA TS_IPS TS_HOST_IPS
    if command -v tailscale >/dev/null 2>&1; then
        while IFS= read -r line; do
            ts_ip=$(echo "$line" | awk '{print $1}')
            ts_host=$(echo "$line" | awk '{print $2}')
            [ -z "$ts_ip" ] && continue
            TS_IPS["$ts_ip"]="$ts_ip"
            TS_HOST_IPS["$ts_host"]="$ts_ip"
        done < <(tailscale status 2>/dev/null | awk 'NF>=2{print $1, $2}')
    fi

    SORTED_NODES=$(echo "$RAW_NODES_JSON" | jq -r '
        .items[] |
        (if .metadata.labels["node-role.kubernetes.io/control-plane"] != null then "1_master" else "2_worker" end) as $role_sort |
        [$role_sort, .metadata.name] | @tsv
    ' | sort -k1,1 -k2,2 | cut -f2)

    ALL_PODS=$(echo "$RAW_PODS_JSON" | jq -r '
        .items[] |
        (.spec.nodeName // "<none>") as $node |
        .metadata.namespace as $ns |
        .metadata.name as $name |
        (((.status.containerStatuses // []) | map(select(.ready == true)) | length | tostring) + "/" + ((.spec.containers // []) | length | tostring)) as $ready |
        (
            if .metadata.deletionTimestamp != null then "Terminating"
            elif ((.status.containerStatuses // []) | map(.state.waiting.reason // empty) | first // null) != null then
                ((.status.containerStatuses // []) | map(.state.waiting.reason // empty) | first)
            else .status.phase
            end
        ) as $status |
        (((.status.containerStatuses // []) | map(.restartCount // 0) | add // 0) | tostring) as $restarts |
        (now - (.metadata.creationTimestamp | fromdateiso8601)) as $age_sec |
        (if $age_sec < 60 then "\($age_sec | floor)s"
         elif $age_sec < 3600 then "\($age_sec / 60 | floor)m"
         elif $age_sec < 86400 then "\($age_sec / 3600 | floor)h"
         else "\($age_sec / 86400 | floor)d" end) as $age |
        [$node, $ns, $name, $ready, $status, $restarts, $age] | @tsv
    ' 2>/dev/null | sort -k1,1 -k2,2 -k3,3)

    # Pre-compute PVC→node mapping
    declare -gA PVC_TO_NODE
    while IFS=$'\t' read -r pnode pns ppvc; do
        [ -n "$ppvc" ] && PVC_TO_NODE["${pns}/${ppvc}"]="$pnode"
    done < <(echo "$RAW_PODS_JSON" | jq -r '
        .items[] |
        .spec.nodeName as $node |
        (.spec.volumes[]? | select(.persistentVolumeClaim != null) | .persistentVolumeClaim.claimName) as $pvc |
        .metadata.namespace as $ns |
        [$node, $ns, $pvc] | @tsv
    ' 2>/dev/null | sort -u)

    # Parallelize ping
    declare -gA PING_CACHE
    for node in $SORTED_NODES; do
        ip=$(get_ts_ip "$node")
        if [ "$node" = "$(hostname)" ]; then
            PING_CACHE["$node"]="localhost"
        elif [ "$ip" != "N/A" ]; then
            ( lat=$(ping -c 1 -W 1 "$ip" 2>/dev/null | grep 'time=' | sed -E 's/.*time=([0-9.]+) ms.*/\1/')
              echo "${lat:-timeout}" > "/tmp/k3s_check_ping_${node}" ) &
        else
            PING_CACHE["$node"]="N/A"
        fi
    done
    wait
    # Collect results from temp files
    for node in $SORTED_NODES; do
        if [ -z "${PING_CACHE[$node]}" ]; then
            PING_CACHE["$node"]=$(cat "/tmp/k3s_check_ping_${node}" 2>/dev/null || echo "timeout")
        fi
        rm -f "/tmp/k3s_check_ping_${node}"
    done

    _cache_loaded=true
}

get_ts_ip() {
    local node="$1"
    local node_ips=$(echo "$RAW_NODES_JSON" | jq -r --arg n "$node" '.items[] | select(.metadata.name==$n) | .status.addresses[]?.address')
    for ip in $node_ips; do
        if [ -n "${TS_IPS[$ip]}" ]; then
            echo "$ip"; return
        fi
    done

    # Fallback: use hostname→IP map (no extra tailscale status call)
    local ts_ip="${TS_HOST_IPS[$node]}"
    [ -n "$ts_ip" ] && echo "$ts_ip" && return

    echo "N/A"
}

# ======================== SECTIONS ========================
section_overview() {
    load_cache
    section_header "1/8" "OVERVIEW: SỨC KHỎE CỤM"
    explain "Section này đặt các tín hiệu hay xem nhất lên đầu: node Ready, pod lỗi, PVC bound, workload available và tài nguyên local node."

    local nodes_total nodes_ready pods_total pods_healthy pods_problem pod_restarts
    local pvc_total pvc_bound workloads_total workloads_ready

    nodes_total=$(echo "$RAW_NODES_JSON" | jq '.items | length')
    nodes_ready=$(echo "$RAW_NODES_JSON" | jq '[.items[] | select(any(.status.conditions[]?; .type=="Ready" and .status=="True"))] | length')

    pods_total=$(echo "$RAW_PODS_JSON" | jq '.items | length')
    pods_healthy=$(echo "$RAW_PODS_JSON" | jq '[.items[] | select(.status.phase=="Running" or .status.phase=="Succeeded")] | length')
    pods_problem=$(echo "$RAW_PODS_JSON" | jq '[
        .items[] |
        select(
            (.metadata.deletionTimestamp != null) or
            (.status.phase != "Running" and .status.phase != "Succeeded") or
            (((.status.containerStatuses // []) | map(.state.waiting.reason // empty) | length) > 0)
        )
    ] | length')
    pod_restarts=$(echo "$RAW_PODS_JSON" | jq '[.items[].status.containerStatuses[]?.restartCount // 0] | add // 0')

    pvc_total=$(echo "$RAW_PVC_JSON" | jq '.items | length')
    pvc_bound=$(echo "$RAW_PVC_JSON" | jq '[.items[] | select(.status.phase=="Bound")] | length')

    workloads_total=$(echo "$RAW_WORKLOADS_JSON" | jq '[.items[] | select(.metadata.namespace != "kube-system")] | length')
    workloads_ready=$(echo "$RAW_WORKLOADS_JSON" | jq '[
        .items[] |
        select(.metadata.namespace != "kube-system") |
        select(
            (.kind=="Deployment" and ((.spec.replicas // 0) == 0 or ((.status.readyReplicas // 0) >= (.spec.replicas // 0)))) or
            (.kind=="StatefulSet" and ((.spec.replicas // 0) == 0 or ((.status.readyReplicas // 0) >= (.spec.replicas // 0)))) or
            (.kind=="DaemonSet" and ((.status.desiredNumberScheduled // 0) == 0 or ((.status.numberReady // 0) >= (.status.desiredNumberScheduled // 0))))
        )
    ] | length')

    echo -e "  ${YELLOW}>> HEALTH SUMMARY${NC}"
    metric_ratio "Nodes Ready" "$nodes_ready" "$nodes_total" "Ready"
    metric_ratio "Pods Healthy" "$pods_healthy" "$pods_total" "Running/Succeeded"
    metric_ratio "PVC Bound" "$pvc_bound" "$pvc_total" "Bound"
    metric_ratio "Workloads Ready" "$workloads_ready" "$workloads_total" "Available"

    local problem_color="$GREEN"
    [ "$pods_problem" -gt 0 ] && problem_color="$RED"
    local restart_color="$GREEN"
    [ "$pod_restarts" -gt 0 ] && restart_color="$ORANGE"
    printf "  ${CYAN}%-18s${NC} %b%d%b pod cần xem\n" "Pod Problems" "$problem_color" "$pods_problem" "$NC"
    printf "  ${CYAN}%-18s${NC} %b%d%b container restart\n" "Restarts" "$restart_color" "$pod_restarts" "$NC"

    echo -e "\n  ${YELLOW}>> LOCAL NODE QUICK GRAPH${NC}"
    local ram_used ram_total ram_pct disk_used_pct disk_used disk_total
    if command -v free >/dev/null 2>&1; then
        read -r ram_used ram_total ram_pct < <(free -m | awk 'NR==2{printf "%d %d %d", $3, $2, ($3*100/$2)}')
        printf "  ${CYAN}%-18s${NC} %b  %s/%s MB\n" "RAM" "$(bar_pct "$ram_pct" 22)" "$ram_used" "$ram_total"
    else
        printf "  ${CYAN}%-18s${NC} ${ORANGE}unavailable${NC}\n" "RAM"
    fi
    read -r disk_used disk_total disk_used_pct < <(df -hP / | awk 'NR==2{pct=$(NF-1); gsub("%","",pct); print $(NF-3), $(NF-4), pct}')
    printf "  ${CYAN}%-18s${NC} %b  %s/%s\n" "Disk /" "$(bar_pct "$disk_used_pct" 22)" "$disk_used" "$disk_total"

    echo -e "\n  ${YELLOW}>> POD DENSITY BY NODE${NC}"
    local max_pods
    max_pods=$(echo "$ALL_PODS" | awk -F'\t' '{count[$1]++} END{max=0; for (n in count) if (count[n]>max) max=count[n]; print max+0}')
    for node in $SORTED_NODES; do
        local count
        count=$(echo "$ALL_PODS" | awk -F'\t' -v n="$node" '$1==n{c++} END{print c+0}')
        printf "  ${CYAN}%-18s${NC} %b  %d pods\n" "$node" "$(bar_count "$count" "$max_pods" 22)" "$count"
    done

    echo -e "\n  ${YELLOW}>> HOT LIST${NC}"
    local hot_list
    hot_list=$(echo "$ALL_PODS" | awk -F'\t' '($5!="Running" && $5!="Succeeded") || ($6+0>0) {print $2"\t"$3"\t"$1"\t"$4"\t"$5"\t"$6"\t"$7}' | sort -k1,1 -k2,2 | head -12)
    if [ -z "$hot_list" ]; then
        echo -e "     ${GREEN}Không có pod lỗi hoặc restart.${NC}"
    else
        print_ns_grouped_table "$hot_list" "POD\tNODE\tREADY\tSTATUS\tRESTARTS\tAGE" | awk '
        />> /{print; next}
        /POD[[:space:]]+NODE/{print; next}
        {
            line=$0
            if (line ~ /CrashLoopBackOff|ImagePullBackOff|ErrImagePull|Error/) sub(/CrashLoopBackOff|ImagePullBackOff|ErrImagePull|Error/, "'"${RED}"'&'"${NC}"'", line)
            else if (line ~ /Pending|ContainerCreating/) sub(/Pending|ContainerCreating/, "'"${YELLOW}"'&'"${NC}"'", line)
            else if (line ~ /Terminating/) sub("Terminating", "'"${ORANGE}"'Terminating'"${NC}"'", line)
            else if (line ~ /Running/) sub("Running", "'"${GREEN}"'Running'"${NC}"'", line)
            print line
        }'
    fi
}

section_sys() {
    section_header "5/8" "LOCAL NODE: CPU, RAM, DISK"
    explain "Đọc tài nguyên ngay trên node đang chạy script. Dùng phần này khi cluster chậm, Vector/Redpanda OOM, hoặc disk MinIO gần đầy."

    printf "${CYAN}%-14s${NC} %s" "Hostname:" "$(hostname)"; explain_suffix "Tên Linux host hiện tại"; echo
    printf "${CYAN}%-14s${NC} %s" "Kernel:" "$(uname -r)"; explain_suffix "Phiên bản Linux kernel"; echo
    local uptime_text="N/A"
    command -v uptime >/dev/null 2>&1 && uptime_text=$(uptime -p 2>/dev/null || uptime 2>/dev/null || echo "N/A")
    printf "${CYAN}%-14s${NC} %s" "Uptime:" "$uptime_text"; explain_suffix "Thời gian máy đã chạy liên tục"; echo
    printf "${CYAN}%-14s${NC} %s cores | %s" "CPU:" "$(nproc)" "$(grep -m 1 'model name' /proc/cpuinfo | sed 's/.*: //')"
    explain_suffix "Số core và model CPU của node"; echo

    local cores load1 load5 load15 load_pct
    cores=$(nproc)
    if command -v uptime >/dev/null 2>&1; then
        read -r load1 load5 load15 < <(uptime | awk -F'load average:' '{gsub(",","",$2); print $2}' | awk '{print $1, $2, $3}')
    else
        load1=0; load5=0; load15=0
    fi
    load_pct=$(awk -v l="$load1" -v c="$cores" 'BEGIN{if(c==0)c=1; printf "%d", (l*100/c)}')
    printf "${CYAN}%-14s${NC} %b  %s / %s / %s\n" "Load avg:" "$(bar_pct "$load_pct" 24)" "$load1" "$load5" "$load15"

    local ram_used ram_total ram_pct swap_used swap_total swap_pct disk_used disk_total disk_pct
    if command -v free >/dev/null 2>&1; then
        read -r ram_used ram_total ram_pct < <(free -m | awk 'NR==2{printf "%d %d %d", $3, $2, ($3*100/$2)}')
        printf "${CYAN}%-14s${NC} %b  %s/%s MB\n" "RAM:" "$(bar_pct "$ram_pct" 24)" "$ram_used" "$ram_total"

        read -r swap_used swap_total swap_pct < <(free -m | awk 'NR==3{if($2>0) printf "%d %d %d", $3, $2, ($3*100/$2); else printf "0 0 0"}')
        if [ "$swap_total" -gt 0 ]; then
            printf "${CYAN}%-14s${NC} %b  %s/%s MB\n" "Swap:" "$(bar_pct "$swap_pct" 24)" "$swap_used" "$swap_total"
        else
            printf "${CYAN}%-14s${NC} ${GREEN}disabled${NC}\n" "Swap:"
        fi
    else
        printf "${CYAN}%-14s${NC} ${ORANGE}unavailable${NC}\n" "RAM:"
        printf "${CYAN}%-14s${NC} ${ORANGE}unavailable${NC}\n" "Swap:"
    fi

    read -r disk_used disk_total disk_pct < <(df -hP / | awk 'NR==2{pct=$(NF-1); gsub("%","",pct); print $(NF-3), $(NF-4), pct}')
    printf "${CYAN}%-14s${NC} %b  %s/%s\n" "Disk /:" "$(bar_pct "$disk_pct" 24)" "$disk_used" "$disk_total"

    echo -e "\n  ${YELLOW}>> TOP RAM PROCESSES${NC}"
    local top_rss
    top_rss=$(ps -eo comm=,rss= --sort=-rss 2>/dev/null | head -5)
    if [ -z "$top_rss" ]; then
        echo -e "     ${CYAN}(Không đọc được process list)${NC}"
    else
        local max_rss
        max_rss=$(echo "$top_rss" | awk 'NR==1{print $NF+0}')
        echo "$top_rss" | awk -v max="$max_rss" '
        {
            rss=$NF; name=$1;
            pct=(max>0 ? int(rss*100/max) : 0);
            printf "%s\t%d\t%d\n", name, rss/1024, pct
        }' | while IFS=$'\t' read -r name rss_mb pct; do
            printf "     ${CYAN}%-22s${NC} %b  %s MB\n" "$name" "$(bar_pct "$pct" 18)" "$rss_mb"
        done
    fi
}

section_node() {
    load_cache
    section_header "2/8" "TOPOLOGY, NODES & PODS"
    explain "Tóm tắt node, phiên bản K3s, IP Tailscale, độ trễ ping và namespace đang có pod trên từng node."

    # --- Collect raw data ---
    local -a _NODE _STATUS _ROLE _VER _IP _LAT _NS
    local idx=0

    for node in $SORTED_NODES; do
        ip=$(get_ts_ip "$node")

        node_info=$(echo "$RAW_NODES_JSON" | jq -r --arg n "$node" '
            .items[] | select(.metadata.name==$n) |
            (if .metadata.labels["node-role.kubernetes.io/control-plane"] != null then "master" else "worker" end) as $role |
            (.status.conditions[] | select(.type=="Ready") | .status) as $ready |
            .status.nodeInfo.kubeletVersion as $ver |
            [$role, $ready, $ver] | @tsv
        ')
        role_raw=$(echo "$node_info" | awk -F'\t' '{print $1}')
        ready_raw=$(echo "$node_info" | awk -F'\t' '{print $2}')
        ver_raw=$(echo "$node_info" | awk -F'\t' '{print $3}')

        latency="${PING_CACHE[$node]:-N/A}"
        [ "$latency" != "localhost" ] && [ "$latency" != "timeout" ] && [ "$latency" != "N/A" ] && latency="${latency}ms"

        status_txt="Ready"; [ "$ready_raw" != "True" ] && status_txt="NotReady"

        ns_summary=$(echo "$ALL_PODS" | awk -v n="$node" '$1==n {print $2}' \
            | sort | uniq -c | awk '{printf "%s(%d) ", $2, $1}' | sed 's/ $//')
        [ -z "$ns_summary" ] && ns_summary="-"

        _NODE[$idx]="$node"
        _STATUS[$idx]="$status_txt"
        _ROLE[$idx]="$role_raw"
        _VER[$idx]="$ver_raw"
        _IP[$idx]="$ip"
        _LAT[$idx]="$latency"
        _NS[$idx]="$ns_summary"
        ((idx++))
    done

    # --- Compute column widths (plain text only) ---
    local w_node=4 w_status=6 w_role=4 w_ver=7 w_ip=2 w_lat=4
    for ((i=0; i<idx; i++)); do
        (( ${#_NODE[$i]}   > w_node   )) && w_node=${#_NODE[$i]}
        (( ${#_STATUS[$i]} > w_status )) && w_status=${#_STATUS[$i]}
        (( ${#_ROLE[$i]}   > w_role   )) && w_role=${#_ROLE[$i]}
        (( ${#_VER[$i]}    > w_ver    )) && w_ver=${#_VER[$i]}
        (( ${#_IP[$i]}     > w_ip     )) && w_ip=${#_IP[$i]}
        (( ${#_LAT[$i]}    > w_lat    )) && w_lat=${#_LAT[$i]}
    done

    # --- Print header ---
    printf "${YELLOW}%-${w_node}s  %-${w_status}s  %-${w_role}s  %-${w_ver}s  %-${w_ip}s  %-${w_lat}s  %s${NC}\n" \
        NODE STATUS ROLE VERSION IP PING NAMESPACES

    # --- Print rows with color, preserving alignment ---
    for ((i=0; i<idx; i++)); do
        # Status color + right-pad to column width
        if [ "${_STATUS[$i]}" = "Ready" ]; then
            s_col="${GREEN}${_STATUS[$i]}${NC}$(printf '%*s' $((w_status - ${#_STATUS[$i]})) '')"
        else
            s_col="${RED}${_STATUS[$i]}${NC}$(printf '%*s' $((w_status - ${#_STATUS[$i]})) '')"
        fi

        # Role color + right-pad
        if [ "${_ROLE[$i]}" = "master" ]; then
            r_col="${PURPLE}${_ROLE[$i]}${NC}$(printf '%*s' $((w_role - ${#_ROLE[$i]})) '')"
        else
            r_col="${ORANGE}${_ROLE[$i]}${NC}$(printf '%*s' $((w_role - ${#_ROLE[$i]})) '')"
        fi

        # Ping color + right-pad
        lat="${_LAT[$i]}"
        case "$lat" in
            localhost) lat_col="${CYAN}${lat}${NC}" ;;
            timeout|N/A) lat_col="${RED}${lat}${NC}" ;;
            *)
                num="${lat%ms}"
                if awk "BEGIN{exit !($num+0 < 50)}"; then
                    lat_col="${GREEN}${lat}${NC}"
                elif awk "BEGIN{exit !($num+0 < 150)}"; then
                    lat_col="${YELLOW}${lat}${NC}"
                else
                    lat_col="${RED}${lat}${NC}"
                fi
                ;;
        esac
        lat_col+="$(printf '%*s' $((w_lat - ${#lat})) '')"

        echo -e "$(printf "%-${w_node}s" "${_NODE[$i]}")  ${s_col}  ${r_col}  $(printf "%-${w_ver}s" "${_VER[$i]}")  $(printf "%-${w_ip}s" "${_IP[$i]}")  ${lat_col}  ${_NS[$i]}"
    done

    echo -e "\n${CYAN}PODS LAYOUT:${NC}"
    explain "STATUS=Ready nghĩa kubelet khỏe; PING đo đường Tailscale giữa các node; NAMESPACES cho biết workload đang nằm ở đâu."
    if $EXPLAIN; then
        echo -en "  ${CYAN}ⓘ Liệt kê pod theo node.${NC} "
    fi
    for node in $SORTED_NODES; do
        echo -e "  ${ORANGE}>> $node${NC}"
        NODE_PODS=$(echo "$ALL_PODS" | awk -v n="$node" '$1==n {print $2"\t"$3"\t"$4"\t"$5"\t"$6"\t"$7}')

        if [ -z "$NODE_PODS" ]; then
            echo -e "     ${CYAN}(Không có pod)${NC}"
        else
            print_ns_grouped_table "$NODE_PODS" "NAME\tREADY\tSTATUS\tRESTARTS\tAGE" "     " "        " | awk '
            />> /{print; next}
            /NAME[[:space:]]+READY/{print; next}
            {
                line=$0;

                # 1) Color ready fraction FIRST (before ANSI codes break spacing)
                if (match(line, /[0-9]+\/[0-9]+/)) {
                    frac=substr(line, RSTART, RLENGTH);
                    split(frac, r, "/");
                    if (r[1]+0 == r[2]+0 && r[1]+0 > 0) sub(frac, "'"${GREEN}"'" frac "'"${NC}"'", line);
                    else if (r[1]+0 == 0) sub(frac, "'"${RED}"'" frac "'"${NC}"'", line);
                    else sub(frac, "'"${YELLOW}"'" frac "'"${NC}"'", line);
                }

                # 2) Color restart count (field 5) — before status coloring injects ANSI codes
                n=split(line, fields, /  +/);
                for (i=1; i<=n; i++) {
                    if (fields[i]+0 > 0 && fields[i] ~ /^[1-9][0-9]*$/) {
                        sub(" " fields[i] " ", " '"${ORANGE}"'" fields[i] "'"${NC}"' ", line);
                        break;
                    }
                }

                # 3) Color status LAST
                if (line ~ /CrashLoopBackOff/) sub("CrashLoopBackOff", "'"${RED}"'CrashLoopBackOff'"${NC}"'", line);
                else if (line ~ /ImagePullBackOff/) sub("ImagePullBackOff", "'"${RED}"'ImagePullBackOff'"${NC}"'", line);
                else if (line ~ /ErrImagePull/) sub("ErrImagePull", "'"${RED}"'ErrImagePull'"${NC}"'", line);
                else if (line ~ /Error/) sub("Error", "'"${RED}"'Error'"${NC}"'", line);
                else if (line ~ /Terminating/) sub("Terminating", "'"${ORANGE}"'Terminating'"${NC}"'", line);
                else if (line ~ /ContainerCreating/) sub("ContainerCreating", "'"${PURPLE}"'ContainerCreating'"${NC}"'", line);
                else if (line ~ /Pending/) sub("Pending", "'"${YELLOW}"'Pending'"${NC}"'", line);
                else if (line ~ /Succeeded/) sub("Succeeded", "'"${BLUE}"'Succeeded'"${NC}"'", line);
                else if (line ~ /Running/) sub("Running", "'"${GREEN}"'Running'"${NC}"'", line);

                print line;
            }'
        fi
    done
}

section_secrets() {
    load_cache
    section_header "8/8" "SECRETS (TÊN, TYPE, KEYS)"
    explain "Chỉ in tên Secret, type và key; không in giá trị secret để tránh lộ credential trong terminal/report."
    local ns_list=$(echo "$RAW_SECRETS_JSON" | jq -r '
        .items[] | select(.type != "kubernetes.io/service-account-token" and .metadata.namespace != "kube-system") |
        .metadata.namespace
    ' 2>/dev/null | sort -u)

    if [ -z "$ns_list" ]; then
        echo -e "  ${CYAN}(Không có secrets ngoài kube-system)${NC}"
        return
    fi

    for ns in $ns_list; do
        echo -e "  ${ORANGE}>> $ns${NC}"
        local sec_data=$(echo "$RAW_SECRETS_JSON" | jq -r --arg ns "$ns" '
            .items[] | select(.metadata.namespace==$ns and .type != "kubernetes.io/service-account-token") |
            "\(.metadata.name)\t\(.type)\t\((.data // {}) | keys | join(", "))"
        ' 2>/dev/null)

        if [ -n "$sec_data" ]; then
            (
                echo -e "${YELLOW}NAME\tTYPE\tKEYS${NC}"
                echo -e "$sec_data"
            ) | column -t -s $'\t' | sed 's/^/     /'
        else
            echo -e "     ${CYAN}(Không có secret)${NC}"
        fi
    done
}

section_pvc() {
    load_cache
    section_header "4/8" "STORAGE: PVC"
    explain "PVC là claim lưu trữ bền vững cho pod. Bảng này nhóm PVC theo node đang mount để thấy dữ liệu đang nằm ở đâu."

    ALL_PVC=$(echo "$RAW_PVC_JSON" | jq -r '
        .items[] | [.metadata.namespace, .metadata.name, (.status.capacity.storage // "N/A")] | @tsv
    ')

    for node in $SORTED_NODES; do
        echo -e "  ${ORANGE}>> $node${NC}"
        NODE_PVC=""
        while IFS=$'\t' read -r pvc_ns pvc_name pvc_size; do
            [ -z "$pvc_name" ] && continue
            # Use pre-computed PVC→node map for O(1) lookup
            local node_for_pvc="${PVC_TO_NODE["${pvc_ns}/${pvc_name}"]}"
            if [ "$node_for_pvc" = "$node" ]; then
                NODE_PVC+="${pvc_ns}\t${pvc_name}\t${pvc_size}\n"
            fi
        done <<< "$ALL_PVC"

        if [ -z "$NODE_PVC" ]; then
            echo -e "     ${CYAN}(Không có PVC)${NC}"
        else
            print_ns_grouped_table "$NODE_PVC" "NAME\tSIZE" "     " "        "
        fi
    done
}

section_res() {
    load_cache
    local ns_filter="$1"
    section_header "3/8" "WORKLOADS, HPA & SERVICES"
    explain "Tổng hợp workload và service ngoài kube-system."

    local jq_ns_filter=""
    if [ -n "$ns_filter" ]; then
        jq_ns_filter=" and (.metadata.namespace | startswith(\"$ns_filter\"))"
    fi

    echo -e "  ${YELLOW}>> WORKLOADS (Deployments, StatefulSets, DaemonSets)${NC}"
    local workloads=$(echo "$RAW_WORKLOADS_JSON" | jq -r '
        .items[] | select(.metadata.namespace != "kube-system"'"$jq_ns_filter"') |
        .metadata.namespace as $ns |
        .kind as $kind |
        .metadata.name as $name |
        (if $kind == "Deployment" then
            [($ns), "deploy", $name, (.spec.replicas // 0), (.status.readyReplicas // 0), (.status.updatedReplicas // 0), (.status.availableReplicas // 0)]
         elif $kind == "StatefulSet" then
            [($ns), "sts", $name, (.spec.replicas // 0), (.status.readyReplicas // 0), (.status.updatedReplicas // 0), (.status.availableReplicas // 0)]
         elif $kind == "DaemonSet" then
            [($ns), "ds", $name, (.status.desiredNumberScheduled // 0), (.status.numberReady // 0), (.status.updatedNumberScheduled // 0), (.status.numberAvailable // 0)]
         else empty end) | @tsv
    ' 2>/dev/null | sort -k1,1 -k2,2 -k3,3)

    if [ -z "$workloads" ]; then
        echo -e "     ${CYAN}(Không có workloads)${NC}"
    else
        local workloads_colored=$(echo "$workloads" | awk -F'\t' 'OFS="\t" {
            desired=$4; ready=$5; upto=$6; avail=$7;
            color="'"${GREEN}"'";
            if (desired+0 > 0) {
                if (ready+0 == 0 && avail+0 == 0) color="'"${RED}"'";
                else if (ready+0 < desired+0 || avail+0 < desired+0 || upto+0 < desired+0) color="'"${ORANGE}"'";
            }
            $4 = color desired "'"${NC}"'";
            $5 = color ready "'"${NC}"'";
            $6 = color upto "'"${NC}"'";
            $7 = color avail "'"${NC}"'";

            if ($2 == "deploy") $2 = "'"${CYAN}"'" $2 "'"${NC}"'";
            else if ($2 == "sts") $2 = "'"${PURPLE}"'" $2 "'"${NC}"'";
            else if ($2 == "ds") $2 = "'"${ORANGE}"'" $2 "'"${NC}"'";
            print $0
        }')
        print_ns_grouped_table "$workloads_colored" "KIND\tNAME\tDESIRED\tREADY\tUP-TO-DATE\tAVAILABLE"
        explain "DESIRED là số replica mong muốn; READY/AVAILABLE thấp hơn DESIRED là dấu hiệu rollout chưa xong hoặc pod lỗi."
    fi

    # ========================== KHỐI HPA ==========================
    echo -e "\n  ${YELLOW}>> AUTOSCALING (HPA)${NC}"
    explain "HPA tự tăng/giảm replica theo metric. Không có HPA là bình thường ở giai đoạn bootstrap tài nguyên thấp."
    local hpas=$(echo "$RAW_HPA_JSON" | jq -r '
        .items[] | select(.metadata.namespace != "kube-system"'"$jq_ns_filter"') |
        .metadata.namespace as $ns |
        .metadata.name as $name |
        .spec.scaleTargetRef.kind as $targetKind |
        .spec.scaleTargetRef.name as $targetName |
        (.spec.minReplicas // 1) as $min |
        .spec.maxReplicas as $max |
        (.status.currentReplicas // 0) as $current |
        (.status.desiredReplicas // 0) as $desired |
        [$ns, $name, "\($targetKind)/\($targetName)", "\($min) -> \($max)", "\($current)/\($desired)"] | @tsv
    ' 2>/dev/null | sort -k1,1 -k2,2)

    if [ -z "$hpas" ]; then
        echo -e "     ${CYAN}(Không có HPA nào được cấu hình)${NC}"
    else
        local hpas_colored=$(echo "$hpas" | awk -F'\t' 'OFS="\t" {
            current=$5;
            split(current, arr, "/");
            curr_val=arr[1]; des_val=arr[2];

            color="'"${GREEN}"'";
            split($4, max_arr, " -> ");
            max_val=max_arr[2];

            if (curr_val >= max_val && max_val > 0) color="'"${RED}"'";
            else if (curr_val >= max_val * 0.8) color="'"${ORANGE}"'";

            $5 = color current "'"${NC}"'";
            $3 = "'"${PURPLE}"'" $3 "'"${NC}"'";
            print $0
        }')

        print_ns_grouped_table "$hpas_colored" "HPA NAME\tTARGET\tMIN->MAX\tCURRENT/DESIRED"
    fi
    # ===================================================================

    echo -e "\n  ${YELLOW}>> SERVICES${NC}"
    explain "Service là endpoint nội bộ của Kubernetes. ClusterIP chỉ truy cập trong cluster."
    local svcs=$(echo "$RAW_SVC_JSON" | jq -r '
        .items[] | select(.metadata.namespace != "kube-system" and .metadata.name != "kubernetes"'"$jq_ns_filter"') |
        .metadata.namespace as $ns |
        .metadata.name as $name |
        .spec.type as $type |
        .spec.clusterIP as $cip |
        ([.spec.ports[]? | "\(.port)/\(.protocol)"] | join(",")) as $ports |
        [$ns, $name, $type, $cip, $ports] | @tsv
    ' 2>/dev/null | sort -k1,1 -k2,2)

    if [ -z "$svcs" ]; then
        echo -e "     ${CYAN}(Không có services)${NC}"
    else
        local svcs_colored=$(echo "$svcs" | awk -F'\t' 'OFS="\t" {
            if ($3 == "ClusterIP") $3 = "'"${CYAN}"'" $3 "'"${NC}"'";
            else if ($3 == "NodePort") $3 = "'"${ORANGE}"'" $3 "'"${NC}"'";
            else if ($3 == "LoadBalancer") $3 = "'"${PURPLE}"'" $3 "'"${NC}"'";
            print $0
        }')
        print_ns_grouped_table "$svcs_colored" "NAME\tTYPE\tCLUSTER-IP\tPORTS"
    fi
}

section_img() {
    load_cache
    section_header "6/8" "CUSTOM IMAGES & USAGE"
    explain "Hiển thị image không thuộc nhóm system image. [In-Use] nghĩa đang được pod dùng; [Unused] có thể là cache cũ."
    POD_DATA=$(echo "$RAW_PODS_JSON" | jq -r '.items[] | .spec.nodeName as $node | .metadata.name as $pod | (.spec.containers[], (.spec.initContainers[]? // empty)) | [$node, (.image | split("/") | last | split(":") | first | split("@") | first), $pod] | @tsv' | sort -u)
    SYS_IMAGES="rancher|k8s\.io|gcr\.io|klipper|pause|coredns|traefik|metrics|local-path"

    for node in $SORTED_NODES; do
        echo -e "${ORANGE}>> Node: $node${NC}"
        NODE_IMAGES=$(echo "$RAW_NODES_JSON" | jq -r --arg n "$node" '
            .items[] | select(.metadata.name==$n) | .status.images[]? | "\(.names[0])\t\(.sizeBytes)"
        ' 2>/dev/null | grep -vE "$SYS_IMAGES" | grep -v "<none>" | sort -u)

        if [ -z "$NODE_IMAGES" ]; then
            echo -e "   ${CYAN}(Trống)${NC}"
        else
            output=$(echo "$NODE_IMAGES" | while IFS=$'\t' read -r full_img size; do
                short_img=$(echo "$full_img" | sed 's/@sha256:\([a-f0-9]\{6\}\)[a-f0-9]*/@sha256:\1…/')
                core_name=$(echo "$full_img" | awk -F'/' '{print $NF}' | sed 's/:.*//; s/@sha256.*//')
                using_pods=$(echo "$POD_DATA" | awk -v n="$node" -v c="$core_name" '$1==n && $2==c {print $3}' | sort -u | paste -sd "," -)
                size_gb=$(awk -v s="$size" 'BEGIN {printf "%.2f", s/1073741824}')

                if [ -n "$using_pods" ]; then
                    sort_key="1_inuse"
                    tag="${GREEN}[In-Use]${NC}"
                    info="${CYAN}(Pod: $using_pods)${NC}"
                else
                    sort_key="2_unused"
                    tag="${ORANGE}[Unused]${NC}"
                    info=""
                fi
                printf "%s\t-\t%s\t|\t%s GB\t|\t%b\t%b\n" "$sort_key" "$short_img" "$size_gb" "$tag" "$info"
            done | sort -k1,1 | cut -f2-)

            echo "$output" | column -t -s $'\t' | sed 's/^/   /'
        fi
    done
}

section_helm() {
    if ! command -v helm >/dev/null 2>&1; then return; fi
    section_header "7/8" "HELM RELEASES & REPOSITORIES"
    explain "Helm releases là các chart đã cài; repositories là cấu hình repo trên máy đang chạy script, không phải object trong cluster."

    echo -e "  ${YELLOW}>> RELEASES${NC}"
    local releases_json
    releases_json=$(helm list -A -o json 2>/dev/null)

    if [ -z "$releases_json" ] || ! echo "$releases_json" | jq -e 'type == "array"' >/dev/null 2>&1; then
        echo -e "     ${ORANGE}(Không đọc được Helm releases)${NC}"
    elif [ "$(echo "$releases_json" | jq 'length')" -eq 0 ]; then
        echo -e "     ${CYAN}(Không có Helm release)${NC}"
    else
        local releases
        releases=$(echo "$releases_json" | jq -r '
            .[] | [
                (.namespace // "-"),
                (.name // "-"),
                ((.revision // "-") | tostring),
                ((.updated // "-") | split(".") | .[0] | sub("T"; " ")),
                (.status // "-"),
                (.chart // "-"),
                (.app_version // "-")
            ] | @tsv
        ' 2>/dev/null | sort -k1,1 -k2,2)
        print_ns_grouped_table "$releases" "NAME\tREVISION\tUPDATED\tSTATUS\tCHART\tAPP_VERSION" | awk '
        />> /{print; next}
        /NAME[[:space:]]+REVISION/{print; next}
        {
            line=$0;
            if (line ~ /deployed/) sub("deployed", "'"${GREEN}"'deployed'"${NC}"'", line);
            else if (line ~ /failed/) sub("failed", "'"${RED}"'failed'"${NC}"'", line);
            else if (line ~ /pending/) sub("pending", "'"${YELLOW}"'pending'"${NC}"'", line);
            print line;
        }'
        explain "STATUS=deployed là tốt; nếu failed/pending thì cần xem helm history hoặc pod events trong namespace tương ứng."
    fi

    echo -e "\n  ${YELLOW}>> REPOSITORIES${NC}"
    local repos_json
    repos_json=$(helm repo list -o json 2>/dev/null)

    if [ -z "$repos_json" ] || ! echo "$repos_json" | jq -e 'type == "array"' >/dev/null 2>&1; then
        echo -e "     ${ORANGE}(Không đọc được Helm repositories)${NC}"
        return
    fi

    if [ "$(echo "$repos_json" | jq 'length')" -eq 0 ]; then
        echo -e "     ${CYAN}(Không có Helm repo nào)${NC}"
        return
    fi

    local repos
    repos=$(echo "$repos_json" | jq -r '
        .[] |
        (.name // "-") as $name |
        (.url // "-") as $url |
        [$name, $url] | @tsv
    ' 2>/dev/null | sort -k1,1)

    echo "$repos" | (
        echo -e "${YELLOW}NAME\tURL${NC}"
        cat
    ) | column -t -s $'\t' | sed 's/^/     /'
}

# ======================== EXPORT & MAIN ========================
render_two_columns() {
    local left_file="$1"
    local right_file="$2"
    local cols="${COLUMNS:-}"
    local left_width right_width sep_width=5

    if [ -z "$cols" ] && command -v tput >/dev/null 2>&1; then
        cols=$(tput cols 2>/dev/null || true)
    fi
    [[ "$cols" =~ ^[0-9]+$ ]] || cols=160

    left_width=$(( (cols - sep_width) / 2 ))
    [ "$left_width" -lt 24 ] && left_width=24
    right_width=$(( cols - sep_width - left_width ))
    if [ "$right_width" -lt 24 ]; then
        right_width=24
        left_width=$(( cols - sep_width - right_width ))
        [ "$left_width" -lt 24 ] && left_width=24
    fi

    awk -v left_width="$left_width" -v right_width="$right_width" -v sep="  \033[0;34m│\033[0m  " -v reset="\033[0m" '
    function strip_ansi(s, out) {
        out = s
        gsub(/\033\[[0-9;]*[mK]/, "", out)
        return out
    }
    function visible_len(s) {
        return length(strip_ansi(s))
    }
    function rstrip(s) {
        sub(/[[:space:]]+$/, "", s)
        return s
    }
    function ansi_cut(s, width,    i, j, c, vis, cut_raw, last_space_raw, last_space_vis, len) {
        len = length(s)
        vis = 0
        cut_raw = len
        last_space_raw = 0
        last_space_vis = 0

        for (i = 1; i <= len; i++) {
            c = substr(s, i, 1)
            if (c == "\033" && substr(s, i + 1, 1) == "[") {
                for (j = i + 2; j <= len; j++) {
                    if (substr(s, j, 1) ~ /[A-Za-z]/) {
                        i = j
                        break
                    }
                }
                continue
            }

            vis++
            if (c ~ /[[:space:]]/) {
                last_space_raw = i
                last_space_vis = vis
            }
            if (vis >= width) {
                cut_raw = i
                break
            }
        }

        if (vis < width || cut_raw >= len) {
            WRAP_PART = s
            WRAP_REST = ""
            return
        }

        if (last_space_raw > 0 && last_space_vis >= int(width * 0.45)) {
            cut_raw = last_space_raw
        }

        WRAP_PART = rstrip(substr(s, 1, cut_raw))
        WRAP_REST = substr(s, cut_raw + 1)
        sub(/^[[:space:]]+/, "", WRAP_REST)
    }
    function append_wrapped(s, width, out, count,    guard, previous) {
        guard = 0

        if (s == "") {
            out[++count] = ""
            return count
        }

        while (visible_len(s) > width && guard++ < 200) {
            previous = s
            ansi_cut(s, width)
            out[++count] = WRAP_PART
            s = WRAP_REST
            if (s == "" || s == previous) {
                break
            }
        }

        if (s != "") {
            out[++count] = s
        }

        return count
    }
    FNR == NR {
        left[++left_count] = $0
        next
    }
    {
        right[++right_count] = $0
    }
    END {
        for (i = 1; i <= left_count; i++) {
            left_wrapped_count = append_wrapped(left[i], left_width, left_wrapped, left_wrapped_count)
        }
        for (i = 1; i <= right_count; i++) {
            right_wrapped_count = append_wrapped(right[i], right_width, right_wrapped, right_wrapped_count)
        }

        max_count = left_wrapped_count > right_wrapped_count ? left_wrapped_count : right_wrapped_count
        for (i = 1; i <= max_count; i++) {
            l = i <= left_wrapped_count ? left_wrapped[i] : ""
            r = i <= right_wrapped_count ? right_wrapped[i] : ""
            pad = left_width - visible_len(l)
            if (pad < 0) {
                pad = 0
            }
            printf "%s%s%*s%s%s\n", l, reset, pad, "", sep, r
        }
    }
    ' "$left_file" "$right_file"
}

legend_item() {
    printf "  ${CYAN}%-20s${NC} %s\n" "$1" "$2"
}

print_legend() {
    echo -e "\n${BLUE}${BOLD}--- LEGEND ---${NC}"

    echo -e "  ${YELLOW}>> HEALTH SUMMARY${NC}"
    legend_item "Nodes Ready" "Số node có condition Ready=True trên tổng số node."
    legend_item "Pods Healthy" "Pod có phase Running hoặc Succeeded trên tổng số pod."
    legend_item "PVC Bound" "PVC đã bind được volume trên tổng số PVC."
    legend_item "Workloads Ready" "Workload ngoài kube-system có số replica sẵn sàng đạt mong muốn."
    legend_item "Pod Problems" "Pod không Running/Succeeded, đang terminating, hoặc có container waiting/error."
    legend_item "Restarts" "Tổng restart count của container trong toàn cluster."
    legend_item "Pod Density" "Số pod đang chạy trên từng node, giúp thấy workload phân bố lệch hay đều."

    echo ""
    echo -e "  ${YELLOW}>> CLUSTER & OBJECTS${NC}"
    legend_item "NS" "Kubernetes namespace. Trong report này namespace được gom thành header '>> <namespace>' thay cho cột NS lặp lại."
    legend_item "NODE" "Máy tham gia cluster Kubernetes/K3s; pod được scheduler đặt chạy trên node."
    legend_item "ROLE" "Vai trò node. master/control-plane giữ API/etcd; worker chủ yếu chạy workload."
    legend_item "IP" "Địa chỉ node dùng để liên lạc trong cluster, ở đây thường là Tailscale IP."
    legend_item "PING" "Độ trễ mạng từ node đang chạy script tới node khác; timeout/N/A là dấu hiệu cần kiểm tra mạng."
    legend_item "NAMESPACES" "Tóm tắt số pod theo namespace đang nằm trên từng node."
    legend_item "POD" "Đơn vị chạy container nhỏ nhất trong Kubernetes."
    legend_item "READY" "Với pod: số container ready/tổng container. Với workload: số replica ready."
    legend_item "STATUS" "Trạng thái hiện tại, ví dụ Running, Succeeded, Pending, Failed, CrashLoopBackOff."
    legend_item "RESTARTS" "Tổng số lần container trong pod bị restart."
    legend_item "AGE" "Tuổi object tính từ thời điểm được tạo."
    legend_item "PVC" "PersistentVolumeClaim, yêu cầu lưu trữ bền vững cho pod."
    legend_item "SIZE" "Dung lượng PVC hoặc image."

    echo -e "\n  ${YELLOW}>> WORKLOADS & SCALING${NC}"
    legend_item "WORKLOAD" "Nhóm object điều khiển pod, ví dụ Deployment, StatefulSet, DaemonSet."
    legend_item "KIND" "Loại workload: deploy=Deployment, sts=StatefulSet, ds=DaemonSet."
    legend_item "DESIRED" "Số replica mong muốn theo spec."
    legend_item "UP-TO-DATE" "Số replica đã chạy revision/template mới nhất."
    legend_item "AVAILABLE" "Số replica sẵn sàng phục vụ traffic theo điều kiện availability."
    legend_item "HPA" "HorizontalPodAutoscaler, tự tăng/giảm replica theo metric."
    legend_item "TARGET" "Workload mà HPA đang điều khiển."
    legend_item "MIN->MAX" "Khoảng replica tối thiểu và tối đa HPA được phép dùng."
    legend_item "CURRENT/DESIRED" "Replica hiện tại so với replica HPA đang muốn đạt tới."

    echo -e "\n  ${YELLOW}>> NETWORK, IMAGES, HELM & SECRETS${NC}"
    legend_item "SERVICE" "Endpoint ổn định để truy cập pod trong cluster."
    legend_item "TYPE" "Kiểu Service/Secret. Service thường gặp: ClusterIP, NodePort, LoadBalancer."
    legend_item "CLUSTER-IP" "IP nội bộ của Service trong Kubernetes cluster; None nghĩa headless service."
    legend_item "PORTS" "Danh sách port/protocol Service expose."
    legend_item "IMAGE" "Container image đang có trên node."
    legend_item "[In-Use]" "Image đang được ít nhất một pod dùng."
    legend_item "[Unused]" "Image còn trong cache node nhưng không thấy pod hiện tại dùng."
    legend_item "HELM RELEASE" "Một lần cài đặt Helm chart vào cluster."
    legend_item "REVISION" "Số phiên bản release sau mỗi lần helm install/upgrade/rollback."
    legend_item "UPDATED" "Thời điểm Helm release được cập nhật gần nhất."
    legend_item "CHART" "Tên và phiên bản Helm chart."
    legend_item "APP_VERSION" "Phiên bản app mà chart khai báo."
    legend_item "REPOSITORY" "Nguồn Helm chart cấu hình trên máy đang chạy script."
    legend_item "SECRET" "Object chứa dữ liệu nhạy cảm, thường được lưu dạng base64; report chỉ in tên/key, không in giá trị."
    legend_item "KEYS" "Tên các key có trong Secret."

    echo -e "\n  ${YELLOW}>> COLORS & BARS${NC}"
    legend_item "Health bar" "Dùng cho Nodes/Pods/PVC/Workloads: xanh lá là tỷ lệ tốt cao, vàng/cam/đỏ là cần chú ý."
    legend_item "Resource bar" "Dùng cho CPU/RAM/Disk/load/process: xanh lá là dùng thấp, vàng/cam/đỏ là dùng cao."
    legend_item "Load avg" "Tải CPU trung bình 1/5/15 phút; so với số core để ước lượng mức bận."
    legend_item "RAM/Disk/Swap" "Tài nguyên local của node đang chạy script."
}

generate_full_report() {
    echo "K3s Cluster Check — $(date '+%Y-%m-%d %H:%M:%S')"
    echo "================================================="

    local tmp_dir left_report right_report
    tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/k3s-check-cols.XXXXXX" 2>/dev/null)
    if [ -z "$tmp_dir" ]; then
        section_timed section_overview
        section_timed section_node
        section_timed section_res
        section_timed section_pvc
        section_timed section_sys
        section_timed section_img
        section_timed section_helm
        section_timed section_secrets
        echo -e "\n>>> Kiểm tra hoàn tất!"
        return
    fi

    left_report="$tmp_dir/left.txt"
    right_report="$tmp_dir/right.txt"

    {
        echo -e "${BLUE}${BOLD}CỘT 1: SECTION 1-3${NC}"
        section_timed section_overview
        section_timed section_node
        section_timed section_res
    } > "$left_report"

    {
        echo -e "${BLUE}${BOLD}CỘT 2: SECTION 4-8${NC}"
        section_timed section_pvc
        section_timed section_sys
        section_timed section_img
        section_timed section_helm
        section_timed section_secrets
    } > "$right_report"

    render_two_columns "$left_report" "$right_report"
    rm -rf "$tmp_dir"
    print_legend

    echo -e "\n>>> Kiểm tra hoàn tất!"
}

do_export() {
    local compact=false
    [ "$1" = "-c" ] || [ "$1" = "--compact" ] && compact=true

    mkdir -p "$CK_DIR"
    local ts=$(date +"%H%M%S-%d%m%y")
    local suffix=$($compact && echo "-compact" || echo "")
    local outfile="$CK_DIR/k3s-check-${ts}${suffix}.txt"

    if $compact; then
        echo -e "${YELLOW}>>> Compact mode không hỗ trợ ở phiên bản rút gọn này. Xin dùng bản full.${NC}"
        return
    else
        generate_full_report | strip_colors > "$outfile"
    fi

    local size=$(du -h "$outfile" | awk '{print $1}')
    local lines=$(wc -l < "$outfile")
    echo -e "${GREEN}✔ Exported: $outfile ($lines lines, $size)${NC}"
}

POSITIONAL_ARGS=()
for arg in "$@"; do
    case "$arg" in
        -e|--explain)
            EXPLAIN=true
            ;;
        *)
            POSITIONAL_ARGS+=("$arg")
            ;;
    esac
done
set -- "${POSITIONAL_ARGS[@]}"

case "${1:-}" in
    -h|--help)
        echo "K3s Cluster Check"
        echo ""
        echo "Cú pháp: bash k3s-check.sh [-e|--explain] [section] [args]"
        echo ""
        echo "Options:"
        echo "  -e, --explain  Hiển thị thêm giải thích ngắn cho từng section/cột chính"
        echo ""
        echo "Sections:"
        echo "  overview  Tóm tắt sức khỏe cụm, hot list, graph nhanh"
        echo "  node      Topology, nodes, pod layout"
        echo "  res [ns]  Workloads, HPA, Services (filter by namespace)"
        echo "  pvc       Persistent Volume Claims"
        echo "  sys       Local node CPU, RAM, Disk"
        echo "  img       Container images & usage"
        echo "  helm      Helm releases và repositories"
        echo "  secrets   Secrets theo namespace, không in giá trị"
        echo "  export    Xuất report ra file (scripts/k3s-check/)"
        echo ""
        echo "Không có argument = chạy tất cả sections"
        echo "Ví dụ: bash k3s-check.sh -e | bash k3s-check.sh overview | bash k3s-check.sh res argocd -e"
        ;;
    overview|summary) check_dependencies; check_k3s_connection; section_overview ;;
    node|pod) check_dependencies; check_k3s_connection; section_node ;;
    res) check_dependencies; check_k3s_connection; section_res "${2:-}" ;;
    pvc) check_dependencies; check_k3s_connection; section_pvc ;;
    sys) section_sys ;;
    img) check_dependencies; check_k3s_connection; section_img ;;
    helm) check_dependencies; check_k3s_connection; section_helm ;;
    secrets) check_dependencies; check_k3s_connection; section_secrets ;;
    export)
        check_dependencies
        check_k3s_connection
        echo -e "${YELLOW}>>> Đang export...${NC}"
        do_export "${2:-}"
        ;;
    *)
        check_dependencies
        check_k3s_connection
        if $EXPLAIN; then
            echo -e "${YELLOW}>>> Đang thu thập dữ liệu từ K3s API...${NC} ${CYAN}(explain mode: bật chú thích tường minh)${NC}"
        else
            echo -e "${YELLOW}>>> Đang thu thập dữ liệu từ K3s API...${NC}"
        fi
        generate_full_report
        ;;
esac
