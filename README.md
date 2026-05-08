<p align="center">
  <a href="https://www.uit.edu.vn/" title="Trường Đại học Công nghệ Thông tin">
    <img src="https://i.imgur.com/WmMnSRt.png" alt="Trường Đại học Công nghệ Thông tin | University of Information Technology">
  </a>
</p>
<h1 align="center"><b>IS211.Q22 & IS405.Q23 - CƠ SỞ DỮ LIỆU PHÂN TÁN & DỮ LIỆU LỚN</b></h1>

<p align="center">
  <img src="https://img.shields.io/badge/version-v0.1.1-0A7CC7?style=flat-square" alt="Version v0.1.1">
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
- [docs/REPORT.md](./docs/REPORT.md) — Báo cáo tổng thể đồ án (nguồn để chuyển sang LaTeX).
- [docs/REQUIREMENT.md](./docs/REQUIREMENT.md) — Yêu cầu chức năng & phi chức năng.
- [docs/STRUCTURE.md](./docs/STRUCTURE.md) — Cấu trúc thư mục dự án đề xuất.
- [docs/TIMELINE.md](./docs/TIMELINE.md) — Lộ trình thực hiện theo mốc thời gian.
- [docs/WBS.md](./docs/WBS.md) — Work Breakdown Structure chi tiết.
- [docs/SETUP.md](./docs/SETUP.md) — Hướng dẫn thiết lập hệ thống toàn diện (bootstrap K3s → chạy pipeline).

---

## THÀNH VIÊN NHÓM
| STT |   MSSV   |           Họ và Tên |                                                      Github |                  Email |
|-----|:--------:|--------------------:|------------------------------------------------------------:|-----------------------:|
| 1   | 23521367 |         Ngô Tiến Sỹ |               [helios-ryuu](https://github.com/helios-ryuu) | 23521367@gm.uit.edu.vn |
| 2   | 23520982 |      Nguyễn Văn Nam |               [Sinister-VN](https://github.com/Sinister-VN) | 23520982@gm.uit.edu.vn |

---

## CÀI ĐẶT PHẦN MỀM

> *Hướng dẫn chi tiết sẽ được cập nhật trong quá trình triển khai.*

**Hạ tầng tham chiếu (đã triển khai):**
- **`continux-imac`** — iMac19,2 Ubuntu Server 24.04 LTS · Intel i5-8500 (6 cores) · 8 GB DDR4 · 200 GB SSD. Vai trò: K3s server chính (control-plane #1) + data plane (MinIO, Redpanda, RisingWave, Vector).
- **`continux-vps`** — DigitalOcean Droplet gói **$12/mo** (1 vCPU · 2 GB RAM · 50 GB SSD · 2 TB transfer, nâng lên $24/mo khi cần) · Ubuntu 24.04 LTS. Vai trò: K3s server phụ (control-plane #2) + control/observability plane (ArgoCD, VictoriaMetrics, Grafana).
- **Mạng liên node:** Tailscale mesh VPN (K3s dùng IP range `100.64.0.0/10`).


**Phiên bản công cụ tối thiểu:**
- K3s ≥ v1.34.6 · Helm ≥ v4.1.1 · Argo CD ≥ v3.3 · RisingWave ≥ v2.4 · Redpanda ≥ v26.1 · Vector ≥ 0.45 · Tailscale ≥ 1.80.

Hướng dẫn thiết lập chi tiết: [docs/SETUP.md](./docs/SETUP.md).

---

## KHỞI CHẠY DỰ ÁN

> *Chi tiết các bước khởi chạy sẽ được cập nhật khi hệ thống hoàn thiện.*

**Các bước tổng quát dự kiến:**
1. Khởi tạo cụm K3s và cấu hình `kubectl`.
2. Cài đặt ArgoCD và đăng ký repository Git của dự án.
3. Triển khai hạ tầng nền: MinIO, Redpanda, RisingWave, VictoriaMetrics, Grafana thông qua ArgoCD.
4. Tải bảng tham chiếu TLC Taxi Zone lên MinIO.
5. Khởi chạy Vector để phát luồng sự kiện NYC TLC vào Redpanda.
6. Đăng ký các Source, Sink và Materialized View trên RisingWave.
7. Truy cập Grafana để giám sát các chỉ số hiệu năng, độ trễ và Consumer Lag.

---

## CÔNG NGHỆ SỬ DỤNG

**Nền tảng & điều phối:**
- **K3s / Kubernetes** — điều phối container.
- **ArgoCD** — GitOps Continuous Delivery.

**Thu thập & truyền tải dữ liệu:**
- **Vector** — trình tạo tải và đường ống dữ liệu hiệu năng cao (Rust).
- **Redpanda** — Message Broker tương thích Kafka API.

**Xử lý luồng & lưu trữ:**
- **RisingWave** — Streaming Database xử lý SQL thời gian thực (Rust).
- **Apache Iceberg** — Table Format hỗ trợ ACID, Time Travel, Schema Evolution.
- **MinIO** — Object Storage tương thích S3, làm nền tảng cho Data Lakehouse và Shared-Storage cho Checkpoint.

**Giám sát:**
- **VictoriaMetrics** — Time-Series Database tiêu thụ ít tài nguyên.
- **Grafana** — Trực quan hóa các chỉ số vận hành.

**Dataset:**
- **NYC Taxi & Limousine Commission (TLC) Trip Record Data** — <https://registry.opendata.aws/nyc-tlc-trip-records-pds/>.
