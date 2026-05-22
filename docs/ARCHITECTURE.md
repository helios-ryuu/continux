# ARCHITECTURE

> Phiên bản dự án: `v0.2.3`. Kiến trúc dưới đây phản ánh cụm thật sau khi hoàn tất `docs/SETUP.md` §1-10 và `docs/FINALIZE.md` §1-4.

## 1. Tổng quan

Continux là kiến trúc Data Lakehouse thời gian thực chạy trên cụm K3s 3 server. Mục tiêu là ingest dữ liệu NYC TLC, xử lý streaming SQL bằng RisingWave, ghi kết quả xuống Apache Iceberg trên MinIO, và quan sát pipeline bằng VictoriaMetrics/Grafana.

Stack chính:

- **K3s + Tailscale**: cụm Kubernetes HA qua mesh VPN.
- **Argo CD + Helm**: GitOps và triển khai chart.
- **Vector + Redpanda**: giả lập stream JSONL và broker Kafka-compatible.
- **RisingWave + Apache Iceberg + MinIO**: compute streaming và lưu trữ lakehouse.
- **VictoriaMetrics + Grafana + metrics-exporter + Cloudflare Tunnel**: metrics, dashboard và metric thực nghiệm `continux_*`.

## 2. Topology

| Node | Tài nguyên | Vai trò |
|------|------------|---------|
| `imac` | iMac19,2, Intel i5-8500, 6 cores, 8 GB RAM, 200 GB SSD, Ubuntu 26.04 | K3s server #1, data plane |
| `continux-vps` | user `helios`, 2 vCPU, 4 GB RAM, 80 GB SSD, 4 TB transfer, Ubuntu 24.04 | K3s server #2, control/observability |
| `helios-pc` | Windows host `Helios-PC`, WSL Ubuntu 26.04, Intel i5-12500H, 16 GB RAM | K3s server #3, quorum-only |

Tailscale inventory chuẩn:

| Tailscale IP | Tailscale device | Tailnet user | OS | Ghi chú |
|--------------|------------------|--------------|----|---------|
| `100.120.64.5` | `imac` | `ngotiensy2005@` | Linux | K3s server #1 |
| `100.113.151.56` | `continux-vps` | `ngotiensy2005@` | Linux | K3s server #2 |
| `100.78.46.87` | `helios-pc-wsl` | `ngotiensy2005@` | Linux | K3s server #3; shell hostname `Helios-PC`, Kubernetes node `helios-pc` |
| `100.125.106.89` | `helios-pc` | `ngotiensy2005@` | Windows | Windows host, ngoài cụm K3s |

Ba máy thuộc cụm là `imac`, `continux-vps`, và WSL `helios-pc-wsl`. Khi thao tác Kubernetes dùng node name `helios-pc`; khi kiểm tra kết nối Tailscale tới WSL nên dùng `helios-pc-wsl` hoặc `100.78.46.87`.

```
Vector -> Redpanda -> RisingWave -> Iceberg objects on MinIO
                       |
                       +-> Grafana/VictoriaMetrics observability
```

Placement:

```yaml
# Stateful/data workload
nodeSelector: { role: data-plane }

# Control/observability workload
nodeSelector: { role: control-plane }
tolerations:
  - { key: dedicated, operator: Equal, value: edge, effect: NoSchedule }

# Quorum node
nodeSelector: { role: quorum }
tolerations:
  - { key: dedicated, operator: Equal, value: quorum, effect: NoSchedule }
```

Ứng dụng không schedule lên `helios-pc`; node này giữ quorum cho embedded etcd. Ngoại lệ có chủ đích là `prometheus-node-exporter` chạy dạng DaemonSet trên cả 3 node để quan sát tài nguyên node; trên WSL cần `scripts/wsl-enable-shared-root.sh` để hostPath mount `/` hoạt động.

## 3. Data Flow

1. `scripts/partojsonl.py` convert Yellow Taxi Parquet sang JSONL trong `data/raw/`.
2. Vector đọc `/data/*.jsonl`, thêm `event_id` và `event_time`.
3. Vector publish JSON vào Redpanda topic `nyc-taxi-events` qua Kafka sink có disk buffer và rate limit để tránh flood cụm nhỏ.
4. RisingWave đọc topic, join với TLC Taxi Zone CSV trong MinIO.
5. Materialized View `mv_zone_stats` tổng hợp thống kê theo zone/borough.
6. Iceberg sink ghi kết quả xuống bucket `iceberg-data`.
7. VictoriaMetrics scrape metrics; Grafana import dashboard từ `dashboards/*.json`.
8. `metrics-exporter` đọc RisingWave catalog/MV và expose metric `continux_*` cho dashboard thực nghiệm.

## 4. GitOps Layout

| Path | Nội dung |
|------|----------|
| `config/argocd/` | Argo CD values và cloudflared manifest |
| `config/minio/` | MinIO Helm values |
| `config/redpanda/` | Redpanda Helm values |
| `config/risingwave/` | RisingWave Helm values |
| `config/vector/` | Vector ConfigMap, PVC, Deployment |
| `config/metrics-exporter/` | Exporter metric thực nghiệm `continux_*` và VMServiceScrape |
| `config/victoria-metrics/` | VictoriaMetrics values và scrape config |
| `gitops/apps/` | App-of-Apps cho Argo CD |
| `gitops/pipeline/` | SQL apply Job |
| `pipelines/redpanda/` | Topic bootstrap Job |
| `sql/` | Source, table, MV, sink SQL |

## 5. Yêu cầu chính

| ID | Yêu cầu | Tiêu chí |
|----|---------|----------|
| FR-01 | Ingest NYC TLC Trip Record Data | Vector publish được JSON vào `nyc-taxi-events` |
| FR-02 | Streaming SQL | RisingWave query được source/table/MV |
| FR-03 | Lakehouse sink | MinIO bucket `iceberg-data` có Iceberg metadata/data |
| FR-04 | GitOps deployment | Argo CD quản lý app manifests |
| FR-05 | Observability | Grafana đọc datasource VictoriaMetrics |
| NFR-01 | HA control plane | 3 server Ready, quorum `2/3` |
| NFR-02 | Resource safety | Vector mặc định `replicas: 0`, scale thủ công |
| NFR-04 | Demo replay | `docs/SETUP.md` §11 có quy trình clear Redpanda/RisingWave/Iceberg để chạy ingest lại |
| NFR-03 | Reproducible setup | `docs/SETUP.md` đi từ máy sạch tới verify end-to-end |

## 6. Vận hành

- `imac` giữ clone repo `~/continux` và là node quản trị chính.
- `k3s-purge.sh` mặc định reset cluster về trạng thái vừa cài K3s.
- `k3s-purge.sh --nuke` xóa K3s khỏi node hiện tại.
- Secrets không commit vào Git; tạo qua `kubectl create secret ... --dry-run=client -o yaml | kubectl apply -f -`.
- Dataset lớn nằm trong `data/raw/` và không commit.
