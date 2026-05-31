# DEMO

Chạy một lượt thực nghiệm hoàn chỉnh từ bước tải bộ dữ liệu đến replay, Blue/Green cutover và thu bằng chứng. Điều kiện đầu vào là [SETUP.md](./SETUP.md) đã hoàn tất hoặc [CLEANUP.md](./CLEANUP.md) đã đưa hệ thống về trạng thái trước thực nghiệm.

Quy trình này giả định hạ tầng đã sẵn sàng, không còn bộ dữ liệu cục bộ, lookup CSV
trên MinIO hoặc trạng thái thực nghiệm cũ. Nếu lượt trước đã chạy, hãy hoàn tất
[CLEANUP.md](./CLEANUP.md) trước khi bắt đầu lượt mới.

## Runner Theo Pha

Luồng chuẩn dùng runner để thu bằng chứng nhất quán và luôn trả Vector về trạng
thái an toàn sau replay. Giữ các terminal port-forward ở §1 mở trong lúc
chạy:

```bash
cd ~/continux

bash experiments/runners/demo.sh preflight
bash experiments/runners/demo.sh init smoke
bash experiments/runners/demo.sh prepare-data
bash experiments/runners/demo.sh baseline
bash experiments/runners/demo.sh replay
bash experiments/runners/demo.sh cutover
```

Để benchmark có chủ đích, thay `smoke` bằng `benchmark-low`,
`benchmark-medium` hoặc `benchmark-high` tại lệnh `init`. Các mục §1-§8
phía dưới giữ lệnh chi tiết tương ứng để debug từng bước.

## 1. Trạng Thái Khởi Đầu Và Bố Trí Terminal

**Điều kiện đầu vào:**

| Hạng mục | Yêu cầu |
|----------|---------|
| Cluster | Ba node `imac`, `continux-vps`, `helios-pc` ở `Ready` |
| Argo CD | Các app hạ tầng `Synced/Healthy`; app `pipeline` được sync tại §3 |
| Vector | `Deployment pipeline/vector` có `replicas=0` |
| Repo cục bộ | `git status --porcelain --untracked-files=all` không in thay đổi |
| Bộ dữ liệu cục bộ | Chưa có `data/raw/`, `.venv/` từ lượt trước |
| MinIO `tlc-zone/` | Chưa upload, hoặc đã upload bởi lượt này |
| Redpanda topic | `nyc-taxi-events` tồn tại với cấu hình chuẩn |
| RisingWave | Chưa có object SQL thực nghiệm; sẽ apply ở §3 sau khi upload lookup |

**Bố trí terminal (giữ mở suốt buổi chạy):**

| Terminal | Mục đích | Lệnh chạy và giữ mở |
|----------|----------|----------------------|
| 1 | Điều khiển chính, thu bằng chứng | Các lệnh ở từng bước phía dưới |
| 2 | Kết nối SQL tới RisingWave | `kubectl -n risingwave port-forward svc/risingwave 4567:4567` |
| 3 | Kết nối API tới MinIO | `kubectl -n minio port-forward --address 127.0.0.1 svc/minio 9000:9000` |
| 4 | Đọc metrics exporter | `kubectl -n pipeline port-forward svc/continux-metrics 9108:9108` |
| 5 | Query VictoriaMetrics | `kubectl -n observability port-forward svc/vmsingle-victoria-metrics 8428:8428` |
| 6 | Chạy query loop khi cutover | Chỉ dùng tại §7 |

**Khai báo biến và thư mục bằng chứng:**

```bash
cd ~/continux

export DATA_MONTH=2026-03
export DATA_DIR="$PWD/data/raw"
export DATA_PARQUET="${DATA_DIR}/yellow_tripdata_${DATA_MONTH}.parquet"
export DATA_JSONL="data/raw/yellow_tripdata_${DATA_MONTH}.jsonl"
export ZONE_CSV="$PWD/data/zone/taxi_zone_lookup.csv"
export ZONE_RW_CSV="$PWD/data/zone/taxi_zone_lookup_risingwave.csv"
export DATA_URL="https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_${DATA_MONTH}.parquet"
export ZONE_URL="https://d37ci6vzurychx.cloudfront.net/misc/taxi_zone_lookup.csv"
export BROKERS="redpanda.redpanda.svc.cluster.local:9093"

RUN_ID="$(date +%Y%m%d-%H%M%S)"
EVIDENCE_DIR="$HOME/continux-demo-evidence/${RUN_ID}"
export RUN_ID EVIDENCE_DIR
mkdir -p "${EVIDENCE_DIR}"

printf 'export RUN_ID=%q\nexport EVIDENCE_DIR=%q\n' "${RUN_ID}" "${EVIDENCE_DIR}" \
  > /tmp/continux-demo-env.sh

printf 'RUN_ID=%s\nEVIDENCE_DIR=%s\n' "${RUN_ID}" "${EVIDENCE_DIR}" \
  | tee "${EVIDENCE_DIR}/00-run-id.txt"
```

Bằng chứng nằm tại `~/continux-demo-evidence/<RUN_ID>/`, ngoài repo. Không ghi mật khẩu, token hoặc nội dung secret vào bằng chứng.

## 2. Chuẩn Bị Dataset

Đây là bước tạo dữ liệu đầu tiên của lượt mới. Mọi file sinh trên máy nằm trong `data/raw/`, đã được `.gitignore` bỏ qua.

```bash
cd ~/continux

kubectl -n pipeline get deploy/vector \
  -o jsonpath='{.spec.replicas}{" desired\n"}'

test ! -e "${DATA_DIR}"
test ! -e .venv
```

Vector phải là `0 desired` và chưa có thư mục dữ liệu/môi trường Python từ lượt trước.

```bash
cd ~/continux

mkdir -p "${DATA_DIR}" "$PWD/data/zone"

wget -c -O "${DATA_PARQUET}" "${DATA_URL}" \
  2>&1 | tee "${EVIDENCE_DIR}/01-download-yellow-taxi.txt"
wget -c -O "${ZONE_CSV}" "${ZONE_URL}" \
  2>&1 | tee "${EVIDENCE_DIR}/01-download-taxi-zone.txt"

{ printf 'location_id,borough,zone,service_zone\n'; tail -n +2 "${ZONE_CSV}"; } \
  > "${ZONE_RW_CSV}"

python3 -m venv .venv
. .venv/bin/activate
python -m pip install --upgrade pip pyarrow \
  2>&1 | tee "${EVIDENCE_DIR}/01-install-pyarrow.txt"

python scripts/partojsonl.py "${DATA_PARQUET}" "${DATA_JSONL}" \
  | tee "${EVIDENCE_DIR}/01-convert-jsonl.txt"

wc -l "${DATA_JSONL}" \
  | tee "${EVIDENCE_DIR}/01-jsonl-lines.txt"
find "${DATA_DIR}" -maxdepth 1 -type f -printf '%f\n' \
  | sort | tee "${EVIDENCE_DIR}/01-local-data-files.txt"
```

Upload lookup lên MinIO:

```bash
cd ~/continux

mc alias set local http://127.0.0.1:9000 adminuser "${MINIO_ROOT_PASSWORD}"
mc cp "${ZONE_RW_CSV}" local/tlc-zone/taxi_zone_lookup.csv \
  | tee "${EVIDENCE_DIR}/01-upload-taxi-zone.txt"
mc ls local/tlc-zone \
  | tee "${EVIDENCE_DIR}/01-minio-tlc-zone.txt"

JSONL_COUNT="$(find "${DATA_DIR}" -maxdepth 1 -type f -name '*.jsonl' | wc -l | tr -d ' ')"
printf 'JSONL_COUNT=%s\n' "${JSONL_COUNT}" \
  | tee "${EVIDENCE_DIR}/01-jsonl-count.txt"
test "${JSONL_COUNT}" -eq 1
test -s "${DATA_JSONL}"

GIT_STATUS="$(git status --porcelain --untracked-files=all)"
printf '%s' "${GIT_STATUS}" | tee "${EVIDENCE_DIR}/01-git-after-data.txt"
test -z "${GIT_STATUS}"
```

**Kết quả mong đợi:**

- Parquet và JSONL nằm trong `data/raw/`; hai file Taxi Zone staging (CSV gốc + CSV cho RisingWave) nằm trong `data/zone/`.
- `JSONL_COUNT=1` — Vector sẽ phát toàn bộ file `/data/*.jsonl`, nên một lượt sạch chỉ được có một file JSONL.
- MinIO liệt kê `taxi_zone_lookup.csv`.
- `git status` rỗng vì mọi tệp sinh ra nằm trong đường dẫn Git bỏ qua.

## 3. Sync Vector Và Apply SQL Pipeline

Vector luôn được sync ở `replicas=0` để không phát event ngoài ý muốn.

```bash
cd ~/continux

argocd app sync vector --grpc-web
argocd app wait vector --health --sync --grpc-web

kubectl --request-timeout=10s -n pipeline scale deploy/vector --replicas=0
kubectl -n pipeline get deploy/vector -o jsonpath='{.spec.replicas}{" desired\n"}'
```

Apply SQL pipeline (Argo CD hook `mv-apply-job` có thể bị xóa sau khi `Succeeded` — verify bằng catalog thay vì tìm Job còn tồn tại):

```bash
cd ~/continux

argocd app sync pipeline --grpc-web
argocd app wait pipeline --health --sync --grpc-web

psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT 'table' AS kind, name FROM rw_catalog.rw_tables WHERE name = 'tlc_zone'
   UNION ALL
   SELECT 'source' AS kind, name FROM rw_catalog.rw_sources WHERE name = 'nyc_taxi_src'
   UNION ALL
   SELECT 'mv' AS kind, name FROM rw_catalog.rw_materialized_views WHERE name IN ('mv_zone_stats_blue', 'mv_zone_stats')
   UNION ALL
   SELECT 'sink' AS kind, name FROM rw_catalog.rw_sinks WHERE name = 'sink_zone_stats'
   ORDER BY kind, name;" \
  | tee "${EVIDENCE_DIR}/02-risingwave-catalog-objects.txt"

psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT COUNT(*) AS tlc_zone_rows FROM tlc_zone;" \
  | tee "${EVIDENCE_DIR}/02-tlc-zone-count.txt"
```

**Kết quả mong đợi:** catalog có `tlc_zone`, `nyc_taxi_src`, `mv_zone_stats_blue`, `mv_zone_stats`, `sink_zone_stats`; `tlc_zone` có số dòng bằng số dòng của Taxi Zone lookup vừa upload.

Không dùng `\dt public.*` hoặc `\dm public.*` để verify RisingWave; meta-command có pattern có thể sinh collation regex không tương thích.

## 4. Verify Topic, SQL Và Quan Sát

```bash
cd ~/continux

kubectl -n redpanda exec redpanda-0 -c redpanda -- \
  rpk topic describe nyc-taxi-events --brokers "${BROKERS}" \
  | tee "${EVIDENCE_DIR}/02-redpanda-topic.txt"

psql -h localhost -p 4567 -d dev -U root -c 'SHOW CLUSTER;' \
  | tee "${EVIDENCE_DIR}/02-risingwave-cluster.txt"

curl -fsS http://127.0.0.1:9108/metrics \
  | grep '^continux_exporter_up' \
  | tee "${EVIDENCE_DIR}/02-exporter-up.txt"

curl -fsSG 'http://127.0.0.1:8428/api/v1/query' \
  --data-urlencode 'query=continux_exporter_up' \
  | tee "${EVIDENCE_DIR}/02-vm-exporter-up.json"
```

**Kết quả mong đợi:** topic `nyc-taxi-events` có `3` partition, `1` replica; RisingWave báo các worker `RUNNING`; exporter trả `continux_exporter_up 1`; VictoriaMetrics trả series.

## 5. Dựng Trạng Thái Nền Blue Sạch (Khi Cần)

Bước này chỉ cần khi tiếp tục từ runtime cũ chưa chạy
[CLEANUP.md](./CLEANUP.md). Nếu bước dọn dẹp vừa hoàn tất hoặc đây là lượt đầu sau
[SETUP.md](./SETUP.md), runner vẫn thực hiện reset idempotent để dựng Blue sạch
sau khi lookup đã được upload.

> Cảnh báo: phần này xóa bản tin trong topic, đối tượng SQL pipeline, đầu ra Iceberg hiện hành và metric cutover hiện thời. Không xóa cluster, PVC, dataset, lookup CSV, bucket hoặc secret.

Lưu trạng thái trước khi xóa:

```bash
cd ~/continux

{
  date -Is
  kubectl -n pipeline get deploy/vector -o wide
  kubectl -n redpanda exec redpanda-0 -c redpanda -- \
    rpk topic describe nyc-taxi-events --brokers "${BROKERS}"
} | tee "${EVIDENCE_DIR}/03-before-reset-runtime.txt"

psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT name FROM rw_catalog.rw_materialized_views
   WHERE name IN ('mv_zone_stats_blue', 'mv_zone_stats', 'mv_zone_stats_green')
   ORDER BY name;" \
  | tee "${EVIDENCE_DIR}/03-before-reset-mvs.txt"

mc ls --recursive local/iceberg-data/nyc/zone_stats/ | sed -n '1,50p' \
  | tee "${EVIDENCE_DIR}/03-before-reset-iceberg.txt"
```

Dừng Vector và xác nhận:

```bash
cd ~/continux

kubectl -n pipeline get deploy/vector \
  -o jsonpath='{.spec.replicas}{" desired\n"}'

read -r -p "Nhập RESET-DEMO để xóa trạng thái khi chạy và tạo trạng thái nền sạch: " CONFIRM
test "${CONFIRM}" = "RESET-DEMO"

kubectl --request-timeout=10s -n pipeline scale deploy/vector --replicas=0
kubectl -n pipeline wait --for=delete pod -l app=vector --timeout=120s || true

kubectl -n pipeline get deploy/vector \
  -o jsonpath='{.spec.replicas}{" desired\n"}' \
  | tee "${EVIDENCE_DIR}/03-vector-stopped.txt"
```

Xóa object SQL pipeline (sink trước, MV, source, table):

```bash
cd ~/continux

psql -h localhost -p 4567 -d dev -U root <<'SQL' \
  | tee "${EVIDENCE_DIR}/03-drop-sql-state.txt"
DROP SINK IF EXISTS sink_zone_stats;
DROP MATERIALIZED VIEW IF EXISTS mv_zone_stats_green;
DROP MATERIALIZED VIEW IF EXISTS mv_zone_stats;
DROP MATERIALIZED VIEW IF EXISTS mv_zone_stats_blue;
DROP SOURCE IF EXISTS nyc_taxi_src;
DROP TABLE IF EXISTS tlc_zone;
SQL
```

Xóa và tái tạo topic sạch:

```bash
cd ~/continux

{
  if kubectl -n redpanda exec redpanda-0 -c redpanda -- \
    rpk topic list --brokers "${BROKERS}" | grep -q 'nyc-taxi-events'; then
    kubectl -n redpanda exec redpanda-0 -c redpanda -- \
      rpk topic delete nyc-taxi-events --brokers "${BROKERS}"
  else
    echo "Topic nyc-taxi-events đã không tồn tại; tiếp tục tạo lại."
  fi
} | tee "${EVIDENCE_DIR}/03-topic-delete.txt"

argocd app sync redpanda-topics --grpc-web
argocd app wait redpanda-topics --health --sync --grpc-web

kubectl -n redpanda exec redpanda-0 -c redpanda -- \
  rpk topic describe nyc-taxi-events --brokers "${BROKERS}" \
  | tee "${EVIDENCE_DIR}/03-topic-recreated.txt"
```

Dọn đầu ra Iceberg và metric cutover hiện thời:

```bash
cd ~/continux

mc rm --recursive --force local/iceberg-data/nyc/zone_stats/ \
  | tee "${EVIDENCE_DIR}/03-clear-iceberg.txt"

kubectl -n pipeline exec deploy/continux-metrics -- \
  rm -f /state/cutover.prom

sleep 12
curl -fsS http://127.0.0.1:9108/metrics \
  | grep -E '^continux_(cutover_duration_seconds|last_swap_timestamp_seconds|query_errors_total)' \
  | tee "${EVIDENCE_DIR}/03-cutover-metrics-cleared.txt"
```

MinIO có thể hiển thị delete marker nếu bucket bật lưu phiên bản; đây là hành vi bình thường, không phải lỗi.

Apply lại pipeline Blue và xác nhận trạng thái nền:

```bash
cd ~/continux

argocd app sync pipeline --grpc-web
argocd app wait pipeline --health --sync --grpc-web

psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT 'table' AS kind, name FROM rw_catalog.rw_tables WHERE name = 'tlc_zone'
   UNION ALL
   SELECT 'source' AS kind, name FROM rw_catalog.rw_sources WHERE name = 'nyc_taxi_src'
   UNION ALL
   SELECT 'mv' AS kind, name FROM rw_catalog.rw_materialized_views
     WHERE name IN ('mv_zone_stats_blue', 'mv_zone_stats', 'mv_zone_stats_green')
   UNION ALL
   SELECT 'sink' AS kind, name FROM rw_catalog.rw_sinks WHERE name = 'sink_zone_stats'
   ORDER BY kind, name;" \
  | tee "${EVIDENCE_DIR}/03-baseline-objects.txt"

psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT COUNT(*) AS tlc_zone_rows FROM tlc_zone;
   SELECT 'public' AS view_name, COUNT(*) AS zones, COALESCE(SUM(trip_count),0) AS trips FROM mv_zone_stats
   UNION ALL
   SELECT 'blue', COUNT(*), COALESCE(SUM(trip_count),0) FROM mv_zone_stats_blue;
   SELECT COUNT(*) AS green_objects FROM rw_catalog.rw_materialized_views
     WHERE name = 'mv_zone_stats_green';" \
  | tee "${EVIDENCE_DIR}/03-baseline-counts.txt"

if mc ls --recursive local/iceberg-data/nyc/zone_stats/ | grep -q '\.parquet$'; then
  echo "FAIL: trạng thái nền vẫn còn file Parquet Iceberg." | tee "${EVIDENCE_DIR}/03-baseline-iceberg-check.txt"
  exit 1
else
  echo "OK: trạng thái nền chưa có tệp Parquet của replay." | tee "${EVIDENCE_DIR}/03-baseline-iceberg-check.txt"
fi
```

**Kết quả mong đợi cho trạng thái nền:**

| Kiểm tra | Kết quả |
|----------|---------|
| Object SQL | Có `tlc_zone`, `nyc_taxi_src`, `mv_zone_stats_blue`, `mv_zone_stats`, `sink_zone_stats` |
| Green MV | `green_objects = 0` |
| Lookup | `tlc_zone` có dòng bằng số dòng Taxi Zone CSV |
| Public và blue | `trips = 0` trước replay sạch |
| Vector | `0 desired` |
| Iceberg | Chưa có tệp dữ liệu Parquet của replay mới |

## 6. Replay End-To-End

```bash
cd ~/continux

REPLAY_START_EPOCH="$(date +%s)"
printf 'REPLAY_START_EPOCH=%s\n' "${REPLAY_START_EPOCH}" \
  | tee "${EVIDENCE_DIR}/04-replay-start.txt"

kubectl -n pipeline scale deploy/vector --replicas=1
kubectl -n pipeline rollout status deploy/vector --timeout=300s

kubectl -n pipeline logs deploy/vector --tail=120 \
  | tee "${EVIDENCE_DIR}/04-vector-startup-logs.txt"
```

**Dừng khẩn cấp nếu Vector gây tải cao:**

```bash
kubectl --request-timeout=10s -n pipeline scale deploy/vector --replicas=0
kubectl -n pipeline wait --for=delete pod -l app=vector --timeout=120s || true
```

Quan sát dữ liệu đi theo pipeline:

```bash
# Vector đang phát dữ liệu
kubectl -n pipeline logs deploy/vector --tail=120 \
  | tee "${EVIDENCE_DIR}/04-observe-vector.txt"

# Redpanda đang nhận sự kiện
kubectl -n redpanda exec redpanda-0 -c redpanda -- \
  rpk topic describe nyc-taxi-events --brokers "${BROKERS}" \
  | tee "${EVIDENCE_DIR}/04-observe-topic.txt"

# RisingWave cập nhật MV
for i in $(seq 1 12); do
  date -Is
  psql -h localhost -p 4567 -d dev -U root -At -c \
    "SELECT COUNT(*) AS zones, COALESCE(SUM(trip_count),0) AS trips FROM mv_zone_stats;"
  sleep 5
done | tee "${EVIDENCE_DIR}/04-mv-progress.txt"

# Exporter phản ánh kết quả
curl -fsS http://127.0.0.1:9108/metrics \
  | grep -E '^continux_(events_processed_total|mv_rows|mv_trips|green_ready)' \
  | tee "${EVIDENCE_DIR}/04-exporter-progress.txt"

# Iceberg có đầu ra mới
mc ls --recursive local/iceberg-data/nyc/zone_stats/ | sed -n '1,50p' \
  | tee "${EVIDENCE_DIR}/04-iceberg-progress.txt"
```

Mở Grafana với khoảng thời gian `Last 15 minutes` hoặc bắt đầu từ `REPLAY_START_EPOCH`; dashboard `streaming-perf` và `resource-util` phải có hoạt động trong khoảng replay.

Dừng replay và chốt kết quả:

```bash
cd ~/continux

psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT COUNT(*) AS zones, COALESCE(SUM(trip_count),0) AS trips FROM mv_zone_stats;" \
  | tee "${EVIDENCE_DIR}/04-mv-before-stop.txt"

kubectl --request-timeout=10s -n pipeline scale deploy/vector --replicas=0
kubectl -n pipeline wait --for=delete pod -l app=vector --timeout=120s || true

sleep 15

psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT COUNT(*) AS zones, COALESCE(SUM(trip_count),0) AS trips FROM mv_zone_stats;
   SELECT borough, SUM(trip_count) AS trips
   FROM mv_zone_stats GROUP BY borough ORDER BY trips DESC LIMIT 10;" \
  | tee "${EVIDENCE_DIR}/04-mv-final.txt"

mc ls --recursive local/iceberg-data/nyc/zone_stats/ | sed -n '1,50p' \
  | tee "${EVIDENCE_DIR}/04-iceberg-final.txt"

bash scripts/k3s-check.sh overview \
  | tee "${EVIDENCE_DIR}/04-health-after-replay.txt"
```

**Kết quả mong đợi:** Vector về `0`, `mv_zone_stats` có trips lớn hơn `0`, Iceberg có tệp Parquet/metadata mới, cluster vẫn khỏe.

## 7. Blue/Green Cutover

Tạo green MV và kiểm tra sẵn sàng:

```bash
cd ~/continux

kubectl -n pipeline get deploy/vector \
  -o jsonpath='{.spec.replicas}{" desired\n"}'

psql -h localhost -p 4567 -d dev -U root <<'SQL' \
  | tee "${EVIDENCE_DIR}/05-create-green.txt"
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

for i in $(seq 1 20); do
  date -Is
  psql -h localhost -p 4567 -d dev -U root -At -c \
    "SELECT 'public', COUNT(*), COALESCE(SUM(trip_count),0) FROM mv_zone_stats
     UNION ALL
     SELECT 'blue', COUNT(*), COALESCE(SUM(trip_count),0) FROM mv_zone_stats_blue
     UNION ALL
     SELECT 'green', COUNT(*), COALESCE(SUM(trip_count),0) FROM mv_zone_stats_green;"
  sleep 5
done | tee "${EVIDENCE_DIR}/05-green-ready-samples.txt"
```

**Kết quả mong đợi trước swap:** public và blue có cùng số liệu; green có dữ liệu và có thể có ít trips hơn blue (cố ý loại sự kiện `fare_amount < 0` hoặc `trip_distance < 0`).

**Terminal 6 — query loop trong lúc swap:**

```bash
cd ~/continux
source /tmp/continux-demo-env.sh

QUERY_LOG="${EVIDENCE_DIR}/05-query-loop-during-cutover.txt"
: > "${QUERY_LOG}"

while true; do
  TS="$(date -Is)"
  if RESULT="$(psql -h localhost -p 4567 -d dev -U root -AtX -c \
    "SELECT COUNT(*), COALESCE(SUM(trip_count),0) FROM mv_zone_stats;" 2>&1)"; then
    printf '%s OK %s\n' "${TS}" "${RESULT}" | tee -a "${QUERY_LOG}"
  else
    printf '%s ERROR %s\n' "${TS}" "${RESULT}" | tee -a "${QUERY_LOG}"
  fi
  sleep 0.5
done
```

Giữ vòng lặp chạy, chuyển về Terminal 1 để swap:

```bash
cd ~/continux

test -s "${EVIDENCE_DIR}/05-query-loop-during-cutover.txt"
grep -q ' OK ' "${EVIDENCE_DIR}/05-query-loop-during-cutover.txt"

CUTOVER_START_NS="$(date +%s%N)"

psql -h localhost -p 4567 -d dev -U root -c \
  "ALTER MATERIALIZED VIEW mv_zone_stats SWAP WITH mv_zone_stats_green;" \
  | tee "${EVIDENCE_DIR}/05-swap.txt"

CUTOVER_END_NS="$(date +%s%N)"
CUTOVER_DURATION="$(
  python3 -c 'import sys; print(f"{(int(sys.argv[2]) - int(sys.argv[1])) / 1_000_000_000:.6f}")' \
    "${CUTOVER_START_NS}" "${CUTOVER_END_NS}"
)"
SWAP_TIMESTAMP="$((CUTOVER_END_NS / 1000000000))"

printf 'continux_cutover_duration_seconds %s\ncontinux_last_swap_timestamp_seconds %s\n' \
  "${CUTOVER_DURATION}" "${SWAP_TIMESTAMP}" \
  | tee "${EVIDENCE_DIR}/05-duration.txt"
```

Sau khi Terminal 6 có thêm vài dòng `OK` sau swap, dừng vòng lặp bằng `Ctrl+C`. Tính query errors và verify:

```bash
cd ~/continux

QUERY_ERRORS="$(grep -c ' ERROR ' "${EVIDENCE_DIR}/05-query-loop-during-cutover.txt" || true)"
printf 'continux_query_errors_total %s\n' "${QUERY_ERRORS}" \
  | tee "${EVIDENCE_DIR}/05-query-errors.txt"

psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT 'public' AS view_name, COUNT(*) AS zones, COALESCE(SUM(trip_count),0) AS trips FROM mv_zone_stats
   UNION ALL
   SELECT 'green_name_after_swap', COUNT(*), COALESCE(SUM(trip_count),0) FROM mv_zone_stats_green
   UNION ALL
   SELECT 'blue', COUNT(*), COALESCE(SUM(trip_count),0) FROM mv_zone_stats_blue;" \
  | tee "${EVIDENCE_DIR}/05-after-swap-counts.txt"

kubectl -n risingwave get pods \
  | tee "${EVIDENCE_DIR}/05-risingwave-after-swap.txt"
```

**Kết quả mong đợi:**

- Public MV sau swap mang kết quả green.
- `mv_zone_stats_green` sau swap giữ logic public cũ (hai MV đã đổi tên cho nhau).
- `continux_query_errors_total = 0`.
- Các pod RisingWave vẫn `Running`.

Ghi metric cutover vào exporter và xem dashboard:

```bash
cd ~/continux

kubectl -n pipeline exec -i deploy/continux-metrics -- sh -c 'cat > /state/cutover.prom' <<EOF
# HELP continux_cutover_duration_seconds Thời gian swap Blue/Green đo được gần nhất.
# TYPE continux_cutover_duration_seconds gauge
continux_cutover_duration_seconds ${CUTOVER_DURATION}
# HELP continux_last_swap_timestamp_seconds Unix timestamp của lần swap Blue/Green gần nhất.
# TYPE continux_last_swap_timestamp_seconds gauge
continux_last_swap_timestamp_seconds ${SWAP_TIMESTAMP}
# HELP continux_query_errors_total Số lỗi truy vấn ghi nhận trong lúc cutover.
# TYPE continux_query_errors_total counter
continux_query_errors_total ${QUERY_ERRORS}
EOF

sleep 20

curl -fsS http://127.0.0.1:9108/metrics \
  | grep -E '^continux_(cutover|last_swap|query_errors|green_ready|mv_rows|mv_trips|checksum)' \
  | tee "${EVIDENCE_DIR}/05-exporter-cutover.txt"

curl -fsSG 'http://127.0.0.1:8428/api/v1/query' \
  --data-urlencode 'query=continux_cutover_duration_seconds' \
  | tee "${EVIDENCE_DIR}/05-vm-duration.json"

curl -fsSG 'http://127.0.0.1:8428/api/v1/query' \
  --data-urlencode 'query=continux_query_errors_total' \
  | tee "${EVIDENCE_DIR}/05-vm-query-errors.json"
```

Dashboard `cutover` phải có green ready, duration của lượt vừa chạy, query errors `0`. Dashboard `data-integrity` cho thấy public đã chuyển sang logic green. `Checksum mismatch = 1` sau swap có thể là kết quả mong đợi vì dashboard đang so public mang logic mới với view mang logic cũ.

## 8. Xác Minh SQL, Iceberg Và Sức Khỏe Cluster

```bash
cd ~/continux

psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT COUNT(*) AS zones, COALESCE(SUM(trip_count), 0) AS trips FROM mv_zone_stats;"

psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT borough, SUM(trip_count) AS trips FROM mv_zone_stats GROUP BY borough ORDER BY trips DESC LIMIT 10;"

mc ls --recursive local/iceberg-data/nyc/zone_stats/ | head

bash scripts/k3s-check.sh
argocd app list --grpc-web
```

**Tiêu chí kết thúc lượt thực nghiệm:**

- `Nodes Ready = 3/3`, workloads còn `Available` sau replay.
- Argo CD không còn drift không giải thích được.
- Vector dừng ở `0 desired` sau replay.
- `mv_zone_stats` mang logic green sau swap, query errors `0`.
- Iceberg có data Parquet, equality-delete Parquet và position-delete Parquet trong `iceberg-data/nyc/zone_stats/`.

## Chuyển Sang Dọn Dẹp

Sau khi đã thu đủ kết quả và bằng chứng, tiếp tục với [CLEANUP.md](./CLEANUP.md) để trở về trạng thái sau thiết lập và có thể chạy lại một lượt mới.
