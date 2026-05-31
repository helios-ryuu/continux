# ARCHITECTURE

Tài liệu này mô tả kiến trúc Continux: cụm K3s 3 server, pipeline Data Lakehouse thời gian thực, GitOps, quan sát và kịch bản Blue/Green cutover.

## 1. Tổng Quan

Continux xây dựng một Data Lakehouse thời gian thực cho dữ liệu giao thông. Hệ thống ingest NYC TLC Yellow Taxi, xử lý streaming SQL bằng RisingWave, ghi kết quả xuống Apache Iceberg trên MinIO và quan sát bằng VictoriaMetrics/Grafana.

Stack chính:

- **K3s + Tailscale:** cụm Kubernetes HA qua mesh VPN.
- **Argo CD + Helm:** GitOps và quản lý release.
- **Vector + Redpanda:** giả lập stream JSONL và broker Kafka-compatible.
- **RisingWave + Apache Iceberg + MinIO:** xử lý luồng, kho trạng thái và lakehouse sink.
- **VictoriaMetrics + Grafana + metrics-exporter:** quan sát hạ tầng và metric thực nghiệm `continux_*`.
- **Cloudflare Tunnel:** expose UI Argo CD/Grafana qua domain có kiểm soát.

## 2. Bố Trí Hạ Tầng

| Node | Tài nguyên | Vai trò |
|------|------------|---------|
| `imac` | iMac19,2, Intel i5-8500, 6 cores, 8 GB RAM, 200 GB SSD, Ubuntu 26.04 | K3s server #1, data plane |
| `continux-vps` | 2 vCPU, 4 GB RAM, 80 GB SSD, Ubuntu 24.04 | K3s server #2, control/observability |
| `helios-pc` | WSL Ubuntu 26.04 trên Windows host `Helios-PC`, Intel i5-12500H, 16 GB RAM | K3s server #3, quorum-only |

Tailscale inventory:

| Tailscale IP | Device | OS | Ghi chú |
|--------------|--------|----|---------|
| `100.120.64.5` | `imac` | Linux | K3s server #1 |
| `100.113.151.56` | `continux-vps` | Linux | K3s server #2 |
| `100.78.46.87` | `helios-pc-wsl` | Linux | K3s server #3; Kubernetes node `helios-pc` |
| `100.125.106.89` | `helios-pc` | Windows | Windows host, ngoài cụm K3s |

Placement chuẩn:

```yaml
# Workload có trạng thái và dữ liệu
nodeSelector:
  role: data-plane

# Control/observability workload
nodeSelector:
  role: control-plane
tolerations:
  - key: dedicated
    operator: Equal
    value: edge
    effect: NoSchedule

# Quorum node
nodeSelector:
  role: quorum
tolerations:
  - key: dedicated
    operator: Equal
    value: quorum
    effect: NoSchedule
```

Ứng dụng không schedule lên `helios-pc` theo mặc định; node này giữ quorum cho embedded etcd. Ngoại lệ có chủ đích là node-exporter dạng DaemonSet để quan sát tài nguyên node.

## 3. Luồng Dữ Liệu

```text
NYC TLC Parquet
  -> scripts/partojsonl.py
  -> Vector file source
  -> Redpanda topic nyc-taxi-events
  -> RisingWave source/table/MV
  -> Iceberg sink on MinIO
  -> VictoriaMetrics/Grafana
```

Các bước chính:

1. `scripts/partojsonl.py` convert Yellow Taxi Parquet sang JSONL.
2. Vector đọc `/data/*.jsonl`, phát JSON vào Redpanda với disk buffer và rate limit.
3. Redpanda lưu topic `nyc-taxi-events` có 3 partitions.
4. RisingWave đọc topic, join với TLC Taxi Zone CSV trên MinIO.
5. `mv_zone_stats` tổng hợp `trip_count`, `total_fare`, `avg_distance` theo `borough/zone`.
6. `sink_zone_stats` ghi kết quả xuống Iceberg prefix `iceberg-data/nyc/zone_stats/`.
7. `metrics-exporter` đọc RisingWave catalog/MV và expose `continux_*`.
8. VictoriaMetrics scrape metrics; Grafana hiển thị dashboard resource, streaming, cutover và integrity.

## 4. Bố Trí GitOps

| Path | Nội dung |
|------|----------|
| `config/argocd/` | Argo CD values và cloudflared manifest |
| `config/minio/` | MinIO Helm values |
| `config/redpanda/` | Redpanda Helm values |
| `config/risingwave/` | RisingWave Helm values |
| `config/metrics-exporter/` | Exporter metric thực nghiệm và VMServiceScrape |
| `config/victoria-metrics/` | VictoriaMetrics values và scrape config |
| `gitops/apps/` | App-of-Apps cho Argo CD |
| `pipelines/vector/` | Vector TOML, profile tốc độ, PVC và Deployment |
| `pipelines/redpanda/` | Topic bootstrap Job |
| `sql/` | Source, table, MV, sink SQL và apply Job |
| `dashboards/` | Dashboard JSON và ConfigMap cấp phát cho Grafana |
| `experiments/` | Kịch bản, runner theo pha và trạng thái cục bộ đã bỏ qua |

## 5. Blue/Green Cutover

Cutover được thực hiện ở lớp RisingWave materialized view:

1. Public view `mv_zone_stats` đang phục vụ logic hiện tại.
2. Green view `mv_zone_stats_green` được tạo với schema tương thích và logic mới.
3. Query loop chạy liên tục để đo lỗi truy vấn trong lúc swap.
4. Khi green ổn định, chạy:

```sql
ALTER MATERIALIZED VIEW mv_zone_stats SWAP WITH mv_zone_stats_green;
```

Sau swap, tên public `mv_zone_stats` phục vụ logic mới mà không cần đổi query phía người dùng; view giữ tên `mv_zone_stats_green` chứa logic cũ. Số đo cụ thể (thời lượng, lỗi truy vấn, số dòng trước/sau) của từng lượt thực nghiệm được lưu tại `~/continux-demo-evidence/<RUN_ID>/` ngoài repo. Lệch checksum sau swap là kết quả dự kiến nếu dashboard so logic mới với logic cũ.

## 6. Yêu Cầu Và Tiêu Chí

| ID | Yêu cầu | Tiêu chí đạt |
|----|---------|--------------|
| FR-01 | Ingest NYC TLC Trip Record Data | Vector phát được JSON vào `nyc-taxi-events` |
| FR-02 | Streaming SQL | RisingWave query được source, table, MV |
| FR-03 | Lakehouse sink | MinIO bucket `iceberg-data` có Iceberg metadata/data |
| FR-04 | Triển khai GitOps | Argo CD quản lý các app từ repo |
| FR-05 | Observability | Grafana đọc VictoriaMetrics và metric `continux_*` |
| NFR-01 | HA control plane | 3 K3s server Ready, quorum `2/3` |
| NFR-02 | Resource safety | Vector mặc định `replicas=0`, profile `smoke=2 events/s`; benchmark phải opt-in |
| NFR-03 | Thiết lập có thể tái lập | `runbook/SETUP.md` đi từ máy sạch đến trạng thái sẵn sàng thực nghiệm |
| NFR-04 | Replay thực nghiệm | `runbook/DEMO.md` và `runbook/CLEANUP.md` có replay sạch và dọn dẹp để chạy lại từ đầu |

## 7. Vận Hành

- `imac` là node quản trị chính, giữ clone repo `~/continux`.
- Vector luôn giữ `replicas=0` khi không chạy ingest thực nghiệm.
- `experiments/runners/demo.sh` điều phối từng pha và trả Vector về profile `smoke` sau replay.
- Secrets tạo runtime bằng Kubernetes Secret, không lưu trong Git.
- Dataset lớn nằm trong `data/raw/` và không commit.
- Bằng chứng, ảnh chụp màn hình và log lớn nộp riêng, không commit vào repo.
- Công cụ reset/phá hủy nằm trong `scripts/k3s-purge.sh` và chỉ dùng theo [SCRIPTS.md](./SCRIPTS.md).
