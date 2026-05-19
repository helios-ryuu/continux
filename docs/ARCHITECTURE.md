# ARCHITECTURE — KIẾN TRÚC, CẤU TRÚC & YÊU CẦU HỆ THỐNG

> **Dự án:** Xây dựng kiến trúc Data Lakehouse thời gian thực cho hệ thống giao thông thông minh trên cụm Kubernetes.
> **Nền tảng:** K3s · ArgoCD v3.4.2 (Helm chart `argo-cd` 9.5.14) · MinIO · Redpanda · RisingWave · Apache Iceberg · Vector · VictoriaMetrics · Grafana.
> **Dataset:** NYC TLC Trip Record Data + TLC Taxi Zone Lookup (265 zones).
> **Cụm:** 4 máy — `continux-imac`, `continux-vps`, `helios`, `nammn` (chi tiết §1).
> Các mã `FR-xx`, `NFR-xx` được tham chiếu trong [SETUP.md](./SETUP.md) và [REPORT.md](./REPORT.md).

---

## 1. Hạ tầng — Bốn máy của cụm

### 1.1. Hai node chính (luôn bật)

| Node | Phần cứng | Hệ điều hành | Vai trò |
|------|-----------|-------------|---------|
| **`continux-imac`** | iMac19,2 · Intel i5-8500 (6 cores, 3.0–4.1 GHz) · 8 GB DDR4 · 200 GB SSD | Ubuntu Server 24.04 LTS (native) | K3s server #1, `--cluster-init` · **Data plane**: MinIO, Redpanda, RisingWave, Vector · Nơi chạy mọi lệnh quản trị |
| **`continux-vps`** | DigitalOcean Droplet · 1 vCPU / 2 GB RAM (gói $12/mo, nâng lên 2 vCPU / 4 GB khi cần) · 50 GB SSD · SGP1 | Ubuntu 24.04 LTS (native) | K3s server #2 · **Control & observability plane**: ArgoCD, VictoriaMetrics, Grafana |

> **Mạng liên node:** Tailscale mesh VPN — mọi lưu lượng K3s, Flannel, etcd đi qua đường hầm mã hóa Tailscale (IP range `100.64.0.0/10`). Không node nào expose trực tiếp ra internet; chỉ ArgoCD và Grafana được expose qua Cloudflare Tunnel.

### 1.2. Hai node phụ trợ (bật khi cần burst)

| Node | Phần cứng | Hệ điều hành | Vai trò |
|------|-----------|-------------|---------|
| **`helios`** | Laptop HP (HELIOS-PC) · Intel Core i5-12500H (12C/16T, max 4.5 GHz) · 16 GB DDR5 4800 MHz (2×8 GB Samsung) · NVIDIA GeForce RTX 3050 Ti 4 GB | Windows 11 → **WSL2 Ubuntu 24.04** | K3s worker phụ trợ — bật khi cần thực nghiệm song song hoặc dự phòng |
| **`nammn`** | Laptop HP (SINISTER) · AMD Ryzen 5 7640HS (8C/16T, boost 4.3 GHz) · 32 GB DDR5 5600 MHz (2×16 GB Hynix) · NVIDIA GeForce RTX 3050 6 GB | Windows 11 → **WSL2 Ubuntu 24.04** | K3s worker phụ trợ — bật khi `continux-imac` OOM hoặc cần throughput > 10 k events/s |

> **Khi nào bật `helios` / `nammn`:** Chỉ trong Giai đoạn 4–5 khi stress test. Không bật thường xuyên để tránh overhead etcd và tiết kiệm điện.

### 1.3. Sơ đồ phân bổ workload

```
┌─────────────────── continux-imac (K3s server #1, 8 GB) ───────────────────┐
│  Vector ──▶ Redpanda ──▶ RisingWave (Meta + Compute + Frontend)           │
│                               │                                            │
│                               ├── iceberg sink ──▶ MinIO (iceberg-data)   │
│                               └── checkpoint   ──▶ MinIO (rw-checkpoint)  │
└────────────────────────────────────────────────────────────────────────────┘
                                │  Tailscale overlay (100.x.x.x)
                                ▼
┌─────────────────── continux-vps (K3s server #2, 2→4 GB) ──────────────────┐
│  ArgoCD ── VictoriaMetrics ── Grafana                                      │
│  (public UI qua Cloudflare Tunnel, điều phối GitOps, dashboard giám sát)   │
└────────────────────────────────────────────────────────────────────────────┘
                                │  Tailscale (chỉ bật khi cần burst)
                    ┌───────────┴───────────┐
                    ▼                       ▼
        ┌─── helios (WSL2) ───┐  ┌─── nammn (WSL2) ───┐
        │  K3s worker         │  │  K3s worker         │
        │  workload=heavy     │  │  workload=heavy      │
        └─────────────────────┘  └─────────────────────┘
```

---

## 2. Cây thư mục dự án

```
continux/
├── README.md                        # Tổng quan repo
├── LICENSE
├── Makefile                         # Lệnh tiện ích: bootstrap, sync, experiment
├── .gitignore
│
├── docs/                            # Toàn bộ tài liệu đồ án
│   ├── PROPOSE.md                   # Đề cương (nguồn)
│   ├── REPORT.md                    # Báo cáo tổng thể (convert sang LaTeX)
│   ├── ARCHITECTURE.md              # (chính file này) Kiến trúc + yêu cầu + cấu trúc
│   ├── TIMELINE.md                  # Lộ trình theo mốc, Gantt, phân công
│   ├── SETUP.md                     # Hướng dẫn thiết lập toàn diện
│   ├── diagrams/                    # Sơ đồ kiến trúc (PlantUML, Mermaid, PNG)
│   │   ├── architecture-overview.puml
│   │   ├── bluegreen-sequence.puml
│   │   └── exports/                 # PNG render cho báo cáo
│   ├── references/
│   │   └── ursa-vldb-2025.pdf
│   └── meeting-notes/
│       └── 2026-04-08-scope-lock.md
│
├── config/                          # Helm values & K8s manifests (nguồn cho ArgoCD)
│   ├── argocd/
│   │   ├── helm-values.yaml
│   │   └── cloudflared.yaml
│   ├── minio/
│   │   ├── helm-values.yaml
│   │   └── buckets-job.yaml
│   ├── redpanda/
│   │   └── helm-values.yaml
│   ├── risingwave/
│   │   ├── helm-values.yaml
│   │   └── secrets.yaml
│   ├── vector/
│   │   ├── deployment.yaml
│   │   └── pvc.yaml
│   ├── victoria-metrics/
│   │   ├── helm-values.yaml
│   │   └── scrape-configs.yaml
│   └── grafana/
│       ├── helm-values.yaml
│       └── dashboards-configmap.yaml
│
├── gitops/                          # ArgoCD Application definitions
│   ├── apps/                        # App-of-Apps pattern
│   │   ├── root-app.yaml            # Quản lý toàn bộ child apps
│   │   ├── infra-app.yaml
│   │   ├── pipeline-app.yaml
│   │   └── observability-app.yaml
│   └── pipeline/                    # Job manifests cho pipeline automation
│       ├── sql-configmap.yaml
│       ├── mv-apply-job.yaml
│       ├── swap-job.yaml            # Job swap Blue/Green (PostSync Hook)
│       └── kustomization.yaml
│
├── sql/                             # Mọi SQL chạy trên RisingWave
│   ├── 01-sources/
│   │   └── redpanda-nyc-taxi.sql
│   ├── 02-tables/
│   │   └── tlc-taxi-zone.sql
│   ├── 03-mv/
│   │   ├── mv_zone_stats_blue.sql
│   │   └── mv_zone_stats_green.sql
│   ├── 04-sinks/
│   │   └── iceberg-zone-stats.sql
│   └── README.md                    # Quy ước đặt tên & thứ tự áp dụng
│
├── pipelines/
│   ├── vector/
│   │   ├── vector.toml              # Source JSONL → transform → sink Redpanda
│   │   └── rates/                   # Preset throughput 1k/5k/10k/20k events/s
│   │       ├── low.env
│   │       ├── medium.env
│   │       └── high.env
│   └── redpanda/
│       └── topics.yaml
│
├── dashboards/
│   ├── 01-streaming-perf.json
│   ├── 02-resource-util.json
│   ├── 03-cutover.json
│   └── 04-data-integrity.json
│
├── experiments/
│   ├── scenarios/
│   │   ├── throughput-sweep.yaml
│   │   └── cutover-repeat-5x.yaml
│   ├── runners/
│   │   ├── run_stress.sh
│   │   ├── run_swap.sh
│   │   └── verify_integrity.py
│   └── results/                     # CSV/JSON output thô
│
├── scripts/
│   ├── bootstrap-k3s.sh
│   ├── install-argocd.sh
│   └── upload-tlc-zone.sh
│
├── data/                            # DỮ LIỆU LOCAL — KHÔNG COMMIT
│   ├── raw/                         # NYC TLC parquet + JSONL đã convert
│   └── zone/                        # taxi_zone_lookup.csv (nhỏ, có thể commit)
│
└── tools/
    └── swap-runner/
        ├── Dockerfile               # Image chứa psql + script backfill-check
        └── entrypoint.sh
```

---

## 3. Luận giải thiết kế

### 3.1. Vì sao tách `config/` khỏi `gitops/`, `sql/` và `pipelines/`?

- `config/` chứa **Helm values và K8s manifests** cho từng service. ArgoCD Applications trong `gitops/apps/` trỏ vào đây để sync.
- `gitops/` chỉ chứa **ArgoCD Application definitions** và **Job manifests** điều khiển pipeline tự động (swap, apply SQL).
- `sql/` và `pipelines/` chứa **nội dung logic** (SQL, vector.toml). Các file này được embed vào ConfigMap/Secret qua Kustomize, cho phép sửa SQL độc lập với manifest hạ tầng mà vẫn tuân thủ GitOps (FR-11, FR-12).
- Khi commit SQL mới → Kustomize regenerate ConfigMap → ArgoCD phát hiện drift → Job swap chạy tự động (FR-14, FR-16).

### 3.2. App-of-Apps cho ArgoCD

`gitops/apps/root-app.yaml` là Application "cha" — tự quản lý các Application "con" (infra, pipeline, observability):
- Tạo/xoá/tái tạo toàn bộ cluster chỉ bằng **một** `kubectl apply`.
- Tách nhịp sync: infra hiếm khi đổi; pipeline thay đổi thường xuyên (mỗi lần upgrade MV).

### 3.3. Phân lớp SQL theo số thứ tự (`01-sources/` … `04-sinks/`)

Thứ tự dependency rõ ràng: Source → Table → MV → Sink. Job `mv-apply-job` duyệt folder theo thứ tự, tránh lỗi reference. Mỗi MV là một file độc lập → dễ diff giữa Blue và Green.

### 3.4. Quy ước đặt tên Materialized View

- `mv_zone_stats_blue` / `mv_zone_stats_green` — đuôi `_blue`/`_green` bắt buộc.
- Public alias `mv_zone_stats` luôn trỏ về MV hiện hành qua `ALTER MATERIALIZED VIEW mv_zone_stats SWAP WITH mv_zone_stats_green`.
- Dashboard và code ứng dụng **chỉ query** `mv_zone_stats` → đảm bảo zero-downtime nhờ swap nguyên tử (FR-14, NFR-04).

### 3.5. Node placement qua `nodeSelector` + `tolerations`

Mọi `helm-values.yaml` trong `config/` **bắt buộc** khai báo nodeSelector phù hợp. Lệnh gán label thực hiện trong [SETUP.md §5.4](./SETUP.md):

```yaml
# Workload nặng → continux-imac (hoặc helios/nammn khi đang làm worker)
nodeSelector: { role: data-plane }

# Workload nhẹ → continux-vps
nodeSelector: { role: control-plane }
tolerations:
  - { key: dedicated, operator: Equal, value: edge, effect: NoSchedule }
```

Quy tắc này ngăn scheduler đặt nhầm RisingWave vào Droplet (OOM) và Grafana vào iMac (chiếm RAM data plane).

### 3.6. `data/` không commit

NYC TLC dataset có thể lên đến vài GB — `.gitignore` loại trừ `data/raw/`. Chỉ `data/zone/taxi_zone_lookup.csv` (≤ 20 KB) được commit để đảm bảo tái lập (NFR-21, NFR-22).

---

## 4. Yêu cầu chức năng (Functional Requirements)

### 4.1. Nhóm Data Ingestion

| Mã | Yêu cầu | Mức độ | Tiêu chí nghiệm thu |
|----|---------|:------:|---------------------|
| FR-01 | Hệ thống dùng được NYC TLC Trip Record làm nguồn dữ liệu. | MUST | Parquet được convert sang JSONL và Vector load được ≥ 1 file mẫu từ volume gắn vào pod trên `continux-imac`. |
| FR-02 | Hệ thống mô phỏng luồng sự kiện thời gian thực từ file tĩnh. | MUST | Vector publish JSON event vào Redpanda topic `nyc-taxi-events`; throughput test thực hiện bằng kích thước file JSONL/chạy thử theo batch. |
| FR-03 | Hệ thống đẩy toàn bộ event vào topic Redpanda `nyc-taxi-events`. | MUST | Kafka consumer đọc lại đúng số lượng event Vector đã publish. |
| FR-04 | Hệ thống lưu bảng tham chiếu TLC Taxi Zone (265 bản ghi) trên MinIO. | MUST | File CSV tồn tại ở bucket `tlc-zone`, đọc được qua S3 API. |

### 4.2. Nhóm Stream Processing

| Mã | Yêu cầu | Mức độ | Tiêu chí nghiệm thu |
|----|---------|:------:|---------------------|
| FR-05 | RisingWave khai báo `SOURCE` kết nối topic Redpanda. | MUST | `SELECT * FROM source LIMIT 10` trả về dữ liệu hợp lệ. |
| FR-06 | RisingWave khai báo `TABLE` đọc TLC Taxi Zone từ MinIO. | MUST | Table chứa đúng 265 bản ghi. |
| FR-07 | Hệ thống tạo Materialized View v1 — **Blue**: JOIN luồng sự kiện với Taxi Zone, tổng hợp theo Zone. | MUST | MV cập nhật liên tục; `SELECT` phản ánh event mới nhất. |
| FR-08 | Hệ thống tạo Materialized View v2 — **Green**: logic phân tích mới, chạy song song Blue. | MUST | MV Green backfill độc lập, không làm gián đoạn Blue. |
| FR-09 | Hệ thống ghi kết quả MV xuống Apache Iceberg (Built-in Hosted Catalog) trên MinIO. | MUST | Có file metadata JSON + Parquet trong bucket `iceberg-data`. |
| FR-10 | RisingWave offload state (checkpoint) xuống MinIO bucket `rw-checkpoint`. | MUST | Restart pod → MV tiếp tục từ offset gần nhất, không mất state. |

### 4.3. Nhóm Blue/Green MV Swap & GitOps

| Mã | Yêu cầu | Mức độ | Tiêu chí nghiệm thu |
|----|---------|:------:|---------------------|
| FR-11 | Toàn bộ SQL và manifest triển khai được quản lý trong một Git repo duy nhất. | MUST | Repo chứa `gitops/`; ArgoCD trỏ vào đó. |
| FR-12 | ArgoCD tự động sync khi có commit mới trên nhánh chính. | MUST | Commit thử → ArgoCD detect & sync ≤ 3 phút. |
| FR-13 | Hệ thống phát hiện Green backfill hoàn tất dựa trên Consumer Lag. | MUST | Khi lag ≤ ngưỡng trong khoảng quan sát, trạng thái chuyển "READY". |
| FR-14 | Hệ thống thực hiện `ALTER MATERIALIZED VIEW ... SWAP WITH ...` nguyên tử khi Green sẵn sàng. | MUST | Sau swap, tên public `mv_zone_stats` trỏ về định nghĩa Green; Blue chờ drop. |
| FR-15 | Hệ thống tự drop MV cũ sau khi swap thành công, sau khoảng retention định sẵn. | SHOULD | `SHOW MATERIALIZED VIEWS` không còn MV cũ sau thời gian retention. |
| FR-16 | Kubernetes Job thực hiện swap chạy qua ArgoCD PostSync Hook. | MUST | Sync thành công → Job tự động tạo; log rõ từng bước. |

### 4.4. Nhóm Monitoring & Observability

| Mã | Yêu cầu | Mức độ | Tiêu chí nghiệm thu |
|----|---------|:------:|---------------------|
| FR-17 | VictoriaMetrics scrape metrics từ Redpanda, RisingWave, Vector, MinIO. | MUST | Query `up == 1` trả về đúng các service. |
| FR-18 | Grafana có 4 dashboard ứng với 4 nhóm chỉ số đánh giá. | MUST | Hiển thị: Streaming Perf · Resource Utilization · Cutover · Data Integrity. |
| FR-19 | Hệ thống ghi log sự kiện swap (start → ready → swapped → drop) để truy vết. | SHOULD | Log xem được qua `kubectl logs`. |

### 4.5. Nhóm Data Quality & Verification

| Mã | Yêu cầu | Mức độ | Tiêu chí nghiệm thu |
|----|---------|:------:|---------------------|
| FR-20 | Hệ thống đếm số record đầu vào (Vector) vs đầu ra (Iceberg) để so khớp. | MUST | Query hoặc script trả ra số lượng hai đầu để tính tỉ lệ loss. |
| FR-21 | Hệ thống phát hiện được duplicate record trong Iceberg theo `event_id`. | MUST | `GROUP BY event_id HAVING COUNT(*) > 1` trả về kết quả có thể đo đếm. |
| FR-22 | Hệ thống đo downtime thực tế trong lúc swap. | MUST | Script polling query `mv_zone_stats` liên tục; báo thời điểm thất bại (nếu có). |

---

## 5. Yêu cầu phi chức năng (Non-Functional Requirements)

### 5.1. Hiệu năng (Performance)

| Mã | Yêu cầu | Mục tiêu |
|----|---------|----------|
| NFR-01 | Throughput pipeline end-to-end trên hạ tầng tham chiếu (`continux-imac` + `continux-vps`). | ≥ 5.000 events/s ổn định; stretch goal 10.000 events/s (có thể đạt khi thêm `helios`/`nammn` làm worker). |
| NFR-02 | Độ trễ end-to-end Vector → Iceberg. | P95 ≤ 5 giây ở mức tải mục tiêu. |
| NFR-03 | Consumer Lag trong điều kiện thường. | ≤ 2 giây. Spike trong lúc backfill Green được chấp nhận. |

### 5.2. Độ tin cậy (Reliability)

| Mã | Yêu cầu | Mục tiêu |
|----|---------|----------|
| NFR-04 | **Zero-downtime khi swap MV.** | Downtime đo được ≤ 1 giây; mục tiêu 0s. |
| NFR-05 | **Exactly-Once Semantics** xuyên suốt swap. | Tỉ lệ duplicate ≤ 0,01%; tỉ lệ loss ≤ 0,01%. |
| NFR-06 | Phục hồi sau restart pod RisingWave. | MV tiếp tục từ offset checkpoint gần nhất, không mất state. |
| NFR-07 | Pipeline chạy liên tục ≥ 4h không crash ở tải mục tiêu. | Verify trong test end-to-end (FR-09). |

### 5.3. Khả năng vận hành & Quan sát (Operability)

| Mã | Yêu cầu | Mục tiêu |
|----|---------|----------|
| NFR-08 | Toàn bộ cấu hình được quản lý khai báo qua Git — không cấu hình thủ công trên cluster. | Không `kubectl apply` thủ công sau bước bootstrap. |
| NFR-09 | Thay đổi thuật toán chỉ cần commit SQL. | Thời gian commit → sync ≤ 3 phút. |
| NFR-10 | Dashboard Grafana hiển thị real-time. | Refresh ≤ 30s. |
| NFR-11 | Cảnh báo khi Consumer Lag vượt ngưỡng. | SHOULD — cấu hình qua VictoriaMetrics alerting rules. |

### 5.4. Tài nguyên & Khả năng mở rộng (Resource & Scalability)

| Mã | Yêu cầu | Mục tiêu |
|----|---------|----------|
| NFR-12 | Chạy trên hạ tầng tham chiếu 2 node chính (§1.1) mà không pod nào `OOMKilled` trong 4h. | Swap không vượt quá 20% trên cả hai node. |
| NFR-13 | Mỗi thành phần có thể scale horizontally khi thêm worker (`helios`, `nammn`, hoặc node mới). | Verified qua cấu hình `replicas` trong Helm values. |
| NFR-14 | Dung lượng Iceberg ≤ 50 GB trong suốt đồ án. | Compact và retention được cấu hình. |

### 5.5. Bảo mật (Security)

| Mã | Yêu cầu | Mục tiêu |
|----|---------|----------|
| NFR-15 | Access key MinIO riêng biệt cho Vector, RisingWave, ArgoCD (least-privilege). | Mỗi service chỉ có quyền tối thiểu cần thiết. |
| NFR-16 | Secret trong repo Git không lưu plaintext. | COULD — ít nhất dùng K8s Secret; tốt hơn: Sealed Secrets. |
| NFR-17 | Grafana và ArgoCD UI có xác thực username/password. | Không để mặc định; đổi ngay lần đầu đăng nhập. |

### 5.6. Khả năng bảo trì (Maintainability)

| Mã | Yêu cầu | Mục tiêu |
|----|---------|----------|
| NFR-18 | Repo tuân theo cây thư mục tại §2 của tài liệu này. | Thành viên mới setup được trong ≤ 1 buổi theo [SETUP.md](./SETUP.md). |
| NFR-19 | Mỗi phiên bản MV SQL lưu lịch sử qua Git với changelog ngắn trong commit message. | Xem quy ước commit §8. |
| NFR-20 | Tài liệu kỹ thuật cập nhật song song với code. | `docs/` đồng bộ với phiên bản deploy hiện tại. |

### 5.7. Tính tái lập (Reproducibility)

| Mã | Yêu cầu | Mục tiêu |
|----|---------|----------|
| NFR-21 | Cluster dựng lại từ đầu bằng scripts + manifests trong repo. | Một lệnh `make bootstrap` hoặc tuần tự theo [SETUP.md](./SETUP.md). |
| NFR-22 | Dataset dùng nguồn công khai, ghi rõ ngày snapshot/tải. | Ghi trong [PROPOSE.md](./PROPOSE.md) và [REPORT.md](./REPORT.md). |

---

## 6. Ràng buộc (Constraints)

| Mã | Ràng buộc |
|----|-----------|
| C-01 | Stack **JVM-free**: không dùng Flink, Kafka JVM, ksqlDB JVM. Chỉ dùng Rust/C++ (RisingWave, Redpanda, Vector). |
| C-02 | Phải dùng **RisingWave Built-in Hosted Catalog** cho Iceberg — không triển khai Hive Metastore hay Nessie. |
| C-03 | Mô phỏng luồng **bắt buộc qua Vector** — không dùng producer Python/Java tự viết để tránh rò rỉ bộ nhớ. |
| C-04 | Triển khai **bắt buộc qua ArgoCD GitOps** — không `kubectl apply` thủ công sau bước bootstrap ban đầu. |
| C-05 | Toàn bộ Iceberg data + checkpoint lưu trên **MinIO tự dựng** trên `continux-imac` — không dùng S3 thật. |
| C-06 | Lưu lượng liên node bắt buộc qua **Tailscale overlay** — không expose K3s API, Redpanda, MinIO ra internet. |
| C-07 | Chi phí hạ tầng trả phí tối đa **$24/tháng** (một DigitalOcean Droplet) — không thêm Managed DB / LB / Spaces. |

---

## 7. Giả định (Assumptions)

- Các node kết nối ổn định qua Tailscale; ping inter-node < 100 ms.
- GVHD sẵn sàng review tài liệu trong khoảng 15–19/04/2026.
- Dataset NYC TLC còn truy cập được; nếu không, dùng bản snapshot đã tải sẵn.
- Nhóm có quyền admin trên `continux-imac`, `continux-vps`; có thể bật WSL2 trên `helios` và `nammn` khi cần.
- Droplet DigitalOcean duy trì từ 13/04 → 31/05/2026; chi phí ước tính $20–40 tuỳ có resize hay không.

---

## 8. Ngoài phạm vi (Out of Scope)

- Triển khai multi-cluster / multi-region.
- Tích hợp mô hình Machine Learning trực tiếp trong Materialized View.
- Ingest dữ liệu IoT thực tế (camera, GPS thời gian thực).
- Kiểm thử bảo mật xâm nhập (pentest) toàn diện.
- Tối ưu chi phí cloud (không áp dụng cho on-premise K3s).

---

## 9. Phân công trách nhiệm (RACI)

| Hạng mục | Sỹ — 23521367 | Nam — 23520982 | GVHD |
|----------|:-------------:|:--------------:|:----:|
| Chốt scope & đề cương | A/R | C | C/A |
| Nghiên cứu lý thuyết (Ursa, Iceberg, RisingWave) | A/R | C | C |
| Viết tài liệu (ARCHITECTURE, TIMELINE, SETUP, REPORT) | A/R | C | I |
| Document Freeze 19/04 | A/R | C | A |
| Thiết lập K3s + Tailscale (`continux-imac`, `continux-vps`) | A/R | C | I |
| Deploy ArgoCD + GitOps repo | A/R | C | I |
| Deploy MinIO, Redpanda, RisingWave | A/R | C | I |
| Deploy VictoriaMetrics + Grafana | A/R | C | I |
| Pipeline Vector → Redpanda → RisingWave → Iceberg | A/R | C | I |
| Blue/Green MV Swap + PostSync Hook | A/R | C | I |
| Join `helios` / `nammn` làm K3s worker khi cần | R | R | I |
| Thực nghiệm & thu thập số liệu | A/R | C | I |
| Viết báo cáo (REPORT.md → LaTeX) | A/R | C | A |
| Demo hệ thống 31/05/2026 | A/R | C | A |

**Ký hiệu:** R = Responsible (thực hiện) · A = Accountable (chịu trách nhiệm) · C = Consulted (tham khảo) · I = Informed (thông báo).

---

## 10. Quy ước nhánh Git & commit

**Nhánh:**
- `main` — ArgoCD theo dõi; chỉ merge khi đã review. Mọi merge đều tác động trực tiếp đến cluster.
- `feat/<tên>` — nhánh phát triển tính năng hoặc MV mới.
- `exp/<tên>` — nhánh thực nghiệm; không merge vào `main`.

**Commit message (Conventional Commits):**
```
feat(mv): add green v2 with hourly aggregation
chore(infra): bump risingwave to 2.5.0
fix(sink): correct iceberg partition spec
docs: update ARCHITECTURE NFR-12
```

**Pull Request:** mọi thay đổi trên `main` đi qua PR dù nhóm chỉ 2 người — bắt buộc vì ArgoCD auto-sync trên mỗi merge.

---

## 11. Bản đồ tài liệu ↔ mã nguồn

| Tài liệu | Artefact tương ứng trong repo |
|----------|-----------------------------|
| [PROPOSE.md](./PROPOSE.md) | — (tài liệu học thuật, không ánh xạ trực tiếp vào code) |
| [ARCHITECTURE.md §4–§6](./ARCHITECTURE.md) (FR/NFR) | `gitops/pipeline/`, `sql/`, `config/` (FR-01…FR-22 → manifest và SQL cụ thể) |
| [ARCHITECTURE.md §2](./ARCHITECTURE.md) (cây thư mục) | Toàn bộ cấu trúc repo |
| [TIMELINE.md](./TIMELINE.md) (mốc M1–M7) | Git tag: `v0.1-m3-infra-ready`, `v1.0-m7-final`, … |
| [REPORT.md §3](./REPORT.md) (Chương 3 — Phương pháp) | Sơ đồ từ `docs/diagrams/` |
| [REPORT.md §4](./REPORT.md) (Chương 4 — Kết quả) | Dữ liệu từ `experiments/results/`, screenshot từ Grafana |

---

## 12. Workflow vận hành hiện tại

- Windows là môi trường phát triển chính: sửa code, commit và push lên GitHub.
- `continux-imac` là máy quản trị cluster: giữ clone repo ở `~/continux`, chạy `kubectl`, `helm`, `argocd`, `rpk`, `mc`, `psql`.
- Sau bootstrap `root-app`, ArgoCD lấy manifest từ GitHub; repo local trên iMac chủ yếu dùng cho các lệnh bootstrap, kiểm tra và thao tác vận hành cần file manifest local.

## 13. Lệnh tiện ích (Makefile targets)

```make
make bootstrap           # Cài K3s + join node + install ArgoCD (chạy lần đầu)
make join-worker NODE=helios   # Join helios làm K3s worker qua WSL2
make join-worker NODE=nammn    # Join nammn làm K3s worker qua WSL2
make argocd-sync         # Sync thủ công toàn bộ App-of-Apps
make upload-zone         # Upload TLC Taxi Zone lên MinIO
make vector-start        # Chạy Vector với preset throughput
make swap-dry-run        # Chạy Job swap ở chế độ dry-run (không ALTER)
make experiment NAME=throughput-sweep
make dashboards-export   # Export lại JSON dashboards từ Grafana
```
