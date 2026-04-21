# TIMELINE — LỘ TRÌNH THỰC HIỆN ĐỒ ÁN

> **Đề tài:** Xây dựng kiến trúc Data Lakehouse thời gian thực cho hệ thống giao thông thông minh trên cụm Kubernetes.
> **Khoảng thời gian:** 05/04/2026 → 31/05/2026 (≈ 8 tuần).
> **Mốc tài liệu (document freeze):** 19/04/2026 — toàn bộ tài liệu đề cương, REQUIREMENT, STRUCTURE, TIMELINE, WBS phải được chốt với GVHD trước ngày này.
> **Deadline cuối cùng:** 31/05/2026 — nộp báo cáo + demo hệ thống.

---

## 1. Nguyên tắc lập lịch

- **Song song hóa tài liệu & hạ tầng:** từ 13/04, trong khi tài liệu còn đang hoàn thiện, nhóm bắt đầu setup cluster K3s để kịp mốc tài liệu 19/04 mà không chậm tiến độ kỹ thuật.
- **Gối đầu (overlap) giữa các giai đoạn:** giai đoạn sau bắt đầu 2–3 ngày trước khi giai đoạn trước kết thúc, nhằm hấp thụ rủi ro và tận dụng thời gian chờ (verify, stress test).
- **Hai luồng song song ở cuối:** từ 16/05, luồng thực nghiệm và luồng viết báo cáo chạy đồng thời — kết quả đo đến đâu, viết Chương 4 đến đó.
- **Phân công:** Sỹ (23521367) đảm nhận toàn bộ công việc chính; Nam (23520982) hỗ trợ một số nhiệm vụ cụ thể (xem [WBS.md](./WBS.md)).

---

## 2. Các mốc lớn (Milestones)

| #  | Mốc | Ngày | Tiêu chí hoàn thành | Trạng thái |
|----|-----|------|----------------------|------------|
| M1 | **Chốt scope & đề cương với GVHD** | 08/04/2026 | GVHD phê duyệt phạm vi, bài toán, kiến trúc sơ bộ | ✓ Xong |
| M2 | **Document Freeze** | 19/04/2026 | PROPOSE, REQUIREMENT, STRUCTURE, TIMELINE, WBS đã review | ✓ Xong |
| M3 | **Cluster & hạ tầng sẵn sàng** | 24/04/2026 | K3s + ArgoCD + MinIO + Redpanda + RisingWave + VM/Grafana chạy ổn định | 🔄 Đang làm (còn 2.3–2.6) |
| M4 | **Pipeline Blue (MV v1) hoạt động end-to-end** | 03/05/2026 | Vector → Redpanda → RisingWave (JOIN Zone) → Iceberg chạy 4h liên tục không lỗi |
| M5 | **Blue/Green Swap qua GitOps thành công** | 12/05/2026 | Commit SQL mới → ArgoCD sync → Atomic Swap 0s downtime, không mất/trùng dữ liệu |
| M6 | **Bộ số liệu thực nghiệm hoàn chỉnh** | 22/05/2026 | 4 nhóm chỉ số đã đo, tổng hợp bảng biểu/biểu đồ |
| M7 | **Nộp báo cáo + demo hệ thống** | 31/05/2026 | File báo cáo final + demo trực tiếp trên cluster |

---

## 3. Sáu giai đoạn chi tiết

### Giai đoạn 1 — Chuẩn bị tài liệu & đề cương (05/04 → 19/04) ✓

| # | Công việc | Bắt đầu | Kết thúc | Phụ trách | Ghi chú |
|---|-----------|---------|----------|-----------|---------|
| 1.1 | Rà soát đề cương, chốt scope & mục tiêu với GVHD | 05/04 | 08/04 | Sỹ | ✓ Mốc M1 |
| 1.2 | Đọc kỹ Ursa (VLDB 2025), tổng hợp lý thuyết Lakehouse Streaming | 05/04 | 10/04 | Sỹ | ✓ |
| 1.3 | Viết REQUIREMENT.md (functional + non-functional) | 08/04 | 12/04 | Sỹ | ✓ |
| 1.4 | Thiết kế kiến trúc tổng thể + STRUCTURE.md | 10/04 | 14/04 | Sỹ | ✓ |
| 1.5 | Hoàn thiện TIMELINE.md & WBS.md | 12/04 | 15/04 | Sỹ | ✓ |
| 1.6 | Review toàn bộ tài liệu với GVHD — **Document Freeze** | 16/04 | 19/04 | Sỹ | ✓ **Mốc M2** |

### Giai đoạn 2 — Hạ tầng K3s & GitOps (13/04 → 24/04) 🔄

| # | Công việc | Bắt đầu | Kết thúc | Phụ trách | Ghi chú |
|---|-----------|---------|----------|-----------|---------|
| 2.0 | Tạo DigitalOcean Droplet ($12/mo, nâng lên $24/mo khi cần) + cài Tailscale trên iMac và Droplet, lập mesh VPN | 13/04 | 14/04 | Sỹ | ✓ |
| 2.1 | Cài K3s cluster 2 node — `continux-imac` (iMac, server) + `continux-vps` (Droplet, agent) qua Tailscale; `kubectl`, Helm | 14/04 | 16/04 | Sỹ | ✓ |
| 2.2 | Deploy ArgoCD + cấu hình GitOps repo trên GitHub | 15/04 | 18/04 | Sỹ | ⏳ |
| 2.3 | Deploy MinIO + tạo bucket `iceberg-data`, `rw-checkpoint` | 16/04 | 19/04 | Sỹ | ⏳ |
| 2.4 | Deploy Redpanda + tạo topic `nyc-taxi-events` | 18/04 | 20/04 | Sỹ | ⏳ |
| 2.5 | Deploy RisingWave v2.4+, kết nối MinIO & Redpanda | 20/04 | 23/04 | Sỹ | ⏳ |
| 2.6 | Deploy VictoriaMetrics + Grafana + cấu hình scrape | 22/04 | 24/04 | Sỹ | ⏳ **Mốc M3** |

### Giai đoạn 3 — Pipeline dữ liệu & Materialized View Blue (22/04 → 03/05)

| # | Công việc | Bắt đầu | Kết thúc | Phụ trách | Ghi chú |
|---|-----------|---------|----------|-----------|---------|
| 3.1 | Tải NYC TLC Trip Record; upload TLC Taxi Zone CSV lên MinIO | 22/04 | 24/04 | Sỹ | 265 bản ghi Zone |
| 3.2 | Cấu hình Vector đọc CSV → mô phỏng luồng → Redpanda | 24/04 | 27/04 | Sỹ | Điều chỉnh throughput |
| 3.3 | SQL: `CREATE SOURCE` (Redpanda) + `CREATE TABLE` (Taxi Zone) | 26/04 | 28/04 | Sỹ | |
| 3.4 | Viết MV v1 (**Blue**): JOIN luồng với Taxi Zone, phân tích theo Zone | 27/04 | 30/04 | Sỹ | Baseline |
| 3.5 | Cấu hình Iceberg Sink (Built-in Hosted Catalog) | 29/04 | 02/05 | Sỹ | Verify format Iceberg |
| 3.6 | Test end-to-end Vector → Redpanda → RisingWave → Iceberg | 01/05 | 03/05 | Sỹ | Chạy 2–4h, **Mốc M4** |

### Giai đoạn 4 — Blue/Green MV Swap + GitOps (02/05 → 12/05)

| # | Công việc | Bắt đầu | Kết thúc | Phụ trách | Ghi chú |
|---|-----------|---------|----------|-----------|---------|
| 4.1 | Viết MV v2 (**Green**) với logic phân tích mới | 02/05 | 04/05 | Sỹ | Chạy song song Blue |
| 4.2 | Thiết kế cơ chế phát hiện Green backfill hoàn tất (`consumer_lag → 0`) | 04/05 | 06/05 | Sỹ | Metric từ RisingWave |
| 4.3 | K8s Job: ArgoCD trigger → check backfill → `ALTER MV SWAP WITH` | 05/05 | 08/05 | Sỹ | Chạy SQL khi Green sẵn sàng |
| 4.4 | ArgoCD Application + PostSync Hook kích hoạt Job swap | 07/05 | 10/05 | Sỹ | |
| 4.5 | Test toàn bộ flow: commit Git → sync → backfill → Atomic Swap | 09/05 | 12/05 | Sỹ | 0s downtime, **Mốc M5** |

### Giai đoạn 5 — Thực nghiệm & Thu thập kết quả (11/05 → 22/05)

| # | Công việc | Bắt đầu | Kết thúc | Phụ trách | Ghi chú |
|---|-----------|---------|----------|-----------|---------|
| 5.1 | Verify Exactly-Once qua Iceberg Sink trong lúc swap | 11/05 | 13/05 | Sỹ | So sánh record count |
| 5.2 | Stress test throughput Vector; đo events/s, latency, consumer lag | 13/05 | 16/05 | Sỹ | Ghi từng mức tải |
| 5.3 | Đo Cutover Metrics (swap time, recovery, downtime) — 3–5 lần | 15/05 | 18/05 | Sỹ | Lấy trung bình |
| 5.4 | Kiểm chứng Data Integrity: in vs out, duplicate/loss rate | 17/05 | 19/05 | Sỹ | Query Iceberg |
| 5.5 | Thu thập Resource Utilization (CPU, RAM) qua VM/Grafana | 18/05 | 20/05 | Sỹ | Screenshot dashboard |
| 5.6 | Tổng hợp kết quả, bảng biểu, biểu đồ cho báo cáo | 20/05 | 22/05 | Sỹ | **Mốc M6** |

### Giai đoạn 6 — Viết báo cáo & Nộp (16/05 → 31/05)

| # | Công việc | Bắt đầu | Kết thúc | Phụ trách | Ghi chú |
|---|-----------|---------|----------|-----------|---------|
| 6.1 | Chương 1 — Giới thiệu tổng quan | 16/05 | 20/05 | Sỹ | IMRAD-adapted |
| 6.2 | Chương 2 — Cơ sở lý thuyết (Lakehouse, Streaming, Blue/Green, Ursa review) | 18/05 | 23/05 | Sỹ | Trích dẫn APA |
| 6.3 | Chương 3 — Phương pháp & Kiến trúc hệ thống | 20/05 | 25/05 | Sỹ | Sơ đồ + sequence diagram |
| 6.4 | Chương 4 — Kết quả thực nghiệm (4 nhóm chỉ số) | 22/05 | 27/05 | Sỹ | Dựa trên dữ liệu Giai đoạn 5 |
| 6.5 | Chương 5 — Thảo luận & Kết luận | 25/05 | 28/05 | Sỹ | So sánh Ursa, hạn chế, hướng phát triển |
| 6.6 | Abstract (VI + EN), Tài liệu tham khảo, Phụ lục | 26/05 | 29/05 | Sỹ | Abstract viết cuối |
| 6.7 | Rà soát format, APA, review GVHD | 28/05 | 30/05 | Sỹ | |
| 6.8 | **NỘP báo cáo hoàn chỉnh + DEMO hệ thống** | 31/05 | 31/05 | Sỹ & Nam | **Mốc M7 — DEADLINE** |

---

## 4. Biểu đồ Gantt (tóm tắt)

```
Tuần           | 05/04  12/04  19/04  26/04  03/05  10/05  17/05  24/05  31/05
---------------|---------------------------------------------------------------
G1 Tài liệu    | ████████████▓
G2 Hạ tầng     |        ▓█████████▓
G3 Pipeline+Blue|               ▓████████████▓
G4 Blue/Green  |                        ▓████████▓
G5 Thực nghiệm |                                ▓█████████▓
G6 Báo cáo     |                                    ▓████████████▓
Mốc            | M1─────M2─────────M3────M4──────M5────────M6───────M7
```

Ô `█` = công việc chính; ô `▓` = giai đoạn gối đầu.

---

## 5. Rủi ro & phương án dự phòng

| Rủi ro | Tác động | Phương án giảm nhẹ |
|--------|----------|---------------------|
| RAM `continux-imac` 8GB không đủ cho RisingWave + Redpanda + MinIO | Cao | Giới hạn chặt memory trong Helm values (xem [SETUP.md §8](./SETUP.md)); giảm throughput Vector; nếu vẫn OOM → tạm bật Desktop i7 (WSL2 Ubuntu) làm node agent thứ 3 |
| RAM `continux-vps` 2GB không đủ khi chạy đồng thời ArgoCD + VM + Grafana | Trung bình | Dùng ArgoCD light profile (`helm set resources.requests=...`); retention VictoriaMetrics chỉ 7 ngày; hoặc resize lên $24/mo (2 vCPU, 4 GB RAM) |
| Tailscale rớt session do NAT modem tại nhà | Trung bình | Enable `--ssh` + systemd unit autorestart; thêm IPv6 fallback |
| Droplet hết băng thông 2 TB/mo | Thấp | Giữ traffic chính trong Tailscale; Grafana public chỉ cho GVHD khi demo |
| Iceberg Sink gặp sự cố tương thích | Trung bình | Fallback sang Parquet file trên MinIO, vẫn giữ kiến trúc Blue/Green |
| Backfill Green chậm hơn dự kiến → Consumer Lag không về 0 | Trung bình | Giảm tải Vector trong lúc backfill; điều chỉnh parallelism của MV |
| Lịch GVHD bận → không kịp review 19/04 | Thấp | Đặt cuộc hẹn trước 05/04; gửi bản nháp sớm ngày 15/04 |
| Mất dữ liệu đo do K3s restart | Trung bình | VictoriaMetrics lưu trữ persistent volume trên MinIO |
