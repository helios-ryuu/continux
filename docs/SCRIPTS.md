# SCRIPTS

Tất cả script vận hành nằm trong `scripts/`. Repo chỉ giữ các script thuộc bố trí 3 K3s server của dự án; helper dùng chung ngoài bố trí này không được thêm vào đây.

## Danh Sách

| Script | Chạy trên | Mục đích |
|--------|-----------|----------|
| `k3s-install-server-init.sh` | `imac` | Khởi tạo K3s server #1 với embedded etcd |
| `k3s-token.sh` | `imac` | In K3s server join token |
| `k3s-install-server.sh` | `continux-vps`, `helios-pc` | Join server #2/#3 vào cluster |
| `wsl-enable-shared-root.sh` | `helios-pc` WSL | Bật shared root mount propagation để node-exporter/hostPath chạy được |
| `host-update.sh` | Cả ba node | Cập nhật CLI theo vai trò host và chuẩn hóa symlink K3s mà không khởi động lại K3s |
| `k3s-check.sh` | `imac` | Kiểm tra tổng quan, node/pod, workload, lưu trữ, tài nguyên cục bộ, image, Helm và secret |
| `tool-version.sh` | Ubuntu node | Kiểm tra CLI và phiên bản công cụ |
| `partojsonl.py` | `imac` | Convert NYC TLC Yellow Taxi Parquet sang JSONL |
| `../experiments/runners/demo.sh` | `imac` | Chạy thực nghiệm theo pha, thu bằng chứng và dọn dẹp an toàn |
| `k3s-purge.sh` | K3s server có kubeconfig | Công cụ reset/phá hủy có chủ đích |
| `nuke.sh` | Từng host Continux | Xóa toàn bộ trạng thái dự án trên host hiện tại, giữ Tailscale |

## `k3s-install-server-init.sh`

Khởi tạo cluster trên `imac`:

```bash
cd ~/continux
sudo bash scripts/k3s-install-server-init.sh
```

Script tự lấy Tailscale IPv4, cài K3s từ kênh `stable`, dùng
`INSTALL_K3S_SYMLINK=force` và `--cluster-init`, tắt
Traefik/ServiceLB/metrics-server, giữ lưu trữ `local-path` mặc định, đặt
`--flannel-iface=tailscale0`, gán label `workload=heavy role=data-plane`, rồi
in hướng dẫn join cho hai server còn lại.

## `k3s-token.sh`

In join token:

```bash
cd ~/continux
bash scripts/k3s-token.sh
```

Nếu user hiện tại không đọc được token file, script tự dùng `sudo cat /var/lib/rancher/k3s/server/node-token`.

## `k3s-install-server.sh`

Join K3s server:

```bash
cd ~/continux

sudo bash scripts/k3s-install-server.sh <imac-tailscale-ip> <k3s-token> continux-vps edge
sudo bash scripts/k3s-install-server.sh <imac-tailscale-ip> <k3s-token> helios-pc quorum
```

Profile:

| Profile | Label | Taint |
|---------|-------|-------|
| `edge` | `workload=light role=control-plane` | `dedicated=edge:NoSchedule` |
| `quorum` | `workload=quorum role=quorum` | `dedicated=quorum:NoSchedule` |

## `wsl-enable-shared-root.sh`

Chạy trên WSL `helios-pc` sau khi node đã join K3s:

```bash
cd ~/continux
sudo bash scripts/wsl-enable-shared-root.sh
```

Script chạy `mount --make-rshared /`, tạo `wsl-shared-root.service`, thêm thứ tự để `k3s.service` chạy sau service này, rồi khởi động lại K3s.

Output mong đợi:

```text
/ shared
```

## `host-update.sh`

Sau khi pull release mới, chạy đúng vai trò trên từng host:

```bash
# imac
sudo bash scripts/host-update.sh admin

# continux-vps
sudo bash scripts/host-update.sh server

# helios-pc WSL
sudo bash scripts/host-update.sh wsl-server
```

Script kiểm tra K3s đang ở đúng kênh `stable`, ép `kubectl`, `crictl`, `ctr`
trỏ về `/usr/local/bin/k3s` và không khởi động lại K3s. Vai trò `admin` còn cập nhật
APT, Helm, Argo CD CLI, rpk và mc. Vai trò `wsl-server` kiểm tra root mount là
`shared`.

## `k3s-check.sh`

```bash
cd ~/continux

bash scripts/k3s-check.sh
bash scripts/k3s-check.sh overview
bash scripts/k3s-check.sh node
bash scripts/k3s-check.sh res
bash scripts/k3s-check.sh pvc
bash scripts/k3s-check.sh sys
bash scripts/k3s-check.sh img
bash scripts/k3s-check.sh helm
bash scripts/k3s-check.sh secrets
bash scripts/k3s-check.sh export
```

Báo cáo mặc định in dạng hai cột:

- Cột 1: tổng quan, bố trí/node/pod, workload/HPA/service.
- Cột 2: PVC, tài nguyên node cục bộ, image, Helm, secret.

`overview` có tóm tắt sức khỏe, biểu đồ nhanh RAM/ổ đĩa cục bộ, mật độ pod theo node và danh sách pod lỗi hoặc khởi động lại nhiều. Báo cáo xuất ra được ghi vào `scripts/k3s-check/k3s-check-<HHmmss-ddmmyy>.txt`.

## `tool-version.sh`

```bash
cd ~/continux
bash scripts/tool-version.sh
bash scripts/tool-version.sh --profile admin
bash scripts/tool-version.sh --profile server
bash scripts/tool-version.sh --profile wsl-server
```

Script kiểm tra hệ điều hành, kernel, gói APT, Tailscale, K3s, kubectl, Helm,
Argo CD CLI, rpk, mc và psql. Các CLI quản trị chỉ bắt buộc trên `imac`; node
server không bị báo lỗi khi thiếu công cụ không cần thiết.

## `partojsonl.py`

```bash
cd ~/continux

python scripts/partojsonl.py \
  data/raw/yellow_tripdata_<yyyy-mm>.parquet \
  data/raw/yellow_tripdata_<yyyy-mm>.jsonl
```

Smoke run:

```bash
cd ~/continux

python scripts/partojsonl.py input.parquet output.jsonl --limit 1000
```

Output JSONL chứa các field pipeline cần: `pickup_time`, `pu_location_id`, `do_location_id`, `fare_amount`, `trip_distance`.

## `experiments/runners/demo.sh`

Runner giữ các pha tách biệt để có thể quan sát và debug giữa từng bước:

```bash
cd ~/continux

bash experiments/runners/demo.sh preflight
bash experiments/runners/demo.sh init smoke
bash experiments/runners/demo.sh prepare-data
bash experiments/runners/demo.sh baseline
bash experiments/runners/demo.sh replay
bash experiments/runners/demo.sh cutover
bash experiments/runners/demo.sh cleanup-runtime
bash experiments/runners/demo.sh cleanup-local
```

`smoke` phát `2 events/s` và là mặc định an toàn. Các profile
`benchmark-low`, `benchmark-medium`, `benchmark-high` chỉ chạy khi chọn rõ.
Bằng chứng được giữ tại `~/continux-demo-evidence/<RUN_ID>/`; xóa bằng chứng là
thao tác riêng:

```bash
bash experiments/runners/demo.sh purge-evidence <RUN_ID>
```

## `k3s-purge.sh`

`k3s-purge.sh` là công cụ phá hủy có chủ đích. Không dùng trong luồng chính của [CLEANUP.md](./runbook/CLEANUP.md).

Reset cluster về trạng thái vừa cài K3s, giữ K3s và các node:

```bash
cd ~/continux

bash scripts/k3s-purge.sh
bash scripts/k3s-purge.sh --yes
```

Chế độ này xóa Helm release, Helm repository cục bộ, Argo CD Application/finalizer, namespace của app, tài nguyên app, object PV/PVC, CRD thuộc stack dự án và các tài nguyên dự án còn sót trong `kube-system` như service `victoria-metrics-*`. Nếu `redpanda.service` đang tồn tại trên host chạy script, script sẽ dừng và vô hiệu hóa service này để không nhiễu trạng thái nền; không chạm các dịch vụ ngoài như Docker/Grafana. Cache image không được dọn tự động; nếu cần dọn image cũ, chạy thủ công trên từng node bằng `sudo k3s crictl rmi --prune`.

Xóa dấu vết K3s khỏi node hiện tại:

```bash
cd ~/continux

sudo bash scripts/k3s-purge.sh --nuke
sudo bash scripts/k3s-purge.sh --nuke --yes
```

Chỉ chạy `--nuke` khi đã quyết định phá cụm. Nếu cần phá toàn bộ cụm, chạy có kiểm soát trên từng node và xác nhận không còn cần dữ liệu cục bộ.

## `nuke.sh`

`nuke.sh` là mức phá môi trường host-local đầy đủ hơn `k3s-purge.sh --nuke`.
Script này giữ nguyên Tailscale, nhưng xóa trạng thái Continux trên host hiện
tại: K3s, cấu hình CNI/kubelet, drop-in WSL, rule UFW dành cho K3s/pod/service,
CLI quản trị dự án, cấu hình Helm/Argo CD/MinIO client của user chạy setup,
gói APT `redpanda`, `postgresql-client`, `python3-venv`, bằng chứng demo và
checkout Continux.

Mặc định chỉ dry-run, không xóa gì:

```bash
cd ~/continux
bash scripts/nuke.sh
```

Chạy thật cần `sudo`, cờ `--execute` và xác nhận chính xác
`NUKE-CONTINUX`:

```bash
cd ~/continux
sudo bash scripts/nuke.sh --execute
```

Nếu chạy không tương tác, vẫn phải truyền `--execute`:

```bash
cd ~/continux
sudo bash scripts/nuke.sh --execute --yes
```

Script chỉ xử lý node hiện tại, không SSH sang node khác. Nếu phá toàn bộ bố trí
ba máy, chạy riêng trên `imac`, `continux-vps` và WSL `helios-pc`. Không dùng
script này để dọn giữa hai lượt thực nghiệm; dùng runner cleanup trong
[CLEANUP.md](./runbook/CLEANUP.md) cho luồng đó.
