<p align="center">
  <a href="https://www.uit.edu.vn/" title="Trường Đại học Công nghệ Thông tin">
    <img src="https://i.imgur.com/WmMnSRt.png" alt="Trường Đại học Công nghệ Thông tin | University of Information Technology">
  </a>
</p>

<h1 align="center"><b>IS211.Q22 & IS405.Q23 - CƠ SỞ DỮ LIỆU PHÂN TÁN & DỮ LIỆU LỚN</b></h1>

<p align="center">
  <img src="https://img.shields.io/badge/version-v2.1.2-0A7CC7?style=flat-square" alt="Phiên bản v2.1.2">
  <img src="https://img.shields.io/badge/Ubuntu-24.04_%7C_26.04-E95420?style=flat-square&logo=ubuntu&logoColor=white" alt="Ubuntu 24.04 and 26.04">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/K3s-v1.35.5-326CE5?style=flat-square&logo=kubernetes&logoColor=white" alt="K3s">
  <img src="https://img.shields.io/badge/Helm-v4.2.0-0F1689?style=flat-square&logo=helm&logoColor=white" alt="Helm">
  <img src="https://img.shields.io/badge/ArgoCD-v3.4.3-EF7B4D?style=flat-square&logo=argo&logoColor=white" alt="Argo CD">
  <img src="https://img.shields.io/badge/Tailscale-v1.98.2-242424?style=flat-square&logo=tailscale&logoColor=white" alt="Tailscale">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Vector-v0.55.0-10E7FF?style=flat-square&logoColor=white" alt="Vector">
  <img src="https://img.shields.io/badge/Redpanda-v26.1.9-E3402B?style=flat-square&logo=redpanda&logoColor=white" alt="Redpanda">
  <img src="https://img.shields.io/badge/RisingWave-v2.8.4-5B7FFF?style=flat-square&logoColor=white" alt="RisingWave">
  <img src="https://img.shields.io/badge/Apache_Iceberg-v2-3E5F8A?style=flat-square&logo=apache&logoColor=white" alt="Apache Iceberg">
  <img src="https://img.shields.io/badge/MinIO-self--hosted-C72E49?style=flat-square&logo=minio&logoColor=white" alt="MinIO">
  <img src="https://img.shields.io/badge/VictoriaMetrics-v1.144.0-621773?style=flat-square&logoColor=white" alt="VictoriaMetrics">
  <img src="https://img.shields.io/badge/Grafana-v13.0.1%2Bsecurity--01-F46800?style=flat-square&logo=grafana&logoColor=white" alt="Grafana">
</p>

## Bảng Mục Lục

- [Giới thiệu môn học](#giới-thiệu-môn-học)
- [Giới thiệu đồ án](#giới-thiệu-đồ-án)
- [Thành viên nhóm](#thành-viên-nhóm)
- [Phạm vi hệ thống](#phạm-vi-hệ-thống)
- [Hạ tầng triển khai](#hạ-tầng-triển-khai)
- [Quy trình vận hành](#quy-trình-vận-hành)
- [Khái niệm và công nghệ sử dụng](#khái-niệm-và-công-nghệ-sử-dụng)

## Giới Thiệu Môn Học

- **Tên môn học:** Cơ sở dữ liệu phân tán và Dữ liệu lớn
- **Mã môn học:** IS211 và IS405
- **Lớp:** IS211.Q22 và IS405.Q23
- **Năm học:** HK2 2025-2026
- **Giảng viên hướng dẫn:** ThS. **Nguyễn Hồ Duy Trí**
- **Email:** *trinhd@uit.edu.vn*

## Giới Thiệu Đồ Án

- **Tiếng Việt:** Xây dựng kiến trúc Data Lakehouse thời gian thực cho hệ thống giao thông thông minh trên cụm Kubernetes.
- **Tiếng Anh:** Building a Real-Time Data Lakehouse Architecture for Intelligent Transportation Systems on a Kubernetes Cluster.

Continux triển khai một kiến trúc **Data Lakehouse thời gian thực** trên cụm **K3s HA 3 server**. Hệ thống dùng dữ liệu NYC TLC Yellow Taxi, Vector để mô phỏng luồng sự kiện, Redpanda làm broker Kafka-compatible, RisingWave xử lý streaming SQL, MinIO lưu dữ liệu Iceberg/checkpoint, Argo CD điều phối GitOps, VictoriaMetrics và Grafana phục vụ quan sát.

## Thành Viên Nhóm

| STT | MSSV | Họ và tên | GitHub | Email |
|-----|:----:|-----------|--------|-------|
| 1 | 23521367 | Ngô Tiến Sỹ | [helios-ryuu](https://github.com/helios-ryuu) | 23521367@gm.uit.edu.vn |
| 2 | 23520982 | Nguyễn Văn Nam | [Sinister-VN](https://github.com/Sinister-VN) | 23520982@gm.uit.edu.vn |

## Phạm Vi Hệ Thống

- Cụm K3s 3 node Ready qua Tailscale: `imac`, `continux-vps`, `helios-pc`.
- Argo CD quản lý các app chính bằng App-of-Apps: `cloudflared`, `grafana-dashboards`, `redpanda-topics`, `pipeline`, `vector`, `victoria-scrapes`, `metrics-exporter`.
- MinIO, Redpanda, RisingWave, VictoriaMetrics và Grafana được triển khai bằng Helm.
- Dataset NYC TLC Yellow Taxi (Parquet) được convert sang JSONL trước khi replay; Taxi Zone lookup CSV được upload lên MinIO trước khi RisingWave nạp vào bảng `tlc_zone`.
- Pipeline có runner theo pha cho replay xuyên suốt và Blue/Green cutover bằng `ALTER MATERIALIZED VIEW ... SWAP WITH ...`; số đo cụ thể của mỗi lượt được lưu tại `~/continux-demo-evidence/<RUN_ID>/` ngoài repo.
- Bốn nhóm dashboard Grafana (`streaming-perf`, `resource-util`, `cutover`, `data-integrity`) đọc metric `continux_*` và metric hạ tầng từ VictoriaMetrics.

## Hạ Tầng Triển Khai

| Node Kubernetes | Máy | Hệ điều hành | Vai trò |
|-----------------|-----|--------------|---------|
| `imac` | iMac19,2, Intel i5-8500, 6 cores, 8 GB RAM, 200 GB SSD | Ubuntu 26.04 native | K3s server #1, data plane: MinIO, Redpanda, RisingWave, Vector |
| `continux-vps` | VPS user `helios`, 2 vCPU, 4 GB RAM, 80 GB SSD, 4 TB transfer | Ubuntu 24.04 native | K3s server #2, control/observability: Argo CD, VictoriaMetrics, Grafana |
| `helios-pc` | Windows host `Helios-PC`, WSL Ubuntu 26.04, Intel i5-12500H, 16 GB RAM | WSL2 Ubuntu 26.04 | K3s server #3, quorum-only, taint `dedicated=quorum:NoSchedule` |

Tailscale inventory:

| Tailscale IP | Tailscale device | OS | Dùng trong dự án |
|--------------|------------------|----|------------------|
| `100.120.64.5` | `imac` | Linux | K3s server #1 |
| `100.113.151.56` | `continux-vps` | Linux | K3s server #2 |
| `100.78.46.87` | `helios-pc-wsl` | Linux | K3s server #3; Kubernetes node `helios-pc` |
| `100.125.106.89` | `helios-pc` | Windows | Windows host, không tham gia K3s |

## Quy Trình Vận Hành

Luồng dữ liệu chính:

```text
NYC TLC Parquet
  -> scripts/partojsonl.py
  -> Vector
  -> Redpanda topic nyc-taxi-events
  -> RisingWave source/table/materialized views
  -> Apache Iceberg objects on MinIO
  -> VictoriaMetrics/Grafana dashboards
```

Quy trình triển khai chuẩn:

1. Theo [SETUP.md](./docs/runbook/SETUP.md) để dựng hệ thống từ máy sạch, [DEMO.md](./docs/runbook/DEMO.md) để chạy replay + Blue/Green cutover và [CLEANUP.md](./docs/runbook/CLEANUP.md) để dọn trạng thái trước lượt kế tiếp.
2. Đọc kết quả dashboard theo [docs/DASHBOARDS.md](./docs/DASHBOARDS.md).
3. Dùng [paper/main_vi.pdf](./paper/main_vi.pdf) và [paper/main_en.pdf](./paper/main_en.pdf) làm bản paper LaTeX cuối; [docs/REPORT.md](./docs/REPORT.md) là báo cáo đi kèm bằng chứng.

Runner chuẩn sau khi hạ tầng đã sẵn sàng:

```bash
bash experiments/runners/demo.sh init smoke
bash experiments/runners/demo.sh prepare-data
bash experiments/runners/demo.sh baseline
bash experiments/runners/demo.sh replay
bash experiments/runners/demo.sh cutover
bash experiments/runners/demo.sh cleanup-runtime
bash experiments/runners/demo.sh cleanup-local
```

## Khái Niệm Và Công Nghệ Sử Dụng

### Khái Niệm Nền Tảng

| Khái niệm | Ý nghĩa | Cách áp dụng trong Continux |
|-----------|---------|-----------------------------|
| **Data Lakehouse** | Kiến trúc kết hợp khả năng lưu dữ liệu linh hoạt của Data Lake với bảng phân tích có quản trị của Data Warehouse. | Dữ liệu tổng hợp từ RisingWave được ghi theo định dạng Apache Iceberg trên MinIO. |
| **Streaming pipeline** | Chuỗi xử lý dữ liệu ngay khi event được phát sinh hoặc phát lại, thay vì đợi một batch hoàn tất. | Vector phát JSONL vào Redpanda; RisingWave cập nhật materialized view liên tục. |
| **Materialized view** | Kết quả truy vấn được duy trì sẵn và tự cập nhật khi nguồn dữ liệu thay đổi. | `mv_zone_stats` cung cấp số liệu thống kê chuyến xe theo khu vực. |
| **GitOps** | Cách vận hành lấy Git làm nguồn cấu hình mong muốn và tự đồng bộ ra cluster. | Argo CD đọc manifest trong repo và quản lý các application Kubernetes. |
| **Blue/Green cutover** | Duy trì logic hiện tại và logic mới song song, rồi chuyển public workload khi bản mới sẵn sàng. | RisingWave tạo `mv_zone_stats_green` và swap với `mv_zone_stats`. |
| **Observability** | Thu thập metric và hiển thị trạng thái để đánh giá sức khỏe, hiệu năng và chất lượng dữ liệu. | VictoriaMetrics lưu metrics; Grafana trực quan hóa resource, replay, cutover và integrity. |

### Thành Phần Triển Khai

| Nhóm | Công nghệ | Công nghệ là gì | Đóng góp vào dự án |
|------|-----------|-----------------|---------------------|
| Nền tảng | **[K3s](https://docs.k3s.io/)** | Bản phân phối Kubernetes gọn nhẹ, phù hợp cụm nhỏ và edge/lab. | Vận hành cluster HA 3 server để chạy toàn bộ workload của đề tài. |
| Kết nối | **[Tailscale](https://tailscale.com/)** | Mạng mesh VPN dựa trên WireGuard. | Tạo mạng riêng giữa `imac`, `continux-vps`, `helios-pc` cho Kubernetes/etcd giao tiếp an toàn. |
| Đóng gói | **[Helm](https://helm.sh/)** | Trình quản lý package/chart cho Kubernetes. | Cài và cấu hình các stack như Argo CD, MinIO, Redpanda, RisingWave, VictoriaMetrics và Grafana. |
| GitOps | **[Argo CD](https://argo-cd.readthedocs.io/)** | Continuous Delivery controller dành cho Kubernetes. | Đồng bộ manifest từ Git, quản lý App-of-Apps và ghi nhận trạng thái `Synced/Healthy`. |
| Truy cập | **[Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)** | Tunnel đưa dịch vụ nội bộ ra domain HTTPS mà không mở port trực tiếp. | Cung cấp đường truy cập an toàn tới Argo CD UI và Grafana UI. |
| Ingest | **[Vector](https://vector.dev/docs/)** | Công cụ thu thập, biến đổi và chuyển tiếp dữ liệu hiệu năng cao. | Đọc JSONL từ dataset, phát event có kiểm soát vào Redpanda để replay dòng chuyến xe. |
| Message broker | **[Redpanda](https://docs.redpanda.com/)** | Broker streaming tương thích Kafka API. | Lưu topic `nyc-taxi-events`, tách producer Vector khỏi consumer RisingWave. |
| Streaming SQL | **[RisingWave](https://docs.risingwave.com/)** | Cơ sở dữ liệu streaming dùng SQL và materialized view. | Join event với Taxi Zone lookup, tổng hợp thống kê, duy trì Blue/Green MV và ghi sink. |
| Định dạng bảng | **[Apache Iceberg](https://iceberg.apache.org/docs/latest/)** | Định dạng bảng cho lưu trữ đối tượng, quản lý metadata và thay đổi dữ liệu. | Biến đầu ra streaming thành dữ liệu lakehouse có thể kiểm chứng bằng object Parquet/metadata. |
| Lưu trữ đối tượng | **[MinIO](https://min.io/)** | Hệ lưu trữ đối tượng tương thích S3, tự vận hành. | Lưu Taxi Zone CSV, checkpoint/trạng thái của RisingWave và đầu ra Iceberg. |
| Metrics storage | **[VictoriaMetrics](https://docs.victoriametrics.com/)** | Cơ sở dữ liệu chuỗi thời gian tương thích Prometheus. | Thu metric Kubernetes, workload và `continux_*` để truy vấn kết quả thực nghiệm. |
| Visualization | **[Grafana](https://grafana.com/docs/grafana/latest/)** | Công cụ xây dashboard từ datasource quan sát. | Trình bày bốn nhóm chỉ số: streaming, resource, cutover và data integrity. |
| Metric ứng dụng | **[metrics-exporter `continux_*`](./config/metrics-exporter/)** | Exporter tùy biến truy vấn RisingWave rồi xuất Prometheus metrics. | Cung cấp số dòng MV, readiness green, thời gian cutover và số lỗi query cho dashboard. |
| Dữ liệu | **[NYC TLC Trip Record Data](https://www.nyc.gov/site/tlc/about/tlc-trip-record-data.page)** | Bộ dữ liệu mở về các chuyến taxi New York. | Cung cấp nguồn sự kiện Yellow Taxi và Taxi Zone lookup để minh họa bài toán giao thông. |

Thông tin chi tiết được chia theo ba pha vận hành: [SETUP.md](./docs/runbook/SETUP.md), [DEMO.md](./docs/runbook/DEMO.md) và [CLEANUP.md](./docs/runbook/CLEANUP.md).
