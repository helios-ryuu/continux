# REQUIREMENT — YÊU CẦU CHỨC NĂNG & PHI CHỨC NĂNG

> **Dự án:** Real-Time Data Lakehouse Architecture for ITS on Kubernetes.
> **Nền tảng:** K3s (2 node) · ArgoCD · MinIO · Redpanda · RisingWave · Apache Iceberg · Vector · VictoriaMetrics · Grafana.
> **Dataset:** NYC TLC Trip Record Data + TLC Taxi Zone Lookup (265 zones).
> **Nguồn:** [PROPOSE.md](./PROPOSE.md). Các mã tham chiếu `FR-xx`, `NFR-xx` được dùng lại trong [WBS.md](./WBS.md) và [REPORT.md](./REPORT.md).

---

## 1. Quy ước

- **FR** = Functional Requirement (yêu cầu chức năng).
- **NFR** = Non-Functional Requirement (yêu cầu phi chức năng).
- **Priority:** `MUST` (bắt buộc) · `SHOULD` (rất nên có) · `COULD` (nếu còn thời gian).
- Mỗi yêu cầu đi kèm **tiêu chí nghiệm thu** (acceptance criteria) có thể đo đạc được.

---

## 2. Yêu cầu chức năng (Functional Requirements)

### 2.1. Nhóm Data Ingestion

| Mã | Yêu cầu | Priority | Tiêu chí nghiệm thu |
|----|---------|:--------:|---------------------|
| FR-01 | Hệ thống phải đọc file CSV/Parquet NYC TLC Trip Record làm nguồn dữ liệu. | MUST | Vector load được ≥ 1 file mẫu (≥ 1M records) từ volume gắn vào pod. |
| FR-02 | Hệ thống phải mô phỏng luồng sự kiện thời gian thực từ file tĩnh, điều chỉnh được throughput. | MUST | Vector publish được 1k → 20k events/s có thể cấu hình qua biến môi trường. |
| FR-03 | Hệ thống phải đẩy toàn bộ event vào topic Redpanda `nyc-taxi-events`. | MUST | Kafka consumer đọc lại đúng số lượng event do Vector publish. |
| FR-04 | Hệ thống phải lưu bảng tham chiếu TLC Taxi Zone (265 bản ghi) trên MinIO. | MUST | File CSV ở bucket `tlc-zone`, đọc được qua S3 API. |

### 2.2. Nhóm Stream Processing

| Mã | Yêu cầu | Priority | Tiêu chí nghiệm thu |
|----|---------|:--------:|---------------------|
| FR-05 | RisingWave phải khai báo `SOURCE` kết nối topic Redpanda. | MUST | `SELECT * FROM source LIMIT 10` trả về dữ liệu hợp lệ. |
| FR-06 | RisingWave phải khai báo `TABLE` đọc TLC Taxi Zone từ MinIO. | MUST | Table chứa đúng 265 bản ghi. |
| FR-07 | Hệ thống phải tạo Materialized View v1 (Blue) JOIN luồng sự kiện với Taxi Zone, tổng hợp theo Zone. | MUST | MV cập nhật liên tục, kết quả truy vấn phản ánh event mới nhất. |
| FR-08 | Hệ thống phải tạo Materialized View v2 (Green) với logic phân tích mới. | MUST | MV Green chạy song song Blue, không ảnh hưởng Blue. |
| FR-09 | Hệ thống phải ghi kết quả MV xuống Apache Iceberg (Built-in Hosted Catalog) trên MinIO. | MUST | Verify được file metadata + parquet trong bucket `iceberg-data`. |
| FR-10 | RisingWave phải offload state (checkpoint) xuống MinIO bucket `rw-checkpoint`. | MUST | Restart pod RisingWave → MV tiếp tục từ offset gần nhất, không mất state. |

### 2.3. Nhóm Blue/Green MV Swap & GitOps

| Mã | Yêu cầu | Priority | Tiêu chí nghiệm thu |
|----|---------|:--------:|---------------------|
| FR-11 | Toàn bộ SQL và manifest triển khai phải được quản lý trong Git repo duy nhất. | MUST | Repo chứa `gitops/`, ArgoCD trỏ vào repo đó. |
| FR-12 | ArgoCD phải tự động sync khi có commit mới trên nhánh quản lý. | MUST | Commit thử → ArgoCD detect & sync trong ≤ 3 phút. |
| FR-13 | Hệ thống phải phát hiện Green backfill hoàn tất dựa trên Consumer Lag. | MUST | Khi lag ≤ ngưỡng trong khoảng quan sát, trạng thái chuyển "READY". |
| FR-14 | Hệ thống phải thực hiện `ALTER MATERIALIZED VIEW ... SWAP WITH ...` nguyên tử khi Green sẵn sàng. | MUST | Sau swap, tên MV public trỏ về định nghĩa Green; Blue trở thành MV cũ chờ drop. |
| FR-15 | Hệ thống phải tự drop MV cũ sau khi swap thành công. | SHOULD | Sau khoảng retention định sẵn, MV cũ bị xoá; verify bằng `SHOW MATERIALIZED VIEWS`. |
| FR-16 | Kubernetes Job thực hiện swap phải chạy qua ArgoCD PostSync Hook. | MUST | Sync thành công → Job tự động tạo; log rõ trạng thái. |

### 2.4. Nhóm Monitoring & Observability

| Mã | Yêu cầu | Priority | Tiêu chí nghiệm thu |
|----|---------|:--------:|---------------------|
| FR-17 | VictoriaMetrics phải scrape metrics từ Redpanda, RisingWave, Vector, MinIO. | MUST | Query `up == 1` trả về đúng các service. |
| FR-18 | Grafana phải có 4 dashboard ứng với 4 nhóm chỉ số đánh giá. | MUST | Dashboard hiển thị: Streaming Perf, Resource, Cutover, Data Integrity. |
| FR-19 | Hệ thống phải ghi log sự kiện swap (start, ready, swapped, drop) để truy vết. | SHOULD | Log xem được qua `kubectl logs` hoặc Grafana Loki (nếu có). |

### 2.5. Nhóm Data Quality & Verification

| Mã | Yêu cầu | Priority | Tiêu chí nghiệm thu |
|----|---------|:--------:|---------------------|
| FR-20 | Hệ thống phải cho phép đếm số record đầu vào (Vector) vs đầu ra (Iceberg). | MUST | Query hoặc script thống kê trả ra số lượng hai đầu. |
| FR-21 | Hệ thống phải phát hiện duplicate record trong Iceberg theo `event_id`. | MUST | Query `GROUP BY event_id HAVING COUNT(*) > 1` có kết quả rõ ràng. |
| FR-22 | Hệ thống phải đo downtime thực tế khi swap. | MUST | Script polling query MV liên tục; báo thời điểm thất bại (nếu có). |

---

## 3. Yêu cầu phi chức năng (Non-Functional Requirements)

### 3.1. Hiệu năng (Performance)

| Mã | Yêu cầu | Mục tiêu | Ghi chú |
|----|---------|----------|---------|
| NFR-01 | Throughput pipeline end-to-end. | ≥ 5.000 events/s ổn định trên hạ tầng tham chiếu (NFR-12); mục tiêu kéo dãn (stretch) 10.000 events/s. | Đo ở FR-02/FR-09. Ngưỡng 5k/s phản ánh giới hạn 8 GB RAM của `continux-imac`. |
| NFR-02 | Độ trễ end-to-end (Vector → Iceberg). | P95 ≤ 5 giây ở mức tải mục tiêu. | |
| NFR-03 | Consumer Lag tối đa trong điều kiện thường. | ≤ 2 giây. | Spike khi backfill được chấp nhận. |

### 3.2. Độ tin cậy (Reliability)

| Mã | Yêu cầu | Mục tiêu |
|----|---------|----------|
| NFR-04 | **Zero-downtime khi swap MV.** | Downtime ≤ 1 giây (mục tiêu 0s). |
| NFR-05 | **Exactly-Once Semantics** xuyên suốt swap. | Tỉ lệ duplicate ≤ 0,01%; tỉ lệ loss ≤ 0,01%. |
| NFR-06 | Khả năng phục hồi sau khi pod RisingWave restart. | MV tiếp tục từ offset gần nhất, không mất state. |
| NFR-07 | Pipeline hoạt động liên tục ≥ 4h không crash ở tải mục tiêu. | Verify trong test end-to-end (FR-09). |

### 3.3. Khả năng vận hành & Quan sát (Operability)

| Mã | Yêu cầu | Mục tiêu |
|----|---------|----------|
| NFR-08 | Toàn bộ cấu hình được quản lý khai báo qua Git. | Không cấu hình thủ công trực tiếp trên cluster. |
| NFR-09 | Thay đổi thuật toán chỉ cần commit SQL; không cần lệnh thủ công. | Thời gian từ commit đến sync ≤ 3 phút. |
| NFR-10 | Dashboard Grafana hiển thị real-time (refresh ≤ 30s). | |
| NFR-11 | Hệ thống gợi ý cảnh báo (alert) khi Consumer Lag vượt ngưỡng. | SHOULD — cấu hình qua VictoriaMetrics alerting. |

### 3.4. Tài nguyên & Khả năng mở rộng (Resource & Scalability)

| Mã | Yêu cầu | Mục tiêu |
|----|---------|----------|
| NFR-12 | Chạy được trên cụm K3s 2 node hạ tầng tham chiếu: `continux-imac` (server #1, iMac Ubuntu 24.04, i5-8500 6 cores, 8 GB RAM, 200 GB SSD) + `continux-vps` (server #2, DigitalOcean Droplet $12/mo → $24/mo, 1 vCPU / 2 GB RAM → 2 vCPU / 4 GB RAM, SGP1), nối qua Tailscale mesh. | Không pod nào bị `OOMKilled` trong 4h chạy ổn định ở tải mục tiêu (NFR-01); không swap quá 20%. |
| NFR-13 | Mỗi thành phần có thể scale horizontally khi chuyển sang cụm lớn hơn. | Verified qua cấu hình `replicas` Helm. |
| NFR-14 | Dung lượng lưu trữ Iceberg không vượt quá dung tích MinIO dự kiến (≤ 50 GB cho cả đồ án). | Compact/retention được cấu hình. |

### 3.5. Bảo mật (Security)

| Mã | Yêu cầu | Mục tiêu |
|----|---------|----------|
| NFR-15 | Access key MinIO khác nhau cho Vector, RisingWave, ArgoCD. | Least-privilege IAM policy. |
| NFR-16 | Mọi secret trong repo Git được mã hoá (Sealed Secrets / SOPS). | COULD — ít nhất không commit plaintext. |
| NFR-17 | Dashboard Grafana & ArgoCD UI có xác thực tối thiểu username/password. | Không để mặc định / public. |

### 3.6. Khả năng bảo trì (Maintainability)

| Mã | Yêu cầu | Mục tiêu |
|----|---------|----------|
| NFR-18 | Repo tuân theo cấu trúc trong [STRUCTURE.md](./STRUCTURE.md). | Thành viên mới setup được trong ≤ 1 buổi. |
| NFR-19 | Mỗi phiên bản MV SQL lưu lịch sử qua Git; có changelog ngắn trong commit. | |
| NFR-20 | Tài liệu kỹ thuật cập nhật song song với code. | README + docs/ đồng bộ với phiên bản mới nhất. |

### 3.7. Tính tái lập (Reproducibility)

| Mã | Yêu cầu | Mục tiêu |
|----|---------|----------|
| NFR-21 | Cluster có thể dựng lại từ đầu bằng scripts + manifests trong repo. | Một lệnh `make bootstrap` (hoặc tương đương). |
| NFR-22 | Dataset dùng được từ nguồn công khai, ghi rõ snapshot/ngày tải. | Viết trong PROPOSE & REPORT. |

---

## 4. Ràng buộc (Constraints)

- **C-01:** Stack **JVM-free** — không dùng Flink/Kafka/ksqlDB JVM; chỉ Rust/C++ (RisingWave, Redpanda, Vector).
- **C-02:** Phải dùng RisingWave **Built-in Hosted Catalog** cho Iceberg (không triển khai catalog độc lập như Hive/Nessie).
- **C-03:** Mô phỏng luồng **bắt buộc qua Vector**, không dùng producer tùy chỉnh viết bằng Python/Java để tránh rò rỉ bộ nhớ.
- **C-04:** Triển khai **bắt buộc qua ArgoCD GitOps**; không `kubectl apply` thủ công ngoài bước bootstrap ban đầu.
- **C-05:** Toàn bộ dữ liệu Iceberg + checkpoint lưu trên **MinIO tự dựng** (trên `continux-imac`); không dùng S3 thật hoặc dịch vụ object storage trả phí.
- **C-06:** Mạng liên node bắt buộc đi qua **Tailscale overlay** (không expose cổng K3s API/Redpanda/MinIO ra public internet).
- **C-07:** Chi phí hạ tầng trả phí tối đa **$24/tháng** (một DigitalOcean Droplet); không thêm Managed Database / Load Balancer / Spaces.

---

## 5. Giả định (Assumptions)

- Hai node K3s kết nối mạng LAN ổn định ≥ 1 Gbps.
- GVHD sẵn sàng review tài liệu trong khoảng 15–19/04/2026.
- Dataset NYC TLC còn truy cập được trong thời gian dự án; nếu không, dùng bản snapshot đã tải sẵn.
- Nhóm có đủ quyền admin trên cả `continux-imac` (iMac Ubuntu) và `continux-vps` (DigitalOcean Droplet) + tài khoản Tailscale để lập mesh VPN.
- Droplet DigitalOcean duy trì tối thiểu trong suốt Giai đoạn 2–6 (13/04 → 31/05/2026); chi phí ước tính ≈ $12 × 1.7 tháng ≈ $20 (có thể tăng lên ~$40 nếu resize lên $24/mo cho giai đoạn thực nghiệm).

---

## 6. Ngoài phạm vi (Out of Scope)

- Triển khai multi-cluster / multi-region.
- Tích hợp mô hình Machine Learning trực tiếp trong MV.
- Ingest dữ liệu IoT thực tế (camera, GPS thời gian thực).
- Kiểm thử bảo mật xâm nhập (pentest) toàn diện.
- Tối ưu chi phí cloud (không áp dụng cho on-premise K3s).
