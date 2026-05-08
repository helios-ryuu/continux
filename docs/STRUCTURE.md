# STRUCTURE — CẤU TRÚC THƯ MỤC DỰ ÁN ĐỀ XUẤT

> **Mục đích:** chuẩn hoá cấu trúc repo để hai thành viên (và GVHD) định vị nhanh mọi artefact — tài liệu, manifest GitOps, SQL MV, cấu hình Vector, dashboard Grafana, script thực nghiệm.
> **Nguyên tắc:** tách bạch 3 trục lớn — **tài liệu (`docs/`)** · **triển khai khai báo (`gitops/`)** · **logic xử lý dữ liệu (`sql/`, `pipelines/`)** — cộng thêm tầng tiện ích (`scripts/`, `experiments/`, `dashboards/`).

---

## 1. Cây thư mục tổng quát

```
continux/
├── README.md                        # Tổng quan repo (giữ như hiện tại)
├── LICENSE
├── Makefile                         # Lệnh tiện ích: bootstrap, sync, experiment
├── .gitignore
│
├── docs/                            # Toàn bộ tài liệu đồ án
│   ├── PROPOSE.md                   # Đề cương (nguồn)
│   ├── REPORT.md                    # Báo cáo tổng thể (sẽ convert sang LaTeX)
│   ├── REQUIREMENT.md               # Yêu cầu FR + NFR
│   ├── STRUCTURE.md                 # (chính file này)
│   ├── TIMELINE.md                  # Lộ trình theo mốc
│   ├── WBS.md                       # Work Breakdown Structure
│   ├── diagrams/                    # Sơ đồ kiến trúc (PlantUML, Mermaid, PNG)
│   │   ├── architecture-overview.puml
│   │   ├── bluegreen-sequence.puml
│   │   └── exports/                 # PNG render cho báo cáo
│   ├── references/                  # PDF bài báo nền tảng + chú thích
│   │   └── ursa-vldb-2025.pdf
│   └── meeting-notes/               # Biên bản họp với GVHD
│       └── 2026-04-08-scope-lock.md
│
├── config/                          # Helm values & K8s manifests (nguồn cho ArgoCD)
│   ├── argocd/
│   │   ├── helm-values.yaml         # ArgoCD Helm values (nodeSelector, resources, insecure)
│   │   └── cloudflared.yaml         # ConfigMap + Deployment Cloudflare Tunnel
│   ├── minio/
│   │   ├── helm-values.yaml
│   │   └── buckets-job.yaml
│   ├── redpanda/
│   │   └── helm-values.yaml
│   ├── risingwave/
│   │   ├── helm-values.yaml
│   │   └── secrets.yaml             # (SealedSecrets/SOPS)
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
│   │   ├── root-app.yaml            # ArgoCD Application quản lý toàn bộ child apps
│   │   ├── infra-app.yaml
│   │   ├── pipeline-app.yaml
│   │   └── observability-app.yaml
│   └── pipeline/                    # Job manifests cho pipeline automation
│       ├── sql-configmap.yaml       # Template nạp SQL từ sql/ vào ConfigMap
│       ├── mv-apply-job.yaml        # Job chạy psql áp dụng MV hiện tại
│       ├── swap-job.yaml            # Job swap Blue/Green (PostSync Hook)
│       └── kustomization.yaml
│
├── sql/                             # Mọi SQL chạy trên RisingWave
│   ├── 01-sources/                  # CREATE SOURCE
│   │   └── redpanda-nyc-taxi.sql
│   ├── 02-tables/                   # CREATE TABLE (Taxi Zone từ MinIO)
│   │   └── tlc-taxi-zone.sql
│   ├── 03-mv/                       # Materialized Views
│   │   ├── mv_zone_stats_blue.sql
│   │   └── mv_zone_stats_green.sql
│   ├── 04-sinks/                    # Iceberg Sink
│   │   └── iceberg-zone-stats.sql
│   └── README.md                    # Quy ước đặt tên & thứ tự áp dụng
│
├── pipelines/                       # Cấu hình runtime cho các tool
│   ├── vector/
│   │   ├── vector.toml              # Source CSV → transform → sink Redpanda
│   │   └── rates/                   # Preset throughput 1k/5k/10k/20k
│   │       ├── low.env
│   │       ├── medium.env
│   │       └── high.env
│   └── redpanda/
│       └── topics.yaml              # Khai báo topic + retention (IaC)
│
├── dashboards/                      # Grafana dashboards (JSON export)
│   ├── 01-streaming-perf.json
│   ├── 02-resource-util.json
│   ├── 03-cutover.json
│   └── 04-data-integrity.json
│
├── experiments/                     # Thực nghiệm & kết quả thô
│   ├── scenarios/                   # Kịch bản đo (YAML)
│   │   ├── throughput-sweep.yaml
│   │   └── cutover-repeat-5x.yaml
│   ├── runners/                     # Script chạy thử nghiệm (bash/python)
│   │   ├── run_stress.sh
│   │   ├── run_swap.sh
│   │   └── verify_integrity.py
│   └── results/                     # CSV/JSON output (ignored trong .gitignore nếu quá lớn)
│       ├── 2026-05-13-stress.csv
│       └── 2026-05-15-cutover.csv
│
├── scripts/                         # Tiện ích vận hành
│   ├── bootstrap-k3s.sh             # Cài K3s + join node
│   ├── install-argocd.sh
│   └── upload-tlc-zone.sh           # Upload CSV Zone lên MinIO
│
├── data/                            # DỮ LIỆU LOCAL — KHÔNG COMMIT
│   ├── raw/                         # NYC TLC parquet/csv tải về
│   └── zone/                        # TLC Taxi Zone lookup CSV (nhỏ, có thể commit)
│
└── tools/                           # (tuỳ chọn) Dockerfile cho image tuỳ biến
    └── swap-runner/
        ├── Dockerfile               # Image chứa psql + script backfill-check
        └── entrypoint.sh
```

---

## 2. Luận giải thiết kế

### 2.1. Vì sao tách `config/` khỏi `gitops/`, `sql/` và `pipelines/`?

- `config/` chứa **Helm values và K8s manifests** cho từng service. ArgoCD Applications trong `gitops/apps/` trỏ vào đây để sync.
- `gitops/` chỉ chứa **ArgoCD Application definitions** và **Job manifests** điều khiển pipeline tự động (swap, apply SQL).
- `sql/` và `pipelines/` chứa **nội dung logic** (SQL, vector.toml). Những file này được **embed** vào ConfigMap/Secret qua Kustomize/Helm — cho phép sửa SQL độc lập với manifest hạ tầng, lại vẫn tuân thủ GitOps (FR-11, FR-12).
- Khi commit SQL mới → Kustomize regenerate ConfigMap → ArgoCD phát hiện drift → Job swap chạy (FR-14, FR-16).

### 2.2. App-of-Apps cho ArgoCD

`gitops/apps/root-app.yaml` là ArgoCD Application "cha" — tự quản lý các Application "con" (infra, pipeline, observability). Cách này:

- Tạo/xoá/tái tạo toàn bộ cluster chỉ bằng **một** `kubectl apply`.
- Tách nhịp sync: infra hiếm khi đổi; pipeline thay đổi thường xuyên (mỗi lần upgrade MV).

### 2.3. Phân lớp SQL theo số thứ tự (`01-sources/` … `04-sinks/`)

- Thứ tự dependency rõ ràng: Source → Table → MV → Sink.
- Job `mv-apply-job` duyệt folder theo thứ tự, tránh lỗi reference.
- Mỗi MV là một file độc lập → dễ diff giữa Blue và Green.

### 2.4. Quy ước đặt tên MV

- `mv_zone_stats_blue` / `mv_zone_stats_green` — đuôi `_blue`/`_green` bắt buộc.
- Công khai (public-facing) là `mv_zone_stats` — bí danh này luôn trỏ về MV hiện hành qua `ALTER ... SWAP WITH`.
- Dashboard/người dùng cuối **chỉ query** `mv_zone_stats` → hệ thống đảm bảo zero-downtime nhờ swap nguyên tử (FR-14, NFR-04).

### 2.5. Node placement qua `nodeSelector` + `tolerations`

Cluster có hai node với vai trò khác nhau (xem [SETUP.md §0](./SETUP.md#0-tổng-quan-hạ-tầng)):
- `continux-imac` (iMac, 8 GB) — giữ mặc định K3s control-plane, gán label `workload=heavy`; dành cho workload nặng (MinIO, Redpanda, RisingWave, Vector).
- `continux-vps` (Droplet, 4 GB) — giữ mặc định K3s control-plane, gán label `workload=light`, taint `dedicated=edge:NoSchedule`; chỉ chấp nhận workload nhẹ có `toleration` tương ứng (ArgoCD, VictoriaMetrics, Grafana).

Mọi `helm-values.yaml` trong `config/` **bắt buộc** khai báo:

```yaml
# Workload nặng → continux-imac (MinIO, Redpanda, RisingWave, Vector)
nodeSelector: { role: data-plane }

# Workload nhẹ → continux-vps (ArgoCD, VictoriaMetrics, Grafana)
nodeSelector: { role: control-plane }
tolerations:
  - { key: dedicated, operator: Equal, value: edge, effect: NoSchedule }
```

> **Lưu ý:** Mỗi node được gán **hai label** (`role` + `workload`) tại §5.3 của SETUP.md. Config files dùng `role` làm selector chính; `workload` dùng để phân loại trong troubleshooting.

Quy ước này giúp scheduler không nhầm RisingWave vào Droplet (sẽ OOM) và không nhầm Grafana vào iMac (ăn RAM của data plane).

### 2.6. `experiments/` tách khỏi `pipelines/`

Khi bảo vệ đồ án, cần chạy lại các kịch bản đo để chứng minh. `experiments/runners/` là code đo lường, `results/` là dữ liệu thô — giữ riêng để không trộn lẫn với code sản xuất.

### 2.7. `data/` không commit

NYC TLC dataset có thể lên đến vài GB — `.gitignore` loại trừ `data/raw/`. Chỉ `data/zone/taxi_zone_lookup.csv` (≤ 20 KB) được commit để đảm bảo khả năng tái lập (NFR-21, NFR-22).

---

## 3. Quy ước nhánh Git & commit

- **Branches:**
  - `main` — ArgoCD theo dõi, chỉ merge khi đã review.
  - `feat/<tên>` — nhánh phát triển tính năng/MV mới.
  - `exp/<tên>` — nhánh thực nghiệm (không merge, chỉ tham khảo).
- **Commit message:**
  - `feat(mv): add green v2 with hourly aggregation`
  - `chore(infra): bump risingwave to 2.3.0`
  - `docs: update REQUIREMENT FR-13`
- **PR:** mọi thay đổi trên `main` đi qua Pull Request (dù nhóm 2 người) để có review chéo — ràng buộc quan trọng vì ArgoCD auto-sync.

---

## 4. Bản đồ tài liệu ↔ mã nguồn

| Tài liệu | Artefact tương ứng |
|----------|--------------------|
| [PROPOSE.md](./PROPOSE.md) | — |
| [REQUIREMENT.md](./REQUIREMENT.md) | FR-01…FR-22 → manifest trong `gitops/pipeline/` và `sql/` |
| [TIMELINE.md](./TIMELINE.md) | Mốc M1–M7 → nhãn Git tag (`v0.1-m3-infra-ready`, `v1.0-m7-final`) |
| [WBS.md](./WBS.md) | Gói 1.x → `docs/`; gói 2.x → `config/`; 3.x → `sql/` + `pipelines/`; 4.x → `gitops/pipeline/` + `tools/swap-runner/`; 5.x → `experiments/`; 6.x → `docs/REPORT.md` |
| [REPORT.md](./REPORT.md) | Chương 3 sử dụng sơ đồ từ `docs/diagrams/`; Chương 4 sử dụng kết quả từ `experiments/results/` và screenshot từ `dashboards/`. |

---

## 5. Lệnh tiện ích gợi ý (Makefile targets)

```make
make bootstrap       # Cài K3s + join node + install ArgoCD
make argocd-sync     # Sync thủ công toàn bộ App-of-Apps
make upload-zone     # Upload TLC Taxi Zone lên MinIO
make vector-start    # Chạy Vector với preset throughput
make swap-dry-run    # Chạy Job swap ở chế độ dry-run (không ALTER)
make experiment NAME=throughput-sweep
make dashboards-export   # Export lại JSON dashboards từ Grafana
```

Target cụ thể được định nghĩa trong `Makefile` ở root.
