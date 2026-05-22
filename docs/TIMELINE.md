# TIMELINE

> Cập nhật ngày 22/05/2026: đã hoàn tất `docs/SETUP.md` từ §1 tới §10 trên cụm thật. Cụm K3s 3 server Ready, Argo CD/GitOps đã hoạt động, MinIO/Redpanda/RisingWave/VictoriaMetrics/Grafana Ready, dataset NYC TLC 2026-03 đã được convert sang JSONL, Vector đã ingest có kiểm soát, RisingWave query trả dữ liệu và Iceberg sink ghi Parquet vào MinIO. Bước clear state ở §11 đã được xác nhận để chuẩn bị replay demo sạch. Các secret runtime đã được che trong tài liệu.

## Mục Tiêu

Hoàn tất cụm K3s 3 máy, deploy stack lakehouse, chạy pipeline NYC TLC end-to-end, thu bằng chứng thực nghiệm và hoàn thiện báo cáo trước deadline.

Deadline vận hành nội bộ: **30/05/2026 23:59**. Ngày **31/05/2026** chỉ dùng để rà soát, chụp lại bằng chứng thiếu và đóng gói nộp.

## Hiện Trạng Sau Setup §1-10

| Hạng mục | Trạng thái | Bằng chứng hiện có | Việc còn lại |
|----------|------------|--------------------|--------------|
| Repo, docs, scripts, config | Hoàn tất v0.2.2 | README/SETUP/TIMELINE/REPORT đồng bộ trạng thái triển khai §10 | Chốt commit và tag/release nếu cần |
| Máy `imac` | Hoàn tất | Ubuntu 26.04, K3s `v1.35.5+k3s1`, node `Ready`, data plane | Theo dõi CPU/RAM khi benchmark |
| Máy `continux-vps` | Hoàn tất | UFW active, Tailscale `100.113.151.56`, node `Ready`, taint `dedicated=edge` | Theo dõi Grafana/VictoriaMetrics |
| Máy `helios-pc` | Hoàn tất | WSL Ubuntu 26.04, Tailscale `100.78.46.87`, node `Ready`, `wsl-shared-root` trả `/ shared` | Giữ Windows/WSL awake khi benchmark |
| K3s cluster | Hoàn tất | `3/3 Ready`, readyz/etcd OK | Không còn blocker |
| GitOps/Argo CD | Hoàn tất | Argo CD deployed, repo added, `root-app` Synced/Healthy | Sync các app con khi có thay đổi |
| Data plane | Hoàn tất | MinIO deployed, Redpanda topic `nyc-taxi-events`, RisingWave pods `Running`, `SHOW CLUSTER` có 4 workers RUNNING | Theo dõi resource khi benchmark |
| Observability | Một phần | VictoriaMetrics stack deployed, scrape configs Synced, Grafana rollout OK; dashboard JSON đã chuẩn hóa và đã import; resource dashboard có tín hiệu | Bổ sung exporter `continux_*` và chụp dashboard thực nghiệm |
| Pipeline dữ liệu | Hoàn tất §10; §11 clear đã xác nhận | JSONL 450M, 3,952,451 rows, `mv_zone_stats` có dữ liệu, Iceberg có Parquet output; đã dừng Vector, drop RisingWave state, reset topic, dọn Iceberg prefix | Re-apply SQL, bật Vector lại và đo replay nếu cần |
| Báo cáo/kết quả | Đang thu thập | `k3s-check.sh` sau §10: Workloads Ready 100%, query output và Iceberg object đã có | Screenshot/dashboard Grafana với metric thực nghiệm |

## Lịch Chạy Nước Rút

| Ngày | Ưu tiên | Việc phải xong | Trạng thái |
|------|---------|----------------|------------|
| 20/05 | Chuẩn bị tài nguyên | Chốt repo, kiểm tra docs/scripts/config | Xong |
| 21/05 | OS, mạng, K3s, stack nền | Hoàn tất hostname/user/SSH/Tailscale; dựng K3s HA; deploy Argo CD, MinIO, Redpanda, RisingWave, VictoriaMetrics, Grafana; chuẩn bị dataset và Vector | Xong |
| 22/05 | Tài liệu v0.2.2 và SQL | Cập nhật output thực tế trong docs; apply SQL source/table/MV/sink; verify query và Iceberg object | Xong |
| 23/05 | Dashboard và replay | Dashboard JSON đã import; bổ sung exporter `continux_*`, chụp bằng chứng; §11 clear state đã có output, còn replay lại nếu cần | Đang làm |
| 24/05 | Thực nghiệm ingest | Chạy lại demo ingest sạch bằng §11; ghi throughput/lag/resource | Kế tiếp |
| 25/05 | Tối ưu tài nguyên | Điều chỉnh Vector rate, Grafana resource, retention/scrape nếu cần | Kế tiếp |
| 26/05 | Báo cáo kết quả | Cập nhật REPORT bằng số liệu thực nghiệm | Kế tiếp |
| 27/05 | Rà soát end-to-end | Chạy checklist, clear/replay ingest, kiểm tra docs | Kế tiếp |
| 28/05 | Dự phòng kỹ thuật | Sửa lỗi phát sinh, bổ sung hình/log | Kế tiếp |
| 29/05 | Báo cáo gần cuối | Hoàn thiện nội dung, đối chiếu yêu cầu môn học | Kế tiếp |
| 30/05 | Đóng băng | Full checklist xanh, commit/tag cuối | Kế tiếp |
| 31/05 | Buffer | Chỉ rà soát và bổ sung bằng chứng thiếu | Dự phòng |

## Gantt

Ký hiệu: `█` đã làm/chính, `▓` đang làm/phụ thuộc gần, `◆` mốc chốt.

```text
Ngày                         20 21 22 23 24 25 26 27 28 29 30 31
------------------------------------------------------------------
Repo, docs, scripts          █  █  ▓
Chuẩn bị 3 máy + Tailscale   █  █
K3s HA 3 server                 █
Labels, taints, quorum          █
Argo CD + Cloudflare            █
Repo GitOps + App-of-Apps       █
MinIO + Redpanda + RisingWave   █
VictoriaMetrics + Grafana       █
Dataset + JSONL + Taxi Zone     █
Vector ingest có kiểm soát      █
SQL + MV + Iceberg sink            █
Thực nghiệm + dashboard              ▓  █  █
Báo cáo + chứng cứ                       ▓  █  █
Full checklist + đóng băng                              █
Buffer nộp bài                                               ◆
```

## Critical Path

1. 3 máy phải vào được Tailscale và ping qua lại. **Xong.**
2. K3s phải đủ 3 server Ready để có quorum. **Xong.**
3. Argo CD phải sync được repo. **Xong.**
4. MinIO, Redpanda, RisingWave phải Ready trước khi bật Vector. **Xong.**
5. Vector chỉ scale lên sau khi topic, PVC và JSONL đã sẵn sàng. **Xong.**
6. SQL chỉ apply sau khi secrets MinIO/RisingWave đúng. **Xong.**
7. Báo cáo chỉ chốt sau khi có query output, object Iceberg và dashboard. **Query/Iceberg xong, còn dashboard thực nghiệm.**

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

- [x] `imac`, `continux-vps`, `helios-pc` có hostname đúng.
- [x] User `helios` có sudo và SSH hoạt động.
- [x] Tailscale hoạt động trên cả 3 máy.
- [x] Repo có clone ở `~/continux` trên `imac`, `continux-vps`, `helios-pc`.
- [x] `docs/SETUP.md` được chạy theo thứ tự tới §9.

### Sau khi dựng K3s

- [x] `kubectl get nodes -o wide` có đủ 3 node Ready.
- [x] `imac` có `role=data-plane`.
- [x] `continux-vps` có `role=control-plane` và taint `dedicated=edge:NoSchedule`.
- [x] `helios-pc` có `role=quorum` và taint `dedicated=quorum:NoSchedule`.
- [x] `bash scripts/k3s-check.sh overview` không có hot list nghiêm trọng; pod `redpanda-configuration-cdk5k` là job/configuration cũ và không chặn workload.

### Trước khi bật Vector

- [x] MinIO buckets/runtime secret đã được chuẩn bị.
- [x] Redpanda topic `nyc-taxi-events` tồn tại với 3 partitions, retention 24h.
- [x] RisingWave pods và service Ready.
- [x] `psql -h localhost -p 4567 -d dev -U root -c 'SHOW CLUSTER;'` trả 4 workers RUNNING.
- [x] PVC Vector `Bound` và trỏ đúng `imac`.
- [x] JSONL đã tồn tại trong `data/raw/`, kích thước khoảng 450M.
- [x] Deployment Vector ban đầu `replicas: 0`.
- [x] Vector đã scale thủ công lên `1` và healthcheck passed.

### Trước khi chốt báo cáo

- [x] `SELECT COUNT(*) FROM mv_zone_stats` trả số dương (`260`).
- [x] MinIO có Iceberg metadata/data object; §11 đã xác nhận dọn prefix bằng delete marker để chuẩn bị replay.
- [x] Grafana deployment Ready và datasource VictoriaMetrics đã cấu hình.
- [x] Dashboard JSON đã import vào Grafana.
- [ ] Dashboard streaming/cutover/integrity có dữ liệu thật, không chỉ là placeholder hoặc `vector(0)`.
- [x] Có log chứng minh cluster, pipeline, query và object output.
- [ ] Có ảnh/log chứng minh dashboard cho 4 nhóm chỉ số trong `PROPOSE.md`.
- [x] README, SETUP, REPORT nhất quán với topology 3 máy và version `v0.2.2`.

## Rủi Ro

| Rủi ro | Mức | Dấu hiệu | Giảm thiểu |
|--------|-----|----------|------------|
| iMac 8 GB RAM quá tải khi ingest | Cao | Grafana chập chờn, Redpanda/RisingWave CPU tăng | Vector đã thêm Kafka sink rate limit; dùng §11 để clear/replay và giảm `rate_limit_num` nếu cần |
| WSL sleep làm mất quorum | Trung bình | `helios-pc` NotReady, etcd mất quorum | Giữ Windows awake khi setup/benchmark |
| VPS thiếu RAM | Trung bình | Grafana/VictoriaMetrics restart | Grafana đã tăng resource ở v0.2.2; tiếp tục theo dõi dashboard |
| Secret sai | Trung bình | RisingWave không đọc/ghi S3 | Tạo lại Secret bằng `kubectl create secret ... --dry-run=client -o yaml \| kubectl apply -f -`; không commit secret |
| Dataset schema thay đổi | Trung bình | Converter hoặc SQL source lỗi field | Dùng `partojsonl.py` chỉ lấy field cần thiết; đã convert thành công 3,952,451 rows cho `2026-03` |
| Không đủ thời gian thực nghiệm | Cao | Pipeline chạy được nhưng thiếu số liệu | Ưu tiên 1 kịch bản ingest ổn định, screenshot dashboard và output SQL/MinIO |

## Definition Of Done

- Repo sạch về topology hiện tại, không còn node/script cũ trong docs/config/script.
- 3 máy chạy K3s server Ready qua Tailscale.
- Argo CD quản lý được các app chính.
- MinIO, Redpanda, RisingWave, VictoriaMetrics, Grafana Ready.
- Dataset được convert, Vector publish event vào Redpanda.
- RisingWave query được MV và Iceberg sink ghi object ra MinIO.
- Dashboard thực nghiệm có dữ liệu thật cho resource, throughput/lag, cutover và integrity.
- Báo cáo có đủ lệnh, output, ảnh/dashboard hoặc log chứng minh.
