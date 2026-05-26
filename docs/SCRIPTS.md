# SCRIPTS

Tất cả script vận hành nằm trong `scripts/`. Repo chỉ giữ các script thuộc topology 3 K3s server của dự án; helper generic ngoài topology không được thêm vào đây.

## Danh Sách

| Script | Chạy trên | Mục đích |
|--------|-----------|----------|
| `k3s-install-server-init.sh` | `imac` | Khởi tạo K3s server #1 với embedded etcd |
| `k3s-token.sh` | `imac` | In K3s server join token |
| `k3s-install-server.sh` | `continux-vps`, `helios-pc` | Join server #2/#3 vào cluster |
| `wsl-enable-shared-root.sh` | `helios-pc` WSL | Bật shared root mount propagation để node-exporter/hostPath chạy được |
| `k3s-check.sh` | `imac` | Kiểm tra overview, nodes/pods, workloads, storage, local resources, images, Helm và secrets |
| `tool-version.sh` | Ubuntu node | Kiểm tra CLI và phiên bản công cụ |
| `partojsonl.py` | `imac` | Convert NYC TLC Yellow Taxi Parquet sang JSONL |
| `k3s-purge.sh` | K3s server có kubeconfig | Công cụ reset/phá hủy có chủ đích |

## `k3s-install-server-init.sh`

Khởi tạo cluster trên `imac`:

```bash
cd ~/continux
sudo bash scripts/k3s-install-server-init.sh
```

Script tự lấy Tailscale IPv4, cài K3s stable channel, dùng `--cluster-init`, tắt Traefik/ServiceLB/metrics-server, giữ local-path storage mặc định, đặt `--flannel-iface=tailscale0`, gán label `workload=heavy role=data-plane`, rồi in hướng dẫn join cho hai server còn lại.

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

Script chạy `mount --make-rshared /`, tạo `wsl-shared-root.service`, thêm ordering để `k3s.service` chạy sau service này, rồi restart K3s.

Output mong đợi:

```text
/ shared
```

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

Report mặc định in dạng hai cột:

- Cột 1: overview, topology/nodes/pods, workloads/HPA/services.
- Cột 2: PVC, tài nguyên local node, images, Helm, secrets.

`overview` có health summary, graph nhanh RAM/disk local, mật độ pod theo node và hot list các pod lỗi/restart. Report export được ghi vào `scripts/k3s-check/k3s-check-<HHmmss-ddmmyy>.txt`.

## `tool-version.sh`

```bash
cd ~/continux
bash scripts/tool-version.sh
```

Script kiểm tra OS, kernel, APT packages, Tailscale, K3s, kubectl, Helm, Argo CD CLI, rpk, mc và psql.

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

## `k3s-purge.sh`

`k3s-purge.sh` là công cụ phá hủy có chủ đích. Không dùng trong luồng chính của [RUNBOOK.md](./RUNBOOK.md).

Reset cluster về trạng thái vừa cài K3s, giữ K3s và các node:

```bash
cd ~/continux

bash scripts/k3s-purge.sh
bash scripts/k3s-purge.sh --yes
```

Chế độ này xóa Helm releases, Argo CD Applications/finalizers, app namespaces, app resources, PV/PVC objects và CRD thuộc stack dự án.

Xóa dấu vết K3s khỏi node hiện tại:

```bash
cd ~/continux

sudo bash scripts/k3s-purge.sh --nuke
sudo bash scripts/k3s-purge.sh --nuke --yes
```

Chỉ chạy `--nuke` khi đã quyết định phá cụm. Nếu cần phá toàn bộ cụm, chạy có kiểm soát trên từng node và xác nhận không còn cần dữ liệu local.
