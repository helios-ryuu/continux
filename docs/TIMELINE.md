# TIMELINE

> Cập nhật ngày 20/05/2026: hiện trạng mới có repo và tài liệu/config/script trong repo. Công việc thực tế đang ở bước chuẩn bị tài nguyên máy để có thể chạy lệnh setup trên 3 node. Mọi hạng mục phải hoàn tất trước ngày 31/05/2026.

## Mục Tiêu

Hoàn tất cụm K3s 3 máy, deploy stack lakehouse, chạy pipeline NYC TLC end-to-end, thu bằng chứng thực nghiệm và hoàn thiện báo cáo trước deadline.

Deadline vận hành nội bộ: **30/05/2026 23:59**. Ngày **31/05/2026** chỉ dùng để rà soát, chụp lại bằng chứng thiếu và đóng gói nộp.

## Hiện Trạng Ngày 20/05/2026

| Hạng mục | Trạng thái | Việc còn lại |
|----------|------------|--------------|
| Repo, docs, scripts, config | Đã chuẩn hóa trong repo | Kiểm tra lại sau khi chạy thật trên cluster |
| Máy `imac` | Đang chuẩn bị | Cài Ubuntu, hostname, user, SSH, Tailscale, clone repo |
| Máy `continux-vps` | Đang chuẩn bị | Tạo user `helios`, hostname, SSH, Tailscale |
| Máy `helios-pc` | Đang chuẩn bị | WSL Ubuntu, systemd, hostname, Tailscale |
| K3s cluster | Chưa dựng | Init `imac`, join `continux-vps`, join `helios-pc` |
| GitOps/Argo CD | Chưa deploy | Cài Argo CD, đăng ký repo, sync App-of-Apps |
| Data plane | Chưa deploy | MinIO, Redpanda, RisingWave |
| Observability | Chưa deploy | VictoriaMetrics, Grafana, dashboard |
| Pipeline dữ liệu | Chưa chạy | Tải parquet, convert JSONL, Vector ingest, SQL verify |
| Báo cáo/kết quả | Chưa có số liệu thực nghiệm | Thu log, ảnh, metric, query output |

## Lịch Chạy Nước Rút

| Ngày | Ưu tiên | Việc phải xong | Bằng chứng |
|------|---------|----------------|------------|
| 20/05 | Chuẩn bị tài nguyên | Chốt repo, kiểm tra docs/scripts/config; bắt đầu chuẩn bị 3 máy | `git status`, checklist máy |
| 21/05 | OS và mạng | Hoàn tất hostname, user `helios`, SSH, Tailscale trên `imac`, `continux-vps`, `helios-pc` | `tailscale status`, ping 3 node |
| 22/05 | K3s HA | Init server #1 trên `imac`; join `continux-vps` và `helios-pc`; labels/taints đúng | `kubectl get nodes -o wide`, `bash scripts/k3s-check.sh overview` |
| 23/05 | Control plane | Cài CLI, Argo CD, Cloudflare Tunnel, đăng ký repo, sync App-of-Apps | Argo CD UI, `argocd app list` |
| 24/05 | Data plane | Deploy MinIO, Redpanda, RisingWave; tạo buckets/secrets/topic | `kubectl get pods -A`, `rpk topic describe`, `psql SHOW CLUSTER` |
| 25/05 | Observability | Deploy VictoriaMetrics, Grafana, scrape configs, import dashboards | Grafana datasource xanh, dashboard có dữ liệu |
| 26/05 | Dataset và ingest | Tải TLC parquet, convert JSONL, upload Taxi Zone, bật Vector có kiểm soát | File JSONL, Vector log, Redpanda topic có event |
| 27/05 | SQL và Iceberg | Apply source/table/MV/sink; verify query và object output | `SELECT COUNT(*)`, `mc ls --recursive iceberg-data` |
| 28/05 | Thực nghiệm | Chạy kịch bản ingest, ghi throughput/lag/resource, chụp dashboard | CSV/log/screenshot kết quả |
| 29/05 | Báo cáo | Hoàn thiện REPORT, cập nhật hình/chứng cứ, rà tính nhất quán docs | Bản báo cáo gần cuối |
| 30/05 | Đóng băng | Chạy lại full checklist, fix lỗi cuối, đóng gói nộp | Checklist xanh, tag/commit cuối |
| 31/05 | Buffer | Chỉ rà soát và bổ sung bằng chứng thiếu | Không thêm thay đổi kiến trúc lớn |

## Gantt

Ký hiệu: `█` đang làm/chính, `▓` phụ thuộc gần, `◆` mốc chốt.

```text
Ngày                         20 21 22 23 24 25 26 27 28 29 30 31
------------------------------------------------------------------
Repo, docs, scripts          █
Chuẩn bị 3 máy + Tailscale   █  █
K3s HA 3 server                    █
Labels, taints, quorum             ▓  █
Argo CD + Cloudflare                  █
Repo GitOps + App-of-Apps              ▓  █
MinIO + Redpanda + RisingWave             █
VictoriaMetrics + Grafana                   █
Dataset + JSONL + Taxi Zone                    █
Vector ingest có kiểm soát                    ▓  █
SQL + MV + Iceberg sink                           █
Thực nghiệm + dashboard                               █
Báo cáo + chứng cứ                                     █
Full checklist + đóng băng                                █
Buffer nộp bài                                               ◆
```

## Critical Path

1. 3 máy phải vào được Tailscale và ping qua lại.
2. K3s phải đủ 3 server Ready để có quorum.
3. Argo CD phải sync được repo.
4. MinIO, Redpanda, RisingWave phải Ready trước khi bật Vector.
5. Vector chỉ scale lên sau khi topic, PVC và JSONL đã sẵn sàng.
6. SQL chỉ apply sau khi secrets MinIO/RisingWave đúng.
7. Báo cáo chỉ chốt sau khi có query output, object Iceberg và dashboard.

## Phân Công

| Nhóm việc | Sỹ | Nam | GVHD |
|-----------|:--:|:--:|:----:|
| Chuẩn bị máy, K3s, Tailscale | A/R | C | I |
| Argo CD, GitOps, Cloudflare Tunnel | A/R | C | I |
| MinIO, Redpanda, RisingWave | A/R | C | I |
| Dataset, Vector, topic bootstrap | A/R | R | I |
| SQL, Iceberg sink, verify dữ liệu | A/R | R | C |
| Grafana, thực nghiệm, báo cáo | R | A/R | C |

## Checklist Theo Mốc

### Trước khi chạy lệnh setup

- [ ] `imac`, `continux-vps`, `helios-pc` có hostname đúng.
- [ ] User `helios` có sudo và SSH hoạt động.
- [ ] Tailscale hoạt động trên cả 3 máy.
- [ ] Repo có clone ở `~/continux` trên `imac`.
- [ ] `docs/SETUP.md` được đọc theo đúng thứ tự, không nhảy bước.

### Sau khi dựng K3s

- [ ] `kubectl get nodes -o wide` có đủ 3 node Ready.
- [ ] `imac` có `role=data-plane`.
- [ ] `continux-vps` có `role=control-plane` và taint `dedicated=edge:NoSchedule`.
- [ ] `helios-pc` có `role=quorum` và taint `dedicated=quorum:NoSchedule`.
- [ ] `bash scripts/k3s-check.sh overview` không có hot list nghiêm trọng.

### Trước khi bật Vector

- [ ] MinIO buckets đã có.
- [ ] Redpanda topic `nyc-taxi-events` tồn tại.
- [ ] RisingWave kết nối được qua `psql`.
- [ ] PVC Vector `Bound` và trỏ đúng `imac`.
- [ ] JSONL đã tồn tại trong `data/raw/`.
- [ ] Deployment Vector vẫn `replicas: 0`.

### Trước khi chốt báo cáo

- [ ] `SELECT COUNT(*) FROM mv_zone_stats` trả số dương.
- [ ] MinIO có Iceberg metadata/data object.
- [ ] Grafana có dashboard đọc được VictoriaMetrics.
- [ ] Có ảnh hoặc log chứng minh cluster, pipeline, query, object output.
- [ ] README, SETUP, REPORT nhất quán với topology 3 máy.

## Rủi Ro

| Rủi ro | Mức | Dấu hiệu | Giảm thiểu |
|--------|-----|----------|------------|
| Chuẩn bị máy trễ | Cao | Chưa ping được đủ 3 node qua Tailscale sau 21/05 | Ưu tiên K3s trước, dashboard/báo cáo để sau |
| iMac 8 GB RAM quá tải | Cao | Pod OOMKilled, node memory cao | Giữ Vector `replicas: 0`, giới hạn resource, chạy dataset nhỏ trước |
| WSL sleep làm mất quorum | Trung bình | `helios-pc` NotReady, etcd mất quorum | Giữ Windows awake khi setup/benchmark |
| VPS thiếu RAM | Trung bình | Grafana/VictoriaMetrics restart | Giảm retention, giữ workload nhẹ trên VPS |
| Secret sai | Trung bình | RisingWave không đọc/ghi S3 | Tạo lại Secret bằng `kubectl create secret ... --dry-run=client -o yaml \| kubectl apply -f -` |
| Dataset schema thay đổi | Trung bình | Converter hoặc SQL source lỗi field | Dùng `partojsonl.py` chỉ lấy field cần thiết; smoke run `--limit` trước |
| Không đủ thời gian thực nghiệm | Cao | Pipeline chạy được nhưng thiếu số liệu | Ưu tiên 1 kịch bản ingest ổn định và chứng cứ end-to-end |

## Definition Of Done

- Repo sạch về topology hiện tại, không còn node/script cũ trong docs/config/script.
- 3 máy chạy K3s server Ready qua Tailscale.
- Argo CD quản lý được các app chính.
- MinIO, Redpanda, RisingWave, VictoriaMetrics, Grafana Ready.
- Dataset được convert, Vector publish event vào Redpanda.
- RisingWave query được MV và Iceberg sink ghi object ra MinIO.
- Báo cáo có đủ lệnh, output, ảnh/dashboard hoặc log chứng minh.
