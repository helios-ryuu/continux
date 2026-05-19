# BÁO CÁO ĐỒ ÁN — XÂY DỰNG KIẾN TRÚC DATA LAKEHOUSE THỜI GIAN THỰC CHO HỆ THỐNG GIAO THÔNG THÔNG MINH TRÊN CỤM KUBERNETES

> **English title:** Building a Real-Time Data Lakehouse Architecture for Intelligent Transportation Systems on a Kubernetes Cluster.
> **Môn học:** IS211.Q22 — Cơ sở dữ liệu phân tán · IS405.Q23 — Dữ liệu lớn · HK2 2025–2026.
> **GVHD:** ThS. Nguyễn Hồ Duy Trí — trinhd@uit.edu.vn.
> **Nhóm thực hiện:** Ngô Tiến Sỹ (23521367) · Nguyễn Văn Nam (23520982).
> **Ghi chú:** Tài liệu này là **báo cáo nguồn dạng Markdown**; sẽ được chuyển sang LaTeX cho bản nộp cuối cùng. Cấu trúc bám sát IMRAD-adapted + phụ lục, đồng bộ với [PROPOSE.md](./PROPOSE.md), [ARCHITECTURE.md](./ARCHITECTURE.md), [TIMELINE.md](./TIMELINE.md).

---

## TÓM TẮT (Abstract)

**Tiếng Việt.** Báo cáo trình bày một kiến trúc Data Lakehouse thời gian thực triển khai trên cụm Kubernetes nhẹ (K3s) hai node, hướng tới hệ thống giao thông thông minh (ITS). Điểm khác biệt so với các công trình gần đây — đặc biệt là Ursa (VLDB 2025) — là tập trung giải bài toán **Zero-Downtime** khi cập nhật logic phân tích luồng: nhóm đề xuất cơ chế **Blue/Green Materialized View Swap ở cấp engine** kết hợp **GitOps qua ArgoCD**. Dữ liệu thử nghiệm là NYC TLC Trip Record; luồng sự kiện được mô phỏng bằng Vector, đưa qua Redpanda, xử lý bởi RisingWave (JOIN với bảng TLC Taxi Zone lưu trên MinIO) và ghi xuống Apache Iceberg. Hệ thống được đánh giá trên bốn nhóm chỉ số: Cutover & GitOps, Data Integrity & Exactly-Once, Streaming Performance, và Resource Utilization.

**English.** This report presents a real-time Data Lakehouse architecture deployed on a lightweight two-node Kubernetes (K3s) cluster, targeting Intelligent Transportation Systems. The novelty with respect to recent work — notably Ursa (VLDB 2025) — is addressing **Zero-Downtime** algorithm upgrades for live streams via an in-engine **Blue/Green Materialized View Swap** coordinated by **GitOps (ArgoCD)**. Using the NYC TLC Trip Record dataset, events are simulated by Vector, transported through Redpanda, joined with the TLC Taxi Zone lookup (MinIO) inside RisingWave, and persisted to Apache Iceberg. Four metric families are reported: Cutover & GitOps, Data Integrity & Exactly-Once, Streaming Performance, Resource Utilization.

**Từ khoá / Keywords:** Data Lakehouse, Streaming Database, RisingWave, Apache Iceberg, Redpanda, GitOps, ArgoCD, Blue/Green Deployment, Zero-Downtime, Exactly-Once, Kubernetes, K3s, Intelligent Transportation Systems.

---

## MỤC LỤC (sẽ tự sinh trong LaTeX)

- Chương 1 — Giới thiệu tổng quan
- Chương 2 — Cơ sở lý thuyết
- Chương 3 — Phương pháp & Kiến trúc hệ thống
- Chương 4 — Kết quả thực nghiệm
- Chương 5 — Thảo luận & Kết luận
- Tài liệu tham khảo
- Phụ lục A/B/C/D

---

## DANH MỤC HÌNH ẢNH (placeholder)

- Hình 3.1. Sơ đồ kiến trúc tổng thể (`docs/diagrams/architecture-overview.puml`).
- Hình 3.2. Sequence diagram Blue/Green Swap (`docs/diagrams/bluegreen-sequence.puml`).
- Hình 4.1. Throughput vs tải (events/s).
- Hình 4.2. End-to-end latency theo thời gian.
- Hình 4.3. Consumer Lag quanh khoảnh khắc Swap.
- Hình 4.4. CPU/Memory các pod trong Swap window.

## DANH MỤC BẢNG BIỂU (placeholder)

- Bảng 3.1. Thang đo & tiêu chí đánh giá (map về REQUIREMENT).
- Bảng 4.1. Kết quả Cutover (5 lần swap).
- Bảng 4.2. Kết quả Data Integrity.
- Bảng 4.3. Kết quả Streaming Performance.
- Bảng 4.4. Kết quả Resource Utilization.

## DANH MỤC TỪ VIẾT TẮT

ACID · CDC · CI/CD · GitOps · ITS · JVM · K8s / K3s · MV (Materialized View) · MQ (Message Queue) · OLAP · OLTP · P95/P99 · SDG · VLDB · WAL.

---

# CHƯƠNG 1 — GIỚI THIỆU TỔNG QUAN

## 1.1. Đặt vấn đề

Hệ thống giao thông thông minh (ITS) sản sinh dữ liệu luồng với khối lượng lớn và tần suất cao: mỗi giây hàng chục nghìn tín hiệu GPS, giao dịch thanh toán, cảm biến đèn giao thông. Kiến trúc **Data Lakehouse** truyền thống (Delta Lake, Iceberg, Hudi) thành công trong việc hợp nhất kho dữ liệu và hồ dữ liệu, hỗ trợ ACID trên Object Storage. Tuy nhiên, khi dữ liệu đến từ luồng thời gian thực, kiến trúc này bộc lộ một **điểm mù vận hành**: *làm thế nào cập nhật thuật toán phân tích đang chạy mà không làm gián đoạn dòng dữ liệu?*

## 1.2. Lý do chọn đề tài

Đề tài gắn với ba mục tiêu phát triển bền vững của Liên Hợp Quốc — **SDG 8** (tăng trưởng kinh tế bền vững), **SDG 9** (hạ tầng công nghiệp đổi mới), **SDG 11** (đô thị thông minh, bền vững). Về học thuật, đề tài xuất phát từ **khoảng trống vận hành** của bài báo Ursa (VLDB 2025): Ursa tối ưu cho việc ghi trực tiếp Kafka xuống Lakehouse nhưng chưa xử lý bài toán thay đổi logic phân tích không gián đoạn.

## 1.3. Mục tiêu nghiên cứu

1. Xây dựng kiến trúc Lakehouse streaming JVM-free trên cụm K3s 2 node.
2. Đề xuất & hiện thực cơ chế **Blue/Green Materialized View Swap** cấp engine (RisingWave) kết hợp GitOps (ArgoCD).
3. Đánh giá định lượng trên bốn nhóm chỉ số: Cutover, Data Integrity, Streaming Performance, Resource Utilization.

## 1.4. Đối tượng & Phạm vi

- **Đối tượng:** kiến trúc xử lý luồng cho dữ liệu giao thông, cụ thể là NYC TLC Trip Record.
- **Phạm vi:** cụm K3s 4 máy — `continux-imac` (iMac Ubuntu 24.04, 8 GB RAM) server #1 data plane; `continux-vps` (DigitalOcean Droplet $12→$24/mo, 2→4 GB RAM) server #2 observability/control plane; `helios` (i5-12500H, 16 GB, WSL2) và `nammn` (Ryzen 5 7640HS, 32 GB, WSL2) làm K3s worker khi cần burst; nối qua Tailscale overlay VPN; stack JVM-free; Built-in Hosted Catalog RisingWave cho Iceberg; không multi-tenant, không ML pipeline (xem [ARCHITECTURE.md §8](./ARCHITECTURE.md)).

## 1.5. Câu hỏi nghiên cứu / Giả thuyết

- **H1:** Có thể đạt Zero-Downtime (downtime ≤ 1s, mục tiêu 0s) khi hoán đổi MV Blue/Green cấp engine không?
- **H2:** Exactly-Once Semantics có được duy trì xuyên suốt quá trình swap xuống tầng Iceberg Sink không?
- **H3:** Consumer Lag có được kiểm soát ≤ 2s ở tải mục tiêu 10k events/s trên K3s 2 node không?

## 1.6. Đóng góp của đề tài

1. **Cơ chế Blue/Green MV Swap** khai thác `ALTER MATERIALIZED VIEW ... SWAP WITH ...` của RisingWave, bổ trợ bằng phát hiện readiness qua `consumer_lag`.
2. **Pipeline GitOps** (ArgoCD + PostSync Hook + Kubernetes Job) tự động hoá toàn bộ quá trình nâng cấp thuật toán phân tích.
3. **Bộ đo bốn nhóm chỉ số** tái lập được trên cụm hạn chế tài nguyên — minh chứng cho tính khả thi của kiến trúc ngay cả khi on-premise.

## 1.7. Cấu trúc báo cáo

Chương 2 trình bày cơ sở lý thuyết và khoảng trống nghiên cứu; Chương 3 đặc tả phương pháp và kiến trúc; Chương 4 báo cáo kết quả thực nghiệm; Chương 5 thảo luận, nêu hạn chế và hướng phát triển.

---

# CHƯƠNG 2 — CƠ SỞ LÝ THUYẾT

## 2.1. Kiến trúc Data Lakehouse

So sánh Data Warehouse (truy vấn nhanh, schema chặt, chi phí cao) vs Data Lake (rẻ, linh hoạt, thiếu ACID) vs Data Lakehouse (kế thừa ưu điểm hai bên). Giới thiệu **Apache Iceberg** như định dạng bảng mở hỗ trợ ACID, Time Travel, Schema Evolution trên Object Storage.

## 2.2. Stream Processing

Khái niệm Materialized View trong ngữ cảnh streaming, Stateful Processing, Checkpoint & State Offloading. Phân biệt micro-batch (Spark Structured Streaming) vs continuous (Flink, RisingWave).

## 2.3. Message Broker & Event Streaming

Kafka API, Redpanda (C++, không JVM, không ZooKeeper), offset, consumer group, consumer lag — đại lượng đo lường then chốt cho chương 4.

## 2.4. RisingWave — Streaming Database

- Viết bằng Rust, tách biệt Compute/Storage, state backend trên Object Storage (MinIO).
- Từ v2.x hỗ trợ **Built-in Iceberg Engine**: cho phép quản lý Checkpoint + Iceberg Snapshot trong cùng một giao dịch — nền tảng cho Exactly-Once.
- Cú pháp `ALTER MATERIALIZED VIEW ... SWAP WITH ...` là mấu chốt cho Blue/Green cấp engine.

## 2.5. Chiến lược Blue/Green

Blue/Green truyền thống làm ở **hạ tầng** (hai cụm/replica set song song, switch load balancer). Đề tài áp dụng ở **cấp cơ sở dữ liệu (in-engine)**: hai MV cùng tồn tại, swap nguyên tử tên public-facing. Ưu thế: không cần duplicate hạ tầng, giữ nguyên state offloaded.

## 2.6. GitOps & ArgoCD

Nguyên tắc Single Source of Truth, khai báo (declarative), auto-sync, PostSync Hook — cơ chế kích hoạt Job sau khi sync thành công, nơi logic swap được thực thi.

## 2.7. Tổng quan Ursa (VLDB 2025) & khoảng trống

Tóm tắt đóng góp Ursa: streaming-native ghi trực tiếp Kafka xuống Lakehouse, tối ưu chi phí và độ trễ. **Khoảng trống:** Ursa không mô tả cơ chế vận hành khi cập nhật thuật toán phân tích trên luồng đang chạy — điểm đề tài này lấp đầy.

## 2.8. Các công trình liên quan

- **Apache Flink + Kafka Streams + ksqlDB** — JVM-based, kill-and-restart là chuẩn khi đổi job, gây downtime.
- **Delta Live Tables (Databricks)** — hỗ trợ upgrade pipeline nhưng phụ thuộc hệ sinh thái đóng.
- **Materialize / ksqlDB** — có khái niệm stream/view nhưng chưa khai thác SWAP nguyên tử ở tầng engine kết hợp GitOps.

---

# CHƯƠNG 3 — PHƯƠNG PHÁP & KIẾN TRÚC HỆ THỐNG

## 3.1. Phương pháp nghiên cứu

Áp dụng **Design Science Research (DSR)**: (1) xác định vấn đề từ bài báo Ursa, (2) thiết kế artefact (kiến trúc + cơ chế Blue/Green), (3) hiện thực hoá trên K3s, (4) đánh giá thực nghiệm trên 4 nhóm chỉ số, (5) rút kinh nghiệm & hướng phát triển.

## 3.2. Nguồn dữ liệu

- **NYC TLC Trip Record Data** — tập dữ liệu mở, hàng triệu bản ghi/ngày.
- **TLC Taxi Zone Lookup** — 265 zone (LocationID → Zone Name, Borough), dùng làm bảng tham chiếu tĩnh trên MinIO.
- **Mô phỏng luồng:** Parquet NYC TLC được convert sang JSONL; Vector đọc JSONL → transform event-time → publish Redpanda topic `nyc-taxi-events`.

## 3.3. Kiến trúc tổng thể

```
┌────────┐   ┌──────────┐   ┌───────────────┐   ┌─────────────┐
│ Vector │ → │ Redpanda │ → │  RisingWave   │ → │   Iceberg   │
└────────┘   └──────────┘   │ JOIN w/ Zone  │   │   (MinIO)   │
                            │ (MV Blue/Gr.) │   └─────────────┘
                            └───────┬───────┘
                                    │ state
                                    ▼
                            ┌──────────────┐
                            │    MinIO     │
                            │ rw-checkpoint│
                            └──────────────┘

GitOps:  Git → ArgoCD → (Sync) → K8s Job (PostSync) → ALTER MV SWAP WITH
Monitor: All components → VictoriaMetrics → Grafana
```

(Phiên bản vector sẽ được render từ `docs/diagrams/architecture-overview.puml` — Hình 3.1.)

## 3.4. Chi tiết từng thành phần

| Thành phần | Vai trò | Lý do chọn |
|------------|---------|-------------|
| **Vector** | Trình tạo tải, đọc JSONL → Redpanda | Rust, nhẹ, phù hợp chạy trong pod tài nguyên giới hạn |
| **Redpanda** | Message Broker | Kafka API, không JVM/ZooKeeper, triển khai nhẹ trên K3s |
| **RisingWave** | Streaming Database (Compute) | Rust, state offloading, hỗ trợ `ALTER MV SWAP WITH`, Built-in Iceberg |
| **MinIO** | Object Storage | S3-compatible, on-premise, dùng chung cho Iceberg + checkpoint |
| **Apache Iceberg** | Table Format | ACID, Time Travel, tích hợp native với RisingWave |
| **ArgoCD** | GitOps CD | Sync tự động, PostSync Hook — đúng mẫu cho Blue/Green SQL |
| **VictoriaMetrics + Grafana** | Observability | Tiêu thụ ít tài nguyên, phù hợp K3s nhỏ |

## 3.5. Thiết kế Blue/Green MV Swap

**Flow (xem Hình 3.2 — sequence diagram):**

1. Developer commit SQL Green vào Git.
2. ArgoCD detect → Sync ConfigMap chứa SQL mới.
3. PostSync Hook kích hoạt Kubernetes Job `mv-swap-runner`.
4. Job gọi RisingWave `CREATE MATERIALIZED VIEW mv_..._green AS ...`.
5. Job poll metric `consumer_lag` → chờ Green đạt ngưỡng ready.
6. Job thực thi `ALTER MATERIALIZED VIEW mv_... SWAP WITH mv_..._green`.
7. Job drop MV cũ sau thời gian retention.

Mọi dashboard/consumer phía dưới chỉ query **bí danh public** `mv_zone_stats` — do đó swap nguyên tử giữ zero-downtime (H1).

## 3.6. Hạ tầng K3s & GitOps Pipeline

- Topology: 1 K3s server #1 `continux-imac` (iMac Ubuntu 24.04, i5-8500 6 cores, 8 GB RAM, 200 GB SSD) chạy data plane (Redpanda + RisingWave + MinIO + Vector); 1 K3s server #2 `continux-vps` (DigitalOcean Droplet, khởi đầu 1 vCPU, 2 GB RAM, 50 GB SSD — nâng lên 2 vCPU, 4 GB RAM khi cần) chạy control/observability (ArgoCD + VictoriaMetrics + Grafana).
- Mạng liên node: **Tailscale mesh VPN** (range `100.64.0.0/10`); K3s cấu hình `--flannel-iface=tailscale0`, `--node-ip=<tailscale-ip>` để đảm bảo mọi lưu lượng pod-to-pod đều được mã hoá và đi xuyên NAT không cần port-forward.
- ArgoCD App-of-Apps ở `gitops/apps/root-app.yaml` (xem [ARCHITECTURE.md §2](./ARCHITECTURE.md)).
- Helm charts cho từng thành phần, values đặt trong `config/*/helm-values.yaml`.

## 3.7. Hệ thống giám sát

Bốn dashboard Grafana tương ứng bốn nhóm chỉ số — xem `dashboards/*.json`. VictoriaMetrics scrape qua `vmagent`; job scrape định nghĩa trong `config/victoria-metrics/scrape-configs.yaml`.

## 3.8. Thiết kế thang đo & Tiêu chí đánh giá

| Nhóm | Chỉ số | Tham chiếu NFR |
|------|--------|----------------|
| Cutover & GitOps | Thời gian swap, thời gian phục hồi, downtime | NFR-04, NFR-09 |
| Data Integrity & Exactly-Once | Loss rate, duplicate rate, accuracy | NFR-05 |
| Streaming Performance | Throughput, latency P95, consumer lag | NFR-01, NFR-02, NFR-03 |
| Resource Utilization | CPU, Memory theo thời gian | NFR-12, NFR-13 |

---

# CHƯƠNG 4 — KẾT QUẢ THỰC NGHIỆM

## 4.1. Môi trường thực nghiệm

- **Phần cứng `continux-imac`:** iMac19,2 chạy Ubuntu Server 24.04.4 LTS · Intel i5-8500 (6 cores @ 4.1 GHz) · 8 GB DDR4 · 200 GB SSD · LAN 1 Gbps.
- **Phần cứng `continux-vps`:** DigitalOcean Droplet (Singapore `sgp1`) · khởi đầu gói **$12/mo** (1 vCPU, 2 GB RAM, 50 GB SSD, 2 TB/mo transfer) · nâng lên **$24/mo** (2 vCPU, 4 GB RAM, 80 GB SSD) khi cần · Ubuntu 24.04 LTS.
- **Liên kết mạng:** Tailscale 1.98.2+ mesh VPN (WireGuard) — K3s dùng `tailscale0` làm Flannel interface; độ trễ quan trắc giữa hai node: ~45–70 ms (VN ↔ SGP1).
- **CLI:** kubectl/helm/argocd/rpk/mc/psql cài trực tiếp trên `continux-imac`.
- **Phần mềm:** K3s v1.35.4+k3s1 · Helm v4.2.0 · Argo CD v3.4.2 (Helm chart `argo-cd` 9.5.14) · MinIO RELEASE.2025-08-13 · Redpanda v26.1 · RisingWave v2.4 · Vector 0.45 · VictoriaMetrics 1.110 · Grafana 11.6.

## 4.2. Kết quả Cutover & GitOps *(placeholder — sẽ điền sau giai đoạn 5)*

- Thời gian từ Git commit đến Swap hoàn tất (ArgoCD sync + backfill + ALTER): `TBD` giây (trung bình 5 lần).
- Downtime đo được: mục tiêu `0s`, ngưỡng chấp nhận `≤ 1s`.
- Thời gian backfill Green cho đến khi `consumer_lag ≤ 2s`: `TBD`.

## 4.3. Kết quả Data Integrity *(placeholder)*

- Tổng event Vector publish: `N_in` — Tổng record Iceberg: `N_out`.
- Duplicate rate: `TBD %` — Loss rate: `TBD %` — mục tiêu ≤ 0.01%.

## 4.4. Kết quả Streaming Performance *(placeholder)*

Biểu đồ throughput/latency/lag ở các mức tải 1k/5k/10k/20k events/s (xem Hình 4.1–4.3).

## 4.5. Kết quả Resource Utilization *(placeholder)*

Biểu đồ CPU/Memory theo thời gian, đặc biệt cửa sổ ±30s quanh khoảnh khắc Swap (Hình 4.4).

## 4.6. Tổng hợp đánh giá *(placeholder)*

Bảng đối chiếu kết quả đo vs mục tiêu NFR-01 đến NFR-14 → kết luận H1/H2/H3.

---

# CHƯƠNG 5 — THẢO LUẬN & KẾT LUẬN

## 5.1. Thảo luận kết quả

So sánh với khoảng trống Ursa: đề tài bổ sung tầng vận hành Zero-Downtime mà Ursa chưa đề cập. Thảo luận điểm mạnh của việc chọn **in-engine Blue/Green** thay vì infra-level (tiết kiệm tài nguyên, giữ state liên tục). Phân tích sự đánh đổi giữa độ tươi mới của Green (backfill lâu) và chi phí chạy song song.

## 5.2. Hạn chế

- Tài nguyên phần cứng giới hạn (`continux-imac` 8 GB + `continux-vps` 4 GB = 12 GB RAM tổng) — không thử nghiệm được tải trên ~10k events/s; mục tiêu thực tế là 5k events/s (xem NFR-01).
- Độ trễ xuyên quốc gia giữa hai node qua Tailscale (~50 ms) làm tăng nhẹ latency của metric scrape VictoriaMetrics — không ảnh hưởng data plane (nằm trọn trên `continux-imac`).
- Chưa test multi-tenant, chưa áp dụng cho IoT data nguồn thật.
- Dataset mô phỏng; throughput thực tế của ITS có thể khác.
- Không đo trên mạng WAN/multi-region.

## 5.3. Hướng phát triển

- Mở rộng multi-cluster (Karmada/Argo CD ApplicationSet) để kiểm chứng swap xuyên cụm.
- Tích hợp ML pipeline (streaming feature store) — MV Green mang feature mới.
- Thay Vector bằng nguồn IoT thực (MQTT/HTTP) cho Smart City.
- Áp dụng các chính sách compaction/retention của Iceberg để kéo dài thời gian chạy thực địa.

## 5.4. Kết luận

Báo cáo đã đề xuất, hiện thực hoá và đánh giá một kiến trúc Data Lakehouse thời gian thực lấp đầy khoảng trống vận hành của Ursa (VLDB 2025). **Blue/Green Materialized View Swap kết hợp GitOps** là đóng góp chính, chứng minh tính khả thi ngay trên cụm K3s 2 node với tài nguyên khiêm tốn. Kết quả bốn nhóm chỉ số (sẽ cập nhật ở bản final) kỳ vọng khẳng định ba giả thuyết H1–H3.

---

## TÀI LIỆU THAM KHẢO (APA 7th — ≥ 15 nguồn)

*(Danh sách sẽ hoàn thiện ở bước 6.6 (xem [TIMELINE.md](./TIMELINE.md)). Các nguồn chính đã xác định:)*

1. Guo, S., et al. (2025). *Ursa: A Lakehouse-Native Data Streaming Engine for Kafka.* PVLDB, 18. https://www.vldb.org/pvldb/vol18/p5184-guo.pdf
2. Apache Iceberg Documentation. https://iceberg.apache.org/docs/
3. RisingWave Labs. (2025). *RisingWave Documentation v2.x.* https://docs.risingwave.com/
4. Redpanda Data. (2025). *Redpanda Platform Documentation.* https://docs.redpanda.com/
5. Argo CD. (2025). *GitOps Continuous Delivery for Kubernetes.* https://argo-cd.readthedocs.io/
6. Vector.dev. (2025). *Vector Reference.* https://vector.dev/docs/
7. MinIO Inc. (2025). *MinIO Object Storage Documentation.* https://min.io/docs/
8. K3s.io. (2025). *Lightweight Kubernetes.* https://docs.k3s.io/
9. NYC Taxi & Limousine Commission. *Trip Record Data.* https://registry.opendata.aws/nyc-tlc-trip-records-pds/
10. VictoriaMetrics. (2025). *VictoriaMetrics Documentation.* https://docs.victoriametrics.com/
11. Grafana Labs. (2025). *Grafana Documentation.* https://grafana.com/docs/
12. Humble, J., & Farley, D. (2010). *Continuous Delivery.* Addison-Wesley.
13. Kleppmann, M. (2017). *Designing Data-Intensive Applications.* O'Reilly.
14. Armbrust, M., et al. (2021). *Lakehouse: A New Generation of Open Platforms That Unify Data Warehousing and Advanced Analytics.* CIDR.
15. Zaharia, M., et al. (2013). *Discretized Streams: Fault-Tolerant Streaming Computation at Scale.* SOSP.

---

## PHỤ LỤC

### Phụ lục A — Mã nguồn SQL (Blue/Green)

Trích từ `sql/03-mv/mv_zone_stats_blue.sql` và `sql/03-mv/mv_zone_stats_green.sql`.

### Phụ lục B — Cấu hình YAML

Trích từ `gitops/apps/root-app.yaml`, `gitops/pipeline/swap-job.yaml`, `pipelines/vector/vector.toml`.

### Phụ lục C — Ảnh chụp Grafana Dashboard

4 dashboard xuất PNG từ `dashboards/*.json`.

### Phụ lục D — Bảng thuật ngữ chi tiết

Kế thừa từ mục "PHỤ LỤC — THUẬT NGỮ" của [PROPOSE.md](./PROPOSE.md), bổ sung các thuật ngữ mới phát sinh trong báo cáo (MV Swap, PostSync Hook, Consumer Lag Readiness, v.v.).
