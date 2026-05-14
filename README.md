<p align="center">
  <a href="https://www.uit.edu.vn/" title="Trường Đại học Công nghệ Thông tin">
    <img src="https://i.imgur.com/WmMnSRt.png" alt="Trường Đại học Công nghệ Thông tin | University of Information Technology">
  </a>
</p>
<h1 align="center"><b>IS211.Q22 & IS405.Q23 - CƠ SỞ DỮ LIỆU PHÂN TÁN & DỮ LIỆU LỚN</b></h1>

<p align="center">
  <img src="https://img.shields.io/badge/version-v0.1.2-0A7CC7?style=flat-square" alt="Version v0.1.2">
  <img src="https://img.shields.io/badge/Ubuntu-24.04_LTS-E95420?style=flat-square&logo=ubuntu&logoColor=white" alt="Ubuntu">
</p>

<p align="center">
  <!-- Nền tảng & điều phối -->
  <img src="https://img.shields.io/badge/K3s-v1.34.6-326CE5?style=flat-square&logo=kubernetes&logoColor=white" alt="K3s">
  <img src="https://img.shields.io/badge/Helm-v4.1.1-0F1689?style=flat-square&logo=helm&logoColor=white" alt="Helm">
  <img src="https://img.shields.io/badge/ArgoCD-v3.3-EF7B4D?style=flat-square&logo=argo&logoColor=white" alt="ArgoCD">
  <img src="https://img.shields.io/badge/Tailscale-v1.96.4-242424?style=flat-square&logo=tailscale&logoColor=white" alt="Tailscale">
</p>

<p align="center">
  <!-- Thu thập & truyền tải -->
  <img src="https://img.shields.io/badge/Vector-v0.45-10E7FF?style=flat-square&logoColor=white" alt="Vector">
  <img src="https://img.shields.io/badge/Redpanda-v26.1-E3402B?style=flat-square&logo=redpanda&logoColor=white" alt="Redpanda">
</p>

<p align="center">
  <!-- Xử lý luồng & lưu trữ -->
  <img src="https://img.shields.io/badge/RisingWave-v2.4-5B7FFF?style=flat-square&logoColor=white" alt="RisingWave">
  <img src="https://img.shields.io/badge/Apache_Iceberg-v2-3E5F8A?style=flat-square&logo=apache&logoColor=white" alt="Apache Iceberg">
  <img src="https://img.shields.io/badge/MinIO-latest-C72E49?style=flat-square&logo=minio&logoColor=white" alt="MinIO">
</p>

<p align="center">
  <!-- Giám sát -->
  <img src="https://img.shields.io/badge/VictoriaMetrics-v1.110-621773?style=flat-square&logoColor=white" alt="VictoriaMetrics">
  <img src="https://img.shields.io/badge/Grafana-v11.6-F46800?style=flat-square&logo=grafana&logoColor=white" alt="Grafana">
</p>

## BẢNG MỤC LỤC
* [Giới thiệu môn học](#giới-thiệu-môn-học)
* [Giới thiệu đồ án môn học](#giới-thiệu-đồ-án-môn-học)
* [Thành viên nhóm](#thành-viên-nhóm)
* [Hạ tầng máy chủ](#hạ-tầng-máy-chủ)
* [Cài đặt phần mềm](#cài-đặt-phần-mềm)
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

Đề tài thiết kế một kiến trúc **Data Lakehouse thời gian thực** vận hành trên cụm **Kubernetes (K3s)**, giải quyết bài toán **Zero-Downtime** khi cập nhật thuật toán phân tích luồng cho hệ thống giao thông thông minh. Hệ thống sử dụng tập dữ liệu **NYC TLC Trip Record Data**, với Vector giả lập luồng sự kiện vào Redpanda, RisingWave làm lõi tính toán streaming (JOIN với bảng TLC Taxi Zone trên MinIO), ghi xuống Apache Iceberg, và ArgoCD điều phối triển khai Blue/Green ở cấp Materialized View.

Chi tiết đề cương xem tại [docs/PROPOSE.md](./docs/PROPOSE.md).

Tài liệu liên quan:
- [docs/ARCHITECTURE.md](./docs/ARCHITECTURE.md) — Kiến trúc hệ thống, cấu trúc repo, yêu cầu chức năng & phi chức năng (FR/NFR), ràng buộc, quy ước Git.
- [docs/TIMELINE.md](./docs/TIMELINE.md) — Lộ trình thực hiện theo mốc thời gian, phân công, biểu đồ Gantt.
- [docs/SETUP.md](./docs/SETUP.md) — Hướng dẫn thiết lập hệ thống toàn diện (bootstrap K3s → chạy pipeline).
- [docs/SCRIPTS.md](./docs/SCRIPTS.md) — Tài liệu các script vận hành trong `scripts/` (cú pháp, argument, flags, cách dùng từ Windows).
- [docs/REPORT.md](./docs/REPORT.md) — Báo cáo tổng thể đồ án (nguồn để chuyển sang LaTeX).

---

## THÀNH VIÊN NHÓM
| STT |   MSSV   |           Họ và Tên |                                                      Github |                  Email |
|-----|:--------:|--------------------:|------------------------------------------------------------:|-----------------------:|
| 1   | 23521367 |         Ngô Tiến Sỹ |               [helios-ryuu](https://github.com/helios-ryuu) | 23521367@gm.uit.edu.vn |
| 2   | 23520982 |      Nguyễn Văn Nam |               [Sinister-VN](https://github.com/Sinister-VN) | 23520982@gm.uit.edu.vn |

---

## HẠ TẦNG MÁY CHỦ

Cụm gồm **4 máy** — 2 node chính luôn bật, 2 node phụ trợ bật khi cần burst hoặc stress test. Tất cả kết nối qua **Tailscale mesh VPN**.

| Tên node | Phần cứng | Hệ điều hành | Vai trò |
|----------|-----------|-------------|---------|
| **`continux-imac`** | iMac19,2 · Intel i5-8500 (6 cores) · 8 GB DDR4 · 200 GB SSD | Ubuntu Server 24.04 LTS (native) | K3s server #1 · Data plane (MinIO, Redpanda, RisingWave, Vector) |
| **`continux-vps`** | DigitalOcean Droplet $12→$24/mo · 1→2 vCPU · 2→4 GB RAM · 50→80 GB SSD · SGP1 | Ubuntu 24.04 LTS (native) | K3s server #2 · Control & observability plane (ArgoCD, VictoriaMetrics, Grafana) |
| **`helios`** | Laptop HP (HELIOS-PC) · Intel i5-12500H (12C) · 16 GB DDR5 4800 MHz · NVIDIA RTX 3050 Ti 4 GB | Windows 11 → **WSL2 Ubuntu 24.04** | K3s worker phụ trợ — bật khi burst hoặc thực nghiệm song song |
| **`nammn`** | Laptop HP (SINISTER) · AMD Ryzen 5 7640HS (8C) · 32 GB DDR5 5600 MHz · NVIDIA RTX 3050 6 GB | Windows 11 → **WSL2 Ubuntu 24.04** | K3s worker phụ trợ — bật khi iMac OOM hoặc cần > 10 k events/s |

Chi tiết thiết lập từng máy: [docs/SETUP.md](./docs/SETUP.md).

---

## CÀI ĐẶT PHẦN MỀM

Hướng dẫn chi tiết từng bước: [docs/SETUP.md](./docs/SETUP.md).

**Phiên bản công cụ tối thiểu (stable):**
- K3s ≥ v1.34.6 · Helm ≥ v4.1.1 · Argo CD ≥ v3.3 · RisingWave ≥ v2.4 · Redpanda ≥ v26.1 · Vector ≥ 0.45 · Tailscale ≥ 1.80.

---

## KHỞI CHẠY DỰ ÁN

**Các bước tổng quát:**
1. Khởi tạo cụm K3s (`continux-imac` làm server #1, `continux-vps` làm server #2) và cấu hình `kubectl`.
2. Cài đặt ArgoCD và đăng ký repository Git của dự án.
3. Triển khai hạ tầng nền: MinIO, Redpanda, RisingWave (trên `continux-imac`), VictoriaMetrics, Grafana (trên `continux-vps`) thông qua ArgoCD.
4. Tải bảng tham chiếu TLC Taxi Zone lên MinIO.
5. Khởi chạy Vector để phát luồng sự kiện NYC TLC vào Redpanda.
6. Đăng ký các Source, Sink và Materialized View Blue trên RisingWave.
7. Truy cập Grafana để giám sát Consumer Lag, throughput, latency.
8. *(Khi cần burst)* Join `helios` hoặc `nammn` vào cụm làm K3s worker qua WSL2.

---

## CÔNG NGHỆ SỬ DỤNG

**Nền tảng & điều phối:**
- **K3s / Kubernetes** — điều phối container trên cụm phân tán.
- **ArgoCD** — GitOps Continuous Delivery: Git là nguồn chân lý duy nhất.
- **Tailscale** — Mesh VPN mã hóa đầu-cuối, kết nối các node trên nhiều mạng khác nhau.

**Thu thập & truyền tải dữ liệu:**
- **Vector** — Đường ống dữ liệu hiệu năng cao (Rust), đóng vai trò load generator giả lập luồng sự kiện.
- **Redpanda** — Message Broker tương thích Kafka API, không JVM, không ZooKeeper.

**Xử lý luồng & lưu trữ:**
- **RisingWave** — Streaming Database xử lý SQL thời gian thực (Rust), hỗ trợ Blue/Green Materialized View Swap nguyên tử.
- **Apache Iceberg** — Table Format ACID, Time Travel, Schema Evolution trên Object Storage.
- **MinIO** — Object Storage tương thích S3: lưu Iceberg data, RisingWave checkpoint, TLC Taxi Zone.

**Giám sát:**
- **VictoriaMetrics** — Time-Series Database tiêu thụ ít tài nguyên.
- **Grafana** — Trực quan hóa 4 nhóm chỉ số: Streaming Perf, Resource, Cutover, Data Integrity.

**Dataset:**
- **NYC Taxi & Limousine Commission (TLC) Trip Record Data** — <https://registry.opendata.aws/nyc-tlc-trip-records-pds/>.
