# SCRIPTS

Tất cả script nằm trong `scripts/`. Setup mặc định chỉ cần các script K3s, token, check, version và converter dataset.

## Danh sách

| Script | Chạy trên | Mục đích |
|--------|-----------|----------|
| `k3s-install-server-init.sh` | `imac` | Khởi tạo K3s server #1 với embedded etcd |
| `k3s-token.sh` | `imac` | In K3s server join token |
| `k3s-install-server.sh` | `continux-vps`, `helios-pc` | Join server #2/#3 vào cluster |
| `wsl-enable-shared-root.sh` | `helios-pc` WSL | Bật shared root mount propagation để node-exporter/hostPath chạy được |
| `k3s-check.sh` | `imac` | Kiểm tra overview, nodes/pods, workloads, storage, local resources, images, Helm |
| `k3s-purge.sh` | K3s server có kubeconfig | Reset cluster hoặc xóa K3s khỏi node |
| `tool-version.sh` | Ubuntu node | Kiểm tra CLI so với latest stable |
| `partojsonl.py` | `imac` | Convert NYC TLC Yellow Taxi Parquet sang JSONL |
| `k3s-install.sh` | optional worker | Helper agent generic, không thuộc setup mặc định |

## `k3s-install-server-init.sh`

Khởi tạo cluster trên `imac`:

```bash
sudo bash scripts/k3s-install-server-init.sh
```

Script tự lấy Tailscale IPv4, cài K3s stable channel, dùng `--cluster-init`, tắt Traefik/ServiceLB/metrics-server, giữ local-path storage mặc định, đặt `--flannel-iface=tailscale0`, gán label `workload=heavy role=data-plane`, rồi in lệnh join cho `continux-vps` và `helios-pc`.

## `k3s-token.sh`

In join token:

```bash
bash scripts/k3s-token.sh
```

Nếu user hiện tại không đọc được token file, script tự gọi `sudo cat /var/lib/rancher/k3s/server/node-token`.

## `k3s-install-server.sh`

Join K3s server:

```bash
sudo bash scripts/k3s-install-server.sh <tailscale-ip-imac> <token> continux-vps edge
sudo bash scripts/k3s-install-server.sh <tailscale-ip-imac> <token> helios-pc quorum
```

Profile:

| Profile | Label | Taint |
|---------|-------|-------|
| `edge` | `workload=light role=control-plane` | `dedicated=edge:NoSchedule` |
| `quorum` | `workload=quorum role=quorum` | `dedicated=quorum:NoSchedule` |

## `wsl-enable-shared-root.sh`

Chạy trên WSL `helios-pc` sau khi node đã join K3s:

```bash
sudo bash scripts/wsl-enable-shared-root.sh
```

Script chạy `mount --make-rshared /`, tạo `wsl-shared-root.service`, thêm ordering để `k3s.service` chạy sau service này, rồi restart K3s. Output đã xác nhận trong v0.2.2:

```text
/ shared
```

## `k3s-check.sh`

```bash
bash scripts/k3s-check.sh
bash scripts/k3s-check.sh -e
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

Default report in dạng 2 cột để dễ đọc trên terminal rộng: cột 1 gồm section 1-3 (overview, node/pod layout, workloads/HPA/services), cột 2 gồm section 4-8 (storage, tài nguyên local node, images, Helm, secrets). Mỗi cột tự wrap và tự chảy nội dung trong chiều rộng riêng để giữ vạch phân chia liền mạch, không tạo khoảng trống giả khi cột đối diện có dòng dài. Các bảng có namespace được gom theo header `>> <namespace>` thay vì lặp cột `NS`; cuối report có legend giải thích các khái niệm/cột chính. `overview` có graph nhanh cho RAM/disk local, mật độ pod theo node và hot list các pod lỗi/restart.

Report export được ghi vào `scripts/k3s-check/k3s-check-<HHmmss-ddmmyy>.txt`.

## `k3s-purge.sh`

Reset cluster về trạng thái vừa cài K3s, giữ K3s và các node:

```bash
bash scripts/k3s-purge.sh
bash scripts/k3s-purge.sh --yes
```

Chế độ này xóa Helm releases, Argo CD Applications/finalizers, app namespaces, app resources, PV/PVC objects và CRD thuộc stack dự án.

Xóa dấu vết K3s khỏi node hiện tại:

```bash
sudo bash scripts/k3s-purge.sh --nuke
sudo bash scripts/k3s-purge.sh --nuke --yes
```

Chạy `--nuke` trên từng node khi muốn phá cụm hoàn toàn.

## `tool-version.sh`

```bash
bash scripts/tool-version.sh
```

Script kiểm tra OS, kernel, APT packages, Tailscale, K3s, kubectl, Helm, Argo CD CLI, rpk, mc và psql.

## `partojsonl.py`

```bash
python scripts/partojsonl.py \
  data/raw/yellow_tripdata_<yyyy-mm>.parquet \
  data/raw/yellow_tripdata_<yyyy-mm>.jsonl
```

Smoke run:

```bash
python scripts/partojsonl.py input.parquet output.jsonl --limit 1000
```

Output JSONL chứa các field pipeline cần: `pickup_time`, `pu_location_id`, `do_location_id`, `fare_amount`, `trip_distance`.

## `k3s-install.sh`

Helper agent generic:

```bash
sudo bash scripts/k3s-install.sh <tailscale-ip-imac> <token> <node-name>
```

Script này không nằm trong luồng setup mặc định.
