# WBS — WORK BREAKDOWN STRUCTURE

> **Dự án:** Real-Time Data Lakehouse Architecture for ITS on Kubernetes.
> **Cơ sở:** [TIMELINE.md](./TIMELINE.md) — mọi WBS Package đều ánh xạ ngược về các mốc M1–M7.
> **Quy ước mã:** `1.2.3` = Giai đoạn.Gói công việc.Nhiệm vụ con.

---

## 0. Tổng quan phân rã

```
Đồ án (ROOT)
├── 1. Chuẩn bị tài liệu & đề cương        (05/04 → 19/04)
├── 2. Hạ tầng K3s & GitOps                 (13/04 → 24/04)
├── 3. Pipeline dữ liệu & MV Blue           (22/04 → 03/05)
├── 4. Blue/Green MV Swap + GitOps          (02/05 → 12/05)
├── 5. Thực nghiệm & Thu thập kết quả       (11/05 → 22/05)
└── 6. Viết báo cáo & Nộp                   (16/05 → 31/05)
```

---

## 1. Chuẩn bị tài liệu & đề cương  `M1 → M2`  ✓

### 1.1. Thống nhất phạm vi đề tài
- 1.1.1 Rà soát đề cương hiện tại, liệt kê câu hỏi mở cho GVHD.
- 1.1.2 Họp GVHD, chốt scope, mục tiêu, tiêu chí đánh giá.
- 1.1.3 Cập nhật [PROPOSE.md](./PROPOSE.md) nếu cần điều chỉnh sau họp.
- **Kết quả:** biên bản phê duyệt của GVHD.

### 1.2. Nghiên cứu nền tảng lý thuyết
- 1.2.1 Đọc kỹ Ursa (VLDB 2025), ghi chú khoảng trống nghiên cứu.
- 1.2.2 Tổng hợp tài liệu về Lakehouse, Apache Iceberg, RisingWave, Blue/Green.
- 1.2.3 Dựng thư mục `references/` lưu PDF + chú thích.
- **Kết quả:** bản tóm tắt lý thuyết (nháp Chương 2).

### 1.3. Viết REQUIREMENT.md
- 1.3.1 Liệt kê yêu cầu chức năng (FR) theo luồng: ingest → stream → sink → swap → monitor.
- 1.3.2 Xác định yêu cầu phi chức năng (NFR): hiệu năng, độ tin cậy, bảo mật, khả năng vận hành.
- 1.3.3 Tiêu chí nghiệm thu cho từng yêu cầu.
- **Kết quả:** [REQUIREMENT.md](./REQUIREMENT.md).

### 1.4. Thiết kế kiến trúc & STRUCTURE.md
- 1.4.1 Vẽ sơ đồ kiến trúc tổng thể (logical + deployment).
- 1.4.2 Đặc tả cấu trúc repo GitOps + source code.
- 1.4.3 Chuẩn hóa naming convention cho manifests, SQL, scripts.
- **Kết quả:** [STRUCTURE.md](./STRUCTURE.md).

### 1.5. Hoàn thiện TIMELINE.md & WBS.md
- 1.5.1 Rà lại thứ tự phụ thuộc giữa các gói.
- 1.5.2 Xác nhận phân công: Sỹ phụ trách toàn bộ, Nam hỗ trợ review.
- 1.5.3 Khóa mốc 19/04 (Document Freeze).

### 1.6. Review cuối với GVHD — **Document Freeze M2**
- 1.6.1 Gửi bản nháp trước 15/04.
- 1.6.2 Nhận góp ý, chỉnh sửa lần cuối.
- 1.6.3 Chốt toàn bộ tài liệu đề cương vào 19/04.

---

## 2. Hạ tầng K3s & GitOps  `→ M3`

### 2.0. Tailscale mesh (prereq)  ✓
- 2.0.1 Tạo tài khoản Tailscale (miễn phí) + tailnet chung cho nhóm.
- 2.0.2 Cài Tailscale trên iMac (`continux-imac`) và Droplet (`continux-vps`); `tailscale up --ssh`.
- 2.0.3 Verify ping qua IP `100.x.x.x` giữa hai máy; ghi lại IP Tailscale để dùng ở bước 2.1.

### 2.1. Cluster K3s (v1.32+)  ✓
- 2.1.1 Tạo DigitalOcean Droplet Ubuntu 24.04 LTS, plan **$12/mo** (1 vCPU, 2 GB RAM, 50 GB SSD, SGP1); user non-root `continux`. Nâng lên $24/mo (2 vCPU, 4 GB RAM) khi deploy full observability stack.
- 2.1.2 Chuẩn bị iMac (`continux-imac`, Ubuntu 24.04 đã cài sẵn) — tắt swap, bật IP forwarding, `ufw` allow `100.64.0.0/10`.
- 2.1.3 Cài K3s server trên iMac với `--flannel-iface=tailscale0`, `--node-ip=<tailscale-ip>`.
- 2.1.4 Join Droplet làm K3s agent qua IP Tailscale.
- 2.1.5 Cài `helm 4.1+` + các CLI trên `continux-imac` (`kubectl` có sẵn qua K3s).
- 2.1.6 Gán label `role=data-plane` cho `continux-imac`, `role=control-plane` + taint `dedicated=edge:NoSchedule` cho `continux-vps`.
- 2.1.7 Verify networking (Flannel qua Tailscale), DNS nội bộ, StorageClass `local-path`.

### 2.2. ArgoCD & GitOps repo
- 2.2.1 Helm install ArgoCD vào namespace `argocd`.
- 2.2.2 Tạo GitHub repo chứa manifests (folder `gitops/`).
- 2.2.3 Đăng ký repo vào ArgoCD, cấu hình sync policy.
- 2.2.4 Tạo App-of-Apps pattern để quản lý thành phần con.

### 2.3. MinIO (Object Storage)
- 2.3.1 Deploy MinIO qua Helm, expose service nội bộ.
- 2.3.2 Tạo bucket `iceberg-data`, `rw-checkpoint`, `tlc-zone`.
- 2.3.3 Tạo access key/secret riêng cho từng service (least-privilege).

### 2.4. Redpanda (Message Broker)
- 2.4.1 Deploy Redpanda qua Helm với replication=1 (K3s 2 node).
- 2.4.2 Tạo topic `nyc-taxi-events`, cấu hình retention.
- 2.4.3 Verify bằng `rpk` từ máy client.

### 2.5. RisingWave (Streaming DB)
- 2.5.1 Deploy RisingWave v2.4+ qua Helm.
- 2.5.2 Cấu hình state backend trỏ vào `rw-checkpoint` (MinIO).
- 2.5.3 Cấu hình kết nối Redpanda source; bật Built-in Hosted Catalog Iceberg.
- 2.5.4 Kiểm tra kết nối bằng `psql`.

### 2.6. VictoriaMetrics + Grafana
- 2.6.1 Deploy VictoriaMetrics (single-node đủ cho đồ án).
- 2.6.2 Cài `vmagent` scrape metrics từ tất cả service trên.
- 2.6.3 Deploy Grafana, kết nối data source VictoriaMetrics.
- 2.6.4 Tạo 4 dashboard: Streaming Perf / Resource / Cutover / Data Integrity.

---

## 3. Pipeline dữ liệu & Materialized View Blue  `→ M4`

### 3.1. Chuẩn bị dataset
- 3.1.1 Tải NYC TLC Trip Record (Parquet tháng mẫu).
- 3.1.2 Upload TLC Taxi Zone Lookup (CSV, 265 bản ghi) vào bucket `tlc-zone`.
- 3.1.3 Chuẩn hóa schema (timestamp, locationID, fare, distance, …).

### 3.2. Vector Load Generator
- 3.2.1 Viết `vector.toml`: source = CSV file, transform = mô phỏng event-time, sink = Redpanda.
- 3.2.2 Thêm biến môi trường điều chỉnh throughput (events/s).
- 3.2.3 Triển khai Vector như DaemonSet / Deployment trên K3s.

### 3.3. SQL khai báo Source & Table tham chiếu
- 3.3.1 `CREATE SOURCE` đọc topic Redpanda, schema JSON.
- 3.3.2 `CREATE TABLE` từ CSV MinIO cho TLC Taxi Zone.
- 3.3.3 Viết query thử JOIN đơn giản để verify.

### 3.4. Materialized View v1 — **Blue**
- 3.4.1 Thiết kế aggregation theo Zone: số chuyến, tổng fare, avg distance.
- 3.4.2 Viết SQL `CREATE MATERIALIZED VIEW mv_zone_stats_blue`.
- 3.4.3 Commit SQL vào repo GitOps, ArgoCD sync.
- 3.4.4 Verify output qua `SELECT` và Grafana.

### 3.5. Iceberg Sink
- 3.5.1 Cấu hình sink ghi xuống bucket `iceberg-data` với Built-in Hosted Catalog.
- 3.5.2 Định nghĩa partitioning theo `pickup_date`, `borough`.
- 3.5.3 Verify file Iceberg (metadata + data) trên MinIO.

### 3.6. Test end-to-end
- 3.6.1 Chạy pipeline liên tục 2–4h.
- 3.6.2 Check Consumer Lag, độ trễ end-to-end, lỗi.
- 3.6.3 So khớp tổng số event Vector phát vs số dòng trong Iceberg.

---

## 4. Blue/Green MV Swap + GitOps Automation  `→ M5`

### 4.1. Materialized View v2 — **Green**
- 4.1.1 Thiết kế logic phân tích mới (ví dụ: thêm aggregation theo giờ).
- 4.1.2 Viết SQL `CREATE MATERIALIZED VIEW mv_zone_stats_green`.
- 4.1.3 Chạy song song Blue; quan sát trạng thái backfill.

### 4.2. Phát hiện Green backfill hoàn tất
- 4.2.1 Điều tra metric `consumer_lag` của RisingWave.
- 4.2.2 Script Python/Go query Prometheus API để kiểm tra lag ≤ ngưỡng.
- 4.2.3 Định nghĩa điều kiện "ready": lag giữ ≤ N giây trong M phút liên tiếp.

### 4.3. Kubernetes Job thực hiện Atomic Swap
- 4.3.1 Docker image chứa `psql` + script kiểm tra readiness.
- 4.3.2 Manifest `Job` nhận tham số tên MV Blue/Green, timeout.
- 4.3.3 Logic: chờ ready → `ALTER MATERIALIZED VIEW ... SWAP WITH ...` → drop MV cũ.

### 4.4. ArgoCD PostSync Hook
- 4.4.1 Chuyển MV SQL thành template Helm/Kustomize.
- 4.4.2 Đánh dấu Job bằng annotation `argocd.argoproj.io/hook: PostSync`.
- 4.4.3 Test Sync thủ công; kiểm tra lịch sử hook trong ArgoCD UI.

### 4.5. Luồng GitOps end-to-end
- 4.5.1 Commit SQL phiên bản mới vào Git.
- 4.5.2 ArgoCD tự sync → tạo MV Green → Job chạy → Swap.
- 4.5.3 Verify 0s downtime: query liên tục suốt quá trình swap.
- 4.5.4 Verify không mất/trùng dữ liệu trong Iceberg.

---

## 5. Thực nghiệm & Thu thập kết quả  `→ M6`

### 5.1. Exactly-Once qua Swap
- 5.1.1 Chạy swap 5 lần, mỗi lần đếm record Iceberg trước/sau.
- 5.1.2 So khớp với số event do Vector phát ra (ground truth).
- 5.1.3 Ghi nhận bất kỳ sai số nào và nguyên nhân.

### 5.2. Streaming Performance
- 5.2.1 Đo throughput (events/s) ở các mức tải 1k/5k/10k/20k/s.
- 5.2.2 Đo end-to-end latency (thời gian từ Vector phát đến Iceberg sink).
- 5.2.3 Đo Consumer Lag ở từng mức tải.

### 5.3. Cutover Metrics
- 5.3.1 Đo thời gian từ commit Git đến lúc Swap hoàn tất.
- 5.3.2 Đo downtime khi swap (phải ≈ 0s).
- 5.3.3 Đo thời gian phục hồi trạng thái (backfill) của Green.

### 5.4. Data Integrity
- 5.4.1 `SELECT COUNT(*)` Iceberg vs số event Vector.
- 5.4.2 Tìm duplicate (GROUP BY event_id HAVING COUNT > 1).
- 5.4.3 Tính tỉ lệ loss / duplicate / accuracy.

### 5.5. Resource Utilization
- 5.5.1 Thu thập CPU/RAM của từng pod trước/trong/sau swap.
- 5.5.2 Export biểu đồ Grafana dạng PNG cho báo cáo.
- 5.5.3 Tính peak vs baseline.

### 5.6. Tổng hợp kết quả
- 5.6.1 Bảng tổng kết 4 nhóm chỉ số so với mục tiêu.
- 5.6.2 Biểu đồ đường / cột cho Chương 4.
- 5.6.3 Đóng gói dữ liệu thô (CSV) làm phụ lục.

---

## 6. Viết báo cáo & Nộp  `→ M7`

### 6.1. Chương 1 — Giới thiệu
- 6.1.1 Đặt vấn đề ITS + lý do đề tài (liên hệ SDG 8/9/11).
- 6.1.2 Mục tiêu, phạm vi, câu hỏi nghiên cứu.
- 6.1.3 Đóng góp & cấu trúc báo cáo.

### 6.2. Chương 2 — Cơ sở lý thuyết
- 6.2.1 Lakehouse, Iceberg, Stream Processing.
- 6.2.2 RisingWave, Redpanda, MV, ACID trên Object Storage.
- 6.2.3 Blue/Green, GitOps/ArgoCD, tóm tắt Ursa + khoảng trống.

### 6.3. Chương 3 — Phương pháp & Kiến trúc
- 6.3.1 Design Science Research.
- 6.3.2 Sơ đồ kiến trúc tổng thể + chi tiết từng thành phần.
- 6.3.3 Flow Blue/Green Swap; thiết kế thang đo.

### 6.4. Chương 4 — Kết quả thực nghiệm
- 6.4.1 Môi trường thực nghiệm (phần cứng + phần mềm).
- 6.4.2 4 mục con ứng với 4 nhóm chỉ số, mỗi mục có bảng + biểu đồ.
- 6.4.3 Tổng hợp đánh giá.

### 6.5. Chương 5 — Thảo luận & Kết luận
- 6.5.1 So sánh với Ursa; phân tích điểm mạnh/yếu kiến trúc.
- 6.5.2 Hạn chế (tài nguyên, phạm vi, multi-tenant).
- 6.5.3 Hướng phát triển; kết luận đóng góp.

### 6.6. Abstract, TLTK, Phụ lục
- 6.6.1 Abstract VI + EN (viết sau cùng).
- 6.6.2 Tài liệu tham khảo APA ≥ 15 nguồn.
- 6.6.3 Phụ lục A (SQL), B (YAML), C (Grafana), D (thuật ngữ).

### 6.7. Rà soát & Nộp
- 6.7.1 Rà format, citation, đánh số hình/bảng.
- 6.7.2 Nhờ GVHD review bản gần cuối (28–30/05).
- 6.7.3 **Nộp báo cáo + demo hệ thống trực tiếp ngày 31/05/2026.**

---

## 7. Ma trận trách nhiệm (RACI rút gọn)

| Gói WBS | Sỹ (23521367) | Nam (23520982) | GVHD |
|---------|:-------------:|:--------------:|:----:|
| 1.1 Scope | A/R | C | C/A |
| 1.2 Literature | A/R | C | C |
| 1.3 REQUIREMENT | A/R | C | I |
| 1.4 STRUCTURE | A/R | C | I |
| 1.5 TIMELINE/WBS | A/R | C | C |
| 1.6 Freeze | A/R | C | A |
| 2.1 K3s | A/R | C | I |
| 2.2 ArgoCD | A/R | C | I |
| 2.3 MinIO | A/R | C | I |
| 2.4 Redpanda | A/R | C | I |
| 2.5 RisingWave | A/R | C | I |
| 2.6 VM+Grafana | A/R | C | I |
| 3.x Pipeline Blue | A/R | C | I |
| 4.x Blue/Green | A/R | C | I |
| 5.x Thực nghiệm | A/R | C | I |
| 6.x Báo cáo | A/R | C | A |

Ký hiệu: **R** = Responsible · **A** = Accountable · **C** = Consulted · **I** = Informed.
