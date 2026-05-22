<p align="center">
  <a href="https://www.uit.edu.vn/" title="Trường Đại học Công nghệ Thông tin">
    <img src="https://i.imgur.com/WmMnSRt.png" alt="Trường Đại học Công nghệ Thông tin | University of Information Technology">
  </a>
</p>

<h1 align="center"><b>IS211.Q22 & IS405.Q23 - CƠ SỞ DỮ LIỆU PHÂN TÁN & DỮ LIỆU LỚN</b></h1>

<p align="center">
  <img src="https://img.shields.io/badge/version-v1.0.0-0A7CC7?style=flat-square" alt="Version v1.0.0">
  <img src="https://img.shields.io/badge/Ubuntu-24.04_%7C_26.04-E95420?style=flat-square&logo=ubuntu&logoColor=white" alt="Ubuntu 24.04 and 26.04">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/K3s-v1.35.5-326CE5?style=flat-square&logo=kubernetes&logoColor=white" alt="K3s">
  <img src="https://img.shields.io/badge/Helm-v4.1.4-0F1689?style=flat-square&logo=helm&logoColor=white" alt="Helm">
  <img src="https://img.shields.io/badge/ArgoCD-v3.4.2-EF7B4D?style=flat-square&logo=argo&logoColor=white" alt="Argo CD">
  <img src="https://img.shields.io/badge/Tailscale-v1.98.2-242424?style=flat-square&logo=tailscale&logoColor=white" alt="Tailscale">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Vector-v0.55.0-10E7FF?style=flat-square&logoColor=white" alt="Vector">
  <img src="https://img.shields.io/badge/Redpanda-v26.1.8-E3402B?style=flat-square&logo=redpanda&logoColor=white" alt="Redpanda">
  <img src="https://img.shields.io/badge/RisingWave-v2.8.3-5B7FFF?style=flat-square&logoColor=white" alt="RisingWave">
  <img src="https://img.shields.io/badge/Apache_Iceberg-v2-3E5F8A?style=flat-square&logo=apache&logoColor=white" alt="Apache Iceberg">
  <img src="https://img.shields.io/badge/MinIO-self--hosted-C72E49?style=flat-square&logo=minio&logoColor=white" alt="MinIO">
  <img src="https://img.shields.io/badge/VictoriaMetrics-v1.143.0-621773?style=flat-square&logoColor=white" alt="VictoriaMetrics">
  <img src="https://img.shields.io/badge/Grafana-v13.0.1%2Bsecurity--01-F46800?style=flat-square&logo=grafana&logoColor=white" alt="Grafana">
</p>

## Bảng Mục Lục

- [Giới thiệu môn học](#giới-thiệu-môn-học)
- [Giới thiệu đồ án](#giới-thiệu-đồ-án)
- [Thành viên nhóm](#thành-viên-nhóm)
- [Trạng thái v1.0.0](#trạng-thái-v100)
- [Hạ tầng triển khai](#hạ-tầng-triển-khai)
- [Quy trình vận hành](#quy-trình-vận-hành)
- [Tài liệu chính](#tài-liệu-chính)
- [Công nghệ sử dụng](#công-nghệ-sử-dụng)

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

Đóng góp chính của phiên bản `v1.0.0` là chứng minh pipeline end-to-end, replay dữ liệu có kiểm soát và Blue/Green cutover ở lớp materialized view với thời gian swap đo được `0.145226s`, query errors `0`.

## Thành Viên Nhóm

| STT | MSSV | Họ và tên | GitHub | Email |
|-----|:----:|-----------|--------|-------|
| 1 | 23521367 | Ngô Tiến Sỹ | [helios-ryuu](https://github.com/helios-ryuu) | 23521367@gm.uit.edu.vn |
| 2 | 23520982 | Nguyễn Văn Nam | [Sinister-VN](https://github.com/Sinister-VN) | 23520982@gm.uit.edu.vn |

## Trạng Thái v1.0.0

Phiên bản `v1.0.0` là mốc hoàn tất đồ án:

- Cụm K3s có `3/3` node Ready qua Tailscale: `imac`, `continux-vps`, `helios-pc`.
- Argo CD quản lý các app chính bằng App-of-Apps: `cloudflared`, `redpanda-topics`, `pipeline`, `vector`, `victoria-scrapes`, `metrics-exporter`.
- MinIO, Redpanda, RisingWave, VictoriaMetrics và Grafana đã triển khai ổn định.
- Dataset NYC TLC Yellow Taxi `2026-03` đã được convert từ Parquet sang JSONL với `3,952,451` dòng.
- Lookup TLC Taxi Zone có `265` dòng.
- Replay ingest cuối đạt `69 zones / 986 trips`.
- Blue/Green cutover đưa public MV sang logic green, kết quả sau swap là `69 zones / 978 trips`.
- Metric cutover đã vào VictoriaMetrics: duration `0.145226s`, query errors `0`, timestamp `1779467656`.

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

1. Chạy [docs/SETUP.md](./docs/SETUP.md) để dựng máy, K3s HA, GitOps, data plane, observability, dataset và pipeline SQL.
2. Chạy [docs/FINALIZE.md](./docs/FINALIZE.md) để thu evidence, replay ingest, verify Iceberg, chạy Blue/Green cutover và chốt tag `v1.0.0`.
3. Đọc kết quả dashboard theo [docs/DASHBOARDS.md](./docs/DASHBOARDS.md).
4. Dùng [docs/REPORT.md](./docs/REPORT.md) làm báo cáo học thuật cuối cùng.

## Tài Liệu Chính

- [docs/PROPOSE.md](./docs/PROPOSE.md): Đề cương, bài báo nền tảng và tiêu chí đánh giá.
- [docs/ARCHITECTURE.md](./docs/ARCHITECTURE.md): Kiến trúc, topology, GitOps layout và yêu cầu vận hành.
- [docs/SETUP.md](./docs/SETUP.md): Runbook dựng hệ thống từ máy sạch đến pipeline end-to-end.
- [docs/FINALIZE.md](./docs/FINALIZE.md): Runbook thực nghiệm cuối, replay, cutover và evidence.
- [docs/DASHBOARDS.md](./docs/DASHBOARDS.md): Hướng dẫn đọc dashboard Grafana.
- [docs/SCRIPTS.md](./docs/SCRIPTS.md): Mô tả script vận hành.
- [docs/TIMELINE.md](./docs/TIMELINE.md): Timeline hoàn tất.
- [docs/REPORT.md](./docs/REPORT.md): Báo cáo đồ án bản chốt.

## Công Nghệ Sử Dụng

**Nền tảng và điều phối:** K3s, Argo CD, Helm, Tailscale, Cloudflare Tunnel.

**Thu thập và truyền tải dữ liệu:** Vector, Redpanda.

**Xử lý luồng và lưu trữ:** RisingWave, Apache Iceberg, MinIO.

**Giám sát:** VictoriaMetrics, Grafana, metrics-exporter `continux_*`.

**Dataset:** [NYC TLC Trip Record Data](https://www.nyc.gov/site/tlc/about/tlc-trip-record-data.page).
