<p align="center">
  <a href="https://www.uit.edu.vn/" title="Trường Đại học Công nghệ Thông tin">
    <img src="https://i.imgur.com/WmMnSRt.png" alt="Trường Đại học Công nghệ Thông tin | University of Information Technology">
  </a>
</p>

<h1 align="center"><b>IS211.Q22 & IS405.Q23 - CƠ SỞ DỮ LIỆU PHÂN TÁN & DỮ LIỆU LỚN</b></h1>

<p align="center">
  <img src="https://img.shields.io/badge/version-v0.2.0-0A7CC7?style=flat-square" alt="Version v0.2.0">
  <img src="https://img.shields.io/badge/Ubuntu-24.04_%7C_26.04-E95420?style=flat-square&logo=ubuntu&logoColor=white" alt="Ubuntu 24.04 and 26.04">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/K3s-v1.35.4-326CE5?style=flat-square&logo=kubernetes&logoColor=white" alt="K3s">
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

## BẢNG MỤC LỤC

* [Giới thiệu môn học](#giới-thiệu-môn-học)
* [Giới thiệu đồ án môn học](#giới-thiệu-đồ-án-môn-học)
* [Thành viên nhóm](#thành-viên-nhóm)
* [Hạ tầng máy chủ](#hạ-tầng-máy-chủ)
* [Khởi chạy dự án](#khởi-chạy-dự-án)
* [Công nghệ sử dụng](#công-nghệ-sử-dụng)

## GIỚI THIỆU MÔN HỌC

* **Tên các môn học**: Cơ sở dữ liệu phân tán & Dữ liệu lớn
* **Mã các môn học**: IS211 & IS405
* **Lớp học**: IS211.Q22 & IS405.Q23
* **Năm học**: HK2 2025-2026
* **Giảng viên hướng dẫn:** ThS. **Nguyễn Hồ Duy Trí**
* **Email:** *trinhd@uit.edu.vn*

---

## GIỚI THIỆU ĐỒ ÁN MÔN HỌC

* **Tiếng Việt**: Xây dựng kiến trúc Data Lakehouse thời gian thực cho hệ thống giao thông thông minh trên cụm Kubernetes
* **Tiếng Anh**: Building a Real-Time Data Lakehouse Architecture for Intelligent Transportation Systems on a Kubernetes Cluster

Đề tài xây dựng một kiến trúc **Data Lakehouse thời gian thực** trên cụm **K3s** 3 máy. Hệ thống dùng NYC TLC Trip Record Data, Vector giả lập luồng sự kiện, Redpanda làm broker Kafka-compatible, RisingWave xử lý streaming SQL, MinIO lưu checkpoint/Iceberg, Argo CD điều phối GitOps và Grafana/VictoriaMetrics giám sát.

Chi tiết đề cương xem tại [docs/PROPOSE.md](./docs/PROPOSE.md).

Tài liệu liên quan:
- [docs/ARCHITECTURE.md](./docs/ARCHITECTURE.md) - Kiến trúc, topology, placement và yêu cầu hệ thống.
- [docs/SETUP.md](./docs/SETUP.md) - Trình tự setup từ máy sạch tới pipeline chạy được.
- [docs/SCRIPTS.md](./docs/SCRIPTS.md) - Tài liệu script vận hành.
- [docs/TIMELINE.md](./docs/TIMELINE.md) - Mốc triển khai v0.2.0.
- [docs/REPORT.md](./docs/REPORT.md) - Báo cáo đồ án.

---

## THÀNH VIÊN NHÓM

| STT | MSSV | Họ và Tên | Github | Email |
|-----|:----:|----------:|-------:|------:|
| 1 | 23521367 | Ngô Tiến Sỹ | [helios-ryuu](https://github.com/helios-ryuu) | 23521367@gm.uit.edu.vn |
| 2 | 23520982 | Nguyễn Văn Nam | [Sinister-VN](https://github.com/Sinister-VN) | 23520982@gm.uit.edu.vn |

---

## HẠ TẦNG MÁY CHỦ

Cụm tham chiếu v0.2.0 gồm **3 K3s server** nối với nhau bằng **Tailscale mesh VPN**.

| Node Kubernetes | Máy | Hệ điều hành | Vai trò |
|-----------------|-----|--------------|---------|
| **`imac`** | iMac19,2 · Intel i5-8500 · 6 cores · 8 GB DDR4 · 200 GB SSD | Ubuntu 26.04 native | K3s server #1 · data plane: MinIO, Redpanda, RisingWave, Vector |
| **`continux-vps`** | VPS user `helios` · 2 vCPU · 4 GB RAM · 80 GB SSD · 4 TB transfer | Ubuntu 24.04 native | K3s server #2 · control/observability: Argo CD, VictoriaMetrics, Grafana |
| **`helios-pc`** | Windows host `Helios-PC` · WSL Ubuntu 26.04 · Intel i5-12500H · 16 GB DDR5 | WSL2 Ubuntu 26.04 | K3s server #3 · quorum-only, taint `dedicated=quorum:NoSchedule` |

Tailscale inventory chuẩn:

| Tailscale IP | Tailscale device | Tailnet user | OS | Dùng trong dự án |
|--------------|------------------|--------------|----|------------------|
| `100.120.64.5` | `imac` | `ngotiensy2005@` | Linux | K3s server #1 |
| `100.113.151.56` | `continux-vps` | `ngotiensy2005@` | Linux | K3s server #2 |
| `100.78.46.87` | `helios-pc-wsl` | `ngotiensy2005@` | Linux | K3s server #3; shell hostname `Helios-PC`, Kubernetes node `helios-pc` |
| `100.125.106.89` | `helios-pc` | `ngotiensy2005@` | Windows | Windows host, không phải node K3s |

Lưu ý: WSL trên `Helios-PC` được Tailscale đặt tên `helios-pc-wsl` để tránh trùng với Windows host `helios-pc`; shell prompt vẫn dạng `helios@Helios-PC`, còn Kubernetes dùng node name `helios-pc`.

---

## KHỞI CHẠY DỰ ÁN

**Phiên bản hiện tại:** `v0.2.0` - refactor topology 3 máy, tinh gọn tài liệu vận hành, cập nhật scripts và pin image/tag chính.

Quy trình tổng quát:

1. Chuẩn bị user `helios`, hostname, SSH, systemd/WSL và Tailscale trên 3 máy.
2. Init K3s server #1 trên `imac`, lấy token bằng `scripts/k3s-token.sh`.
3. Join `continux-vps` profile `edge` và `helios-pc` profile `quorum`.
4. Cài CLI quản trị, deploy Argo CD, đăng ký repo GitOps và apply App-of-Apps.
5. Deploy MinIO, Redpanda, RisingWave, VictoriaMetrics và Grafana theo [docs/SETUP.md](./docs/SETUP.md).
6. Tải NYC TLC parquet, convert bằng `scripts/partojsonl.py`, sync Vector ở `replicas: 0`, rồi scale thủ công khi preflight xanh.
7. Apply SQL source/table/MV/sink, verify bằng RisingWave query, Redpanda topic, Iceberg object output và Grafana dashboard.

---

## CÔNG NGHỆ SỬ DỤNG

**Nền tảng & điều phối:** K3s, Argo CD, Helm, Tailscale, Cloudflare Tunnel.

**Thu thập & truyền tải dữ liệu:** Vector, Redpanda.

**Xử lý luồng & lưu trữ:** RisingWave, Apache Iceberg, MinIO.

**Giám sát:** VictoriaMetrics, Grafana.

**Dataset:** [NYC TLC Trip Record Data](https://www.nyc.gov/site/tlc/about/tlc-trip-record-data.page).
