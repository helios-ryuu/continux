#!/usr/bin/env bash
# Chạy quy trình replay và Blue/Green cutover của Continux theo từng pha rõ ràng.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SCENARIO_FILE="${REPO_ROOT}/experiments/scenarios/demo.env"
RESULTS_DIR="${REPO_ROOT}/experiments/results"
CURRENT_STATE="${RESULTS_DIR}/current.env"
TMP_STATE="/tmp/continux-demo-env.sh"

# shellcheck disable=SC1090
source "${SCENARIO_FILE}"

die() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

info() {
    printf '==> %s\n' "$*"
}

usage() {
    cat <<'EOF'
Cú pháp:
  bash experiments/runners/demo.sh help
  bash experiments/runners/demo.sh preflight [--local-only]
  bash experiments/runners/demo.sh init [smoke|benchmark-low|benchmark-medium|benchmark-high]
  bash experiments/runners/demo.sh prepare-data
  bash experiments/runners/demo.sh baseline
  bash experiments/runners/demo.sh replay
  bash experiments/runners/demo.sh cutover
  bash experiments/runners/demo.sh cleanup-runtime
  bash experiments/runners/demo.sh cleanup-local
  bash experiments/runners/demo.sh purge-evidence <RUN_ID>

Profile:
  smoke             2 events/s; profile an toàn mặc định
  benchmark-low     1000 events/s; chỉ dùng khi chủ động benchmark
  benchmark-medium  5000 events/s; chỉ dùng khi chủ động benchmark
  benchmark-high    10000 events/s; chỉ dùng khi chủ động benchmark

Chỉ đặt CONTINUX_ASSUME_YES=1 khi bước dọn dẹp không tương tác đã được kiểm soát.
Bằng chứng mặc định được giữ tại ~/continux-demo-evidence/<RUN_ID>/.
EOF
}

require_commands() {
    local command_name
    for command_name in "$@"; do
        command -v "${command_name}" >/dev/null 2>&1 ||
            die "Không tìm thấy lệnh bắt buộc: ${command_name}"
    done
}

validate_run_id() {
    [[ "$1" =~ ^[0-9]{8}-[0-9]{6}$ ]] ||
        die "RUN_ID không hợp lệ: $1"
}

confirm() {
    local expected="$1"
    local prompt="$2"
    local answer

    if [ "${CONTINUX_ASSUME_YES:-0}" = "1" ]; then
        info "Bỏ qua xác nhận vì CONTINUX_ASSUME_YES=1."
        return
    fi

    printf '%s Nhập %s để tiếp tục: ' "${prompt}" "${expected}"
    read -r answer
    [ "${answer}" = "${expected}" ] || die "Nội dung xác nhận không khớp. Đã hủy."
}

assert_git_clean() {
    local status
    status="$(git -C "${REPO_ROOT}" status --porcelain --untracked-files=all)"
    if [ -n "${status}" ] && [ "${CONTINUX_ALLOW_DIRTY:-0}" != "1" ]; then
        printf '%s\n' "${status}" >&2
        die "Checkout Git chưa sạch. Hãy commit hoặc stash thay đổi trước khi chạy thực nghiệm."
    fi
}

assert_local_port() {
    local port="$1"
    (echo >/dev/tcp/127.0.0.1/"${port}") >/dev/null 2>&1 ||
        die "Không kết nối được localhost:${port}. Hãy mở port-forward theo docs/runbook/DEMO.md."
}

profile_file() {
    case "$1" in
        smoke) printf '%s\n' "${REPO_ROOT}/pipelines/vector/rates/smoke.env" ;;
        benchmark-low) printf '%s\n' "${REPO_ROOT}/pipelines/vector/rates/low.env" ;;
        benchmark-medium) printf '%s\n' "${REPO_ROOT}/pipelines/vector/rates/medium.env" ;;
        benchmark-high) printf '%s\n' "${REPO_ROOT}/pipelines/vector/rates/high.env" ;;
        *) die "Profile không hợp lệ: $1" ;;
    esac
}

profile_rate() {
    local selected_file
    selected_file="$(profile_file "$1")"
    sed -n 's/^VECTOR_THROUGHPUT_EVENTS_PER_SEC=//p' "${selected_file}"
}

write_state() {
    mkdir -p "${RESULTS_DIR}/${RUN_ID}"
    {
        printf 'RUN_ID=%q\n' "${RUN_ID}"
        printf 'EVIDENCE_DIR=%q\n' "${EVIDENCE_DIR}"
        printf 'PROFILE=%q\n' "${PROFILE}"
        printf 'DATA_MONTH=%q\n' "${DATA_MONTH}"
        printf 'DATA_DIR=%q\n' "${DATA_DIR}"
        printf 'DATA_PARQUET=%q\n' "${DATA_PARQUET}"
        printf 'DATA_JSONL=%q\n' "${DATA_JSONL}"
        printf 'ZONE_CSV=%q\n' "${ZONE_CSV}"
        printf 'ZONE_RW_CSV=%q\n' "${ZONE_RW_CSV}"
        printf 'BROKERS=%q\n' "${BROKERS}"
    } > "${CURRENT_STATE}"
    cp "${CURRENT_STATE}" "${RESULTS_DIR}/${RUN_ID}/state.env"
    {
        printf 'export RUN_ID=%q\n' "${RUN_ID}"
        printf 'export EVIDENCE_DIR=%q\n' "${EVIDENCE_DIR}"
    } > "${TMP_STATE}"
}

load_state() {
    [ -f "${CURRENT_STATE}" ] ||
        die "Chưa có lượt chạy đang hoạt động. Bắt đầu bằng: bash experiments/runners/demo.sh init [profile]"
    # shellcheck disable=SC1090
    source "${CURRENT_STATE}"
    validate_run_id "${RUN_ID}"
    mkdir -p "${EVIDENCE_DIR}"
}

preflight_local() {
    require_commands bash git sed python3
    [ -f "${SCENARIO_FILE}" ] || die "Thiếu scenario: ${SCENARIO_FILE}"
    [ -f "$(profile_file smoke)" ] || die "Thiếu profile smoke."
    info "Kiểm tra trước khi chạy trên máy cục bộ đã thành công. Profile mặc định: smoke ($(profile_rate smoke) events/s)."
}

preflight_cluster() {
    preflight_local
    require_commands kubectl argocd psql mc curl wget
    kubectl cluster-info >/dev/null
    kubectl -n pipeline get deploy/vector >/dev/null
    kubectl -n redpanda get pod/redpanda-0 >/dev/null
    assert_local_port 8080
    assert_local_port 4567
    assert_local_port 9000
    assert_local_port 9108
    assert_local_port 8428
    info "Kiểm tra trước khi chạy trên cluster đã thành công."
}

sync_app() {
    local app="$1"
    argocd app sync "${app}" --grpc-web
    argocd app wait "${app}" --health --sync --grpc-web
}

apply_rate_profile() {
    local selected="$1"
    local selected_file
    selected_file="$(profile_file "${selected}")"
    info "Đang áp dụng profile Vector ${selected} ($(profile_rate "${selected}") events/s)."
    kubectl -n pipeline create configmap vector-rate-profile \
        --from-env-file="${selected_file}" \
        --dry-run=client -o yaml |
        kubectl apply -f -
}

stop_vector() {
    kubectl --request-timeout=10s -n pipeline scale deploy/vector --replicas=0
    kubectl -n pipeline wait --for=delete pod -l app=vector --timeout=120s || true
}

restore_smoke_profile() {
    info "Đang khôi phục profile Vector smoke an toàn."
    stop_vector
    apply_rate_profile smoke
    sync_app vector
}

finish_replay() {
    trap - EXIT INT TERM
    restore_smoke_profile
}

ensure_mc_alias() {
    if [ -n "${MINIO_ROOT_PASSWORD:-}" ]; then
        mc alias set local http://127.0.0.1:9000 adminuser "${MINIO_ROOT_PASSWORD}" >/dev/null
    else
        mc ls local >/dev/null 2>&1 ||
            die "Alias MinIO cục bộ chưa dùng được. Hãy export MINIO_ROOT_PASSWORD."
    fi
}

init_run() {
    local selected="${1:-smoke}"
    profile_file "${selected}" >/dev/null
    preflight_cluster
    assert_git_clean

    RUN_ID="$(date +%Y%m%d-%H%M%S)"
    EVIDENCE_DIR="${HOME}/continux-demo-evidence/${RUN_ID}"
    PROFILE="${selected}"
    DATA_DIR="${REPO_ROOT}/data/raw"
    DATA_PARQUET="${DATA_DIR}/yellow_tripdata_${DATA_MONTH}.parquet"
    DATA_JSONL="${DATA_DIR}/yellow_tripdata_${DATA_MONTH}.jsonl"
    ZONE_CSV="${REPO_ROOT}/data/zone/taxi_zone_lookup.csv"
    ZONE_RW_CSV="${REPO_ROOT}/data/zone/taxi_zone_lookup_risingwave.csv"

    [ ! -e "${CURRENT_STATE}" ] || die "Đã có lượt chạy đang hoạt động. Hãy chạy cleanup-local trước."
    [ ! -e "${DATA_DIR}" ] || die "${DATA_DIR} đã tồn tại. Hãy chạy cleanup-local trước."
    [ ! -e "${REPO_ROOT}/.venv" ] || die "${REPO_ROOT}/.venv đã tồn tại. Hãy chạy cleanup-local trước."
    mkdir -p "${EVIDENCE_DIR}"
    write_state
    {
        printf 'RUN_ID=%s\n' "${RUN_ID}"
        printf 'EVIDENCE_DIR=%s\n' "${EVIDENCE_DIR}"
        printf 'PROFILE=%s\n' "${PROFILE}"
        printf 'VECTOR_THROUGHPUT_EVENTS_PER_SEC=%s\n' "$(profile_rate "${PROFILE}")"
    } | tee "${EVIDENCE_DIR}/00-run-id.txt"
}

prepare_data() {
    load_state
    require_commands wget python3 mc
    assert_local_port 9000
    [ ! -e "${DATA_DIR}" ] || die "${DATA_DIR} đã tồn tại. Hãy chạy cleanup-local trước."

    mkdir -p "${DATA_DIR}"
    wget -c -O "${DATA_PARQUET}" \
        "${DATA_URL_BASE}/yellow_tripdata_${DATA_MONTH}.parquet" \
        2>&1 | tee "${EVIDENCE_DIR}/01-download-yellow-taxi.txt"
    wget -c -O "${ZONE_CSV}" "${ZONE_URL}" \
        2>&1 | tee "${EVIDENCE_DIR}/01-download-taxi-zone.txt"
    {
        printf 'location_id,borough,zone,service_zone\n'
        tail -n +2 "${ZONE_CSV}"
    } > "${ZONE_RW_CSV}"

    python3 -m venv "${REPO_ROOT}/.venv"
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/.venv/bin/activate"
    python -m pip install --upgrade pip pyarrow \
        2>&1 | tee "${EVIDENCE_DIR}/01-install-pyarrow.txt"
    python "${REPO_ROOT}/scripts/partojsonl.py" "${DATA_PARQUET}" "${DATA_JSONL}" |
        tee "${EVIDENCE_DIR}/01-convert-jsonl.txt"

    ensure_mc_alias
    mc cp "${ZONE_RW_CSV}" local/tlc-zone/taxi_zone_lookup.csv |
        tee "${EVIDENCE_DIR}/01-upload-taxi-zone.txt"
    mc ls local/tlc-zone | tee "${EVIDENCE_DIR}/01-minio-tlc-zone.txt"

    find "${DATA_DIR}" -maxdepth 1 -type f -printf '%f\n' |
        sort | tee "${EVIDENCE_DIR}/01-local-data-files.txt"
    test "$(find "${DATA_DIR}" -maxdepth 1 -type f -name '*.jsonl' | wc -l | tr -d ' ')" -eq 1
    test -s "${DATA_JSONL}"
}

drop_runtime_sql() {
    psql -h localhost -p 4567 -d dev -U root <<'SQL'
DROP SINK IF EXISTS sink_zone_stats;
DROP MATERIALIZED VIEW IF EXISTS mv_zone_stats_green;
DROP MATERIALIZED VIEW IF EXISTS mv_zone_stats;
DROP MATERIALIZED VIEW IF EXISTS mv_zone_stats_blue;
DROP SOURCE IF EXISTS nyc_taxi_src;
DROP TABLE IF EXISTS tlc_zone;
SQL
}

reset_runtime() {
    local prefix="$1"
    local token="$2"
    local target_state="${3:-baseline-blue}"
    load_state
    assert_local_port 4567
    assert_local_port 9000
    ensure_mc_alias
    confirm "${token}" "Thao tác này xóa trạng thái replay, SQL, Iceberg và cutover."

    stop_vector | tee "${EVIDENCE_DIR}/${prefix}-vector-stopped.txt"
    apply_rate_profile smoke
    sync_app vector
    drop_runtime_sql | tee "${EVIDENCE_DIR}/${prefix}-drop-sql-state.txt"
    {
        if kubectl -n redpanda exec redpanda-0 -c redpanda -- \
            rpk topic list --brokers "${BROKERS}" | grep -q 'nyc-taxi-events'; then
            kubectl -n redpanda exec redpanda-0 -c redpanda -- \
                rpk topic delete nyc-taxi-events --brokers "${BROKERS}"
        else
            echo "Topic nyc-taxi-events đã không tồn tại."
        fi
    } | tee "${EVIDENCE_DIR}/${prefix}-topic-delete.txt"
    sync_app redpanda-topics
    mc rm --recursive --force local/iceberg-data/nyc/zone_stats/ |
        tee "${EVIDENCE_DIR}/${prefix}-clear-iceberg.txt"
    kubectl -n pipeline exec deploy/continux-metrics -- rm -f /state/cutover.prom

    if [ "${target_state}" = "baseline-blue" ]; then
        sync_app pipeline
        psql -h localhost -p 4567 -d dev -U root -c \
            "SELECT COUNT(*) AS tlc_zone_rows FROM tlc_zone;
             SELECT 'public' AS view_name, COUNT(*) AS zones, COALESCE(SUM(trip_count),0) AS trips FROM mv_zone_stats
             UNION ALL
             SELECT 'blue', COUNT(*), COALESCE(SUM(trip_count),0) FROM mv_zone_stats_blue;
             SELECT COUNT(*) AS green_objects FROM rw_catalog.rw_materialized_views
               WHERE name = 'mv_zone_stats_green';" |
            tee "${EVIDENCE_DIR}/${prefix}-clean-baseline-counts.txt"
        return
    fi

    if mc stat local/tlc-zone/taxi_zone_lookup.csv >/dev/null 2>&1; then
        mc rm --force local/tlc-zone/taxi_zone_lookup.csv
    else
        echo "Taxi Zone lookup đã không tồn tại."
    fi | tee "${EVIDENCE_DIR}/${prefix}-clear-taxi-zone.txt"

    psql -h localhost -p 4567 -d dev -U root -c \
        "SELECT COUNT(*) AS demo_sql_objects FROM (
           SELECT name FROM rw_catalog.rw_tables WHERE name = 'tlc_zone'
           UNION ALL
           SELECT name FROM rw_catalog.rw_sources WHERE name = 'nyc_taxi_src'
           UNION ALL
           SELECT name FROM rw_catalog.rw_materialized_views
             WHERE name IN ('mv_zone_stats_blue', 'mv_zone_stats', 'mv_zone_stats_green')
           UNION ALL
           SELECT name FROM rw_catalog.rw_sinks WHERE name = 'sink_zone_stats'
         ) AS demo_objects;" |
        tee "${EVIDENCE_DIR}/${prefix}-post-setup-sql-count.txt"
}

baseline() {
    reset_runtime 03 RESET-DEMO
}

replay() {
    load_state
    assert_local_port 4567
    assert_local_port 9000
    assert_local_port 9108
    test -s "${DATA_JSONL}" || die "Thiếu dataset JSONL. Hãy chạy prepare-data trước."
    ensure_mc_alias

    trap 'finish_replay' EXIT
    trap 'finish_replay; exit 130' INT TERM
    apply_rate_profile "${PROFILE}"
    printf 'REPLAY_START_EPOCH=%s\n' "$(date +%s)" |
        tee "${EVIDENCE_DIR}/04-replay-start.txt"
    kubectl -n pipeline scale deploy/vector --replicas=1
    kubectl -n pipeline rollout status deploy/vector --timeout=300s
    kubectl -n pipeline logs deploy/vector --tail=120 |
        tee "${EVIDENCE_DIR}/04-vector-startup-logs.txt"

    for _ in $(seq 1 "${REPLAY_SAMPLE_COUNT}"); do
        date -Is
        psql -h localhost -p 4567 -d dev -U root -At -c \
            "SELECT COUNT(*) AS zones, COALESCE(SUM(trip_count),0) AS trips FROM mv_zone_stats;"
        sleep "${REPLAY_SAMPLE_INTERVAL_SECONDS}"
    done | tee "${EVIDENCE_DIR}/04-mv-progress.txt"

    stop_vector
    sleep 15
    psql -h localhost -p 4567 -d dev -U root -c \
        "SELECT COUNT(*) AS zones, COALESCE(SUM(trip_count),0) AS trips FROM mv_zone_stats;" |
        tee "${EVIDENCE_DIR}/04-mv-final.txt"
    mc ls --recursive local/iceberg-data/nyc/zone_stats/ |
        sed -n '1,50p' | tee "${EVIDENCE_DIR}/04-iceberg-final.txt"
    bash "${REPO_ROOT}/scripts/k3s-check.sh" overview |
        tee "${EVIDENCE_DIR}/04-health-after-replay.txt"

    finish_replay
}

query_loop() {
    local query_log="$1"
    while true; do
        local timestamp result
        timestamp="$(date -Is)"
        if result="$(psql -h localhost -p 4567 -d dev -U root -AtX -c \
            "SELECT COUNT(*), COALESCE(SUM(trip_count),0) FROM mv_zone_stats;" 2>&1)"; then
            printf '%s OK %s\n' "${timestamp}" "${result}" >> "${query_log}"
        else
            printf '%s ERROR %s\n' "${timestamp}" "${result}" >> "${query_log}"
        fi
        sleep 0.5
    done
}

wait_for_vm_value() {
    local metric="$1"
    local expected="$2"

    for _ in $(seq 1 8); do
        if curl -fsSG --retry 2 --retry-all-errors --retry-delay 1 \
            'http://127.0.0.1:8428/api/v1/query' \
            --data-urlencode "query=${metric} == ${expected}" |
            grep -Fq '"result":[{'; then
            return
        fi
        sleep 5
    done

    die "VictoriaMetrics chưa quan sát được ${metric}=${expected}."
}

cutover() {
    load_state
    assert_local_port 4567
    assert_local_port 9108
    assert_local_port 8428
    local query_log="${EVIDENCE_DIR}/05-query-loop-during-cutover.txt"
    local query_pid cutover_start_ns cutover_end_ns cutover_duration swap_timestamp query_errors

    psql -h localhost -p 4567 -d dev -U root <<'SQL' | tee "${EVIDENCE_DIR}/05-create-green.txt"
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_zone_stats_green AS
SELECT
    z.borough,
    z.zone,
    COUNT(*)             AS trip_count,
    SUM(t.fare_amount)   AS total_fare,
    AVG(t.trip_distance) AS avg_distance
FROM nyc_taxi_src t
JOIN tlc_zone     z ON t.pu_location_id = z.location_id
WHERE t.fare_amount >= 0
  AND t.trip_distance >= 0
GROUP BY z.borough, z.zone;
SQL

    for _ in $(seq 1 "${GREEN_SAMPLE_COUNT}"); do
        date -Is
        psql -h localhost -p 4567 -d dev -U root -At -c \
            "SELECT 'public', COUNT(*), COALESCE(SUM(trip_count),0) FROM mv_zone_stats
             UNION ALL
             SELECT 'blue', COUNT(*), COALESCE(SUM(trip_count),0) FROM mv_zone_stats_blue
             UNION ALL
             SELECT 'green', COUNT(*), COALESCE(SUM(trip_count),0) FROM mv_zone_stats_green;"
        sleep "${GREEN_SAMPLE_INTERVAL_SECONDS}"
    done | tee "${EVIDENCE_DIR}/05-green-ready-samples.txt"

    : > "${query_log}"
    query_loop "${query_log}" &
    query_pid=$!
    trap 'kill "${query_pid}" 2>/dev/null || true' EXIT INT TERM
    sleep 2
    cutover_start_ns="$(date +%s%N)"
    psql -h localhost -p 4567 -d dev -U root -c \
        "ALTER MATERIALIZED VIEW mv_zone_stats SWAP WITH mv_zone_stats_green;" |
        tee "${EVIDENCE_DIR}/05-swap.txt"
    cutover_end_ns="$(date +%s%N)"
    sleep 2
    kill "${query_pid}" 2>/dev/null || true
    wait "${query_pid}" 2>/dev/null || true
    trap - EXIT INT TERM
    grep -q ' OK ' "${query_log}" || die "Vòng lặp truy vấn cutover chưa ghi nhận truy vấn thành công."

    cutover_duration="$(
        python3 -c 'import sys; print(f"{(int(sys.argv[2]) - int(sys.argv[1])) / 1_000_000_000:.6f}")' \
            "${cutover_start_ns}" "${cutover_end_ns}"
    )"
    swap_timestamp="$((cutover_end_ns / 1000000000))"
    query_errors="$(grep -c ' ERROR ' "${query_log}" || true)"
    printf 'continux_cutover_duration_seconds %s\ncontinux_last_swap_timestamp_seconds %s\ncontinux_query_errors_total %s\n' \
        "${cutover_duration}" "${swap_timestamp}" "${query_errors}" |
        tee "${EVIDENCE_DIR}/05-duration-and-errors.txt"

    kubectl -n pipeline exec -i deploy/continux-metrics -- sh -c 'cat > /state/cutover.prom' <<EOF
# HELP continux_cutover_duration_seconds Thời gian swap Blue/Green đo được gần nhất.
# TYPE continux_cutover_duration_seconds gauge
continux_cutover_duration_seconds ${cutover_duration}
# HELP continux_last_swap_timestamp_seconds Unix timestamp của lần swap Blue/Green gần nhất.
# TYPE continux_last_swap_timestamp_seconds gauge
continux_last_swap_timestamp_seconds ${swap_timestamp}
# HELP continux_query_errors_total Số lỗi truy vấn ghi nhận trong lúc cutover.
# TYPE continux_query_errors_total counter
continux_query_errors_total ${query_errors}
EOF

    sleep 20
    wait_for_vm_value continux_cutover_duration_seconds "${cutover_duration}"
    wait_for_vm_value continux_query_errors_total "${query_errors}"
    curl -fsS --retry 3 --retry-all-errors --retry-delay 2 http://127.0.0.1:9108/metrics |
        grep -E '^continux_(cutover|last_swap|query_errors|green_ready|mv_rows|mv_trips|checksum)' |
        tee "${EVIDENCE_DIR}/05-exporter-cutover.txt"
    curl -fsSG --retry 3 --retry-all-errors --retry-delay 2 \
        'http://127.0.0.1:8428/api/v1/query' \
        --data-urlencode 'query=continux_cutover_duration_seconds' |
        tee "${EVIDENCE_DIR}/05-vm-duration.json"
    curl -fsSG --retry 3 --retry-all-errors --retry-delay 2 \
        'http://127.0.0.1:8428/api/v1/query' \
        --data-urlencode 'query=continux_query_errors_total' |
        tee "${EVIDENCE_DIR}/05-vm-query-errors.json"
}

cleanup_runtime() {
    reset_runtime 06 CLEAN-DEMO post-setup
}

cleanup_local() {
    load_state
    local vector_replicas
    vector_replicas="$(kubectl -n pipeline get deploy/vector -o jsonpath='{.spec.replicas}')"
    [ "${vector_replicas}" = "0" ] || die "Vector phải được scale về 0 trước khi dọn file cục bộ."
    [ "${DATA_DIR}" = "${REPO_ROOT}/data/raw" ] || die "DATA_DIR không đúng như mong đợi: ${DATA_DIR}"
    confirm CLEAN-LOCAL "Thao tác này xóa bộ dữ liệu cục bộ, môi trường ảo, log và trạng thái sinh ra cho ${RUN_ID}."

    deactivate 2>/dev/null || true
    rm -rf -- \
        "${DATA_DIR}" \
        "${REPO_ROOT}/.venv" \
        "${RESULTS_DIR:?}/${RUN_ID}" \
        "${REPO_ROOT}/scripts/k3s-check" \
        "${REPO_ROOT}/scripts/__pycache__" \
        "${REPO_ROOT}/dashboards/exports"
    rm -f -- \
        "${ZONE_CSV}" \
        "${ZONE_RW_CSV}" \
        "${TMP_STATE}" \
        "${CURRENT_STATE}"
    info "Đã xóa file cục bộ sinh ra khi chạy. Bằng chứng vẫn được giữ tại ${EVIDENCE_DIR}."
}

purge_evidence() {
    local run_id="${1:-}"
    local retained_target
    [ -n "${run_id}" ] || die "purge-evidence yêu cầu RUN_ID."
    validate_run_id "${run_id}"
    retained_target="${HOME}/continux-demo-evidence/${run_id}"
    confirm PURGE-EVIDENCE "Thao tác này xóa vĩnh viễn bằng chứng của ${run_id}."
    rm -rf -- "${retained_target}" "${RESULTS_DIR}/${run_id}"
    info "Đã xóa bằng chứng của ${run_id}."
}

case "${1:-help}" in
    help|-h|--help) usage ;;
    preflight)
        if [ "${2:-}" = "--local-only" ]; then
            preflight_local
        else
            preflight_cluster
        fi
        ;;
    init) init_run "${2:-smoke}" ;;
    prepare-data) prepare_data ;;
    baseline) baseline ;;
    replay) replay ;;
    cutover) cutover ;;
    cleanup-runtime) cleanup_runtime ;;
    cleanup-local) cleanup_local ;;
    purge-evidence) purge_evidence "${2:-}" ;;
    *) die "Lệnh không hợp lệ: $1. Hãy chạy: bash experiments/runners/demo.sh help" ;;
esac
