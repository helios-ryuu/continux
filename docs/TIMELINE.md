# TIMELINE

Timeline này ghi lại các mốc triển khai Continux từ chuẩn bị hạ tầng đến báo cáo cuối: cluster K3s 3 server Ready, pipeline end-to-end chạy được, replay ingest sinh dữ liệu thật, Blue/Green cutover thành công, dashboard có dữ liệu, evidence được thu cho từng lượt thực nghiệm và paper LaTeX song ngữ được đóng gói.

## 1. Mục Tiêu

Hoàn tất cụm K3s 3 máy, deploy stack lakehouse, chạy pipeline NYC TLC end-to-end, thu bằng chứng thực nghiệm và đóng gói báo cáo trước hạn nộp.

## 2. Mốc Hoàn Tất

| Ngày | Hạng mục | Kết quả |
|------|----------|---------|
| 20/05/2026 | Chuẩn bị repo, docs, scripts, config | Repo có cấu trúc GitOps, script K3s, dashboard và SQL |
| 21/05/2026 | Chuẩn bị OS, Tailscale, K3s | `imac`, `continux-vps`, `helios-pc` join cụm K3s HA, đủ node `Ready` |
| 21/05/2026 | Deploy stack nền | Argo CD, MinIO, Redpanda, RisingWave, VictoriaMetrics, Grafana triển khai thành công |
| 22/05/2026 | Dataset và pipeline SQL | JSONL convert thành công, `tlc_zone` có dữ liệu, `mv_zone_stats` có dữ liệu, Iceberg sinh object |
| 22/05/2026 | Metrics exporter | `continux_exporter_up=1`, VictoriaMetrics scrape được metric `continux_*` |
| 22/05/2026 | Replay ingest | Replay end-to-end sinh MV và Iceberg object |
| 22/05/2026 | Blue/Green cutover | Public MV chuyển sang logic green, query loop không lỗi |
| 22/05/2026 | Chuẩn hóa tài liệu | Docs/runbook/report đồng bộ với evidence cuối |
| 26/05/2026 | Chuẩn hóa paper LaTeX | Tách paper tiếng Việt/Anh thành module trong `paper/src/`, wrapper hai cột và build lại PDF |

## 3. Trạng Thái Hệ Thống Ở Mốc Chốt

| Hạng mục | Trạng thái |
|----------|------------|
| K3s | Đủ 3 node `Ready` |
| PVC | Tất cả `Bound` |
| Workloads | Tất cả `Available` sau replay |
| Argo CD | App chính `Synced/Healthy` |
| Vector | Dừng ở `replicas=0` sau replay |
| RisingWave | meta, compute, compactor, frontend `Running` |
| MinIO/Iceberg | Có data Parquet, equality-delete và position-delete Parquet |
| Grafana | Dashboard streaming/resource/cutover/integrity có dữ liệu |
| Cutover | Query loop ghi nhận `0` lỗi, RisingWave không restart |

## 4. Gantt Hoàn Tất

Ký hiệu: `█` hoàn tất, `◆` mốc chốt.

```text
Ngày                         20 21 22 26
-----------------------------------------
Repo, docs, scripts          █  █  █  █
Chuẩn bị 3 máy + Tailscale   █  █
K3s HA 3 server                 █
Labels, taints, quorum          █
Argo CD + Cloudflare            █
Repo GitOps + App-of-Apps       █
MinIO + Redpanda + RisingWave   █
VictoriaMetrics + Grafana       █
Dataset + JSONL + Taxi Zone     █
Vector ingest có kiểm soát         █
SQL + MV + Iceberg sink            █
Metrics exporter                   █
Replay ingest sạch                 █
Blue/Green cutover                 █
Báo cáo và chuẩn hóa runbook       ◆
Paper LaTeX song ngữ module           ◆
```

## 5. Critical Path Đã Đóng

1. 3 máy vào cùng tailnet Tailscale và ping được nhau.
2. K3s có đủ 3 server Ready, embedded etcd có quorum `2/3`.
3. Argo CD đọc được repo và tạo App-of-Apps.
4. MinIO, Redpanda, RisingWave Ready trước khi bật Vector.
5. Vector chỉ scale lên sau khi topic, PVC, JSONL và SQL sẵn sàng.
6. SQL source/table/MV/sink apply thành công qua Argo CD hook.
7. Metrics exporter expose `continux_*` và VictoriaMetrics scrape được.
8. Replay ingest sinh MV và Iceberg object.
9. Green MV được tạo, query loop không lỗi, swap public MV thành công.
10. Báo cáo và tài liệu dùng cùng một bộ số liệu evidence (số đo cụ thể nằm trong `evidence/` ngoài repo).

## 6. Phân Công

| Nhóm việc | Sỹ | Nam | GVHD |
|-----------|:--:|:--:|:----:|
| Chuẩn bị máy, K3s, Tailscale | A/R | C | I |
| Argo CD, GitOps, Cloudflare Tunnel | A/R | C | I |
| MinIO, Redpanda, RisingWave | A/R | C | I |
| Dataset, Vector, topic bootstrap | A/R | R | I |
| SQL, Iceberg sink, verify dữ liệu | A/R | R | C |
| Grafana, thực nghiệm, báo cáo | R | A/R | C |

## 7. Checklist Cuối

- [x] `imac`, `continux-vps`, `helios-pc` có hostname/node name đúng.
- [x] Tailscale hoạt động trên cả 3 node Linux.
- [x] `kubectl get nodes -o wide` có đủ 3 node Ready.
- [x] `continux-vps` có `role=control-plane`, taint `dedicated=edge:NoSchedule`.
- [x] `helios-pc` có `role=quorum`, taint `dedicated=quorum:NoSchedule`.
- [x] Argo CD quản lý root app và app con.
- [x] MinIO bucket `rw-checkpoint`, `iceberg-data`, `tlc-zone` tồn tại.
- [x] Redpanda topic `nyc-taxi-events` tồn tại.
- [x] RisingWave `SHOW CLUSTER` trả 4 worker `RUNNING`.
- [x] Vector đọc JSONL; runner scale theo pha và trả về profile `smoke`.
- [x] `tlc_zone` được nạp từ Taxi Zone lookup.
- [x] Replay sạch sinh kết quả trong `mv_zone_stats`.
- [x] Iceberg sinh object mới trong MinIO.
- [x] Metrics exporter `continux_*` hoạt động.
- [x] Blue/Green cutover hoàn tất với query errors `0`.
- [x] Dashboard cho 4 nhóm chỉ số có bằng chứng.

## 8. Rủi Ro Đã Xử Lý

| Rủi ro | Cách xử lý |
|--------|-----------|
| iMac 8 GB RAM quá tải khi ingest | Vector dùng rate limit, mặc định `replicas=0`, profile `smoke=2 events/s`; benchmark phải opt-in |
| WSL sleep làm mất quorum | `helios-pc` chỉ giữ quorum; giữ Windows/WSL awake trong thực nghiệm |
| Secret runtime lộ trong Git | Tạo bằng Kubernetes Secret, không commit secret |
| RisingWave meta-command psql không tương thích | Verify bằng `rw_catalog` thay vì `\dt public.*` |
| Argo hook Job biến mất sau khi thành công | Dùng Argo app status và RisingWave catalog làm bằng chứng |
| Dashboard checksum mismatch sau cutover | Giải thích là expected khi so logic mới với logic cũ |

## 9. Definition Of Done

- Bộ `runbook/SETUP.md`, `runbook/DEMO.md`, `runbook/CLEANUP.md` dựng được hệ thống từ máy sạch đến end-to-end và dọn dẹp để chạy lại từ đầu.
- `REPORT.md` là bản báo cáo/evidence companion cho đồ án.
- `paper/main_vi.pdf` và `paper/main_en.pdf` là bản paper LaTeX cuối, build từ source module trong `paper/src/`.
- Không commit dataset, evidence, screenshot lớn hoặc secret.
- Phiên bản hệ thống được phản ánh trong `VERSION` và badge ở `README.md`.
