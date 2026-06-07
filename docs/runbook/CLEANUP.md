# CLEANUP

Dọn toàn bộ trạng thái sinh bởi một lượt thực nghiệm và đưa hệ thống về trạng thái sau [SETUP.md](./SETUP.md), trước [DEMO.md](./DEMO.md): chưa tải bộ dữ liệu cục bộ, chưa upload lookup CSV, không còn object SQL thực nghiệm, topic sạch, đầu ra Iceberg sạch và Vector ở profile an toàn.

Mục đích: dọn trạng thái của lượt vừa chạy mà không phá hạ tầng, để lượt tiếp theo
bắt đầu lại từ bước tải bộ dữ liệu trong [DEMO.md](./DEMO.md). Hành động dọn dẹp
nằm trong cluster (Redpanda topic, RisingWave object SQL, Iceberg prefix,
metric cutover, lookup CSV) và trên máy cục bộ (`data/raw/`, `.venv/`, file
tạm).

> Cảnh báo: phần này xóa kết quả replay và cutover của lượt vừa chạy. Hãy chắc chắn bằng chứng đã đủ trước khi dọn. Tài liệu này **không** xóa K3s cluster, Helm release, PVC, bucket MinIO, hoặc secret.

Luồng chuẩn dùng runner:

```bash
cd ~/continux

bash experiments/runners/demo.sh cleanup-runtime
bash experiments/runners/demo.sh cleanup-local
```

Bằng chứng vẫn được giữ ngoài repo cho tới khi chạy rõ ràng
`bash experiments/runners/demo.sh purge-evidence <RUN_ID>`. Các mục phía dưới
giữ lệnh thủ công tương ứng để debug.

## 1. Thu Bằng Chứng Cuối Trước Khi Dọn Dẹp

```bash
cd ~/continux

{
  date -Is
  kubectl get nodes -o wide
  argocd app list --grpc-web
  kubectl -n pipeline get deploy/vector -o wide
} | tee "${EVIDENCE_DIR}/06-before-cleanup-health.txt"

psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT name FROM rw_catalog.rw_materialized_views
   WHERE name IN ('mv_zone_stats_blue', 'mv_zone_stats', 'mv_zone_stats_green')
   ORDER BY name;
   SELECT 'public' AS view_name, COUNT(*) AS zones, COALESCE(SUM(trip_count),0) AS trips FROM mv_zone_stats
   UNION ALL
   SELECT 'blue', COUNT(*), COALESCE(SUM(trip_count),0) FROM mv_zone_stats_blue;" \
  | tee "${EVIDENCE_DIR}/06-before-cleanup-counts.txt"

curl -fsS http://127.0.0.1:9108/metrics \
  | grep -E '^continux_(mv_rows|mv_trips|green_ready|cutover|last_swap|query_errors)' \
  | tee "${EVIDENCE_DIR}/06-before-cleanup-metrics.txt"

mc ls --recursive local/iceberg-data/nyc/zone_stats/ | sed -n '1,50p' \
  | tee "${EVIDENCE_DIR}/06-before-cleanup-iceberg.txt"
```

## 2. Dừng Vector Và Xác Nhận

```bash
cd ~/continux

read -r -p "Nhập CLEAN-DEMO để xóa kết quả lượt này và sẵn sàng chạy lại: " CONFIRM
test "${CONFIRM}" = "CLEAN-DEMO"

kubectl --request-timeout=10s -n pipeline scale deploy/vector --replicas=0
kubectl -n pipeline wait --for=delete pod -l app=vector --timeout=120s || true

argocd app sync vector --grpc-web
argocd app wait vector --health --sync --grpc-web

kubectl -n pipeline get deploy/vector \
  -o jsonpath='{.spec.replicas}{" desired\n"}' \
  | tee "${EVIDENCE_DIR}/06-vector-stopped.txt"
```

## 3. Xóa Trạng Thái Của Lượt Thực Nghiệm

```bash
cd ~/continux

psql -h localhost -p 4567 -d dev -U root <<'SQL' \
  | tee "${EVIDENCE_DIR}/06-drop-sql-state.txt"
DROP SINK IF EXISTS sink_zone_stats;
DROP MATERIALIZED VIEW IF EXISTS mv_zone_stats_green;
DROP MATERIALIZED VIEW IF EXISTS mv_zone_stats;
DROP MATERIALIZED VIEW IF EXISTS mv_zone_stats_blue;
DROP SOURCE IF EXISTS nyc_taxi_src;
DROP TABLE IF EXISTS tlc_zone;
SQL

{
  if kubectl -n redpanda exec redpanda-0 -c redpanda -- \
    rpk topic list --brokers "${BROKERS}" | grep -q 'nyc-taxi-events'; then
    kubectl -n redpanda exec redpanda-0 -c redpanda -- \
      rpk topic delete nyc-taxi-events --brokers "${BROKERS}"
  else
    echo "Topic nyc-taxi-events đã không tồn tại; tiếp tục tạo lại."
  fi
} | tee "${EVIDENCE_DIR}/06-topic-delete.txt"

argocd app sync redpanda-topics --grpc-web
argocd app wait redpanda-topics --health --sync --grpc-web

mc rm --recursive --force local/iceberg-data/nyc/zone_stats/ \
  | tee "${EVIDENCE_DIR}/06-clear-iceberg.txt"

kubectl -n pipeline exec deploy/continux-metrics -- \
  rm -f /state/cutover.prom

{
  if mc stat local/tlc-zone/taxi_zone_lookup.csv >/dev/null 2>&1; then
    mc rm --force local/tlc-zone/taxi_zone_lookup.csv
  else
    echo "Taxi Zone lookup đã không tồn tại."
  fi
} | tee "${EVIDENCE_DIR}/06-clear-taxi-zone.txt"
```

## 4. Xác Nhận Trạng Thái Sau Khi Thiết Lập

```bash
cd ~/continux

sleep 20

bash scripts/k3s-check.sh overview \
  | tee "${EVIDENCE_DIR}/06-post-setup-health.txt"

argocd app list --grpc-web \
  | tee "${EVIDENCE_DIR}/06-post-setup-apps.txt"

kubectl -n pipeline get deploy/vector \
  -o jsonpath='{.spec.replicas}{" desired\n"}' \
  | tee "${EVIDENCE_DIR}/06-post-setup-vector.txt"

kubectl -n redpanda exec redpanda-0 -c redpanda -- \
  rpk topic describe nyc-taxi-events --brokers "${BROKERS}" \
  | tee "${EVIDENCE_DIR}/06-post-setup-topic.txt"

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
   ) AS demo_objects;" \
  | tee "${EVIDENCE_DIR}/06-post-setup-sql-count.txt"

curl -fsS http://127.0.0.1:9108/metrics \
  | grep -E '^continux_(cutover_duration_seconds|last_swap_timestamp_seconds|query_errors_total|green_ready)' \
  | tee "${EVIDENCE_DIR}/06-post-setup-metrics.txt"

if mc ls --recursive local/iceberg-data/nyc/zone_stats/ | grep -q '\.parquet$'; then
  echo "FAIL: bước dọn dẹp vẫn còn file Parquet Iceberg." | tee "${EVIDENCE_DIR}/06-post-setup-iceberg.txt"
  exit 1
else
  echo "OK: bước dọn dẹp đã loại bỏ tệp Parquet của lượt thực nghiệm." | tee "${EVIDENCE_DIR}/06-post-setup-iceberg.txt"
fi

if mc stat local/tlc-zone/taxi_zone_lookup.csv >/dev/null 2>&1; then
  echo "FAIL: bước dọn dẹp vẫn còn Taxi Zone lookup." | tee "${EVIDENCE_DIR}/06-post-setup-taxi-zone.txt"
  exit 1
else
  echo "OK: Taxi Zone lookup đã được dọn." | tee "${EVIDENCE_DIR}/06-post-setup-taxi-zone.txt"
fi
```

## 5. Xóa File Cục Bộ Sinh Trong Lượt Chạy

Đưa checkout `~/continux` về hình dạng ban đầu của một repo vừa clone: không có bộ dữ liệu tải về và không có `.venv`. Bằng chứng không mất vì đã được lưu ở `~/continux-demo-evidence/<RUN_ID>` ngoài repo.

Runner dọn dẹp chuẩn xóa `data/raw/`, hai CSV staging trong `data/zone/`,
`.venv/`, trạng thái trong `experiments/results/`, `/tmp/continux-demo-env.sh`,
log export `scripts/k3s-check/`, `scripts/__pycache__/` và screenshot export:

```bash
cd ~/continux
bash experiments/runners/demo.sh cleanup-local
```

Bằng chứng chỉ bị xóa bằng lệnh riêng có xác nhận:

```bash
bash experiments/runners/demo.sh purge-evidence <RUN_ID>
```

> Cảnh báo: lệnh dưới đây xóa bộ dữ liệu cục bộ và môi trường ảo tạo bởi pha `prepare-data` trong [DEMO.md](./DEMO.md) §2. Chỉ chạy sau khi Vector đã dừng và bằng chứng cần giữ đã nằm ngoài repo.

```bash
cd ~/continux

test "$PWD" = "$HOME/continux"
test "${EVIDENCE_DIR#"$PWD"/}" = "${EVIDENCE_DIR}"
test "${DATA_DIR}" = "$PWD/data/raw"

VECTOR_REPLICAS="$(
  kubectl -n pipeline get deploy/vector -o jsonpath='{.spec.replicas}'
)"
test "${VECTOR_REPLICAS}" = "0"

test -z "$(git ls-files -- data/raw .venv)"

read -r -p "Nhập CLEAN-LOCAL để xóa data/raw và .venv do lượt thực nghiệm tạo: " CONFIRM
test "${CONFIRM}" = "CLEAN-LOCAL"

deactivate 2>/dev/null || true
rm -rf -- \
  "${DATA_DIR}" \
  "$PWD/.venv" \
  "$PWD/experiments/results/${RUN_ID}" \
  "$PWD/scripts/k3s-check" \
  "$PWD/scripts/__pycache__" \
  "$PWD/dashboards/exports"
rm -f -- \
  /tmp/continux-demo-env.sh \
  "$PWD/experiments/results/current.env"

test ! -e "${DATA_DIR}"
test ! -e "$PWD/.venv"

GIT_STATUS="$(git status --porcelain --untracked-files=all)"
printf '%s' "${GIT_STATUS}" | tee "${EVIDENCE_DIR}/06-git-after-local-cleanup.txt"
test -z "${GIT_STATUS}"
```

Các CSV taxi zone tải về ở `data/zone/` cũng được xóa nếu là file chưa theo dõi:

```bash
cd ~/continux

for generated_csv in \
  data/zone/taxi_zone_lookup.csv \
  data/zone/taxi_zone_lookup_risingwave.csv
do
  if [ -e "${generated_csv}" ] && ! git ls-files --error-unmatch -- "${generated_csv}" >/dev/null 2>&1; then
    rm -f -- "${generated_csv}"
  fi
done

GIT_STATUS="$(git status --porcelain --untracked-files=all)"
test -z "${GIT_STATUS}"
```

## 6. Checklist Runtime Đã Sạch

| Thứ tự | Điều kiện | Kết quả yêu cầu |
|--------|-----------|-----------------|
| 1 | Nodes và Argo CD apps | `Ready`, `Synced/Healthy` |
| 2 | Vector | `0 desired` |
| 3 | Redpanda topic | `nyc-taxi-events` tồn tại với `3` partition, `1` replica |
| 4 | Lookup CSV trên MinIO | Không còn `tlc-zone/taxi_zone_lookup.csv` |
| 5 | SQL thực nghiệm | Không còn `tlc_zone`, source, public/blue/green MV hoặc sink |
| 6 | Metric cutover hiện thời | Duration, timestamp, query errors và green readiness bằng `0` hoặc không tồn tại |
| 7 | Đầu ra Iceberg | Không có tệp dữ liệu Parquet của lượt thực nghiệm vừa dọn |
| 8 | Checkout cục bộ | Không có `data/raw/`, `.venv/`, hai CSV taxi zone tạm, trạng thái/log/ảnh chụp màn hình xuất ra tạm; `git status` rỗng |

Khi toàn bộ checklist đạt, trạng thái đã trở lại sau thiết lập, trước thực nghiệm.
Lịch sử metric cũ vẫn có thể xuất hiện trong Grafana do VictoriaMetrics lưu lịch
sử bảy ngày; chọn khoảng thời gian của lượt mới để tránh nhầm lẫn.

Nếu cần dashboard chỉ chứa sample của loạt thực nghiệm mới, xóa riêng lịch sử
metric `continux_*`. Lệnh này không thể hoàn tác, nhưng không xóa metric hạ tầng:

```bash
curl -fsS -X POST 'http://127.0.0.1:8428/api/v1/admin/tsdb/delete_series' \
  --data-urlencode 'match[]={__name__=~"continux_.*"}'
```

Exporter vẫn chạy nên VictoriaMetrics sẽ scrape lại sample nền sạch sau đó.

Từ trạng thái này, lượt thực nghiệm tiếp theo bắt đầu lại từ
[DEMO.md](./DEMO.md) §1 để bố trí terminal, rồi chạy lại luồng runner tại §2
từ `init`. Không cần lặp lại [SETUP.md](./SETUP.md) vì hạ tầng chưa thay đổi.

## 7. Xử Lý Sự Cố

### 7.1. Vector Làm Máy Nóng Hoặc Replay Quá Nặng

Luôn dừng phát sự kiện trước:

```bash
kubectl --request-timeout=10s -n pipeline scale deploy/vector --replicas=0
kubectl -n pipeline logs -l app=vector --tail=200 2>/dev/null || true
kubectl -n pipeline wait --for=delete pod -l app=vector --timeout=120s || true
```

Sau đó dùng profile `smoke`, hoặc giảm `rate_limit_num` / `max_events` trong `pipelines/vector/vector.toml`, commit, push và sync lại app `vector`. Không tiếp tục replay cho tới khi cluster khỏe lại.

### 7.2. Pod `redpanda-configuration-*` Có Một Bản `Failed`

Nếu Redpanda StatefulSet Ready, console Ready và có một pod configuration mới `Succeeded`, pod configuration cũ `Failed` chỉ là dấu vết lịch sử của hook/configuration. Không dùng nó làm dấu hiệu lỗi chính của trạng thái nền.

```bash
kubectl -n redpanda get sts/redpanda deploy/redpanda-console
kubectl -n redpanda get pods | grep redpanda-configuration
```

### 7.3. Không Thấy Job Apply SQL Của Argo CD

`mv-apply-job` là hook, tức job chạy tại thời điểm sync rồi có thể được Argo CD xóa sau khi thành công. Xác nhận bằng catalog RisingWave thay vì yêu cầu Job vẫn còn:

```bash
psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT name FROM rw_catalog.rw_materialized_views
   WHERE name IN ('mv_zone_stats_blue', 'mv_zone_stats', 'mv_zone_stats_green')
   ORDER BY name;"
```

### 7.4. Thiếu Object SQL Pipeline

```bash
cd ~/continux

argocd app sync pipeline --grpc-web
argocd app wait pipeline --health --sync --grpc-web
argocd app get pipeline --grpc-web
```

Sau đó query lại `rw_catalog`.

### 7.5. Metrics Exporter Không Healthy

```bash
kubectl -n pipeline get pod,svc -l app=continux-metrics
kubectl -n pipeline logs deploy/continux-metrics --tail=100
kubectl -n observability describe vmservicescrape continux-metrics
```

Exporter serve `/metrics` bằng BusyBox `nc`.

### 7.6. VictoriaMetrics Chưa Thấy Metric Mới

Exporter render theo chu kỳ và VictoriaMetrics scrape định kỳ. Chờ ít nhất `20` giây rồi query lại:

```bash
sleep 20
curl -fsSG 'http://127.0.0.1:8428/api/v1/query' \
  --data-urlencode 'query=continux_exporter_up'
```

Kiểm tra selector:

```bash
kubectl -n pipeline get svc continux-metrics --show-labels
kubectl -n observability get vmservicescrape continux-metrics -o yaml
```

### 7.7. Không Reset Được Topic Hoặc Iceberg

Dừng thực nghiệm ở trạng thái an toàn:

```bash
kubectl --request-timeout=10s -n pipeline scale deploy/vector --replicas=0
kubectl -n pipeline wait --for=delete pod -l app=vector --timeout=120s || true
```

Không bắt đầu replay nếu topic cũ hoặc đầu ra Iceberg cũ chưa được xử lý theo mục tiêu của lượt thực nghiệm sạch.

### 7.8. Cần Phá Môi Trường

Không đặt lệnh reset hoặc nuke trong luồng vận hành chính. Nếu chỉ cần chạy lại
thực nghiệm, dùng `cleanup-runtime` và `cleanup-local` ở đầu tài liệu này.

Nếu cần đưa cluster về trạng thái vừa cài K3s nhưng vẫn giữ node, đọc cảnh báo
trong [SCRIPTS.md](../SCRIPTS.md) trước khi dùng `scripts/k3s-purge.sh`. Chế độ
reset này cần Kubernetes API còn phản hồi; có thể xem trước bằng:

```bash
cd ~/continux
bash scripts/k3s-purge.sh --dry-run
```

Nếu API không còn giao tiếp được và mục tiêu là gỡ K3s khỏi host hiện tại, dùng
local uninstall. Chế độ này chạy script uninstall K3s chính thức nếu còn tồn tại
và không cần Kubernetes API:

```bash
cd ~/continux
sudo bash scripts/k3s-purge.sh --nuke --dry-run
sudo bash scripts/k3s-purge.sh --nuke
```

Nếu cần xóa toàn bộ Continux khỏi host hiện tại, giữ Tailscale nhưng xóa K3s,
CLI dự án, cấu hình cục bộ, bằng chứng demo và checkout repo, dùng `nuke.sh`.
Lệnh mặc định chỉ dry-run:

```bash
cd ~/continux
bash scripts/nuke.sh
```

Chạy thật trên từng host cần `sudo`, `--execute` và xác nhận
`NUKE-CONTINUX`:

```bash
cd ~/continux
sudo bash scripts/nuke.sh --execute
```

Script không SSH sang máy khác. Nếu phá toàn bộ bố trí ba node, chạy riêng trên
`imac`, `continux-vps` và WSL `helios-pc`.
