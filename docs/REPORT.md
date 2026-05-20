# REPORT

## 1. Tóm tắt

Đồ án xây dựng kiến trúc Data Lakehouse thời gian thực cho dữ liệu giao thông trên cụm K3s 3 server. Pipeline nhận dữ liệu NYC TLC Yellow Taxi ở dạng JSONL, publish vào Redpanda, xử lý streaming SQL bằng RisingWave, ghi kết quả xuống Apache Iceberg trên MinIO, và giám sát bằng VictoriaMetrics/Grafana.

## 2. Hạ tầng thực nghiệm

| Node | Mô tả | Vai trò |
|------|------|---------|
| `imac` | Ubuntu 26.04, iMac19,2, Intel i5-8500, 6 cores, 8 GB RAM, 200 GB SSD | data plane |
| `continux-vps` | Ubuntu 24.04, user `helios`, 2 vCPU, 4 GB RAM, 80 GB SSD, 4 TB transfer | control/observability |
| `helios-pc` | Windows host `Helios-PC`, WSL Ubuntu 26.04, Intel i5-12500H, 16 GB RAM | quorum-only |

Cụm dùng Tailscale mesh VPN, K3s embedded etcd, quorum `2/3`.

## 3. Stack phần mềm

| Nhóm | Công nghệ |
|------|-----------|
| Orchestration | K3s `v1.35.4+k3s1`, Helm `v4.1.4`, Argo CD `v3.4.2` |
| Streaming ingest | Vector `0.55.0`, Redpanda `v26.1.8` |
| Processing/storage | RisingWave `v2.8.3`, Apache Iceberg v2, MinIO self-hosted |
| Observability | VictoriaMetrics `v1.143.0`, Grafana `v13.0.1+security-01`, cloudflared `2026.5.0` |

## 4. Kiến trúc dữ liệu

1. `partojsonl.py` lấy các cột cần thiết từ Yellow Taxi Parquet.
2. Vector đọc JSONL từ PVC hostPath trên `imac`.
3. Redpanda nhận topic `nyc-taxi-events`.
4. RisingWave tạo source/table/MV và join với Taxi Zone lookup trên MinIO.
5. Iceberg sink ghi kết quả xuống `iceberg-data`.
6. Grafana hiển thị throughput, lag, resource và integrity metrics.

## 5. Kết quả cần chứng minh

| Hạng mục | Cách đo |
|----------|---------|
| Cluster HA | `kubectl get nodes`, `readyz`, node quorum Ready |
| Ingest ổn định | Vector Running, Redpanda topic có event |
| Streaming SQL | `SELECT COUNT(*) FROM mv_zone_stats` trả số dương |
| Lakehouse output | `mc ls --recursive local/iceberg-data/nyc/zone_stats/` có metadata/data |
| Observability | Grafana dashboard đọc datasource VictoriaMetrics |

## 6. Giới hạn

- Tài nguyên data plane giới hạn bởi RAM 8 GB của `imac`.
- Vector được scale thủ công để tránh ingest khi cluster chưa sẵn sàng.
- `helios-pc` giữ quorum, không chạy workload ứng dụng mặc định.
- Secrets được tạo runtime bằng Kubernetes Secret, không lưu trong Git.

## 7. Tài liệu liên quan

- [PROPOSE.md](./PROPOSE.md)
- [ARCHITECTURE.md](./ARCHITECTURE.md)
- [SETUP.md](./SETUP.md)
- [SCRIPTS.md](./SCRIPTS.md)
- [TIMELINE.md](./TIMELINE.md)
