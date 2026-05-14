# SCRIPTS — Tài liệu các Script vận hành

Tất cả script nằm trong thư mục `scripts/`. Mỗi script có ghi rõ **máy nào chạy** trong header.

## Mục lục

| Script | Chạy trên | Mục đích |
|--------|-----------|----------|
| [k3s-install-server-init.sh](#k3s-install-server-initsh) | `continux-imac` | Khởi tạo K3s cluster (server #1, `--cluster-init`) |
| [k3s-install-server.sh](#k3s-install-serversh) | `continux-vps` | Join K3s server #2 vào cluster hiện có |
| [k3s-install.sh](#k3s-installsh) | `helios` / `nammn` (WSL2) | Join K3s agent (worker phụ trợ) |
| [k3s-check.sh](#k3s-checksh) | `continux-imac` | Kiểm tra tổng thể cluster: nodes, pods, PVC, workloads, images, Helm |
| [k3s-purge.sh](#k3s-purgesh) | bất kỳ node nào | Gỡ **toàn bộ** K3s — dùng khi reset hạ tầng |
| [tool-version.sh](#tool-versionsh) | bất kỳ Ubuntu node nào | Kiểm tra phiên bản CLI và so sánh với latest stable/beta trên GitHub |

---

## Chạy script từ Windows (local)

PowerShell không hỗ trợ `<` stdin redirect. Dùng `cmd /c`:

```powershell
cmd /c "ssh imac bash -s < scripts\k3s-check.sh"
cmd /c "ssh imac bash -s -- node < scripts\k3s-check.sh"   # truyền argument

```

> `imac` và `vps` là SSH alias trong `~/.ssh/config`. Thay bằng `user@100.x.x.x` nếu chưa có alias.

Cách tốt hơn cho dùng thường xuyên — pull repo và chạy trực tiếp trên máy đích:

```bash
cd ~/continux && git pull
bash scripts/k3s-check.sh
```

---

## k3s-install-server-init.sh

**Chạy trên:** `continux-imac`
**Mục đích:** Khởi tạo K3s cluster mới với embedded etcd (`--cluster-init`). Chạy **một lần duy nhất** khi dựng cluster từ đầu.

```bash
sudo bash scripts/k3s-install-server-init.sh
```

Script tự phát hiện Tailscale IP, cài K3s stable, gán label `workload=heavy role=data-plane`, rồi in **node token** để dùng ở bước join server #2.

### Flags K3s được dùng

| Tham số | Ý nghĩa kỹ thuật | Vai trò trong đồ án |
|:--------|:-----------------|:--------------------|
| `--cluster-init` | Kích hoạt embedded etcd thay vì SQLite. | Cho phép cụm HA — có thể thêm server #2 (VPS) vào chung control-plane. |
| `--write-kubeconfig-mode=644` | Quyền đọc `/etc/rancher/k3s/k3s.yaml` cho non-root. | Chạy `kubectl` không cần `sudo`. |
| `--disable=traefik` | Tắt Ingress Controller mặc định. | Thay bằng Cloudflare Tunnel — không cần mở port. |
| `--disable=servicelb` | Tắt Klipper LoadBalancer. | Tránh xung đột port; dùng port-forward + Cloudflare. |
| `--disable=local-storage` | Tắt local storage provisioner. | Không cần — dùng MinIO làm object storage. |
| `--disable=metrics-server` | Tắt metrics-server mặc định. | Thay bằng VictoriaMetrics chi tiết hơn. |
| `--node-name=continux-imac` | Định danh node trong cluster. | Phân biệt rõ `continux-imac` (data plane) và `continux-vps` (control plane). |
| `--node-ip` | IP chính của node. | Ép K3s dùng **IP Tailscale** — ổn định hơn LAN khi modem đổi IP. |
| `--advertise-address` | IP quảng bá tới các node khác. | VPS biết đúng IP Tailscale để kết nối API server. |
| `--flannel-iface=tailscale0` | Interface cho Flannel CNI. | Pod-to-pod traffic đi qua **Tailscale** — mã hoá end-to-end. |
| `--tls-san` | Thêm IP vào Subject Alternative Name của TLS cert. | Gọi API server từ xa qua IP Tailscale không bị lỗi chứng chỉ. |
| `--etcd-expose-metrics=true` | Mở metrics endpoint của etcd. | VictoriaMetrics scrape được etcd health. |

---

## k3s-install-server.sh

**Chạy trên:** `continux-vps`
**Mục đích:** Join DigitalOcean Droplet làm K3s **server #2** vào cluster đã có trên `continux-imac`.

```bash
sudo bash scripts/k3s-install-server.sh <tailscale-ip-imac> <token>
# Hoặc chạy không arg để nhập tương tác:
sudo bash scripts/k3s-install-server.sh
```

| Argument | Ví dụ | Mô tả |
|----------|-------|-------|
| `<tailscale-ip-imac>` | `100.102.51.39` | IP Tailscale của `continux-imac` (lấy từ `tailscale ip -4` trên iMac) |
| `<token>` | `K10...::server:...` | Node join token — in ra ở cuối `k3s-install-server-init.sh` |

Script tự ping kiểm tra kết nối trước, cài K3s server joining, rồi gán:
- Label: `workload=light role=control-plane`
- Taint: `dedicated=edge:NoSchedule` — chỉ pod có toleration `dedicated=edge` mới schedule trên VPS

---

## k3s-install.sh

**Chạy trên:** `helios` hoặc `nammn` (WSL2 Ubuntu 24.04)
**Mục đích:** Join máy phụ trợ làm K3s **agent (worker)** — dùng khi cần burst capacity (Giai đoạn 4–5).

```bash
sudo bash scripts/k3s-install.sh <tailscale-ip-imac> <token> <node-name>
# Hoặc chạy không arg để nhập tương tác:
sudo bash scripts/k3s-install.sh
```

| Argument | Ví dụ | Mô tả |
|----------|-------|-------|
| `<tailscale-ip-imac>` | `100.102.51.39` | IP Tailscale của `continux-imac` |
| `<token>` | `K10...::server:...` | Node join token |
| `<node-name>` | `helios` hoặc `nammn` | Tên node trong cluster (mặc định: `hostname`) |

Script tự cài Tailscale nếu chưa có. Sau khi join, chạy lệnh sau trên `continux-imac` để gán label:

```bash
kubectl label node helios workload=heavy role=data-plane   # hoặc nammn
```

**Gỡ worker khi xong:**

```bash
# Trên continux-imac:
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
kubectl delete node <node-name>

# Trên helios / nammn (WSL2):
sudo /usr/local/bin/k3s-agent-uninstall.sh
```

---

## k3s-check.sh

**Chạy trên:** `continux-imac`
**Mục đích:** Kiểm tra tổng thể trạng thái cụm K3s — nodes, pods, PVC, workloads, HPA, services, images, Helm releases.

```bash
bash scripts/k3s-check.sh              # toàn bộ (6 sections)
bash scripts/k3s-check.sh node         # topology + pod layout
bash scripts/k3s-check.sh sys          # tài nguyên hệ thống (CPU, RAM, Disk)
bash scripts/k3s-check.sh pvc          # Persistent Volume Claims
bash scripts/k3s-check.sh res          # workloads, HPA, services
bash scripts/k3s-check.sh res <ns>     # filter theo namespace
bash scripts/k3s-check.sh img          # container images và trạng thái in-use/unused
bash scripts/k3s-check.sh helm         # Helm releases
bash scripts/k3s-check.sh secrets      # Secrets theo namespace (chỉ hiện tên)
bash scripts/k3s-check.sh export       # xuất report ra scripts/k3s-check/<timestamp>.txt
```

Report export lưu tại `scripts/k3s-check/k3s-check-<HHmmss-ddmmyy>.txt`.

---

## k3s-purge.sh

**Chạy trên:** bất kỳ node nào cần gỡ K3s
**Mục đích:** Xoá **toàn bộ** K3s — binary, config, network interfaces, PVC data.

```bash
sudo bash scripts/k3s-purge.sh
```

> ⚠️ **Không thể hoàn tác.** Xoá sạch `/var/lib/rancher/k3s`, `/etc/rancher`, toàn bộ network interface CNI/Flannel. Backup dữ liệu MinIO (`mc mirror`) và etcd snapshot (`k3s etcd-snapshot save`) trước khi chạy.

---

## tool-version.sh

**Chạy trên:** bất kỳ Ubuntu node nào
**Mục đích:** Kiểm tra phiên bản đã cài của toàn bộ CLI, so sánh với **latest stable** và phát hiện bản **beta** mới hơn qua GitHub API.

```bash
bash scripts/tool-version.sh
```

Hiển thị trạng thái cho: OS/Kernel, APT packages, Tailscale, K3s, kubectl, Helm, ArgoCD CLI, rpk, mc, psql.

| Ký hiệu | Ý nghĩa |
|---------|---------|
| `✓ cập nhật` | Phiên bản đã cài khớp với latest stable |
| `↑ lỗi thời → vX.Y.Z` | Có bản stable mới hơn |
| `⚡ [beta mới: vX.Y.Z-rc1]` | Có bản prerelease mới hơn stable (không dùng khi thực nghiệm) |
| `✗ chưa cài` | Công cụ chưa được cài |
| `?` | Không kết nối được GitHub API |

> GitHub API không cần auth, giới hạn 60 request/giờ cho IP public.

