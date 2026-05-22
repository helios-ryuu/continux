# FINALIZE v1.0.0

Runbook này chạy sau khi đã hoàn tất [SETUP.md](./SETUP.md). Mục tiêu là thu evidence cuối cùng cho đồ án: baseline cluster, replay ingest sạch, verify Iceberg, Blue/Green cutover, dashboard và commit/tag `v1.0.0`.

## 0. Kết Quả Chốt Của Lần Thực Nghiệm

| Hạng mục | Kết quả đã xác nhận |
|----------|---------------------|
| Evidence run | `RUN_ID=20260522-151720` |
| K3s | `3/3` nodes Ready qua Tailscale |
| PVC | `5/5` Bound |
| Argo CD | Các app chính `Synced/Healthy` |
| RisingWave | meta, compute, compactor, frontend đều `RUNNING` |
| Lookup table | `tlc_zone = 265` dòng |
| Replay start epoch | `1779465600` |
| Replay cuối | `mv_zone_stats = 69 zones / 986 trips` |
| Iceberg | Có data Parquet, equality-delete và position-delete Parquet trong `iceberg-data/nyc/zone_stats/` |
| Public sau cutover | `mv_zone_stats = 69 zones / 978 trips` |
| View giữ tên green sau swap | `mv_zone_stats_green = 69 zones / 986 trips` |
| Cutover duration | `0.145226s` |
| Swap timestamp | `1779466691` |
| VictoriaMetrics query timestamp | `1779467656` |
| Query errors | `0` |

Ghi chú quan trọng: sau cutover, `Checksum mismatch = 1` là expected nếu dashboard so public MV logic mới với view giữ tên `mv_zone_stats_green` đang chứa logic cũ. Dùng evidence trước cutover để chứng minh cùng logic mismatch `0`, và dùng evidence sau cutover để chứng minh public MV đã chuyển sang logic mới.

## 1. Chuẩn Bị Terminal

Terminal cần giữ port-forward:

| Terminal | Lệnh giữ chạy |
|----------|---------------|
| RisingWave SQL | `kubectl -n risingwave port-forward svc/risingwave 4567:4567` |
| MinIO API | `kubectl -n minio port-forward --address 127.0.0.1 svc/minio 9000:9000` |
| Metrics exporter | `kubectl -n pipeline port-forward svc/continux-metrics 9108:9108` |
| VictoriaMetrics | `kubectl -n observability port-forward svc/vmsingle-victoria-metrics 8428:8428` |

Terminal điều khiển chính luôn bắt đầu bằng:

```bash
cd ~/continux
```

Nếu cụm nóng hoặc cần dừng ingest ngay:

```bash
kubectl --request-timeout=10s -n pipeline scale deploy/vector --replicas=0
```

## 2. Tạo Evidence Dir Và Thu Baseline

```bash
cd ~/continux

RUN_ID="$(date +%Y%m%d-%H%M%S)"
EVIDENCE_DIR="evidence/finalize/${RUN_ID}"
mkdir -p "${EVIDENCE_DIR}"

echo "${RUN_ID}" | tee "${EVIDENCE_DIR}/run-id.txt"
```

Với lần chạy chốt đã dùng:

```bash
cd ~/continux

RUN_ID=20260522-151720
EVIDENCE_DIR="evidence/finalize/${RUN_ID}"
mkdir -p "${EVIDENCE_DIR}"
```

Thu baseline:

```bash
cd ~/continux

bash scripts/k3s-check.sh | tee "${EVIDENCE_DIR}/00-k3s-check.txt"
argocd app list --grpc-web | tee "${EVIDENCE_DIR}/00-argocd-app-list.txt"
kubectl get nodes -o wide | tee "${EVIDENCE_DIR}/00-nodes.txt"
kubectl get pods -A -o wide | tee "${EVIDENCE_DIR}/00-pods.txt"
kubectl get pvc -A | tee "${EVIDENCE_DIR}/00-pvc.txt"
```

## 3. Chốt GitOps Drift Và Giữ Vector Dừng

```bash
cd ~/continux

argocd app diff cloudflared --grpc-web | tee "${EVIDENCE_DIR}/01-diff-cloudflared.txt" || true
argocd app diff vector --grpc-web | tee "${EVIDENCE_DIR}/01-diff-vector.txt" || true
```

Sync lại các app có drift do annotation/tracking hoặc do từng scale thủ công:

```bash
cd ~/continux

argocd app sync cloudflared --grpc-web
argocd app wait cloudflared --health --sync --grpc-web
kubectl -n argocd rollout status deploy/cloudflared --timeout=300s

argocd app sync vector --grpc-web
argocd app wait vector --health --sync --grpc-web
kubectl --request-timeout=10s -n pipeline scale deploy/vector --replicas=0
kubectl -n pipeline get deploy/vector -o jsonpath='{.spec.replicas}{" desired\n"}'
```

Output mong đợi:

```text
0 desired
```

Thu trạng thái sau sync:

```bash
cd ~/continux

bash scripts/k3s-check.sh overview | tee "${EVIDENCE_DIR}/01-k3s-overview-after-sync.txt"
argocd app list --grpc-web | tee "${EVIDENCE_DIR}/01-argocd-after-sync.txt"
```

## 4. Verify RisingWave Và MinIO Trước Replay

### 4.1. RisingWave

```bash
cd ~/continux

psql -h localhost -p 4567 -d dev -U root -c 'SHOW CLUSTER;' \
  | tee "${EVIDENCE_DIR}/02-risingwave-show-cluster.txt"
```

Apply lại SQL nếu catalog chưa có object:

```bash
cd ~/continux

argocd app sync pipeline --grpc-web
argocd app wait pipeline --health --sync --grpc-web
argocd app get pipeline --grpc-web | tee "${EVIDENCE_DIR}/02-pipeline-app-get.txt"
```

`mv-apply-job` là Argo CD sync hook; sau khi `Succeeded`, Job/Pod có thể bị xóa theo hook policy. Đây là hành vi bình thường. Verify bằng `rw_catalog`:

```bash
cd ~/continux

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

psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT COUNT(*) AS mv_rows, COALESCE(SUM(trip_count), 0) AS trips FROM mv_zone_stats;" \
  | tee "${EVIDENCE_DIR}/02-mv-zone-stats-count.txt"
```

Không dùng `\dt public.*` hoặc `\dm public.*` để verify RisingWave trong bản này; dùng query `rw_catalog` để tránh meta-command PostgreSQL sinh biểu thức collation không tương thích.

### 4.2. MinIO

```bash
cd ~/continux

mc alias set local http://127.0.0.1:9000 adminuser <minio-root-password>

mc ls local/tlc-zone | tee "${EVIDENCE_DIR}/02-minio-tlc-zone.txt"
mc ls --recursive local/iceberg-data/nyc/zone_stats/ | head \
  | tee "${EVIDENCE_DIR}/02-minio-iceberg-head.txt"
```

Output đã xác nhận trước replay:

```text
tlc-zone/taxi_zone_lookup.csv
iceberg-data/nyc/zone_stats/metadata/v1.metadata.json
iceberg-data/nyc/zone_stats/metadata/version-hint.text
```

## 5. Verify Metrics Exporter Và VictoriaMetrics Scrape

Render manifest:

```bash
cd ~/continux

kubectl kustomize config/metrics-exporter
kubectl kustomize gitops/apps | grep -A20 'name: metrics-exporter'
```

Sync GitOps:

```bash
cd ~/continux

argocd app sync root-app --grpc-web
argocd app wait root-app --health --sync --grpc-web

argocd app sync metrics-exporter --grpc-web
argocd app wait metrics-exporter --health --sync --grpc-web

kubectl -n pipeline get deploy,pod,svc -l app=continux-metrics \
  | tee "${EVIDENCE_DIR}/03-metrics-exporter-k8s.txt"
kubectl -n observability get vmservicescrape continux-metrics \
  | tee "${EVIDENCE_DIR}/03-metrics-exporter-scrape.txt"
```

Verify trực tiếp:

```bash
cd ~/continux

curl -s http://127.0.0.1:9108/metrics \
  | grep '^continux_' \
  | tee "${EVIDENCE_DIR}/03-exporter-direct-metrics.txt"
```

Verify VictoriaMetrics:

```bash
cd ~/continux

curl -G 'http://127.0.0.1:8428/api/v1/query' \
  --data-urlencode 'query=continux_exporter_up' \
  | tee "${EVIDENCE_DIR}/03-vm-query-exporter-up.json"

curl -G 'http://127.0.0.1:8428/api/v1/query' \
  --data-urlencode 'query=continux_mv_rows' \
  | tee "${EVIDENCE_DIR}/03-vm-query-continux-mv-rows.json"

curl -G 'http://127.0.0.1:8428/api/v1/query' \
  --data-urlencode 'query=continux_green_ready' \
  | tee "${EVIDENCE_DIR}/03-vm-query-green-ready.json"
```

Output đã xác nhận:

```text
continux_exporter_up = 1
continux_mv_rows có series cho mv_zone_stats, mv_zone_stats_blue, mv_zone_stats_green
continux_green_ready = 0 trước khi tạo green MV
```

## 6. Clear State Demo An Toàn

Chỉ chạy phần này khi đã lưu baseline. Mục tiêu là xóa state downstream để replay sạch, nhưng giữ cluster, Helm release, dashboard, bucket và dataset local.

```bash
cd ~/continux

kubectl --request-timeout=10s -n pipeline scale deploy/vector --replicas=0
kubectl -n pipeline wait --for=delete pod -l app=vector --timeout=120s || true
```

Drop object RisingWave:

```bash
cd ~/continux

psql -h localhost -p 4567 -d dev -U root <<'SQL' | tee "${EVIDENCE_DIR}/04-risingwave-clear-state.txt"
DROP SINK IF EXISTS sink_zone_stats;
DROP MATERIALIZED VIEW IF EXISTS mv_zone_stats_green;
DROP MATERIALIZED VIEW IF EXISTS mv_zone_stats;
DROP MATERIALIZED VIEW IF EXISTS mv_zone_stats_blue;
DROP SOURCE IF EXISTS nyc_taxi_src;
DROP TABLE IF EXISTS tlc_zone;
SQL
```

Recreate Redpanda topic:

```bash
cd ~/continux

kubectl -n redpanda exec redpanda-0 -c redpanda -- \
  rpk topic delete nyc-taxi-events \
  --brokers redpanda.redpanda.svc.cluster.local:9093 \
  | tee "${EVIDENCE_DIR}/04-redpanda-topic-delete.txt"

argocd app sync redpanda-topics --grpc-web
argocd app wait redpanda-topics --health --sync --grpc-web

kubectl -n redpanda exec redpanda-0 -c redpanda -- \
  rpk topic describe nyc-taxi-events \
  --brokers redpanda.redpanda.svc.cluster.local:9093 \
  | tee "${EVIDENCE_DIR}/04-redpanda-topic-after-recreate.txt"
```

Clear Iceberg prefix khi cần output sạch:

```bash
cd ~/continux

mc rm --recursive --force local/iceberg-data/nyc/zone_stats/ \
  | tee "${EVIDENCE_DIR}/04-minio-clear-iceberg-prefix.txt"
```

MinIO có thể trả delete marker vì bucket versioned; đây là hành vi bình thường cho demo.

Apply lại SQL:

```bash
cd ~/continux

argocd app sync pipeline --grpc-web
argocd app wait pipeline --health --sync --grpc-web

psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT COUNT(*) AS tlc_zone_rows FROM tlc_zone;" \
  | tee "${EVIDENCE_DIR}/04-tlc-zone-after-reapply.txt"
```

Output đã xác nhận: `tlc_zone_rows = 265`.

## 7. Replay Ingest

Bật Vector:

```bash
cd ~/continux

REPLAY_START_EPOCH="$(date +%s)"
echo "${REPLAY_START_EPOCH}" | tee "${EVIDENCE_DIR}/05-replay-start-epoch.txt"

kubectl -n pipeline scale deploy/vector --replicas=1
kubectl -n pipeline rollout status deploy/vector --timeout=300s
kubectl -n pipeline logs deploy/vector --tail=120 \
  | tee "${EVIDENCE_DIR}/05-vector-startup-logs.txt"
```

Theo dõi topic và MV:

```bash
cd ~/continux

kubectl -n redpanda exec redpanda-0 -c redpanda -- \
  rpk topic describe nyc-taxi-events \
  --brokers redpanda.redpanda.svc.cluster.local:9093 \
  | tee "${EVIDENCE_DIR}/05-redpanda-topic-during-replay.txt"

psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT COUNT(*) AS zones, COALESCE(SUM(trip_count), 0) AS trips FROM mv_zone_stats;" \
  | tee "${EVIDENCE_DIR}/05-mv-progress.txt"
```

Lấy mẫu exporter trong lúc replay:

```bash
cd ~/continux

curl -s http://127.0.0.1:9108/metrics \
  | grep -E '^continux_(events|mv_rows|mv_trips|kafka)' \
  | tee "${EVIDENCE_DIR}/05-exporter-progress.txt"
```

Dừng Vector khi đủ dữ liệu hoặc khi cần bảo toàn tài nguyên:

```bash
cd ~/continux

psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT COUNT(*) AS zones, COALESCE(SUM(trip_count), 0) AS trips FROM mv_zone_stats;" \
  | tee "${EVIDENCE_DIR}/05-mv-before-stop.txt"

curl -s http://127.0.0.1:9108/metrics \
  | grep -E '^continux_(events|mv_rows|mv_trips|kafka)' \
  | tee "${EVIDENCE_DIR}/05-exporter-before-stop.txt"

kubectl --request-timeout=10s -n pipeline scale deploy/vector --replicas=0
kubectl -n pipeline wait --for=delete pod -l app=vector --timeout=120s || true
```

Thu kết quả cuối:

```bash
cd ~/continux

psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT COUNT(*) AS zones, COALESCE(SUM(trip_count), 0) AS trips FROM mv_zone_stats;" \
  | tee "${EVIDENCE_DIR}/05-mv-final-count.txt"

psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT borough, SUM(trip_count) AS trips FROM mv_zone_stats GROUP BY borough ORDER BY trips DESC LIMIT 10;" \
  | tee "${EVIDENCE_DIR}/05-mv-final-top-boroughs.txt"

mc ls --recursive local/iceberg-data/nyc/zone_stats/ | head -50 \
  | tee "${EVIDENCE_DIR}/05-minio-iceberg-after-replay.txt"

bash scripts/k3s-check.sh overview \
  | tee "${EVIDENCE_DIR}/05-k3s-overview-after-replay.txt"
```

Kết quả chốt:

```text
05-replay-start-epoch.txt: 1779465600
05-mv-before-stop.txt: 66 zones / 912 trips
05-mv-final-count.txt: 69 zones / 986 trips
05-k3s-overview-after-replay.txt: Nodes Ready 3/3, PVC Bound 5/5, Workloads Ready 23/23
```

Ghi chú về metric Kafka catalog: `continux_events_ingested_total`, `continux_kafka_processed_offsets_total` và `continux_kafka_lag` có thể bằng `0` trong cấu hình này vì RisingWave không trả dữ liệu Kafka catalog phù hợp. Dùng `continux_events_processed_total`, `continux_mv_rows`, `continux_mv_trips`, output topic Redpanda và dashboard proxy để kết luận replay.

## 8. Blue/Green Cutover

### 8.1. Tạo Green MV

```bash
cd ~/continux

psql -h localhost -p 4567 -d dev -U root <<'SQL' | tee "${EVIDENCE_DIR}/06-create-green-mv.txt"
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
```

Theo dõi green:

```bash
cd ~/continux

for i in $(seq 1 20); do
  date -Is
  psql -h localhost -p 4567 -d dev -U root -At -c \
    "SELECT 'public', COUNT(*), COALESCE(SUM(trip_count),0) FROM mv_zone_stats
     UNION ALL
     SELECT 'blue', COUNT(*), COALESCE(SUM(trip_count),0) FROM mv_zone_stats_blue
     UNION ALL
     SELECT 'green', COUNT(*), COALESCE(SUM(trip_count),0) FROM mv_zone_stats_green;"
  sleep 10
done | tee "${EVIDENCE_DIR}/06-green-catchup-samples.txt"
```

Kết quả trước swap:

```text
public = 69 zones / 986 trips
blue   = 69 zones / 986 trips
green  = 69 zones / 978 trips
```

### 8.2. Query Loop Trong Lúc Swap

Terminal riêng:

```bash
cd ~/continux

QUERY_LOG="${EVIDENCE_DIR}/06-query-loop-during-cutover.txt"

while true; do
  TS="$(date -Is)"
  if psql -h localhost -p 4567 -d dev -U root -At -c \
    "SELECT COUNT(*), COALESCE(SUM(trip_count),0) FROM mv_zone_stats;" >/tmp/continux-query-loop.out 2>/tmp/continux-query-loop.err; then
    printf '%s OK %s\n' "${TS}" "$(cat /tmp/continux-query-loop.out)"
  else
    printf '%s ERROR %s\n' "${TS}" "$(cat /tmp/continux-query-loop.err)"
  fi
  sleep 0.5
done | tee "${QUERY_LOG}"
```

Sau swap, dừng bằng `Ctrl+C`. Kết quả đã ghi nhận: không có dòng `ERROR`; public MV chuyển từ `69|986` sang `69|978`.

### 8.3. Swap Public MV

Terminal điều khiển:

```bash
cd ~/continux

CUTOVER_START_NS="$(date +%s%N)"

psql -h localhost -p 4567 -d dev -U root -c \
  "ALTER MATERIALIZED VIEW mv_zone_stats SWAP WITH mv_zone_stats_green;" \
  | tee "${EVIDENCE_DIR}/06-cutover-swap.txt"

CUTOVER_END_NS="$(date +%s%N)"
python3 - <<PY | tee "${EVIDENCE_DIR}/06-cutover-duration.txt"
start_ns = int("${CUTOVER_START_NS}")
end_ns = int("${CUTOVER_END_NS}")
print(f"continux_cutover_duration_seconds {(end_ns - start_ns) / 1_000_000_000:.6f}")
print(f"continux_last_swap_timestamp_seconds {end_ns // 1_000_000_000}")
PY
```

Kết quả đã đo:

```text
ALTER_MATERIALIZED_VIEW
continux_cutover_duration_seconds 0.145226
continux_last_swap_timestamp_seconds 1779466691
```

Verify sau swap:

```bash
cd ~/continux

psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT COUNT(*) AS zones, COALESCE(SUM(trip_count),0) AS trips FROM mv_zone_stats;" \
  | tee "${EVIDENCE_DIR}/06-public-after-swap.txt"

psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT COUNT(*) AS zones, COALESCE(SUM(trip_count),0) AS trips FROM mv_zone_stats_green;" \
  | tee "${EVIDENCE_DIR}/06-green-name-after-swap.txt"

kubectl -n risingwave get pods \
  | tee "${EVIDENCE_DIR}/06-risingwave-pods-after-swap.txt"
```

Kết quả đã xác nhận:

```text
mv_zone_stats = 69 zones / 978 trips
mv_zone_stats_green = 69 zones / 986 trips
RisingWave compactor, compute, frontend, meta đều Running
```

### 8.4. Ghi Cutover Metrics Vào Exporter

Dùng `kubectl exec -i` để truyền heredoc vào pod:

```bash
cd ~/continux

kubectl -n pipeline exec -i deploy/continux-metrics -- sh -c 'cat > /state/cutover.prom' <<'EOF'
# HELP continux_cutover_duration_seconds Latest measured blue/green swap duration.
# TYPE continux_cutover_duration_seconds gauge
continux_cutover_duration_seconds 0.145226
# HELP continux_last_swap_timestamp_seconds Unix timestamp of the last blue/green swap.
# TYPE continux_last_swap_timestamp_seconds gauge
continux_last_swap_timestamp_seconds 1779466691
# HELP continux_query_errors_total Query errors observed during cutover.
# TYPE continux_query_errors_total counter
continux_query_errors_total 0
EOF

kubectl -n pipeline exec deploy/continux-metrics -- sh -c \
  'wc -c /state/cutover.prom; sed -n "1,40p" /state/cutover.prom' \
  | tee "${EVIDENCE_DIR}/06-cutover-prom-file.txt"
```

Verify exporter và VictoriaMetrics:

```bash
cd ~/continux

curl -s http://127.0.0.1:9108/metrics \
  | grep -E '^continux_(cutover|last_swap|query_errors|green_ready|mv_rows)' \
  | tee "${EVIDENCE_DIR}/06-exporter-cutover-metrics.txt"

curl -G 'http://127.0.0.1:8428/api/v1/query' \
  --data-urlencode 'query=continux_cutover_duration_seconds' \
  | tee "${EVIDENCE_DIR}/06-vm-query-cutover-duration.json"

curl -G 'http://127.0.0.1:8428/api/v1/query' \
  --data-urlencode 'query=continux_query_errors_total' \
  | tee "${EVIDENCE_DIR}/06-vm-query-query-errors.json"
```

Kết quả cuối đã xác nhận:

```text
continux_mv_rows{view="mv_zone_stats"} 69
continux_mv_rows{view="mv_zone_stats_blue"} 69
continux_mv_rows{view="mv_zone_stats_green"} 69
continux_green_ready 1
continux_cutover_duration_seconds 0.145226
continux_last_swap_timestamp_seconds 1779466691
continux_query_errors_total 0
VictoriaMetrics: continux_cutover_duration_seconds = 0.145226 at 1779467656
VictoriaMetrics: continux_query_errors_total = 0 at 1779467656
```

## 9. Dashboard Và Evidence Checklist

Chụp hoặc export 4 nhóm dashboard:

| Nhóm chỉ số | Dashboard | Evidence đề xuất |
|-------------|-----------|------------------|
| Streaming performance | `streaming-perf` | `grafana-01-streaming-perf.png` |
| Resource utilization | `resource-util` | `grafana-02-resource-util.png` |
| Cutover and GitOps deployment | `cutover` | `grafana-03-cutover.png` |
| Data integrity | `data-integrity` | `grafana-04-data-integrity.png` |

Các screenshot trong phiên làm việc được tham chiếu trong báo cáo bằng tên file:

```text
grafana-01-streaming-perf.png
grafana-02-resource-util.png
grafana-03-cutover.png
grafana-04-data-integrity.png
```

Không commit ảnh lớn hoặc thư mục `evidence/` vào repo; nộp riêng nếu cần.

## 10. Kiểm Tra Cuối, Commit Và Tag

```bash
cd ~/continux

bash scripts/k3s-check.sh overview
argocd app list --grpc-web
kubectl -n pipeline get deploy/vector -o jsonpath='{.spec.replicas}{" desired\n"}'
psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT COUNT(*) AS zones, COALESCE(SUM(trip_count),0) AS trips FROM mv_zone_stats;"
mc ls --recursive local/iceberg-data/nyc/zone_stats/ | head
```

Điều kiện chốt:

- `Nodes Ready = 3/3`.
- `Workloads Ready = 100%`.
- Argo CD không còn drift không giải thích được.
- Vector dừng ở `0 desired` sau replay.
- `mv_zone_stats = 69 zones / 978 trips` sau cutover.
- `continux_query_errors_total = 0`.
- Evidence run `20260522-151720` có đủ file từ `00-*` đến `06-*`.

Commit tài liệu:

```bash
cd ~/continux

git status --short
git add VERSION README.md docs scripts
git commit -m "docs(release): finalize v1.0.0 documentation"
git tag -a v1.0.0 -m "Continux v1.0.0 final report"
git push
git push origin v1.0.0
```

## 11. Troubleshooting

### Metrics Exporter Không Healthy

```bash
kubectl -n pipeline get pod,svc -l app=continux-metrics
kubectl -n pipeline logs deploy/continux-metrics --tail=100
kubectl -n observability describe vmservicescrape continux-metrics
```

Exporter bản `v1.0.0` serve `/metrics` bằng BusyBox `nc`.

### VictoriaMetrics Chưa Có Series Mới

Chờ ít nhất một scrape interval rồi query lại:

```bash
curl -G 'http://127.0.0.1:8428/api/v1/query' \
  --data-urlencode 'query=continux_exporter_up'
```

Kiểm tra selector:

```bash
kubectl -n pipeline get svc continux-metrics --show-labels
kubectl -n observability get vmservicescrape continux-metrics -o yaml
```

### Vector Replay Quá Nặng

```bash
kubectl --request-timeout=10s -n pipeline scale deploy/vector --replicas=0
kubectl -n pipeline logs deploy/vector --tail=200
```

Giảm `rate_limit_num` hoặc `max_events` trong `config/vector/vector-config.yaml`, commit, push và sync lại `vector`.

### Pod Configuration Cũ Của Redpanda

Một pod `redpanda-configuration-*` cũ ở trạng thái `Failed` không chặn hệ thống nếu StatefulSet Redpanda Ready và configuration job mới đã `Succeeded`:

```bash
kubectl -n redpanda get sts/redpanda deploy/redpanda-console
kubectl -n redpanda get pods | grep redpanda-configuration
```

### Cần Reset Demo Lần Nữa

Dùng lại §6 của tài liệu này. Không chạy `scripts/k3s-purge.sh` trong finalize trừ khi mục tiêu là reset cluster. Nếu cần reset cluster thật, đọc [SCRIPTS.md](./SCRIPTS.md) trước.
