# BÁO CÁO ĐỒ ÁN

## 1. Trang Thông Tin Đề Tài

| Mục | Nội dung |
|-----|----------|
| Trường | Trường Đại học Công nghệ Thông tin, Đại học Quốc gia TP.HCM |
| Môn học | Cơ sở dữ liệu phân tán và Dữ liệu lớn |
| Mã lớp | IS211.Q22 và IS405.Q23 |
| Tên đề tài tiếng Việt | Xây dựng kiến trúc Data Lakehouse thời gian thực cho hệ thống giao thông thông minh trên cụm Kubernetes |
| Tên đề tài tiếng Anh | Building a Real-Time Data Lakehouse Architecture for Intelligent Transportation Systems on a Kubernetes Cluster |
| Giảng viên hướng dẫn | ThS. Nguyễn Hồ Duy Trí |

| MSSV | Họ và tên | Vai trò chính |
|------|-----------|---------------|
| 23521367 | Ngô Tiến Sỹ | Hạ tầng K3s, GitOps, Data Lakehouse, thực nghiệm |
| 23520982 | Nguyễn Văn Nam | Dataset, SQL pipeline, dashboard, báo cáo |

## 2. Tóm Tắt

Đồ án xây dựng và kiểm chứng một kiến trúc Data Lakehouse thời gian thực trên cụm Kubernetes nhẹ K3s. Hệ thống dùng dữ liệu NYC TLC Yellow Taxi, chuyển đổi Parquet sang JSONL, phát luồng sự kiện bằng Vector, truyền qua Redpanda, xử lý streaming SQL bằng RisingWave, ghi kết quả xuống Apache Iceberg trên MinIO và quan sát bằng VictoriaMetrics/Grafana.

Hệ thống chứng minh được cụm K3s 3 server hoạt động ổn định, pipeline end-to-end sinh được materialized view và Iceberg object, và kịch bản Blue/Green cutover bằng `ALTER MATERIALIZED VIEW ... SWAP WITH ...` hoàn tất mà không gây lỗi truy vấn ở lớp SQL. Số đo cụ thể của từng lượt thực nghiệm được lưu trong `evidence/` ngoài repo.

## 3. Mở Đầu

### 3.1. Bối Cảnh

Các hệ thống giao thông thông minh cần xử lý dữ liệu phát sinh liên tục: chuyến xe, vị trí, thời gian, chi phí, khu vực đón/trả khách và các tín hiệu vận hành khác. Kiến trúc batch truyền thống có thể phục vụ phân tích sau sự kiện, nhưng không đủ linh hoạt khi cần quan sát và cập nhật logic phân tích gần thời gian thực.

Data Lakehouse là hướng tiếp cận phù hợp vì kết hợp chi phí lưu trữ thấp của Data Lake với khả năng truy vấn có cấu trúc của Data Warehouse. Khi kết hợp với streaming SQL, hệ thống có thể vừa lưu trữ lịch sử vừa duy trì các chỉ số phân tích cập nhật liên tục.

### 3.2. Vấn Đề

Vấn đề chính của đề tài là: làm thế nào để triển khai một pipeline streaming lakehouse trên cụm Kubernetes tài nguyên giới hạn, có khả năng quan sát đầy đủ và có thể cập nhật logic phân tích mà không gây lỗi truy vấn trong lúc chuyển giao?

### 3.3. Mục Tiêu

Đề tài đặt ra các mục tiêu:

- Dựng cụm K3s HA 3 server qua Tailscale.
- Triển khai pipeline `Vector -> Redpanda -> RisingWave -> Iceberg/MinIO`.
- Quản lý manifest bằng GitOps qua Argo CD.
- Quan sát hệ thống bằng VictoriaMetrics và Grafana.
- Chạy replay ingest có kiểm soát trên dataset NYC TLC.
- Thực nghiệm Blue/Green cutover ở lớp RisingWave materialized view.
- Ghi lại evidence có thể kiểm chứng bằng lệnh, output và dashboard.

## 4. Cơ Sở Lý Thuyết Và Bài Báo Nền Tảng Ursa

### 4.1. Data Lakehouse

Data Lakehouse là mô hình kết hợp Data Lake và Data Warehouse. Dữ liệu được lưu trên object storage, nhưng được tổ chức bằng table format như Apache Iceberg để hỗ trợ metadata, snapshot, schema evolution và truy vấn phân tích có cấu trúc.

Trong đề tài này, MinIO đóng vai trò S3-compatible object storage, còn Iceberg là lớp table format lưu kết quả sink của RisingWave.

### 4.2. Streaming SQL Và Materialized View

Streaming SQL cho phép xử lý dữ liệu đến liên tục bằng cú pháp SQL. Materialized view trong RisingWave duy trì kết quả truy vấn cập nhật liên tục khi source thay đổi. Điều này phù hợp với bài toán thống kê theo khu vực taxi vì kết quả `trip_count`, `total_fare`, `avg_distance` luôn cần được cập nhật khi có event mới.

### 4.3. GitOps

GitOps dùng Git làm nguồn chân lý cho trạng thái hệ thống. Argo CD so sánh trạng thái mong muốn trong repo với trạng thái thật trên Kubernetes, sau đó sync manifest khi cần. Mô hình này giúp triển khai có kiểm soát, dễ audit và tái lập.

### 4.4. Bài Báo Ursa

Bài báo *Ursa: A Lakehouse-Native Data Streaming Engine for Kafka* đề xuất hướng streaming engine gắn trực tiếp với lakehouse, giúp giảm chi phí vận hành khi đưa dữ liệu từ Kafka-compatible log vào lakehouse. Ursa nhấn mạnh sự hội tụ giữa streaming log và table format, đặc biệt ở khía cạnh ingestion hiệu quả, giảm độ trễ và tận dụng lưu trữ lakehouse.

Continux kế thừa tinh thần lakehouse-native streaming của Ursa nhưng tập trung vào lớp vận hành phía trên: triển khai trên Kubernetes nhỏ, dùng GitOps, quan sát bằng dashboard và cập nhật logic phân tích bằng Blue/Green materialized view.

## 5. Phương Pháp Và Kiến Trúc Đề Xuất

### 5.1. Kiến Trúc Tổng Thể

```text
NYC TLC Parquet
  -> scripts/partojsonl.py
  -> Vector
  -> Redpanda topic nyc-taxi-events
  -> RisingWave source/table/materialized views
  -> Iceberg sink on MinIO
  -> VictoriaMetrics/Grafana
```

### 5.2. Các Thành Phần Chính

| Thành phần | Vai trò |
|------------|---------|
| K3s | Kubernetes nhẹ, chạy HA 3 server |
| Tailscale | Mạng riêng giữa các node |
| Argo CD | GitOps App-of-Apps |
| Helm | Cài chart hạ tầng |
| MinIO | Object storage cho checkpoint, lookup CSV và Iceberg |
| Redpanda | Broker Kafka-compatible |
| Vector | Đọc JSONL và phát event |
| RisingWave | Streaming SQL, materialized views, Iceberg sink |
| VictoriaMetrics | Time-series database cho metrics |
| Grafana | Dashboard quan sát |
| metrics-exporter | Export metric thực nghiệm `continux_*` |

### 5.3. Thiết Kế Blue/Green

Phiên bản public ban đầu là `mv_zone_stats`. Logic mới được tạo ở `mv_zone_stats_green` với cùng schema nhưng thêm điều kiện lọc chất lượng dữ liệu:

```sql
WHERE t.fare_amount >= 0
  AND t.trip_distance >= 0
```

Khi green view đã ổn định, hệ thống chạy:

```sql
ALTER MATERIALIZED VIEW mv_zone_stats SWAP WITH mv_zone_stats_green;
```

Thao tác swap đổi tên hai materialized view, giúp public name `mv_zone_stats` phục vụ logic mới mà không cần đổi query phía người dùng.

## 6. Môi Trường Triển Khai

### 6.1. Topology Cụm

| Node | Cấu hình | Vai trò |
|------|----------|---------|
| `imac` | Ubuntu 26.04, iMac19,2, Intel i5-8500, 6 cores, 8 GB RAM, 200 GB SSD | K3s server #1, data plane |
| `continux-vps` | Ubuntu 24.04, 2 vCPU, 4 GB RAM, 80 GB SSD | K3s server #2, control/observability |
| `helios-pc` | WSL Ubuntu 26.04 trên Windows host `Helios-PC`, 16 GB RAM | K3s server #3, quorum-only |

Tailscale IP:

| Node/device | IP |
|-------------|----|
| `imac` | `100.120.64.5` |
| `continux-vps` | `100.113.151.56` |
| `helios-pc-wsl` | `100.78.46.87` |
| Windows host `helios-pc` | `100.125.106.89` |

### 6.2. Phiên Bản Phần Mềm

| Thành phần | Phiên bản |
|------------|-----------|
| K3s | `v1.35.5+k3s1` |
| Helm | `v4.1.4` |
| Argo CD | `v3.4.2` |
| Tailscale | `v1.98.2` |
| Redpanda | `v26.1.8` |
| RisingWave | `v2.8.3` |
| Vector | `0.55.0-alpine` |
| VictoriaMetrics | `v1.143.0` |
| Grafana | `v13.0.1+security-01` |
| cloudflared | `2026.5.0` |

## 7. Quy Trình Triển Khai

Quy trình triển khai chi tiết nằm trong [RUNBOOK.md](./RUNBOOK.md). Tóm tắt các bước chính:

1. Chuẩn bị OS, hostname, user, SSH, swap, IP forwarding và UFW.
2. Cài Tailscale trên 3 máy, kiểm tra kết nối mesh.
3. Init K3s server #1 trên `imac`, join `continux-vps` và `helios-pc`.
4. Gán label/taint để phân tách data plane, control plane và quorum node.
5. Cài CLI quản trị: Helm, Argo CD CLI, rpk, mc, psql.
6. Cài Argo CD, Cloudflare Tunnel, đăng ký repo và sync root app.
7. Deploy MinIO, Redpanda, RisingWave.
8. Deploy VictoriaMetrics, Grafana và dashboard.
9. Tải dataset, convert JSONL, upload Taxi Zone lookup.
10. Sync Vector ở `replicas=0`, apply SQL, bật ingest thủ công và verify end-to-end.

### 7.1. Đóng Gói Paper

Từ release `1.2.0`, bản paper nộp kèm được quản lý trong `paper/` thay vì nhồi toàn bộ nội dung vào một file TeX dài. Hai wrapper `paper/main_vi.tex` và `paper/main_en.tex` dùng layout `article` hai cột, còn nội dung từng phần nằm trong `paper/src/vi/` và `paper/src/en/`.

PDF cuối được commit là `paper/main_vi.pdf` và `paper/main_en.pdf`. `docs/REPORT.md` tiếp tục đóng vai trò báo cáo/evidence companion, dùng để tra cứu nhanh quy trình, kết quả và lệnh kiểm chứng.

## 8. Thiết Kế Pipeline Dữ Liệu

### 8.1. Dataset

| Hạng mục | Giá trị |
|----------|---------|
| Dataset | NYC TLC Yellow Taxi |
| Tháng thực nghiệm | Cấu hình trong runbook tại biến `DATA_MONTH` |
| File nguồn | `yellow_tripdata_<yyyy-mm>.parquet` |
| Output convert | JSONL có các field pipeline cần |
| Lookup table | `taxi_zone_lookup.csv` |

### 8.2. Vector

Vector đọc file JSONL từ `/data/*.jsonl` và publish vào Redpanda. Deployment mặc định `replicas=0` để tránh phát event khi cluster chưa sẵn sàng. Khi replay, runbook scale thủ công lên `1`, theo dõi log, rồi scale về `0`.

### 8.3. Redpanda

Redpanda topic:

```text
nyc-taxi-events
partitions: 3
replicas: 1
retention.ms: 86400000
```

### 8.4. RisingWave

RisingWave tạo:

- table `tlc_zone` đọc lookup CSV từ MinIO;
- source `nyc_taxi_src` đọc Redpanda topic;
- materialized view `mv_zone_stats_blue`;
- materialized view public `mv_zone_stats`;
- sink `sink_zone_stats` ghi Iceberg.

Verify object bằng `rw_catalog` thay vì meta-command có pattern của `psql`.

### 8.5. Iceberg Trên MinIO

RisingWave ghi Iceberg vào prefix:

```text
iceberg-data/nyc/zone_stats/
```

Sau replay, MinIO có data Parquet, equality-delete Parquet và position-delete Parquet, chứng minh sink đã ghi output lakehouse.

## 9. Thiết Kế Quan Sát Và Thực Nghiệm

### 9.1. Dashboard

Hệ thống có 4 nhóm dashboard:

| Dashboard | Nhóm chỉ số |
|-----------|-------------|
| `streaming-perf` | Streaming performance |
| `resource-util` | Resource utilization |
| `cutover` | Cutover and GitOps deployment |
| `data-integrity` | Data integrity |

### 9.2. Metrics Exporter

`metrics-exporter` expose các metric chính:

| Metric | Ý nghĩa |
|--------|---------|
| `continux_exporter_up` | Exporter healthy |
| `continux_mv_rows{view="..."}` | Số dòng theo MV |
| `continux_mv_trips{view="..."}` | Tổng trip count theo MV |
| `continux_events_processed_total` | Proxy event đã xử lý |
| `continux_green_ready` | Green MV sẵn sàng |
| `continux_cutover_duration_seconds` | Thời gian swap |
| `continux_last_swap_timestamp_seconds` | Timestamp swap |
| `continux_query_errors_total` | Lỗi query trong cutover |
| `continux_checksum_mismatch_total` | Cờ mismatch khi so cùng logic |
| `continux_records_rejected_total` | Bản ghi bị loại |

### 9.3. Evidence

Evidence của mỗi lượt thực nghiệm được lưu tại:

```text
evidence/finalize/<RUN_ID>/
```

Trong đó `<RUN_ID>` được tạo bằng `date +%Y%m%d-%H%M%S` ở đầu lượt chạy theo runbook. Các file tiêu biểu được runbook ghi ra:

| File | Nội dung |
|------|----------|
| `00-k3s-check.txt` | Baseline cluster |
| `01-argocd-after-sync.txt` | Argo CD app sau sync |
| `02-risingwave-show-cluster.txt` | RisingWave workers |
| `02-tlc-zone-count.txt` | Lookup table count |
| `03-vm-query-exporter-up.json` | Exporter scrape |
| `05-replay-start-epoch.txt` | Epoch bắt đầu replay |
| `05-mv-final-count.txt` | MV count cuối replay |
| `05-minio-iceberg-after-replay.txt` | Iceberg objects |
| `06-green-catchup-samples.txt` | Green MV catch-up |
| `06-query-loop-during-cutover.txt` | Query loop khi swap |
| `06-public-after-swap.txt` | Public MV sau swap |
| `06-green-name-after-swap.txt` | View giữ tên green sau swap |
| `06-exporter-cutover-metrics.txt` | Cutover metrics trực tiếp |
| `06-vm-query-cutover-duration.json` | VictoriaMetrics duration |
| `06-vm-query-query-errors.json` | VictoriaMetrics query errors |

Screenshot dashboard được nộp riêng, tham chiếu bằng tên file:

```text
grafana-01-streaming-perf.png
grafana-02-resource-util.png
grafana-03-cutover.png
grafana-04-data-integrity.png
```

## 10. Kết Quả Thực Nghiệm

### 10.1. Cluster Và GitOps

Hệ thống đáp ứng các tiêu chí sau khi triển khai và chạy replay:

- 3/3 nodes `Ready`, PVC `Bound`, workloads `Available`.
- Argo CD quản lý các app chính (`cloudflared`, `redpanda-topics`, `pipeline`, `vector`, `victoria-scrapes`, `metrics-exporter`) ở trạng thái `Synced/Healthy`.
- Vector dừng ở `replicas=0` sau replay theo chủ đích.

Một pod `redpanda-configuration-*` cũ ở trạng thái `Failed` được ghi nhận là dấu vết lịch sử, không chặn workload vì Redpanda StatefulSet và console đều `Ready`.

### 10.2. RisingWave Và Lookup

- `SHOW CLUSTER` trả về meta, compute, compactor, frontend đều `RUNNING`.
- Catalog SQL chứa đủ table, source, materialized views và sink.
- `tlc_zone` được nạp từ Taxi Zone CSV; số dòng khớp với số dòng CSV vừa upload.

### 10.3. Replay Ingest

- Vector replay JSONL vào Redpanda topic `nyc-taxi-events`.
- RisingWave cập nhật `mv_zone_stats` liên tục trong khi replay.
- Sink `sink_zone_stats` sinh ra data Parquet, equality-delete Parquet và position-delete Parquet trong `iceberg-data/nyc/zone_stats/`.

Số liệu chi tiết của mỗi lượt nằm trong `evidence/finalize/<RUN_ID>/`.

### 10.4. Blue/Green Cutover

- Green MV được tạo song song với cùng schema, thêm điều kiện lọc `fare_amount >= 0 AND trip_distance >= 0`.
- Query loop liên tục chạy `SELECT COUNT(*), SUM(trip_count) FROM mv_zone_stats` mỗi `0.5s` trong lúc swap.
- `ALTER MATERIALIZED VIEW mv_zone_stats SWAP WITH mv_zone_stats_green` hoàn tất, sau đó public MV mang logic green.
- Query loop ghi nhận `0` lỗi và RisingWave không restart trong cửa sổ swap.
- Exporter và VictoriaMetrics ghi nhận `continux_cutover_duration_seconds`, `continux_last_swap_timestamp_seconds` và `continux_query_errors_total`.

Đây là bằng chứng chính cho mục tiêu không gián đoạn truy vấn ở lớp SQL.

### 10.5. Dashboard

Dashboard `resource-util` cho thấy workload vẫn sẵn sàng và PVC còn dư địa. Dashboard `cutover` hiển thị green readiness, duration, query errors và restart. Dashboard `data-integrity` sau cutover có thể hiển thị `Checksum mismatch = 1` vì public view đã chuyển sang logic green, còn view giữ tên `mv_zone_stats_green` đang chứa logic cũ. Đây là lệch có chủ đích do thay đổi logic, không phải mất dữ liệu.

## 11. Đánh Giá Theo 4 Nhóm Chỉ Số

### 11.1. Cutover & GitOps Deployment

Mục tiêu cutover đạt. Green MV được tạo song song, query loop không lỗi, swap hoàn tất nhanh và RisingWave không restart; metric được VictoriaMetrics scrape. GitOps đảm bảo manifest triển khai app chính thống nhất với repo.

### 11.2. Data Quality & Lakehouse Output

Replay sinh kết quả trong `mv_zone_stats` và Iceberg có object mới. Sau cutover, public MV đổi sang logic lọc dữ liệu âm; sự chênh lệch số trips giữa trước/sau swap là kết quả logic mới. `continux_query_errors_total` đạt `0` và `continux_records_rejected_total{reason="parse"}` đạt `0`.

### 11.3. Streaming Performance

Vector replay từ file JSONL thật, Redpanda topic tồn tại, RisingWave MV tăng trong lúc replay và MinIO có object Iceberg mới. Do giới hạn catalog Kafka metrics của RisingWave trong cấu hình này, một số metric Kafka như `continux_events_ingested_total` và `continux_kafka_lag` không phản ánh đầy đủ; báo cáo dùng thêm `continux_events_processed_total`, MV count, Redpanda topic output và dashboard proxy.

### 11.4. Resource Utilization & Stability

Cụm chạy trên phần cứng nhỏ nhưng ổn định: tất cả nodes `Ready`, PVC `Bound`, workloads `Available` sau replay. Vector được giữ `replicas=0` sau khi đo để bảo toàn tài nguyên.

## 12. Hạn Chế Và Hướng Phát Triển

### 12.1. Hạn Chế

- Data plane chính chỉ có 8 GB RAM, nên throughput được kiểm soát bằng rate limit thay vì đẩy tải tối đa.
- `helios-pc` là WSL, phù hợp quorum demo nhưng không lý tưởng cho production.
- Một số metric Kafka catalog trong RisingWave chưa cung cấp số liệu đủ dùng ở cấu hình này.
- Iceberg freshness từ exporter còn cần hoàn thiện nếu muốn đọc sâu metadata snapshot.
- Cutover mới chứng minh ở lớp materialized view, chưa mở rộng sang nhiều sink phụ thuộc phức tạp.

### 12.2. Hướng Phát Triển

- Tách worker data plane riêng có RAM lớn hơn để đo throughput cao hơn.
- Bổ sung synthetic bad records để kiểm thử rejected records.
- Tạo sink green riêng rồi swap downstream consumer theo phiên bản.
- Tự động hóa cutover bằng Argo CD hook hoặc workflow có guardrail.
- Bổ sung lifecycle policy cho MinIO bucket versioned để thu hồi dung lượng sau nhiều lần replay.
- Mở rộng benchmark latency đầu cuối thay vì chỉ dùng proxy metrics.

## 13. Kết Luận

Continux đã hoàn thành mục tiêu xây dựng Data Lakehouse thời gian thực trên Kubernetes. Hệ thống chứng minh được pipeline end-to-end từ dataset NYC TLC đến Iceberg, có GitOps, có dashboard quan sát và có kịch bản Blue/Green cutover không gây lỗi truy vấn. Kết quả cho thấy hướng cập nhật logic phân tích bằng materialized view song song là khả thi trong môi trường K3s tài nguyên giới hạn.

## 14. Tài Liệu Tham Khảo

1. Matteo Merli, Sijie Guo, Penghui Li, Hang Chen, Neng Lu. *Ursa: A Lakehouse-Native Data Streaming Engine for Kafka*. Proceedings of the VLDB Endowment, Volume 18, 2025. <https://www.vldb.org/pvldb/vol18/p5184-guo.pdf>
2. NYC Taxi & Limousine Commission Trip Record Data. <https://www.nyc.gov/site/tlc/about/tlc-trip-record-data.page>
3. Redpanda Documentation. <https://docs.redpanda.com/>
4. RisingWave Documentation. <https://docs.risingwave.com/>
5. Apache Iceberg Documentation. <https://iceberg.apache.org/docs/latest/>
6. Argo CD Documentation. <https://argo-cd.readthedocs.io/>
7. K3s Documentation. <https://docs.k3s.io/>
8. VictoriaMetrics Documentation. <https://docs.victoriametrics.com/>
9. Grafana Documentation. <https://grafana.com/docs/>
10. Vector Documentation. <https://vector.dev/docs/>

## 15. Phụ Lục Evidence Và Lệnh Kiểm Chứng

### 15.1. Baseline Cluster

```bash
cd ~/continux

RUN_ID="$(date +%Y%m%d-%H%M%S)"
EVIDENCE_DIR="evidence/finalize/${RUN_ID}"

bash scripts/k3s-check.sh
argocd app list --grpc-web
kubectl get nodes -o wide
kubectl get pods -A -o wide
kubectl get pvc -A
```

Evidence:

```text
evidence/finalize/<RUN_ID>/00-k3s-check.txt
evidence/finalize/<RUN_ID>/00-argocd-app-list.txt
evidence/finalize/<RUN_ID>/00-nodes.txt
evidence/finalize/<RUN_ID>/00-pods.txt
evidence/finalize/<RUN_ID>/00-pvc.txt
```

### 15.2. Verify RisingWave

```bash
psql -h localhost -p 4567 -d dev -U root -c 'SHOW CLUSTER;'

psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT COUNT(*) AS tlc_zone_rows FROM tlc_zone;"
```

Evidence:

```text
evidence/finalize/<RUN_ID>/02-risingwave-show-cluster.txt
evidence/finalize/<RUN_ID>/02-tlc-zone-count.txt
```

### 15.3. Replay

```bash
kubectl -n pipeline scale deploy/vector --replicas=1
kubectl -n pipeline rollout status deploy/vector --timeout=300s

psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT COUNT(*) AS zones, COALESCE(SUM(trip_count), 0) AS trips FROM mv_zone_stats;"

kubectl --request-timeout=10s -n pipeline scale deploy/vector --replicas=0
```

Evidence:

```text
evidence/finalize/<RUN_ID>/05-replay-start-epoch.txt
evidence/finalize/<RUN_ID>/05-vector-startup-logs.txt
evidence/finalize/<RUN_ID>/05-mv-final-count.txt
evidence/finalize/<RUN_ID>/05-minio-iceberg-after-replay.txt
```

### 15.4. Cutover

```bash
psql -h localhost -p 4567 -d dev -U root -c \
  "ALTER MATERIALIZED VIEW mv_zone_stats SWAP WITH mv_zone_stats_green;"

curl -G 'http://127.0.0.1:8428/api/v1/query' \
  --data-urlencode 'query=continux_cutover_duration_seconds'

curl -G 'http://127.0.0.1:8428/api/v1/query' \
  --data-urlencode 'query=continux_query_errors_total'
```

Evidence:

```text
evidence/finalize/<RUN_ID>/06-create-green-mv.txt
evidence/finalize/<RUN_ID>/06-green-catchup-samples.txt
evidence/finalize/<RUN_ID>/06-query-loop-during-cutover.txt
evidence/finalize/<RUN_ID>/06-cutover-duration.txt
evidence/finalize/<RUN_ID>/06-public-after-swap.txt
evidence/finalize/<RUN_ID>/06-green-name-after-swap.txt
evidence/finalize/<RUN_ID>/06-vm-query-cutover-duration.json
evidence/finalize/<RUN_ID>/06-vm-query-query-errors.json
```
