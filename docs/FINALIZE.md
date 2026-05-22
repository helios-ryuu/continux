# FINALIZE

> Phiên bản dự án: `v0.2.3`.
>
> Tài liệu này chạy **sau khi đã hoàn tất `docs/SETUP.md` tới §10**. Mục tiêu không còn là dựng stack nữa, mà là thu bằng chứng thực nghiệm cuối cùng: replay ingest sạch, dashboard có dữ liệu thật, kiểm chứng Blue/Green cutover, kiểm chứng toàn vẹn dữ liệu và cập nhật báo cáo.

## 0. Mốc hiện tại

Baseline `v0.2.3` sau khi đã chạy `FINALIZE.md` tới hết §4 ngày `2026-05-22`:

| Hạng mục | Trạng thái | Ghi chú |
|----------|------------|---------|
| K3s nodes | `3/3 Ready` | `imac`, `continux-vps`, `helios-pc` đều Ready qua Tailscale |
| Pods | `26/27 Running/Succeeded` | 1 pod `redpanda-configuration-cdk5k` `Failed`, là job/configuration cũ |
| PVC | `5/5 Bound` | MinIO, Redpanda, Grafana, VictoriaMetrics đều có PVC |
| Workloads | `22/22 Available` | Không có workload chính bị thiếu replica |
| Argo CD | Tất cả app hiện có `Synced/Healthy` | `cloudflared` và `vector` đã sync lại; `vector` vẫn giữ `replicas=0` |
| RisingWave | `SHOW CLUSTER` có 4 worker `RUNNING` | SQL object đã re-apply qua `pipeline` hook |
| SQL object | Đủ `tlc_zone`, `nyc_taxi_src`, `mv_zone_stats_blue`, `mv_zone_stats`, `sink_zone_stats` | Verify bằng `rw_catalog` |
| Lookup data | `tlc_zone_rows = 265` | MinIO `tlc-zone/taxi_zone_lookup.csv` đã đọc được |
| MV trước replay | `mv_zone_stats = 0 rows / 0 trips` | Hợp lệ vì topic đã clear và chưa bật Vector replay |
| Iceberg trước replay | Có `metadata/v1.metadata.json` và `metadata/version-hint.text` | Sink/table đã tạo; data Parquet sẽ sinh sau replay |
| Resource local `imac` | RAM khoảng `43-44%`, disk `/` khoảng `11%` | Đủ an toàn để replay có kiểm soát |

Kết luận: §1-4 của finalize đã hoàn tất. Bước kế tiếp là §5.1 triển khai `metrics-exporter`, sau đó replay ingest sạch ở §6-7 và chạy cutover ở §8. Không chạy reset toàn cụm, không chạy `k3s-purge.sh`, không chạy `--nuke`.

## 1. Nguyên tắc finalize

- Giữ `Vector` ở `replicas=0` cho tới khi tất cả preflight xanh.
- Mỗi lần replay phải có `RUN_ID` riêng để lưu log, output SQL và screenshot dashboard.
- Không commit secret thật, token Cloudflare, password MinIO/Grafana/Argo CD hoặc kubeconfig.
- Nếu một lệnh cần terminal giữ port-forward, mở terminal riêng và để lệnh chạy trong suốt bước verify.
- Nếu cụm bắt đầu nghẽn, ưu tiên dừng ingest trước:

```bash
kubectl --request-timeout=10s -n pipeline scale deploy/vector --replicas=0
```

## 2. Tạo thư mục bằng chứng

Chạy trên `imac`:

```bash
cd ~/continux

RUN_ID="$(date +%Y%m%d-%H%M%S)"
EVIDENCE_DIR="evidence/finalize/${RUN_ID}"
mkdir -p "${EVIDENCE_DIR}"

echo "${RUN_ID}" | tee "${EVIDENCE_DIR}/run-id.txt"
```

Thu baseline ban đầu:

```bash
bash scripts/k3s-check.sh | tee "${EVIDENCE_DIR}/00-k3s-check.txt"
argocd app list --grpc-web | tee "${EVIDENCE_DIR}/00-argocd-app-list.txt"
kubectl get nodes -o wide | tee "${EVIDENCE_DIR}/00-nodes.txt"
kubectl get pods -A -o wide | tee "${EVIDENCE_DIR}/00-pods.txt"
kubectl get pvc -A | tee "${EVIDENCE_DIR}/00-pvc.txt"
```

Nếu muốn dùng chế độ export có sẵn của script:

```bash
bash scripts/k3s-check.sh export
```

Script sẽ ghi file vào `scripts/k3s-check/`. Copy file export tương ứng vào `${EVIDENCE_DIR}` nếu dùng làm phụ lục báo cáo.

Thư mục `evidence/` là log local và đã được ignore khỏi Git. Nếu cần nộp một phần bằng chứng trong repo, chọn lọc file nhỏ và commit ở đường dẫn riêng có chủ đích.

## 3. Chốt drift GitOps trước khi đo

Mục tiêu của bước này là biết rõ `OutOfSync` là drift thật hay drift có chủ đích do thao tác runtime.

```bash
argocd app diff cloudflared --grpc-web | tee "${EVIDENCE_DIR}/01-diff-cloudflared.txt" || true
argocd app diff vector --grpc-web | tee "${EVIDENCE_DIR}/01-diff-vector.txt" || true
```

Nếu `cloudflared` drift do manifest chưa sync, sync lại:

```bash
argocd app sync cloudflared --grpc-web
argocd app wait cloudflared --health --sync --grpc-web
kubectl -n argocd rollout status deploy/cloudflared --timeout=300s
```

Nếu `vector` drift chỉ do `replicas` đã từng scale thủ công, giữ quy ước Git là `replicas: 0`, sync lại rồi đảm bảo deployment vẫn dừng:

```bash
argocd app sync vector --grpc-web
argocd app wait vector --health --sync --grpc-web
kubectl --request-timeout=10s -n pipeline scale deploy/vector --replicas=0
kubectl -n pipeline get deploy/vector -o jsonpath='{.spec.replicas}{" desired\n"}'
```

Output mong đợi:

```text
0 desired
```

Nếu chỉ còn pod `redpanda-configuration-cdk5k` `Failed` trong hot list và pod configuration mới đã `Succeeded`, có thể ghi nhận là không chặn workload:

```bash
kubectl -n redpanda get pod redpanda-configuration-vl774
kubectl -n redpanda get pod redpanda-configuration-cdk5k
```

Nếu cần hot list sạch để screenshot, chỉ xóa pod failed cũ sau khi đã xác nhận workload Redpanda Ready:

```bash
kubectl -n redpanda get sts/redpanda
kubectl -n redpanda get deploy/redpanda-console
kubectl -n redpanda delete pod redpanda-configuration-cdk5k
```

Kiểm tra lại:

```bash
bash scripts/k3s-check.sh overview | tee "${EVIDENCE_DIR}/01-k3s-overview-after-sync.txt"
argocd app list --grpc-web | tee "${EVIDENCE_DIR}/01-argocd-after-sync.txt"
```

## 4. Verify data layer trước replay

### 4.1. RisingWave SQL

Terminal 1, giữ port-forward:

```bash
kubectl -n risingwave port-forward svc/risingwave 4567:4567
```

Terminal 2:

```bash
psql -h localhost -p 4567 -d dev -U root -c 'SHOW CLUSTER;' \
  | tee "${EVIDENCE_DIR}/02-risingwave-show-cluster.txt"
```

Nếu các query bên dưới báo `table or source not found: tlc_zone`, nghĩa là cụm đang ở mốc sau khi đã chạy clear demo trong `SETUP.md` §11: RisingWave vẫn healthy nhưng SQL object đã bị drop. Apply lại SQL bằng GitOps rồi chạy lại phần verify:

```bash
argocd app sync pipeline --grpc-web
argocd app wait pipeline --health --sync --grpc-web

argocd app get pipeline --grpc-web
```

`mv-apply-job` là Argo CD sync hook và đang có `argocd.argoproj.io/hook-delete-policy: BeforeHookCreation,HookSucceeded`, nên sau khi Argo CD báo `mv-apply-job Succeeded`, Job/Pod có thể đã bị xóa khỏi Kubernetes. Khi đó `kubectl -n pipeline get job,pod -l app=mv-apply-job` trả `No resources found` là bình thường, không phải lỗi.

Verify SQL object bằng RisingWave catalog thay vì dựa vào Job còn tồn tại:

```bash
psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT 'table' AS kind, name FROM rw_catalog.rw_tables WHERE name = 'tlc_zone'
   UNION ALL
   SELECT 'source' AS kind, name FROM rw_catalog.rw_sources WHERE name = 'nyc_taxi_src'
   UNION ALL
   SELECT 'mv' AS kind, name FROM rw_catalog.rw_materialized_views WHERE name IN ('mv_zone_stats_blue', 'mv_zone_stats')
   UNION ALL
   SELECT 'sink' AS kind, name FROM rw_catalog.rw_sinks WHERE name = 'sink_zone_stats'
   ORDER BY kind, name;"
```

Tránh dùng `\dt public.*` hoặc `\dm public.*` với RisingWave `v2.8.3`; psql sẽ sinh query regex/collation kiểu PostgreSQL và có thể lỗi `Collate collation other than C or POSIX is not implemented`. Nếu cần xem nhanh bằng meta-command, dùng `\dt` không kèm pattern, hoặc ưu tiên query `rw_catalog` như trên.

Tiếp tục khi đã thấy `tlc_zone`, `nyc_taxi_src`, `mv_zone_stats_blue`, `mv_zone_stats` và `sink_zone_stats` tồn tại.

```bash

psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT COUNT(*) AS tlc_zone_rows FROM tlc_zone;" \
  | tee "${EVIDENCE_DIR}/02-tlc-zone-count.txt"

psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT COUNT(*) AS mv_rows, COALESCE(SUM(trip_count), 0) AS trips FROM mv_zone_stats;" \
  | tee "${EVIDENCE_DIR}/02-mv-zone-stats-count.txt"

psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT borough, SUM(trip_count) AS trips FROM mv_zone_stats GROUP BY borough ORDER BY trips DESC LIMIT 10;" \
  | tee "${EVIDENCE_DIR}/02-top-boroughs.txt"
```

Mốc end-to-end đã ghi nhận trước khi clear demo:

```text
tlc_zone_rows = 265
mv_zone_stats rows = 260
top borough: Manhattan, Queens, Brooklyn, Bronx, Unknown
```

Nếu vừa clear topic Redpanda ở `SETUP.md` §11 và chưa bật Vector replay lại, `tlc_zone_rows` vẫn phải là `265` nhưng `mv_zone_stats` có thể đang là `0` dòng. Trạng thái này hợp lệ trước replay; MV sẽ tăng sau khi scale Vector lên `1`.

### 4.2. MinIO và Iceberg

Terminal 3, giữ MinIO API port-forward:

```bash
kubectl -n minio port-forward --address 127.0.0.1 svc/minio 9000:9000
```

Terminal 2:

```bash
mc alias set local http://127.0.0.1:9000 adminuser <minio-root-password>

mc ls local/tlc-zone | tee "${EVIDENCE_DIR}/02-minio-tlc-zone.txt"
mc ls --recursive local/iceberg-data/nyc/zone_stats/ | head \
  | tee "${EVIDENCE_DIR}/02-minio-iceberg-head.txt"
```

Không đưa password thật vào file evidence, report hoặc screenshot terminal. Nếu terminal transcript có chứa password và sẽ được chia sẻ/nộp kèm, hãy che lại hoặc rotate password MinIO trước khi công khai.

Nếu `iceberg-data/nyc/zone_stats/` đang trống vì đã chạy clear demo ở `SETUP.md` §11, đó là trạng thái hợp lệ trước replay sạch.

## 5. Bổ sung metric thực nghiệm `continux_*`

Các dashboard đã có panel cho `continux_*`, nhưng metric này không tự sinh ra từ Kubernetes. Đây là phần còn thiếu quan trọng để dashboard không chỉ hiển thị `vector(0)`.

### 5.1. Contract tối thiểu của exporter

Exporter đã được triển khai trong repo ở `config/metrics-exporter/`. App này chạy container `postgres:16-alpine`, dùng `psql` đọc RisingWave catalog/MV, sinh Prometheus text tại `/metrics` và được VictoriaMetrics scrape qua `VMServiceScrape`.

Metric được expose:

| Metric | Cách sinh | Dùng cho dashboard |
|--------|-------------------|--------------------|
| `continux_events_ingested_total` | `rw_catalog.rw_kafka_source_metrics.high_watermark` | Throughput ingest |
| `continux_mv_rows{view="mv_zone_stats"}` | `SELECT COUNT(*) FROM mv_zone_stats` | Integrity, public MV rows |
| `continux_mv_rows{view="mv_zone_stats_blue"}` | `SELECT COUNT(*) FROM mv_zone_stats_blue` | Blue/green row count |
| `continux_mv_rows{view="mv_zone_stats_green"}` | `SELECT COUNT(*) FROM mv_zone_stats_green` nếu tồn tại | Blue/green row count |
| `continux_mv_trips{view="..."}` | `SELECT COALESCE(SUM(trip_count),0)` theo view | Integrity/trip count |
| `continux_events_processed_total` | `SELECT COALESCE(SUM(trip_count),0) FROM mv_zone_stats` | Application processed events/s |
| `continux_kafka_processed_offsets_total` | `rw_catalog.rw_kafka_source_metrics.latest_offset` | Source progress |
| `continux_kafka_lag` | `rw_catalog.rw_kafka_job_lag.lag` | Lag đối chiếu |
| `continux_green_ready` | `1` khi `mv_zone_stats_green` tồn tại và có dòng | Cutover readiness |
| `continux_cutover_duration_seconds` | Script cutover ghi duration gần nhất | Latest cutover duration |
| `continux_last_swap_timestamp_seconds` | Epoch seconds của lần swap gần nhất | Seconds since last swap |
| `continux_query_errors_total` | Query loop tăng khi query lỗi trong lúc swap | Query errors during cutover |
| `continux_checksum_mismatch_total` | `0` nếu public và blue khớp row/trip count | Data integrity |
| `continux_records_rejected_total{reason="parse"}` | Mặc định `0` tới khi thêm parser validation | Rejected records/s |
| `continux_iceberg_last_commit_timestamp_seconds` | `rw_catalog.rw_iceberg_snapshots.timestamp_ms` | Iceberg freshness |

Manifest:

```text
config/metrics-exporter/configmap.yaml
config/metrics-exporter/deployment.yaml
config/metrics-exporter/service.yaml
config/metrics-exporter/vmservicescrape.yaml
config/metrics-exporter/kustomization.yaml
gitops/apps/metrics-exporter-app.yaml
```

Render local trước khi deploy:

```bash
kubectl kustomize config/metrics-exporter
kubectl kustomize gitops/apps | grep -A20 'name: metrics-exporter'
```

Triển khai nhanh để đo ngay từ working tree hiện tại:

```bash
kubectl apply -k config/metrics-exporter
kubectl -n pipeline rollout status deploy/continux-metrics --timeout=300s
```

Triển khai GitOps chuẩn sau khi commit/push manifest lên `main`:

```bash
argocd app sync root-app --grpc-web
argocd app wait root-app --health --sync --grpc-web

argocd app sync metrics-exporter --grpc-web
argocd app wait metrics-exporter --health --sync --grpc-web
```

Verify Kubernetes:

```bash
kubectl -n pipeline get deploy,pod,svc -l app=continux-metrics
kubectl -n observability get vmservicescrape continux-metrics
```

Verify exporter trực tiếp:

```bash
kubectl -n pipeline port-forward svc/continux-metrics 9108:9108
```

Terminal khác:

```bash
curl -s http://127.0.0.1:9108/metrics | grep '^continux_' | tee "${EVIDENCE_DIR}/03-exporter-direct-metrics.txt"
```

Ghi metric cutover thủ công vào exporter khi thực hiện §8:

```bash
kubectl -n pipeline exec deploy/continux-metrics -- sh -c 'cat > /state/cutover.prom' <<EOF
# HELP continux_cutover_duration_seconds Latest measured blue/green swap duration.
# TYPE continux_cutover_duration_seconds gauge
continux_cutover_duration_seconds 0.123
# HELP continux_last_swap_timestamp_seconds Unix timestamp of the last blue/green swap.
# TYPE continux_last_swap_timestamp_seconds gauge
continux_last_swap_timestamp_seconds $(date +%s)
# HELP continux_query_errors_total Query errors observed during cutover.
# TYPE continux_query_errors_total counter
continux_query_errors_total 0
EOF
```

Query trực tiếp VictoriaMetrics:

```bash
kubectl -n observability port-forward svc/vmsingle-victoria-metrics 8428:8428
```

Terminal khác:

```bash
curl -G 'http://127.0.0.1:8428/api/v1/query' \
  --data-urlencode 'query=continux_mv_rows' \
  | tee "${EVIDENCE_DIR}/03-vm-query-continux-mv-rows.json"

curl -G 'http://127.0.0.1:8428/api/v1/query' \
  --data-urlencode 'query=continux_green_ready' \
  | tee "${EVIDENCE_DIR}/03-vm-query-green-ready.json"
```

Nếu metric chưa xuất hiện trong VictoriaMetrics, chờ 30-60 giây rồi kiểm tra selector/service:

```bash
kubectl -n pipeline get svc continux-metrics --show-labels
kubectl -n observability describe vmservicescrape continux-metrics
kubectl -n pipeline logs deploy/continux-metrics --tail=100
```

## 6. Clear demo để replay sạch

Bước này phá state downstream để chạy lại demo từ trạng thái sạch, nhưng giữ cluster, Helm releases, buckets và dataset local. Chỉ chạy khi đã lưu baseline ở các bước trên.

Dừng Vector:

```bash
kubectl --request-timeout=10s -n pipeline scale deploy/vector --replicas=0
kubectl -n pipeline wait --for=delete pod -l app=vector --timeout=120s || true
```

Xóa state RisingWave. Cần port-forward RisingWave ở §4.1 đang chạy:

```bash
psql -h localhost -p 4567 -d dev -U root <<'SQL' | tee "${EVIDENCE_DIR}/04-risingwave-clear-state.txt"
DROP SINK IF EXISTS sink_zone_stats;
DROP MATERIALIZED VIEW IF EXISTS mv_zone_stats_green;
DROP MATERIALIZED VIEW IF EXISTS mv_zone_stats;
DROP MATERIALIZED VIEW IF EXISTS mv_zone_stats_blue;
DROP SOURCE IF EXISTS nyc_taxi_src;
DROP TABLE IF EXISTS tlc_zone;
SQL
```

Xóa và tạo lại topic Redpanda:

```bash
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

Xóa prefix Iceberg nếu cần output sạch. Cần port-forward MinIO ở §4.2 đang chạy:

```bash
mc rm --recursive --force local/iceberg-data/nyc/zone_stats/ \
  | tee "${EVIDENCE_DIR}/04-minio-clear-iceberg-prefix.txt"
```

Lưu ý: nếu output là `Created delete marker`, bucket đang giữ versioning/delete marker. Với demo replay, listing thông thường đã sạch; nếu cần thu hồi dung lượng thật thì dọn version/lifecycle riêng.

Apply lại SQL bằng GitOps:

```bash
argocd app sync pipeline --grpc-web
argocd app wait pipeline --health --sync --grpc-web

psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT COUNT(*) AS tlc_zone_rows FROM tlc_zone;" \
  | tee "${EVIDENCE_DIR}/04-tlc-zone-after-reapply.txt"
```

## 7. Replay ingest và đo hiệu năng

Mở Grafana trước khi scale Vector:

- Dashboard `streaming-perf`: time range `Last 15 minutes`.
- Dashboard `resource-util`: time range `Last 15 minutes`.
- Dashboard `data-integrity`: time range `Last 15 minutes`.
- Dashboard `cutover`: để sẵn cho bước §8.

Đảm bảo Windows/WSL `helios-pc` không sleep trong suốt replay.

Bật Vector:

```bash
REPLAY_START_EPOCH="$(date +%s)"
echo "${REPLAY_START_EPOCH}" | tee "${EVIDENCE_DIR}/05-replay-start-epoch.txt"

kubectl -n pipeline scale deploy/vector --replicas=1
kubectl -n pipeline rollout status deploy/vector --timeout=300s
kubectl -n pipeline logs deploy/vector --tail=120 \
  | tee "${EVIDENCE_DIR}/05-vector-startup-logs.txt"
```

Theo dõi topic Redpanda:

```bash
kubectl -n redpanda exec redpanda-0 -c redpanda -- \
  rpk topic describe nyc-taxi-events \
  --brokers redpanda.redpanda.svc.cluster.local:9093 \
  | tee "${EVIDENCE_DIR}/05-redpanda-topic-during-replay.txt"
```

Theo dõi RisingWave:

```bash
psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT COUNT(*) AS zones, COALESCE(SUM(trip_count), 0) AS trips FROM mv_zone_stats;" \
  | tee "${EVIDENCE_DIR}/05-mv-progress.txt"
```

Nếu muốn lấy nhiều mẫu theo thời gian:

```bash
for i in $(seq 1 12); do
  date -Is
  psql -h localhost -p 4567 -d dev -U root -At -c \
    "SELECT COUNT(*), COALESCE(SUM(trip_count), 0) FROM mv_zone_stats;"
  sleep 10
done | tee "${EVIDENCE_DIR}/05-mv-progress-samples.txt"
```

Khi đã đủ dữ liệu cho dashboard hoặc cụm bắt đầu nóng, dừng Vector:

```bash
kubectl --request-timeout=10s -n pipeline scale deploy/vector --replicas=0
kubectl -n pipeline wait --for=delete pod -l app=vector --timeout=120s || true
```

Thu kết quả sau replay:

```bash
psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT COUNT(*) AS zones, COALESCE(SUM(trip_count), 0) AS trips FROM mv_zone_stats;" \
  | tee "${EVIDENCE_DIR}/05-mv-final-count.txt"

psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT borough, SUM(trip_count) AS trips FROM mv_zone_stats GROUP BY borough ORDER BY trips DESC LIMIT 10;" \
  | tee "${EVIDENCE_DIR}/05-mv-final-top-boroughs.txt"

mc ls --recursive local/iceberg-data/nyc/zone_stats/ | head -50 \
  | tee "${EVIDENCE_DIR}/05-minio-iceberg-after-replay.txt"

bash scripts/k3s-check.sh | tee "${EVIDENCE_DIR}/05-k3s-check-after-replay.txt"
```

Screenshot cần chụp ngay sau bước này:

- `01-streaming-perf`: throughput/network bytes, topic offsets, consumer lag, RisingWave rows/s.
- `02-resource-util`: CPU/RAM theo namespace, top pod CPU/RAM, restarts, PVC.
- `04-data-integrity`: MV rows, Iceberg freshness, MinIO growth, rejected records.

## 8. Blue/Green cutover

RisingWave hỗ trợ đổi logic streaming bằng cách tạo materialized view mới rồi swap/rename. Với bản hiện tại, nên dùng `ALTER MATERIALIZED VIEW ... SWAP WITH ...` để demo đổi tên giữa public MV và green MV cùng loại.

### 8.1. Tạo green MV

Green MV phải cùng schema với `mv_zone_stats` để swap an toàn. Ví dụ dưới đây giữ cùng schema, nhưng thêm điều kiện chất lượng dữ liệu để thể hiện logic mới.

```bash
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

Theo dõi green bắt kịp:

```bash
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

Green được xem là sẵn sàng khi:

- row count không còn tăng lệch bất thường;
- tổng `trip_count` hợp lý với logic mới;
- nếu exporter đã có, `continux_green_ready = 1`.

### 8.2. Bắn query trong lúc cutover

Terminal riêng, chạy query loop để đo lỗi truy vấn:

```bash
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

Dừng loop bằng `Ctrl+C` sau khi cutover xong.

### 8.3. Swap public và green

Terminal khác:

```bash
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

Verify sau swap:

```bash
psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT COUNT(*) AS zones, COALESCE(SUM(trip_count),0) AS trips FROM mv_zone_stats;" \
  | tee "${EVIDENCE_DIR}/06-public-after-swap.txt"

psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT COUNT(*) AS zones, COALESCE(SUM(trip_count),0) AS trips FROM mv_zone_stats_green;" \
  | tee "${EVIDENCE_DIR}/06-green-name-after-swap.txt"

kubectl -n risingwave get pods \
  | tee "${EVIDENCE_DIR}/06-risingwave-pods-after-swap.txt"
```

Nếu cần rollback ngay:

```bash
psql -h localhost -p 4567 -d dev -U root -c \
  "ALTER MATERIALIZED VIEW mv_zone_stats SWAP WITH mv_zone_stats_green;"
```

Screenshot cần chụp:

- `03-cutover`: `Green readiness`, `Latest cutover duration`, `Query errors during cutover`, `Consumer lag during swap`, `RisingWave restarts`.
- `04-data-integrity`: `Blue/green/public row count`, `Checksum mismatch`.

Ghi chú quan trọng: sink Iceberg `sink_zone_stats` được tạo từ `mv_zone_stats`. Sau khi swap, cần verify lại object mới trong MinIO. Nếu sink không phản ánh logic mới như mong đợi, ghi rõ giới hạn trong báo cáo và tạo sink mới cho green ở lần cải tiến sau.

## 9. Checklist dashboard bắt buộc

Mỗi dashboard cần ít nhất một screenshot hoặc export JSON có thời gian đo rõ ràng.

| Nhóm trong `PROPOSE.md` | Dashboard | Bằng chứng tối thiểu |
|-------------------------|-----------|----------------------|
| Streaming performance | `01-streaming-perf` | Vector/Redpanda network bytes tăng, topic offsets tăng, consumer lag không tăng kéo dài, RisingWave rows/s có tín hiệu |
| Resource utilization | `02-resource-util` | CPU/RAM theo namespace, top pod CPU/RAM, restart trong range đo, PVC used/free |
| Cutover & GitOps deployment | `03-cutover` | Green ready, cutover duration, query errors `0`, RisingWave restart `0`, consumer lag hồi phục |
| Data integrity | `04-data-integrity` | Public MV rows, blue/green/public row count, checksum mismatch `0`, rejected records `0`, Iceberg freshness/MinIO object mới |

Tên file screenshot đề xuất:

```text
${EVIDENCE_DIR}/grafana-01-streaming-perf.png
${EVIDENCE_DIR}/grafana-02-resource-util.png
${EVIDENCE_DIR}/grafana-03-cutover.png
${EVIDENCE_DIR}/grafana-04-data-integrity.png
```

## 10. Cập nhật báo cáo

Sau khi có log và screenshot, cập nhật `docs/REPORT.md`:

- Thêm bảng thông số replay: thời điểm, dataset, Vector rate limit, tổng event xử lý, thời lượng replay.
- Thêm kết quả resource: CPU/RAM namespace chính, restart, PVC.
- Thêm kết quả streaming: throughput hoặc proxy throughput, lag, RisingWave rows/s.
- Thêm kết quả integrity: row count, checksum mismatch, rejected records, Iceberg object/freshness.
- Thêm kết quả cutover: green readiness, duration, query errors, restart, rollback nếu có.
- Ghi rõ giới hạn nếu metric nào còn dùng proxy thay vì exporter `continux_*`.

Cập nhật `docs/TIMELINE.md`:

- Tick các dòng còn thiếu trong mục `Trước khi chốt báo cáo`.
- Cập nhật trạng thái ngày `23/05` tới `30/05` theo thực tế.

Cập nhật `docs/DASHBOARDS.md` nếu có thêm exporter hoặc đổi tên metric.

Kiểm tra diff:

```bash
git status --short
git diff -- VERSION docs/REPORT.md docs/TIMELINE.md docs/DASHBOARDS.md docs/FINALIZE.md README.md \
  config/metrics-exporter/ gitops/apps/
```

Commit tài liệu và bằng chứng cần đưa vào repo. Không commit file lớn, secret hoặc screenshot nếu giảng viên chỉ yêu cầu nộp riêng:

```bash
git add VERSION docs/REPORT.md docs/TIMELINE.md docs/DASHBOARDS.md docs/FINALIZE.md README.md \
  config/metrics-exporter/ gitops/apps/metrics-exporter-app.yaml gitops/apps/kustomization.yaml
git commit -m "feat(finalize): add metrics exporter and bump v0.2.3"
git push
```

Nếu cần tag mốc nộp:

```bash
git tag -a v0.3.0 -m "Finalize experiment evidence"
git push origin v0.3.0
```

## 11. Definition of Done cuối cùng

- [ ] `bash scripts/k3s-check.sh` sau replay vẫn có `Nodes Ready 100%`, `PVC Bound 100%`, `Workloads Ready 100%`.
- [ ] `argocd app list --grpc-web` không còn `OutOfSync` không giải thích được.
- [ ] `Vector` đã được dừng lại sau replay.
- [ ] `mv_zone_stats` trả dữ liệu và tổng `trip_count` hợp lý với dataset đã ingest.
- [ ] MinIO có object Iceberg mới trong `iceberg-data/nyc/zone_stats/`.
- [ ] Dashboard `streaming-perf` có tín hiệu throughput/lag/offset/rows/s.
- [ ] Dashboard `resource-util` có tín hiệu CPU/RAM/PVC/restart trong khoảng replay.
- [ ] Dashboard `cutover` có duration, query error, restart và blue/green row count.
- [ ] Dashboard `data-integrity` có public rows, checksum/rejected/freshness hoặc log thay thế.
- [ ] `docs/REPORT.md` có số liệu thực nghiệm, nhận xét và giới hạn.
- [ ] `docs/TIMELINE.md` khớp trạng thái thực tế.
- [ ] Secret runtime vẫn không xuất hiện trong Git.

## 12. Troubleshooting nhanh

### Vector gây tải cao

```bash
kubectl --request-timeout=10s -n pipeline scale deploy/vector --replicas=0
kubectl -n pipeline logs deploy/vector --tail=200
```

Giảm `rate_limit_num` trong `config/vector/vector-config.yaml`, sync lại:

```bash
argocd app sync vector --grpc-web
argocd app wait vector --health --sync --grpc-web
```

### WSL `helios-pc` NotReady

Trên Windows giữ máy awake, vào WSL:

```bash
sudo systemctl status k3s --no-pager
sudo systemctl restart k3s
tailscale status
```

Trên `imac`:

```bash
kubectl get nodes -o wide
kubectl get --raw='/readyz?verbose' | grep -E 'readyz|etcd|ok'
```

### RisingWave query không có dữ liệu

```bash
kubectl -n risingwave get pods -o wide
kubectl -n risingwave logs statefulset/risingwave-compute --tail=100
kubectl -n redpanda exec redpanda-0 -c redpanda -- \
  rpk topic describe nyc-taxi-events \
  --brokers redpanda.redpanda.svc.cluster.local:9093
```

Nếu topic đã có event nhưng MV không tăng, kiểm tra SQL source và apply job:

```bash
argocd app sync pipeline --grpc-web
argocd app get pipeline --grpc-web
```

Vì `mv-apply-job` là hook bị xóa sau khi `Succeeded`, muốn xem log thì mở lệnh watch/log ngay trong lúc `argocd app sync pipeline --grpc-web` đang chạy, hoặc tạm bỏ `HookSucceeded` khỏi `hook-delete-policy` trong nhánh debug rồi sync lại.

### Grafana panel `continux_*` luôn bằng `0`

Kiểm tra exporter và scrape:

```bash
kubectl -n pipeline get pod,svc -l app=continux-metrics
kubectl -n observability get vmservicescrape

curl -G 'http://127.0.0.1:8428/api/v1/query' \
  --data-urlencode 'query=continux_mv_rows'
```

Nếu VictoriaMetrics không có series, kiểm tra label selector của `VMServiceScrape` và port name trên Service exporter.

### Cloudflared hoặc Vector `OutOfSync`

```bash
argocd app diff cloudflared --grpc-web || true
argocd app diff vector --grpc-web || true
```

- `cloudflared`: sync lại nếu drift từ manifest.
- `vector`: drift `replicas` trong lúc replay là bình thường, nhưng trước/sau đo nên đưa về `0`.

## 13. Tài liệu tham khảo vận hành

- `docs/SETUP.md`: bootstrap và clear demo §11.
- `docs/DASHBOARDS.md`: ý nghĩa từng panel Grafana.
- `docs/REPORT.md`: nơi ghi kết quả cuối.
- RisingWave `ALTER MATERIALIZED VIEW`: <https://docs.risingwave.com/sql/commands/sql-alter-materialized-view>
- RisingWave `ALTER ... SWAP`: <https://docs.risingwave.com/sql/commands/sql-alter-swap>
- RisingWave alter streaming job: <https://docs.risingwave.com/operate/alter-streaming>
