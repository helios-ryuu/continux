# SETUP — HƯỚNG DẪN THIẾT LẬP TOÀN DIỆN

## 0. Tổng quan hạ tầng

### 0.1. Ba K3s server chính của cluster

| Vai trò | Máy | Cấu hình | OS | Vị trí mạng |
|---------|-----|----------|----|-------------|
| `continux-imac` (K3s **server #1**) | iMac19,2 | Intel i5-8500, 6 cores, 8 GB DDR4, 200 GB SSD | **Ubuntu Server 24.04.4 LTS** (đã cài sẵn) | LAN nhà — sau NAT |
| `continux-vps` (K3s **server #2**) | DigitalOcean Droplet — gói **$12/mo** (nâng lên **$24/mo** khi cần) | 1 vCPU, 2 GB RAM, 50 GB SSD, 2 TB transfer → 2 vCPU, 4 GB RAM, 80 GB SSD, 4 TB transfer | **Ubuntu 24.04 LTS** | Public IPv4/IPv6 |
| `helios-wsl` (K3s **server #3**) | Laptop HP Helios — WSL2 | Intel i5-12500H, 16 GB DDR5 | **WSL2 Ubuntu 24.04** trên Windows 11 | Tailscale — bật khi cần quorum |

> **Chiến lược chọn gói:** Bắt đầu với gói **$12/mo** (1 vCPU, 2 GB RAM) — đủ RAM để chạy ArgoCD + VictoriaMetrics hoặc Grafana riêng lẻ trong giai đoạn phát triển. Nâng lên **$24/mo** (2 vCPU, 4 GB RAM) khi cần chạy đầy đủ cả ba service cùng lúc liên tục (~800 MB + ~512 MB + ~256 MB = ~1.6 GB). Việc resize Droplet trên DigitalOcean chỉ mất 1–2 phút và giữ nguyên IP, không cần cấu hình lại cluster.
>
> **Lý do cần server #3:** embedded etcd với 2 server cần quorum `2/2`; chỉ cần một peer chập chờn là K3s API có thể timeout. Thêm `helios-wsl` làm server #3 tạo quorum `2/3`, giúp `continux-imac` + `continux-vps` vẫn sống khi một peer tạm lỗi.
>
> **Lý do iMac làm workflow chính (không phải droplet):** iMac có RAM gấp đôi (8 GB) và SSD 200 GB — đủ chỗ cho data plane nặng (RisingWave + MinIO + Redpanda). Dữ liệu Iceberg nằm trên iMac giúp tránh chi phí egress từ droplet.

### 0.2. Phân bổ workload

```
┌──────────────── continux-imac (iMac, K3s server #1, 8 GB) ─────────────────┐
│  Vector ─▶ Redpanda ─▶ RisingWave (Meta + Compute + Frontend)              │
│                            │                                                 │
│                            ├── iceberg sink ──▶ MinIO (iceberg-data)        │
│                            └── checkpoint   ──▶ MinIO (rw-checkpoint)       │
└─────────────────────────────────────────────────────────────────────────────┘
                              │  Tailscale overlay (100.x.x.x)
                              ▼
┌──────────────── continux-vps (DigitalOcean Droplet, K3s server #2, 2→4 GB) ─┐
│  ArgoCD ── VictoriaMetrics ── Grafana                                        │
│  (Cloudflare Tunnel, điều phối GitOps, dashboard giám sát)                   │
└─────────────────────────────────────────────────────────────────────────────┘
                              │  Tailscale overlay / etcd peer 2379-2380
                              ▼
      ┌──────────── helios-wsl (WSL2, K3s server #3, quorum) ────────────┐
      │  Không chạy workload mặc định; chỉ giữ etcd quorum 2/3           │
      │  label: role=quorum · taint: dedicated=quorum:NoSchedule         │
      └──────────────────────────────────────────────────────────────────┘
                              │  Tailscale (chỉ khi cần burst)
                              ▼
                  ┌─── nammn (WSL2, 32 GB) ──┐
                  │  K3s worker phụ trợ      │
                  │  (bật khi OOM hoặc burst) │
                  └───────────────────────────┘
```

### 0.3. Node WSL2 và quy ước bật/tắt

| Node | Máy chủ | CPU | RAM | GPU rời | Vai trò |
|------|---------|-----|-----|---------|---------|
| **`nammn`** | Laptop Nam — Windows 11 (SINISTER) | AMD Ryzen 5 7640HS — 8C/16T, boost 4.3 GHz | 32 GB DDR5 5600 MHz (2×16 GB Hynix) | NVIDIA GeForce RTX 3050 6 GB | K3s worker burst — bật khi `continux-imac` OOM hoặc cần > 10 k events/s |
| **`helios-wsl`** | Laptop Helios — Windows 11 (HELIOS-PC) | Intel Core i5-12500H — 12C/16T, max 4.5 GHz | 16 GB DDR5 4800 MHz (2×8 GB Samsung) | NVIDIA GeForce RTX 3050 Ti 4 GB | K3s server #3 — quorum-only, không nhận workload mặc định |

Hai máy đều dùng **WSL2 Ubuntu 24.04** và join cluster qua Tailscale.

> **Quy ước:** `helios-wsl` nên bật trước khi chạy workload nặng hoặc Vector full ingest để cụm có quorum `2/3`. `nammn` vẫn là worker burst, chỉ bật khi cần thêm tài nguyên data plane.

### 0.4. Ký hiệu máy dùng trong tài liệu này

| Ký hiệu | Máy | Nghĩa trong hướng dẫn |
|---------|-----|----------------------|
| **`[continux-imac]`** | iMac Ubuntu 24.04 | Chạy lệnh trực tiếp trên data plane — nơi mọi quản trị cluster diễn ra |
| **`[continux-vps]`** | DigitalOcean Droplet Ubuntu 24.04 | Chạy lệnh trên observability/control plane |
| **`[ba server]`** | `continux-imac` + `continux-vps` + `helios-wsl` | Chạy lần lượt trên ba K3s server |
| **`[helios-wsl]`** | Laptop Helios — WSL2 Ubuntu 24.04 | Chạy khi `helios-wsl` làm K3s server #3 quorum (§5.4) |
| **`[nammn]`** | Laptop Nam — WSL2 Ubuntu 24.04 | Chạy khi `nammn` đang là K3s worker (§5.7) |
| **`[local]`** | Bất kỳ máy nào trong nhóm | Thao tác cục bộ: git push, SSH vào cluster |

### 0.5. Liên kết mạng (Tailscale)

- **Tailscale Mesh VPN** (miễn phí tier cá nhân đến 100 thiết bị). K3s từ **v1.27+** hỗ trợ tham số `--vpn-auth` dùng Tailscale làm node IP.
- Ưu điểm: mã hoá end-to-end, stable IP trong range `100.x.x.x`, không cần cấu hình firewall phức tạp.

### 0.6. Scripts vận hành

Xem tài liệu đầy đủ cho tất cả script (cú pháp, argument, flags, cách chạy từ Windows) tại [SCRIPTS.md](./SCRIPTS.md).

---

## 1. Phiên bản công cụ (cutting-edge, tham khảo Q1/2026)

| Công cụ | Phiên bản khuyến nghị | Cách kiểm tra |
|---------|-----------------------|---------------|
| Ubuntu Server | 24.04 LTS (Noble) | `lsb_release -a` |
| K3s | **v1.35.4+k3s1** trở lên | `k3s --version` |
| Helm | **v4.2.0+** | `helm version` |
| Argo CD | **v3.4.2** (Helm chart `argo-cd` **9.5.14**) | `argocd version` / `helm show chart argo/argo-cd --version 9.5.14` |
| RisingWave | **v2.8+** (stable, hỗ trợ Iceberg Hosted Catalog) | `psql` → `SELECT version();` |
| Redpanda | **v26.1+** (không JVM, không ZooKeeper — dùng Raft tự thân) | `rpk version` |
| Vector | **0.45+** | `vector --version` |
| MinIO | RELEASE bản mới nhất (tối thiểu **RELEASE.2025-08-13** trở về sau) | `mc admin info` |
| VictoriaMetrics | **1.110+** | `/metrics` endpoint |
| Grafana | **11.6+** hoặc v12 nếu đã phát hành GA | Giao diện |
| Tailscale | **1.98.2+** | `tailscale version` |
| Apache Iceberg spec | v2 bắt buộc, v3 thử nghiệm | Metadata file |

---

## 2. Bản đồ 10 bước (Quickstart)

```
1. Chuẩn bị ba K3s server (iMac Ubuntu + Droplet Ubuntu + helios-wsl) & bật SSH/kết nối Tailscale
2. Cài Tailscale trên ba server, nối chúng vào một tailnet
3. Cài K3s server #1 trên iMac (cluster-init, dùng Tailscale IP làm node IP)
4. Join Droplet làm K3s server #2 qua Tailscale
5. Join helios-wsl làm K3s server #3 quorum-only
6. Cài CLI trên continux-imac và continux-vps
7. Cài Argo CD lên continux-vps và kết nối repo GitOps
8. Deploy hạ tầng: MinIO → Redpanda → RisingWave (continux-imac)
9. Deploy observability: VictoriaMetrics + Grafana (continux-vps)
10. Chuẩn bị dataset + Vector, rồi apply SQL Blue + Iceberg Sink
```

Nếu đủ 10 bước, Grafana dashboard cho Consumer Lag ≤ 2s, và `SELECT COUNT(*) FROM mv_zone_stats` trả về số dương và tăng liên tục.

---

## 3. Chuẩn bị ba K3s server

### 3.1. iMac `continux-imac` (Ubuntu 24.04 đã cài)

Đã có Ubuntu Server chạy sẵn. Thêm các bước sau:

> **Thực thi trên:** `continux-imac`

```bash
# Cập nhật hệ thống
sudo apt update && sudo apt -y upgrade

# Gói cần thiết
sudo apt install -y curl wget git

# Tắt swap (K3s yêu cầu)
sudo swapoff -a
sudo sed -i '/\sswap\s/s/^/#/' /etc/fstab

# Bật IP forwarding (dành cho mesh networking)
echo 'net.ipv4.ip_forward = 1' | sudo tee /etc/sysctl.d/99-k3s.conf
sudo sysctl --system

# ufw cho k3s — chỉ mở những gì cần
sudo ufw allow 6443/tcp #apiserver
sudo ufw allow from 10.42.0.0/16 to any #pods
sudo ufw allow from 10.43.0.0/16 to any #services

# Đổi hostname cho rõ ràng
sudo hostnamectl set-hostname continux-imac
```

### 3.2. DigitalOcean Droplet `continux-vps`

Tạo droplet:

- Region: gần Việt Nam nhất (Singapore — `sgp1`).
- Image: **Ubuntu 24.04 (LTS) x64**.
- Plan: **Basic — Regular / $12/mo** (1 vCPU, 2 GB RAM, 50 GB SSD, 2 TB transfer) — giai đoạn đầu. Resize lên **$24/mo** (2 vCPU, 4 GB RAM, 80 GB SSD) khi cần chạy full observability stack liên tục.
- Authentication: **SSH key** (upload public key `~/.ssh/id_ed25519.pub`).
- Hostname: `continux-vps`.

Sau khi boot:

> **Thực thi trên:** `local` → SSH vào VPS lần đầu bằng root

```bash
ssh root@<droplet-ip>
```

> **Thực thi trên:** `continux-vps` (đang là **root**)

```bash
# Tạo user non-root (đừng làm việc bằng root)
adduser continux
usermod -aG sudo continux
rsync --archive --chown=continux:continux ~/.ssh /home/continux
exit
```

> **Thực thi trên:** `local` → SSH lại bằng user thường

```bash
ssh continux@<droplet-ip>
```

> **Thực thi trên:** `continux-vps` (đang là **continux**)

```bash
# Các bước giống iMac
sudo apt update && sudo apt -y upgrade
sudo swapoff -a
sudo sed -i '/\sswap\s/s/^/#/' /etc/fstab
echo 'net.ipv4.ip_forward = 1' | sudo tee /etc/sysctl.d/99-k3s.conf
sudo sysctl --system

# ufw cho k3s — chỉ mở những gì cần
sudo ufw allow 6443/tcp #apiserver
sudo ufw allow from 10.42.0.0/16 to any #pods
sudo ufw allow from 10.43.0.0/16 to any #services
```

### 3.3. Laptop `helios-wsl` WSL2 Ubuntu 24.04 (server #3 quorum-only)

`helios-wsl` là K3s server #3 để giữ quorum etcd `2/3`. Node này có taint `dedicated=quorum:NoSchedule`, không nhận workload ứng dụng mặc định.

> **Thực thi trên:** Windows PowerShell (Admin)

```powershell
wsl --install -d Ubuntu-24.04
wsl --set-default-version 2
wsl -d Ubuntu-24.04
```

Nếu WSL2 chưa bật systemd, tạo `/etc/wsl.conf` trong Ubuntu:

> **Thực thi trên:** `helios-wsl`

```bash
sudo tee /etc/wsl.conf >/dev/null <<'EOF'
[boot]
systemd=true
EOF
```

Sau đó khởi động lại WSL:

> **Thực thi trên:** Windows PowerShell

```powershell
wsl --shutdown
wsl -d Ubuntu-24.04
```

Chuẩn bị OS:

> **Thực thi trên:** `helios-wsl`

```bash
sudo apt update && sudo apt -y upgrade
sudo apt install -y curl wget git ca-certificates jq netcat-openbsd

sudo swapoff -a
sudo sed -i '/\sswap\s/s/^/#/' /etc/fstab

echo 'net.ipv4.ip_forward = 1' | sudo tee /etc/sysctl.d/99-k3s.conf
sudo sysctl --system

sudo hostnamectl set-hostname helios-wsl || sudo sh -c 'echo helios-wsl > /etc/hostname'
```

> **Lưu ý vận hành:** vì đây là WSL2, giữ session Ubuntu chạy trong Windows Terminal khi muốn `helios-wsl` tham gia quorum. Không sleep/hibernate Windows trong lúc chạy ingest hoặc benchmark.

---

## 4. Tailscale mesh — nối ba K3s server

### 4.1. Cài Tailscale trên ba server

> **Thực thi trên:** `ba server` — lần lượt trên `continux-imac`, `continux-vps`, `helios-wsl`

```bash
curl -fsSL https://tailscale.com/install.sh | sh
```

### 4.2. Đăng ký vào cùng một tailnet

> **Thực thi trên:** `ba server` — lần lượt trên `continux-imac`, `continux-vps`, `helios-wsl`

```bash
sudo tailscale up
# Đăng nhập bằng Google/GitHub trên URL được in ra
```

Verify ở ba server:

> **Thực thi trên:** `ba server`

```bash
tailscale status
# Kết quả mong đợi:
# 100.x.x.x    continux-imac             username@  linux    -
# 100.x.x.x    continux-vps              username@  linux    active; direct [<IPv6>]:41641, tx 1187744 rx 729784
# 100.x.x.x    helios-wsl                username@  linux    active; relay "..."
```

Ghi lại ba IP Tailscale — ta sẽ dùng làm **node IP của K3s** ở bước 5.

### 4.3. Kiểm tra kết nối

> **Thực thi trên:** `continux-vps`

```bash
ping -c 3 continux-imac     # Magic DNS giải IP tailscale
```

> **Thực thi trên:** `continux-imac`

```bash
ping -c 3 continux-vps
ping -c 3 helios-wsl
```

> **Thực thi trên:** `helios-wsl`

```bash
ping -c 3 continux-imac
ping -c 3 continux-vps
```

Nếu cả ba server ping được thì mesh đã hoạt động. Trước khi join server #2/#3, kiểm tra thêm các port K3s/etcd qua Tailscale:

```bash
nc -vz <tailscale-ip-imac> 6443
nc -vz <tailscale-ip-vps> 2380
nc -vz <tailscale-ip-helios-wsl> 2380
```

---

## 5. Bootstrap cụm K3s

### 5.1. Cài K3s server #1 trên iMac (cluster-init)

> **Thực thi trên:** `continux-imac`

[SCRIPTS.md — k3s-install-server-init.sh](./SCRIPTS.md#k3s-install-server-initsh)

### 5.2. Cấu hình kubeconfig cho user thường trên iMac

Sau khi K3s server #1 chạy xong, copy kubeconfig raw sang home của user quản trị. Bước này giúp `kubectl`, `helm` và các script dùng cùng kubeconfig hợp lệ, tránh lỗi Helm kiểu `x509: certificate signed by unknown authority`.

> **Thực thi trên:** `continux-imac`

```bash
mkdir -p ~/.kube

sudo k3s kubectl config view --raw > ~/.kube/config
chmod 600 ~/.kube/config

export KUBECONFIG=$HOME/.kube/config
kubectl get nodes
```

Để shell mới tự dùng kubeconfig này:

```bash
grep -qxF 'export KUBECONFIG=$HOME/.kube/config' ~/.bashrc \
  || echo 'export KUBECONFIG=$HOME/.kube/config' >> ~/.bashrc
```

### 5.3. Join K3s server #2 trên Droplet

> **Thực thi trên:** `continux-vps`

[SCRIPTS.md — k3s-install-server.sh](./SCRIPTS.md#k3s-install-serversh)

```bash
sudo bash scripts/k3s-install-server.sh <tailscale-ip-imac> <node-token> continux-vps edge
```

### 5.4. Join `helios-wsl` làm K3s server #3 quorum-only

> **Thực thi trên:** `helios-wsl`

[SCRIPTS.md — k3s-install-server.sh](./SCRIPTS.md#k3s-install-serversh)

```bash
sudo bash scripts/k3s-install-server.sh <tailscale-ip-imac> <node-token> helios-wsl quorum
```

### 5.5. Gán label/taint theo vai trò cuối cùng

> **Thực thi trên:** `continux-imac`

```bash
kubectl label node continux-imac workload=heavy role=data-plane --overwrite

kubectl label node continux-vps workload=light role=control-plane --overwrite
kubectl taint node continux-vps dedicated=edge:NoSchedule --overwrite

kubectl label node helios-wsl workload=quorum role=quorum --overwrite
kubectl taint node helios-wsl dedicated=quorum:NoSchedule --overwrite
```

Helm values sử dụng:
- Workload nặng (MinIO, Redpanda, RisingWave, Vector) → `nodeSelector: { role: data-plane }`
- Workload nhẹ (ArgoCD, VictoriaMetrics, Grafana) → `nodeSelector: { role: control-plane }` + `tolerations: [{key: dedicated, value: edge, effect: NoSchedule}]`
- `helios-wsl` quorum-only → không đặt workload ứng dụng lên node này; chỉ DaemonSet/system pod được phép chạy nếu cần.

### 5.6. Verify cụm 3 server và quorum `2/3`

> **Thực thi trên:** `continux-imac`

[SCRIPTS.md — k3s-check.sh](./SCRIPTS.md#k3s-checksh)

```bash
kubectl get nodes -o wide
kubectl get nodes -l 'node-role.kubernetes.io/etcd' -o wide
kubectl get nodes -l role=quorum -o wide
kubectl get --raw='/readyz?verbose' | grep -E 'etcd|readyz|ok'

tailscale ping continux-vps
tailscale ping helios-wsl
nc -vz <tailscale-ip-vps> 2380
nc -vz <tailscale-ip-helios-wsl> 2380
```

Kỳ vọng: `continux-imac`, `continux-vps`, `helios-wsl` đều `Ready`, đều có role `control-plane,etcd`. Node `helios-wsl` có label `role=quorum` và taint `dedicated=quorum:NoSchedule`.

### 5.7. Join worker phụ trợ `nammn` (chỉ khi cần burst)

Bật WSL2 Ubuntu 24.04 trên máy `nammn`, sau đó chạy:

> **Thực thi trên:** `nammn` (WSL2 Ubuntu 24.04)

[SCRIPTS.md — k3s-install.sh](./SCRIPTS.md#k3s-installsh)

Sau khi script chạy xong, gán label từ node quản trị:

> **Thực thi trên:** `continux-imac`

```bash
kubectl label node nammn workload=heavy role=data-plane --overwrite
kubectl get nodes -o wide
```

**Gỡ worker khi xong:**

> **Thực thi trên:** `continux-imac`

```bash
kubectl drain <tên-node> --ignore-daemonsets --delete-emptydir-data
kubectl delete node <tên-node>
```

> **Thực thi trên:** `nammn` (WSL2)

```bash
sudo /usr/local/bin/k3s-agent-uninstall.sh
```

---

## 6. Công cụ CLI trên node quản trị

`continux-imac` cần đủ CLI cho data plane. `continux-vps` cần tối thiểu `kubectl`, `helm`, `argocd` để chạy các bước observability từ §9. `helios-wsl` chỉ cần các gói nền, Tailscale và K3s server từ §3-5 vì đây là node quorum-only.

### 6.1. Cài CLI

> **Thực thi trên:** `continux-imac`

```bash
sudo apt install -y unzip postgresql-client

# Helm latest stable — binary nằm ở /usr/local/bin/helm.
# Lưu ý: installer mặc định có thể kéo Helm 3; dùng DESIRED_VERSION để lấy latest Helm 4.
HELM_VERSION=$(curl -sf https://get.helm.sh/helm-latest-version | tr -d '\n')
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 -o /tmp/get-helm.sh
chmod 700 /tmp/get-helm.sh
DESIRED_VERSION="${HELM_VERSION}" /tmp/get-helm.sh
rm -f /tmp/get-helm.sh
helm version --short

# argocd CLI 3.4.2
VERSION=3.4.2
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/download/v$VERSION/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64

# rpk (Redpanda CLI)
curl -1sLf 'https://dl.redpanda.com/nzc4ZYQK3WRGd9sy/redpanda/cfg/setup/bash.deb.sh' | sudo -E bash
sudo apt install redpanda

# mc (MinIO client)
wget https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc && sudo mv mc /usr/local/bin/
```

> **Thực thi trên:** `continux-vps`

```bash
# Bộ CLI tối thiểu cho ArgoCD/observability từ §9 trở đi.
sudo apt update
sudo apt install -y curl ca-certificates unzip jq

# kubectl lấy từ K3s. Nếu symlink chưa có, tạo symlink về k3s.
if ! command -v kubectl; then
  sudo ln -sf /usr/local/bin/k3s /usr/local/bin/kubectl
  command -v kubectl
fi
mkdir -p ~/.kube
sudo k3s kubectl config view --raw > ~/.kube/config
chmod 600 ~/.kube/config
kubectl get nodes -o wide

# Helm latest stable — binary nằm ở /usr/local/bin/helm.
# Lưu ý: installer mặc định có thể kéo Helm 3; dùng DESIRED_VERSION để lấy latest Helm 4.
HELM_VERSION=$(curl -sf https://get.helm.sh/helm-latest-version | tr -d '\n')
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 -o /tmp/get-helm.sh
chmod 700 /tmp/get-helm.sh
DESIRED_VERSION="${HELM_VERSION}" /tmp/get-helm.sh
rm -f /tmp/get-helm.sh
helm version --short

# argocd CLI 3.4.2
VERSION=3.4.2
curl -sSL -o /tmp/argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/download/v$VERSION/argocd-linux-amd64
sudo install -m 555 /tmp/argocd-linux-amd64 /usr/local/bin/argocd
rm -f /tmp/argocd-linux-amd64
argocd version --client
```

Verify:

> **Thực thi trên:** `continux-imac` và `continux-vps`

[SCRIPTS.md — k3s-check.sh](./SCRIPTS.md#k3s-checksh)

### 6.2. Cập nhật phần mềm (Maintenance)

Chạy đầu mỗi giai đoạn hoặc khi có CVE nghiêm trọng. **Không nâng cấp** K3s, rpk, mc khi đang chạy thực nghiệm (Giai đoạn 5).

**Nguyên tắc chọn phiên bản:** ưu tiên stable release. Nếu phiên bản mới nhất có hậu tố `-alpha`, `-beta`, `-rc` → bỏ qua, dùng bản stable liền trước.

Kiểm tra trạng thái trước khi cập nhật:

> **Thực thi trên:** `continux-imac` hoặc `continux-vps`

[SCRIPTS.md — tool-version.sh](./SCRIPTS.md#tool-versionsh)

Các lệnh cập nhật cần sudo — chạy trong SSH session tương tác trực tiếp trên máy đích:

> **Thực thi trên:** `ba server` — lần lượt `continux-imac`, `continux-vps`, `helios-wsl`

```bash
sudo apt update && sudo apt -y upgrade && sudo apt -y autoremove
sudo tailscale update --track=stable
```

> **Thực thi trên:** `continux-imac`

```bash
# K3s server #1 / cluster-init (continux-imac)
# Phải giữ nguyên flags cluster-init/Tailscale/etcd.
# Không chạy lệnh generic `curl ... | sh -` vì sẽ ghi đè k3s.service thiếu flags của cụm này.
TAILSCALE_IP=$(tailscale ip -4)
curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=stable sh -s - server \
    --cluster-init \
    --write-kubeconfig-mode=644 \
    --disable=traefik \
    --disable=servicelb \
    --disable=local-storage \
    --disable=metrics-server \
    --node-name=continux-imac \
    --node-ip="${TAILSCALE_IP}" \
    --advertise-address="${TAILSCALE_IP}" \
    --flannel-iface=tailscale0 \
    --tls-san="${TAILSCALE_IP}" \
    --etcd-expose-metrics=true
```

> **Thực thi trên:** `continux-vps`

```bash
# K3s server #2 / join server (continux-vps)
# Lấy IMAC_TS_IP từ `tailscale ip -4` trên continux-imac.
# K3S_TOKEN lấy từ continux-imac: sudo cat /var/lib/rancher/k3s/server/node-token
IMAC_TS_IP=<tailscale-ip-imac>
K3S_TOKEN=<node-token>
TAILSCALE_IP=$(tailscale ip -4)

curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=stable sh -s - server \
    --server="https://${IMAC_TS_IP}:6443" \
    --token="${K3S_TOKEN}" \
    --write-kubeconfig-mode=644 \
    --disable=traefik \
    --disable=servicelb \
    --disable=local-storage \
    --disable=metrics-server \
    --node-name=continux-vps \
    --node-ip="${TAILSCALE_IP}" \
    --advertise-address="${TAILSCALE_IP}" \
    --flannel-iface=tailscale0 \
    --tls-san="${TAILSCALE_IP}" \
    --etcd-expose-metrics=true
```

> **Thực thi trên:** `helios-wsl`

```bash
# K3s server #3 / quorum-only (helios-wsl)
# Lấy IMAC_TS_IP từ `tailscale ip -4` trên continux-imac.
# K3S_TOKEN lấy từ continux-imac: sudo cat /var/lib/rancher/k3s/server/node-token
IMAC_TS_IP=<tailscale-ip-imac>
K3S_TOKEN=<node-token>
TAILSCALE_IP=$(tailscale ip -4)

curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=stable sh -s - server \
    --server="https://${IMAC_TS_IP}:6443" \
    --token="${K3S_TOKEN}" \
    --write-kubeconfig-mode=644 \
    --disable=traefik \
    --disable=servicelb \
    --disable=metrics-server \
    --node-name=helios-wsl \
    --node-ip="${TAILSCALE_IP}" \
    --advertise-address="${TAILSCALE_IP}" \
    --flannel-iface=tailscale0 \
    --tls-san="${TAILSCALE_IP}" \
    --etcd-expose-metrics=true
```

Sau khi cập nhật từng K3s server, kiểm tra lại từ `continux-imac`:

```bash
kubectl get nodes -o wide
bash scripts/k3s-check.sh node
```

> Nếu worker `nammn` đang bật, cập nhật agent bằng cách chạy lại lệnh join agent trong [SCRIPTS.md — k3s-install.sh](./SCRIPTS.md#k3s-installsh) với cùng `IMAC_TS_IP`, `K3S_TOKEN`, `node-name`.

> **Thực thi trên:** `continux-imac`

```bash

# Helm — binary đang nằm ở /usr/local/bin/helm.
# Lưu ý: installer mặc định có thể kéo Helm 3; dùng DESIRED_VERSION để lấy latest Helm 4.
HELM_VERSION=$(curl -sf https://get.helm.sh/helm-latest-version | tr -d '\n')
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 -o /tmp/get-helm.sh
chmod 700 /tmp/get-helm.sh
DESIRED_VERSION="${HELM_VERSION}" /tmp/get-helm.sh
rm -f /tmp/get-helm.sh
helm version --short

# rpk — KHÔNG chạy khi đang thực nghiệm
sudo apt-get update && sudo apt-get install --only-upgrade -y redpanda

# argocd
VERSION=v3.4.2

curl -sSL -o /tmp/argocd-linux-amd64 \
  "https://github.com/argoproj/argo-cd/releases/download/${VERSION}/argocd-linux-amd64"

sudo install -m 755 /tmp/argocd-linux-amd64 /usr/local/bin/argocd
rm -f /tmp/argocd-linux-amd64

argocd version --client
```

---

## 7. Cài Argo CD trên continux-vps

### 7.1. Deploy ArgoCD

Helm values: [`config/argocd/helm-values.yaml`](../config/argocd/helm-values.yaml)

Chart dùng cho bootstrap: `argo/argo-cd` **9.5.14** (app version **Argo CD v3.4.2**).

> **Thực thi trên:** `continux-imac` — kubectl/helm quản lý cluster từ đây

```bash
cd ~/continux

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm show chart argo/argo-cd --version 9.5.14

# Dry-run để kiểm tra manifest trước khi apply
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --version 9.5.14 \
  -f config/argocd/helm-values.yaml \
  --dry-run=client

helm upgrade --install argocd argo/argo-cd \
    --namespace argocd \
    --version 9.5.14 \
    -f config/argocd/helm-values.yaml

kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
helm -n argocd list
kubectl -n argocd get pods -o wide
```

### 7.2. Expose UI qua Cloudflare Tunnel

ArgoCD UI và Grafana được expose qua Cloudflare Tunnel — không cần port-forward hay NodePort. **Yêu cầu:** domain đã quản lý bởi Cloudflare.

**a. Tạo tunnel trên Cloudflare dashboard:**

1. Vào [Cloudflare Zero Trust](https://one.dash.cloudflare.com) → **Networking → Tunnels → Create Tunnel**.
2. Chọn connector **Cloudflared** → đặt **Tunnel name** là `continux` → **Create Tunnel**.
3. Ở màn hình **Create a Tunnel**, Cloudflare sẽ hỏi **Operating System** và **Architecture** để sinh lệnh mẫu. Vì ta chạy `cloudflared` bằng Kubernetes manifest, không cần chạy `cloudflared service install` trên máy local.
   - Có thể chọn bất kỳ OS/architecture để xem token; nếu đang mở dashboard từ Windows thì chọn **Windows · 64-bit** cũng được.
   - Sao chép phần token sau `--token` trong lệnh mẫu `cloudflared tunnel run --token <TOKEN>` hoặc `cloudflared service install <TOKEN>`.
   - Token hợp lệ thường bắt đầu bằng `eyJ...`; **không** copy cả chuỗi `cloudflared tunnel run --token ...`, không copy dấu `*` bị che trên UI.
   - Không bấm **Continue** vội nếu màn hình còn báo **No connection detected yet**; quay lại sau khi pod `cloudflared` trong K3s đã chạy.
4. Sau khi tunnel connected, Cloudflare chuyển sang màn hình **Add a route**. Chọn **Published application** để publish ứng dụng qua public hostname, rồi thêm 2 route:
   - Public hostname `continux-argo.<domain>` → Service URL `http://argocd-server.argocd:80`
   - Public hostname `continux-grafana.<domain>` → Service URL `http://grafana.observability:80`

   > Lưu ý TLS: dùng hostname một cấp như `continux-argo.<domain>` để khớp Universal SSL mặc định của Cloudflare (`*.<domain>`). Hostname nhiều cấp như `argo.continux.<domain>` thường cần certificate riêng cho `*.continux.<domain>`.

**b. Lưu token vào K8s Secret:**

> **Thực thi trên:** `continux-imac`

```bash
TOKEN=<token-sao-chep-tu-dashboard-cloudflare>

kubectl -n argocd create secret generic cloudflare-tunnel-token \
    --from-literal=token="${TOKEN}" \
    --dry-run=client -o yaml | kubectl apply -f -
# secret/cloudflare-tunnel-token created
```

**c. Deploy cloudflared trong cluster** ([`config/argocd/cloudflared.yaml`](../config/argocd/cloudflared.yaml)):

> **Thực thi trên:** `continux-imac`

```bash
cd ~/continux

kubectl apply -f config/argocd/cloudflared.yaml # deployment.apps/cloudflared created
kubectl -n argocd rollout status deploy/cloudflared
kubectl -n argocd logs deploy/cloudflared --tail=50
```

Khi log có kết nối thành công, quay lại Cloudflare dashboard. Màn hình **Connection Status** sẽ chuyển khỏi trạng thái **Waiting for your Tunnel to connect / No connection detected yet**; lúc đó bấm **Continue**, chọn **Published application** ở màn hình **Add a route**, rồi cấu hình 2 public hostname như bước a.4.

Nếu `cloudflared` bị `CrashLoopBackOff`, kiểm tra container log trước đó và token Secret:

```bash
kubectl -n argocd get pods -l app=cloudflared
kubectl -n argocd logs deploy/cloudflared --previous --tail=80

kubectl -n argocd get secret cloudflare-tunnel-token \
    -o jsonpath='{.data.token}' | base64 -d | cut -c1-24 && echo
```

Kết quả dòng cuối phải bắt đầu bằng `eyJ`. Nếu thấy `cloudflared`, `sudo`, `service install`, dấu `*`, khoảng trắng thừa, hoặc token không bắt đầu bằng `eyJ`, tạo lại Secret bằng token thật rồi restart:

```bash
kubectl -n argocd create secret generic cloudflare-tunnel-token \
    --from-literal=token='<TOKEN_EYJ...>' \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl -n argocd rollout restart deploy/cloudflared
kubectl -n argocd rollout status deploy/cloudflared
```

Nếu token đã hợp lệ nhưng log lặp lỗi kiểu `Failed to dial a quic connection ... timeout: no recent network activity`, đường UDP/QUIC tới Cloudflare edge có thể đang bị chặn. Manifest mặc định của dự án đã ép `--protocol http2` để dùng TCP/TLS ổn định hơn trong môi trường K3s qua VPS. Đảm bảo manifest trên `continux-imac` đã được cập nhật rồi apply lại:

```bash
grep -A12 -- '--metrics' config/argocd/cloudflared.yaml

kubectl apply -f config/argocd/cloudflared.yaml
kubectl -n argocd rollout restart deploy/cloudflared
kubectl -n argocd logs deploy/cloudflared --tail=80
```

**d. Lấy password admin lần đầu:**

> **Thực thi trên:** `continux-imac`

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d && echo
```

Mở `https://continux-argo.<domain>` → đăng nhập `admin` / password trên, **đổi password ngay** (NFR-17).

### 7.3. Kết nối repo GitOps

> **Thực thi trên:** `continux-imac`

Lần bootstrap App-of-Apps cần file manifest local, vì vậy `continux-imac` nên có một bản clone repo tại `~/continux` dù workflow phát triển chính vẫn ở Windows.

```bash
cd ~
git clone https://github.com/helios-ryuu/continux.git
cd ~/continux
git pull

argocd login continux-argo.<domain> --username admin --password <new>

# Tạo GitHub PAT theo hướng dẫn bên dưới trước khi chạy repo add.
# Khuyến nghị: fine-grained token chỉ có quyền Contents: Read-only trên repo continux.
argocd repo add https://github.com/helios-ryuu/continux.git \
    --username <gh-user> \
    --password <gh-PAT>

argocd repo list

# Áp App-of-Apps
kubectl apply -f gitops/apps/root-app.yaml
argocd app sync root-app
# ...
# GROUP        KIND         NAMESPACE  NAME              STATUS  HEALTH  HOOK  MESSAGE
# argoproj.io  Application  argocd     cloudflared       Synced                application.argoproj.io/cloudflared created
# argoproj.io  Application  argocd     victoria-scrapes  Synced                application.argoproj.io/victoria-scrapes created
# argoproj.io  Application  argocd     redpanda-topics   Synced                application.argoproj.io/redpanda-topics created
# argoproj.io  Application  argocd     pipeline          Synced                application.argoproj.io/pipeline created
# argoproj.io  Application  argocd     vector            Synced                application.argoproj.io/vector created

argocd app list
# NAME                     CLUSTER                         NAMESPACE      PROJECT  STATUS     HEALTH   SYNCPOLICY  CONDITIONS  REPO                                         PATH                     TARGET
# argocd/cloudflared       https://kubernetes.default.svc  argocd         default  OutOfSync  Healthy  Manual      <none>      https://github.com/helios-ryuu/continux.git  config/argocd            main
# argocd/pipeline          https://kubernetes.default.svc  pipeline       default  OutOfSync  Missing  Manual      <none>      https://github.com/helios-ryuu/continux.git  gitops/pipeline          main
# argocd/redpanda-topics   https://kubernetes.default.svc  redpanda       default  Synced     Healthy  Manual      <none>      https://github.com/helios-ryuu/continux.git  pipelines/redpanda       main
# argocd/root-app          https://kubernetes.default.svc  argocd         default  Synced     Healthy  Manual      <none>      https://github.com/helios-ryuu/continux.git  gitops/apps              main
# argocd/vector            https://kubernetes.default.svc  pipeline       default  OutOfSync  Missing  Manual      <none>      https://github.com/helios-ryuu/continux.git  config/vector            main
# argocd/victoria-scrapes  https://kubernetes.default.svc  observability  default  OutOfSync  Missing  Manual      <none>      https://github.com/helios-ryuu/continux.git  config/victoria-metrics  main
```

Ý nghĩa output:

- `root-app` dùng pattern **App-of-Apps**. Sync `root-app` chỉ tạo/cập nhật các ArgoCD `Application` con, chưa bắt buộc sync tài nguyên bên trong từng app con.
- `SYNCPOLICY=Manual` nghĩa là app con không tự động sync. Vì vậy sau `argocd app sync root-app`, các app con có thể vẫn `OutOfSync`.
- `OutOfSync` nghĩa là manifest trong Git khác với trạng thái live trên cluster.
- `Missing` nghĩa là tài nguyên của app con chưa tồn tại trong cluster vì app con chưa được sync.
- `cloudflared OutOfSync Healthy` thường xảy ra khi `cloudflared` đã được apply thủ công ở §7.2: pod đang chạy khỏe, nhưng ArgoCD vẫn thấy live state chưa khớp hoàn toàn với Git.

Ở bước này chỉ sync `cloudflared` nếu muốn đưa tunnel đã apply thủ công ở §7.2 về trạng thái do ArgoCD quản lý:

```bash
argocd app sync cloudflared
```

Các app con còn lại sync ở đúng section tương ứng: `redpanda-topics` ở §8.3, `victoria-scrapes` ở §9.1, `vector` ở §10.5, `pipeline` ở §11.4. Không sync quá sớm khi service phụ thuộc chưa sẵn sàng.

Khi muốn xem app lệch gì trước khi sync:

```bash
argocd app diff cloudflared
argocd app diff vector
argocd app diff victoria-scrapes
argocd app diff pipeline
```

> Ghi nhớ: `root-app Synced/Healthy` nghĩa là danh sách app con đã đúng. Các app con `Synced/Healthy` mới nghĩa là workload bên trong app đó đã được tạo và khớp Git.

Sau lần apply `root-app` đầu tiên, ArgoCD đọc trạng thái mong muốn trực tiếp từ GitHub. Nhịp làm việc thường ngày là sửa code trên Windows → commit/push → SSH vào `continux-imac` để `git pull` khi cần chạy lệnh local, hoặc sync bằng ArgoCD UI/CLI.

**Tạo GitHub Personal Access Token (PAT) cho ArgoCD:**

**Cách 1 — Fine-grained token (khuyến nghị):**

1. Mở <https://github.com/settings/personal-access-tokens/new> hoặc vào GitHub → avatar góc phải → **Settings** → **Developer settings** → **Personal access tokens** → **Fine-grained tokens** → **Generate new token**.
2. Đặt **Token name**: `continux-argocd`.
3. Chọn **Expiration** ngắn/vừa đủ, ví dụ 30 hoặc 90 ngày. Khi token hết hạn, chạy lại `argocd repo add` với token mới.
4. Ở **Repository access**, chọn **Only select repositories** → chọn `helios-ryuu/continux`.
5. Ở **Repository permissions**, cấp:
   - **Contents: Read-only** — bắt buộc để ArgoCD đọc manifest.
   - Các quyền khác để mặc định **No access**.
6. Bấm **Generate token**, copy token ngay vì GitHub chỉ hiện một lần.
7. Dùng token đó cho `--password <gh-PAT>` trong lệnh `argocd repo add`; `--username` là username GitHub của người tạo token, ví dụ `helios-ryuu`.

**Cách 2 — Token classic (fallback nếu fine-grained không dùng được):**

1. Mở <https://github.com/settings/tokens/new> hoặc vào **Developer settings** → **Personal access tokens** → **Tokens (classic)** → **Generate new token (classic)**.
2. Đặt **Note**: `continux-argocd`, chọn **Expiration** phù hợp.
3. Chọn scope:
   - Repo private: chọn `repo`.
   - Repo public: chọn `public_repo`.
4. Không cấp thêm scope như `admin:org`, `workflow`, `delete_repo` nếu không cần.
5. Bấm **Generate token**, copy token và dùng cho `--password <gh-PAT>`.

Verify sau khi thêm repo:

```bash
argocd repo list
argocd repo get https://github.com/helios-ryuu/continux.git
```

Nếu trạng thái repo không thành công, kiểm tra lại token còn hạn, token có quyền đọc repo, và repo URL đúng chính xác `https://github.com/helios-ryuu/continux.git`.

> Tham khảo GitHub Docs: [Managing your personal access tokens](https://docs.github.com/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token).

---

## 8. Deploy hạ tầng trên `continux-imac`

Tất cả Helm values dưới đây đều có sẵn trong repo GitOps; ArgoCD sẽ sync tự động. Các giá trị này **đã được tinh chỉnh cho iMac 8 GB** — tránh OOM.

### 8.1. Tạo K8s Secrets cho credentials

MinIO và RisingWave đọc credentials từ K8s Secret thay vì hardcode vào Helm values — tạo trước khi ArgoCD sync các workload hạ tầng.

> **Thực thi trên:** `continux-imac`

```bash
# Namespace cần tạo trước
kubectl create namespace minio      --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace risingwave --dry-run=client -o yaml | kubectl apply -f -

# Secret cho MinIO (chart đọc key: rootUser, rootPassword)
kubectl -n minio create secret generic minio-credentials \
    --from-literal=rootUser=adminuser \
    --from-literal=rootPassword=<minio-root-password>
```

> ⚠️ Thay `<minio-root-password>` bằng giá trị thực trước khi chạy. Secret `risingwave-s3-credentials` sẽ tạo ở cuối §8.2 sau khi có access key `key-risingwave` từ MinIO Console.

### 8.2. MinIO

Helm values: [`config/minio/helm-values.yaml`](../config/minio/helm-values.yaml)

Deploy MinIO trước, sau đó mới port-forward console. Nếu chưa deploy, lệnh `kubectl -n minio port-forward svc/minio-console 9001:9001` sẽ báo `services "minio-console" not found`.

> **Thực thi trên:** `continux-imac`

```bash
helm repo add minio https://charts.min.io/
helm repo update

helm upgrade --install minio minio/minio \
    --namespace minio \
    -f config/minio/helm-values.yaml

kubectl -n minio get deploy,sts,pod,svc,pvc
# NAME                    READY   UP-TO-DATE   AVAILABLE   AGE
# deployment.apps/minio   1/1     1            1           19m

# NAME                         READY   STATUS    RESTARTS   AGE
# pod/minio-6b69f45d76-76mrx   1/1     Running   0          19m

# NAME                    TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
# service/minio           ClusterIP   10.43.29.179    <none>        9000/TCP   19m
# service/minio-console   ClusterIP   10.43.197.139   <none>        9001/TCP   19m

# NAME                          STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
# persistentvolumeclaim/minio   Bound    pvc-204d34a8-bc36-4166-821f-021b032d493e   40Gi       RWO            local-path     <unset>                 19m

kubectl -n minio rollout status deploy/minio --timeout=300s
# deployment "minio" successfully rolled out
```

Tạo access key riêng cho từng service (least-privilege, NFR-15):

> **Thực thi trên:** `continux-imac`

```bash
kubectl -n minio port-forward --address 0.0.0.0 svc/minio-console 9001:9001
# UI từ máy Windows chung Tailscale: http://<tailscale-ip-imac>:9001
# Tạo 3 keys: key-vector (write tlc-zone), key-risingwave (rw iceberg-data + rw-checkpoint)
```

Lệnh `--address 0.0.0.0` cho phép máy khác truy cập port-forward qua IP của `continux-imac`, ví dụ `http://100.102.51.39:9001` trên Tailscale. Chỉ bật trong lúc thao tác MinIO Console, xong thì `Ctrl+C` để đóng phiên port-forward.

**Tạo bucket và access key trong MinIO Console:**

1. Đăng nhập bằng root credential trong secret `minio-credentials`:

   ```bash
   kubectl -n minio get secret minio-credentials -o jsonpath='{.data.rootUser}' | base64 -d && echo
   kubectl -n minio get secret minio-credentials -o jsonpath='{.data.rootPassword}' | base64 -d && echo
   ```

2. Vào **Buckets** → kiểm tra đã có 3 bucket. Nếu thiếu thì tạo:
   - `iceberg-data`
   - `rw-checkpoint`
   - `tlc-zone`

3. Vào **Access Keys** → **Create access key**.

4. Tạo key cho Vector:
   - **Access Key:** `key-vector`
   - **Secret Key:** để random, copy lại sau khi tạo.
   - **Name:** `vector`
   - **Description:** `Write TLC zone/raw objects`
   - **Restrict beyond user policy:** có thể để `OFF` trong giai đoạn bootstrap. Nếu muốn least-privilege ngay, bật `ON` và dùng policy giới hạn bucket `tlc-zone`.

5. Tạo key cho RisingWave:
   - **Access Key:** `key-risingwave`
   - **Secret Key:** để random, copy lại sau khi tạo.
   - **Name:** `risingwave`
   - **Description:** `Read tlc-zone, write iceberg-data and rw-checkpoint`
   - Secret key này phải thay vào placeholder trong `sql/02-tables/tlc-taxi-zone.sql` và `sql/04-sinks/iceberg-zone-stats.sql`.

6. Sau khi bấm **Create**, MinIO chỉ hiển thị Secret Key một lần. Lưu lại ngay vào nơi an toàn; không commit secret vào Git.

Sau khi tạo xong `key-risingwave`, tạo K8s Secret cho RisingWave state store S3/MinIO. Chart RisingWave hiện tại yêu cầu secret có đúng key `AWS_ACCESS_KEY_ID` và `AWS_SECRET_ACCESS_KEY`.

```bash
# Secret cho RisingWave state store S3/MinIO
kubectl -n risingwave create secret generic risingwave-s3-credentials \
    --from-literal=AWS_ACCESS_KEY_ID=key-risingwave \
    --from-literal=AWS_SECRET_ACCESS_KEY=<secret-key-cua-key-risingwave>
```

Nếu cần chạy lại để cập nhật secret:

```bash
kubectl -n risingwave create secret generic risingwave-s3-credentials \
    --from-literal=AWS_ACCESS_KEY_ID=key-risingwave \
    --from-literal=AWS_SECRET_ACCESS_KEY=<secret-key-cua-key-risingwave> \
    --dry-run=client -o yaml | kubectl apply -f -
```

Policy tuỳ chọn cho `key-vector` nếu bật **Restrict beyond user policy**:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:GetObject", "s3:ListBucket"],
      "Resource": ["arn:aws:s3:::tlc-zone", "arn:aws:s3:::tlc-zone/*"]
    }
  ]
}
```

Policy tuỳ chọn cho `key-risingwave`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:ListBucket"],
      "Resource": ["arn:aws:s3:::tlc-zone", "arn:aws:s3:::tlc-zone/*"]
    },
    {
      "Effect": "Allow",
      "Action": ["s3:*"],
      "Resource": [
        "arn:aws:s3:::iceberg-data",
        "arn:aws:s3:::iceberg-data/*",
        "arn:aws:s3:::rw-checkpoint",
        "arn:aws:s3:::rw-checkpoint/*"
      ]
    }
  ]
}
```

### 8.3. Redpanda

Helm values: [`config/redpanda/helm-values.yaml`](../config/redpanda/helm-values.yaml)

Deploy Redpanda bằng Helm trước. Repo hiện tại chỉ có ArgoCD app `redpanda-topics` để tạo topic, chưa có app `redpanda` để cài broker.

> **Thực thi trên:** `continux-imac`

```bash
helm repo add redpanda https://charts.redpanda.com
helm repo update

helm upgrade --install redpanda redpanda/redpanda \
    --namespace redpanda --create-namespace \
    -f config/redpanda/helm-values.yaml

kubectl -n redpanda rollout status statefulset/redpanda --timeout=600s
kubectl -n redpanda get pods,svc -o wide
# Kafka listener nội bộ của Helm chart đang expose qua service port 9093.
# Không dùng 9092 cho service DNS `redpanda.redpanda.svc.cluster.local`.

# Tạo topic qua GitOps Job
argocd app sync redpanda-topics
argocd app wait redpanda-topics --health --sync

# Xác nhận topic thật sự tồn tại trước khi sang Vector
kubectl -n redpanda exec redpanda-0 -c redpanda -- rpk topic list
kubectl -n redpanda exec redpanda-0 -c redpanda -- \
    rpk topic describe nyc-taxi-events --brokers redpanda.redpanda.svc.cluster.local:9093
```

Nếu `argocd app sync redpanda-topics` báo `PermissionDenied`, login lại ArgoCD rồi chạy lại:

```bash
argocd login continux-argo.<domain> --username admin --password <new> --grpc-web
argocd app sync redpanda-topics --grpc-web
```

Nếu `rpk topic list` không thấy `nyc-taxi-events`, đừng chạy Vector vội. Điều tra hook job trước:

```bash
argocd app get redpanda-topics
kubectl -n redpanda get jobs,pods -l app=redpanda-topic-bootstrap
kubectl -n redpanda logs job/redpanda-topic-bootstrap --all-containers --tail=100
```

Nếu job đã bị xoá do hook cũ từng báo success nhưng topic vẫn chưa có, tạo lại bằng sync sau khi đã push cấu hình mới:

```bash
argocd app get redpanda-topics --hard-refresh
argocd app sync redpanda-topics
argocd app wait redpanda-topics --health --sync
```

Fallback thủ công khi cần unblock nhanh:

```bash
kubectl -n redpanda exec redpanda-0 -c redpanda -- \
    rpk topic create nyc-taxi-events \
    --brokers redpanda.redpanda.svc.cluster.local:9093 \
    --partitions 3 \
    --replicas 1 \
    --topic-config retention.ms=86400000 \
    --topic-config cleanup.policy=delete

kubectl -n redpanda exec redpanda-0 -c redpanda -- \
    rpk topic describe nyc-taxi-events --brokers redpanda.redpanda.svc.cluster.local:9093
```

### 8.4. RisingWave

RisingWave v2.8+ gồm 4 thành phần: **meta**, **compute**, **frontend**, **compactor**. Với 8 GB RAM cần giới hạn chặt.

Helm values: [`config/risingwave/helm-values.yaml`](../config/risingwave/helm-values.yaml)

Deploy RisingWave bằng Helm. Repo hiện tại chưa có ArgoCD app `risingwave`, nên không dùng `argocd app sync risingwave`.

> **Lưu ý tài nguyên:** compactor cần RAM đủ lớn; nếu thiếu sẽ CrashLoopBackOff với lỗi `compactor_memory_limit_bytes`. Helm values hiện đặt `requests: 1Gi`, `limits: 2Gi` để tránh panic khi boot trên iMac 8 GB.

> **Thực thi trên:** `continux-imac`

```bash
kubectl -n risingwave get secret risingwave-s3-credentials
kubectl -n risingwave get secret risingwave-s3-credentials -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d && echo

helm repo add risingwavelabs https://risingwavelabs.github.io/helm-charts/
helm repo update
helm search repo risingwave

helm upgrade --install risingwave risingwavelabs/risingwave \
    --namespace risingwave --create-namespace \
    -f config/risingwave/helm-values.yaml

kubectl -n risingwave get pods,svc -o wide
kubectl -n risingwave rollout status statefulset/risingwave-compute --timeout=300s

# Kết nối qua psql
kubectl -n risingwave port-forward svc/risingwave 4567:svc
# Có thể Ctrl+C để tắt port-forward trước khi chuyển sang §8.5.
psql -h localhost -p 4567 -d dev -U root
# psql (16.13 (Ubuntu 16.13-0ubuntu0.24.04.1), server 13.14.0)
# Type "help" for help.

# dev=> SHOW CLUSTER;
#  Id |                                 Addr                                 |           Type           |  State  | Parallelism | Is Streaming | Is Serving | Is Unschedulable |        Started At
# ----+----------------------------------------------------------------------+--------------------------+---------+-------------+--------------+------------+------------------+---------------------------
#   0 | risingwave-meta-0.risingwave-meta-headless.risingwave.svc:5690       | WORKER_TYPE_META         | RUNNING |             |              |            |                  | 2026-05-19 05:28:43+00:00
#   1 | 10.42.0.23:4567                                                      | WORKER_TYPE_FRONTEND     | RUNNING |             | f            | f          | f                | 2026-05-19 05:28:53+00:00
#   2 | risingwave-compute-0.risingwave-compute-headless.risingwave.svc:5688 | WORKER_TYPE_COMPUTE_NODE | RUNNING |           2 | t            | t          | f                | 2026-05-19 05:28:53+00:00
#   5 | 10.42.0.25:6660                                                      | WORKER_TYPE_COMPACTOR    | RUNNING |           3 | f            | f          | f                | 2026-05-19 05:32:45+00:00
# (4 rows)
```

### 8.5. Vector (load generator)

Manifest: [`config/vector/deployment.yaml`](../config/vector/deployment.yaml) · PVC: [`config/vector/pvc.yaml`](../config/vector/pvc.yaml)

Cấu hình Vector: [`pipelines/vector/vector.toml`](../pipelines/vector/vector.toml) — xem §10.4.

`vector/deployment.yaml` mount ConfigMap `vector-config`. Khi sync qua ArgoCD, `config/vector/kustomization.yaml` apply `config/vector/vector-config.yaml` (nội dung bám theo `pipelines/vector/vector.toml`). Nếu apply thủ công không qua Kustomize, tạo ConfigMap trước:

> **Thực thi trên:** `continux-imac`

```bash
kubectl create namespace pipeline --dry-run=client -o yaml | kubectl apply -f -
kubectl -n pipeline create configmap vector-config \
    --from-file=vector.toml=pipelines/vector/vector.toml \
    --dry-run=client -o yaml | kubectl apply -f -
```

---

## 9. Deploy observability trên `continux-vps`

### 9.1. VictoriaMetrics

Helm values: [`config/victoria-metrics/helm-values.yaml`](../config/victoria-metrics/helm-values.yaml)

> **Thực thi trên:** `continux-vps` / kube-context trỏ tới cluster observability.
>
> **Lưu ý:** `config/victoria-metrics/helm-values.yaml` đặt `fullnameOverride: victoria-metrics` để tránh tên resource vượt giới hạn 63 ký tự của Kubernetes. Grafana datasource URL hardcode service name `vmsingle-victoria-metrics`, nên giữ nguyên release name/override này khi deploy.
>
> ```bash
> cd ~/continux
>
> helm repo add vm https://victoriametrics.github.io/helm-charts/
> helm repo update
>
> # Install/update VictoriaMetrics Operator CRDs first. The stack renders
> # VMAgent/VMServiceScrape/VMNodeScrape resources, so Helm needs these
> # kinds to exist before installing the release.
> helm show crds vm/victoria-metrics-k8s-stack \
>     | kubectl apply -f - --server-side
>
> kubectl wait --for condition=Established crd/vmagents.operator.victoriametrics.com --timeout=120s
> kubectl wait --for condition=Established crd/vmservicescrapes.operator.victoriametrics.com --timeout=120s
> kubectl wait --for condition=Established crd/vmnodescrapes.operator.victoriametrics.com --timeout=120s
>
> helm upgrade --install victoria-metrics vm/victoria-metrics-k8s-stack \
>     --namespace observability --create-namespace \
>     -f config/victoria-metrics/helm-values.yaml
> ```

Sau khi VictoriaMetrics đã tồn tại, sync scrape config qua ArgoCD:

> **Thực thi trên:** `continux-imac`

```bash
argocd app sync victoria-scrapes
argocd app wait victoria-scrapes --health --sync
```

### 9.2. Deploy Grafana

Helm values: [`config/grafana/helm-values.yaml`](../config/grafana/helm-values.yaml)

Grafana chưa có ArgoCD app riêng trong repo hiện tại, deploy bằng Helm:

> **Thực thi trên:** `continux-vps`

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm upgrade --install grafana grafana/grafana \
    --namespace observability --create-namespace \
    -f config/grafana/helm-values.yaml

kubectl -n observability rollout status deploy/grafana --timeout=300s
kubectl -n observability get pods,svc -o wide
```

### 9.3. Truy cập Grafana

Grafana đã được expose qua Cloudflare Tunnel cấu hình ở §7.2 — truy cập `https://continux-grafana.<domain>`.

Username được đặt trong [`config/grafana/helm-values.yaml`](../config/grafana/helm-values.yaml): `adminUser: admin`. Password không commit vào repo; Helm chart sinh password vào Kubernetes Secret `grafana`.

Lấy password admin:

> **Thực thi trên:** `continux-vps`

```bash
kubectl -n observability get secret grafana \
    -o jsonpath="{.data.admin-password}" | base64 -d && echo
```

Đăng nhập bằng `admin` / password trên, rồi đổi password ngay lần đầu.

### 9.4. Dashboard Grafana

Thư mục `dashboards/` chứa 4 dashboard JSON đã chuẩn bị sẵn:

- **Streaming Performance** — [`dashboards/01-streaming-perf.json`](../dashboards/01-streaming-perf.json)
- **Resource Utilization** — [`dashboards/02-resource-util.json`](../dashboards/02-resource-util.json)
- **Blue/Green Cutover** — [`dashboards/03-cutover.json`](../dashboards/03-cutover.json)
- **Data Integrity** — [`dashboards/04-data-integrity.json`](../dashboards/04-data-integrity.json)

**Datasource:** vào **Connections -> Data sources -> VictoriaMetrics -> Save & test**. Nếu báo lỗi, kiểm tra URL trong [`config/grafana/helm-values.yaml`](../config/grafana/helm-values.yaml): `http://vmsingle-victoria-metrics.observability.svc.cluster.local:8428`. Lưu ý `vmsingle` dùng port `8428`; port `8429` là service của `vmagent`.

**Import dashboard JSON:**

1. Vào **Dashboards -> New -> Import**.
2. Upload từng file JSON trong `dashboards/`.
3. Khi Grafana hỏi datasource variable `DS_VICTORIAMETRICS`, chọn datasource **VictoriaMetrics**.
4. Bấm **Import**.

**Chỉnh dashboard bằng JSON model:**

1. Mở dashboard cần chỉnh.
2. Vào **Dashboard settings -> JSON model**.
3. Sửa trực tiếp JSON rồi bấm **Save changes**.
4. Sau khi chỉnh ổn trong UI, export lại JSON về đúng file trong `dashboards/`.

Quy ước khi chỉnh JSON:

- Không hardcode datasource UID như `P4169E866C3094E38`; dùng `${DS_VICTORIAMETRICS}` để import được trên Grafana khác.
- Query số hiện tại đặt `"instant": true`, `"range": false`.
- Query time-series đặt `"range": true` và không bật instant.
- Panel **Stat** nhiều query dùng `"reduceOptions": { "values": true, "calcs": ["lastNotNull"] }` và `"textMode": "value_and_name"`.
- Label dài hoặc nhiều label nên đưa sang panel **Table**, không render trực tiếp trong **Stat**.
- Các metric `continux_*` là metric ứng dụng sẽ được expose từ experiment/cutover/verify job; dashboard vẫn import được trước, panel đó có thể tạm `No data`.

**Export thủ công từ UI:**

1. Mở dashboard cần export.
2. Vào **Dashboard settings** → **JSON model**.
3. Copy toàn bộ JSON model và lưu vào repo:
   - `dashboards/01-streaming-perf.json`
   - `dashboards/02-resource-util.json`
   - `dashboards/03-cutover.json`
   - `dashboards/04-data-integrity.json`

---

## 10. Dataset & Vector

Mục tiêu của section này: chuẩn bị **full JSONL dataset**, sync manifest Vector một cách an toàn, rồi bật ingest thủ công.

Quy ước ổn định:

- Vector đọc full JSONL từ `data/raw/*.jsonl`.
- GitOps mặc định giữ Vector ở `replicas: 0`; `argocd app sync vector` không tự chạy ingest.
- Chỉ scale Vector lên `1` sau khi K3s API, Redpanda topic, PV/PVC và file JSONL đều OK.
- Nếu node bắt đầu ì, scale Vector về `0` ngay.

### 10.1. Gate an toàn trước khi làm tiếp

Nếu cụm vừa bị ì, hoặc kernel báo `Memory cgroup out of memory` do Vector, dừng Vector trước:

```bash
kubectl -n pipeline scale deploy/vector --replicas=0
kubectl -n pipeline wait --for=delete pod -l app=vector --timeout=120s
kubectl -n pipeline get pods -l app=vector
```

Không chạy `argocd app diff/sync` khi K3s API chưa khỏe. Khôi phục control plane trước, chỉ tiếp tục khi các lệnh này chạy được:

```bash
~/continux/scripts/k3s-check.sh
kubectl get nodes -o wide
kubectl get nodes -l role=quorum -o wide
kubectl get --raw='/readyz?verbose'
kubectl get --raw='/readyz?verbose' | grep -E 'etcd|readyz|ok'
kubectl get pods -A --field-selector=status.phase!=Running
```

Nếu bất kỳ K3s server nào chưa `Ready`, hoặc port etcd peer `2380` timeout giữa các server, **không scale Vector**. Đợi quorum `2/3` ổn định trước rồi mới tiếp tục.

### 10.2. Tải dataset + convert full JSONL

Nguồn chính thức: [NYC TLC Trip Record Data](https://www.nyc.gov/site/tlc/about/tlc-trip-record-data.page). TLC publish dữ liệu theo tháng, thường trễ khoảng 2 tháng để chờ vendor gửi đủ dữ liệu. Tại thời điểm kiểm tra **20/05/2026**, file Yellow Taxi mới nhất đang có trên trang TLC là **2026-03**.

Khuyến nghị:
- Dùng **`2026-03`** nếu muốn dữ liệu mới nhất hiện tại.
- Dùng **`2024-01`** nếu muốn giữ dataset cũ đã quen thuộc trong docs và tránh thay đổi schema/volume bất ngờ.

> Lưu ý schema: theo TLC, từ dữ liệu **2025 trở đi** Yellow/Green/HVFHV có thêm cột `cbd_congestion_fee`. Nếu pipeline downstream đang giả định schema cũ, dùng `2024-01`; nếu pipeline đọc JSON linh hoạt/ignore field thừa, dùng `2026-03`.

> **Thực thi trên:** `continux-imac`

```bash
DATA_MONTH=2026-03
DATA_URL="https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_${DATA_MONTH}.parquet"
ZONE_URL="https://d37ci6vzurychx.cloudfront.net/misc/taxi_zone_lookup.csv"

curl -I "$DATA_URL"
curl -I "$ZONE_URL"

mkdir -p ~/continux/data/raw ~/continux/data/zone
sudo chown -R "$USER:$USER" ~/continux/data
chmod -R u+rwX ~/continux/data

cd ~/continux/data/raw
wget -c "$DATA_URL"

# Vector đọc JSONL, không đọc trực tiếp Parquet.
# Lệnh dưới convert đúng các field mà RisingWave source ở §11.1 đang khai báo.
cd ~/continux
python3 -m venv .venv
. .venv/bin/activate
pip install --upgrade pip pyarrow
python scripts/tlc-parquet-to-jsonl.py \
    "data/raw/yellow_tripdata_${DATA_MONTH}.parquet" \
    "data/raw/yellow_tripdata_${DATA_MONTH}.jsonl"

ls -lh data/raw/yellow_tripdata_${DATA_MONTH}.parquet \
       data/raw/yellow_tripdata_${DATA_MONTH}.jsonl
```

Mount thư mục raw vào pod Vector bằng PVC `hostPath: /home/helios/continux/data/raw` (xem `config/vector/pvc.yaml`). Thư mục `data/raw/` đã nằm trong `.gitignore`, còn `data/zone/` có thể lưu file nhỏ như `taxi_zone_lookup.csv`.

### 10.3. Upload Taxi Zone vào MinIO

> **Thực thi trên:** `continux-imac`

```bash
cd ~/continux/data/zone
wget -c "$ZONE_URL"

# Upload Zone lookup vào MinIO bucket
PASSWORD=<root-password>

# MinIO service đang là ClusterIP, nên mở port-forward API 9000 trong terminal riêng:
kubectl -n minio port-forward --address 127.0.0.1 svc/minio 9000:9000

# Terminal còn lại:
mc alias set local http://127.0.0.1:9000 adminuser "$PASSWORD"
mc cp taxi_zone_lookup.csv local/tlc-zone/taxi_zone_lookup.csv
mc ls local/tlc-zone
# [2026-05-19 17:31:11 UTC]  12KiB STANDARD taxi_zone_lookup.csv
```

### 10.4. Preflight trước khi sync Vector

Cấu hình nguồn → transform → sink: [`pipelines/vector/vector.toml`](../pipelines/vector/vector.toml)

Luồng hiện tại:

1. Script [`scripts/tlc-parquet-to-jsonl.py`](../scripts/tlc-parquet-to-jsonl.py) convert Yellow Taxi Parquet thành JSONL.
2. Vector đọc `/data/*.jsonl` từ PVC `vector-data`.
3. Transform `parse_and_simulate_event_time` parse từng dòng JSON, thêm `event_id` và `event_time`.
4. Sink Kafka publish JSON vào Redpanda topic `nyc-taxi-events`, dùng disk buffer 512 MiB tại `/var/lib/vector` và `when_full = "block"` để không phình RAM nếu Redpanda chậm.

Các lệnh dưới phải có output rõ ràng; riêng `rpk topic describe` phải in được thông tin topic `nyc-taxi-events`.

> **Thực thi trên:** `continux-imac`

```bash
DATA_MONTH=${DATA_MONTH:-2026-03}

ls -lh ~/continux/data/raw/yellow_tripdata_${DATA_MONTH}.jsonl
kubectl -n redpanda get pod redpanda-0
kubectl -n redpanda exec redpanda-0 -c redpanda -- rpk topic list
kubectl -n redpanda exec redpanda-0 -c redpanda -- \
    rpk topic describe nyc-taxi-events --brokers redpanda.redpanda.svc.cluster.local:9093

kubectl get pv vector-data-pv -o jsonpath='{.spec.hostPath.path}{"\n"}' || true
# Kết quả đúng nếu PV đã tồn tại: /home/helios/continux/data/raw
```

Nếu `rpk topic describe nyc-taxi-events` báo không tìm thấy topic, quay lại §8.3 để sync/tạo topic trước. Vector sẽ publish lỗi nếu topic chưa tồn tại.

Kiểm tra manifest hiện tại trong repo:

```bash
kubectl kustomize config/vector | grep -E 'memory:|sizeLimit:|/data/\*.jsonl|when_full|buffer' -n
```

Kỳ vọng:

- `include = ["/data/*.jsonl"]`
- `memory: 1Gi`
- `sizeLimit: 1Gi`
- `when_full = "block"`
- `config/vector/deployment.yaml` có `replicas: 0`

Nếu PV `vector-data-pv` đã được tạo từ cấu hình cũ và còn trỏ sang path khác, xoá riêng workload/PVC/PV của Vector rồi để ArgoCD tạo lại:

```bash
kubectl -n pipeline delete deploy/vector pvc/vector-data --ignore-not-found
kubectl delete pv/vector-data-pv --ignore-not-found
```

### 10.5. Sync manifest Vector ở trạng thái dừng

Sync manifest Vector:

> **Thực thi trên:** `continux-imac`

```bash
argocd app get vector --hard-refresh --grpc-web
argocd app diff vector --grpc-web
argocd app sync vector --grpc-web
argocd app wait vector --health --sync --grpc-web
```

Sau khi sync, xác nhận Deployment vẫn đang dừng:

```bash
kubectl -n pipeline get deploy/vector -o jsonpath='{.spec.replicas}{" desired, "}{.status.readyReplicas}{" ready\n"}'
# 0 desired,  ready
kubectl -n pipeline get pv vector-data-pv
# NAME             CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                  STORAGECLASS   VOLUMEATTRIBUTESCLASS   REASON   AGE
# vector-data-pv   10Gi       RWO            Retain           Bound    pipeline/vector-data   local-path     <unset>                          19s
kubectl -n pipeline get pvc vector-data
# NAME          STATUS   VOLUME           CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
# vector-data   Bound    vector-data-pv   10Gi       RWO            local-path     <unset>                 21s
```

Kỳ vọng: `0 desired`.

### 10.6. Bật/tắt Vector ingest thủ công

Chỉ scale Vector lên `1` khi K3s API khỏe, PV/PVC đã bound, Redpanda topic sẵn sàng và file JSONL đã nằm trong `data/raw/`.

```bash
kubectl -n pipeline scale deploy/vector --replicas=1
kubectl -n pipeline rollout status deploy/vector --timeout=300s
kubectl -n pipeline logs deploy/vector --tail=100
kubectl -n pipeline get pod -l app=vector -o wide
kubectl -n pipeline describe pod -l app=vector | grep -E 'OOMKilled|Reason|Limits|Requests' -A3
```

Kỳ vọng sau khi bật ingest:

- Pod Vector `1/1 Running`, `RESTARTS=0`.
- Log có `Vector has started`, `Found new file to watch. file=/data/yellow_tripdata_2026-03.jsonl`, `Healthcheck passed`.
- `~/continux/scripts/k3s-check.sh` chạy được, namespace `pipeline` có `vector` Running, RAM node không tăng bất thường.

---

## 11. Apply SQL Blue và Iceberg Sink

> ⚠️ **Trước khi apply SQL:** `sql/02-tables/tlc-taxi-zone.sql` và `sql/04-sinks/iceberg-zone-stats.sql` chứa placeholder `<replace: key-risingwave secret từ MinIO console §8.2>`. Phải thay bằng secret key thực của service account `key-risingwave` (lấy từ MinIO console ở §8.2) rồi mới chạy các file này.

> **RAM guardrail:** `gitops/pipeline/sql-apply-job.yaml` đã giới hạn `128Mi`. Nếu RisingWave compute OOM khi xử lý full dataset, dừng Vector trước, đợi cụm ổn định rồi mới chạy lại.

### 11.1. Source + Table

[`sql/01-sources/redpanda-nyc-taxi.sql`](../sql/01-sources/redpanda-nyc-taxi.sql)

[`sql/02-tables/tlc-taxi-zone.sql`](../sql/02-tables/tlc-taxi-zone.sql)

### 11.2. MV Blue

[`sql/03-mv/mv_zone_stats_blue.sql`](../sql/03-mv/mv_zone_stats_blue.sql)

### 11.3. Iceberg Sink

[`sql/04-sinks/iceberg-zone-stats.sql`](../sql/04-sinks/iceberg-zone-stats.sql)

### 11.4. Commit & Sync

> **Thực thi trên:** `local` — push code từ máy phát triển

```bash
git add sql/ gitops/pipeline/
git commit -m "feat(mv): initial Blue MV mv_zone_stats"
git push
```

> **Thực thi trên:** `continux-imac` — theo dõi ArgoCD sync (ArgoCD tự sync trong ≤ 3 phút — FR-12)

```bash
argocd app sync pipeline
argocd app wait pipeline --health --sync
```

Nếu `pipeline` chưa healthy, xem Job và event trước khi chạy lại:

```bash
kubectl -n pipeline get jobs,pods
kubectl -n pipeline logs job/mv-apply-job --tail=100
kubectl -n risingwave get pods -o wide
kubectl -n risingwave get events --sort-by=.lastTimestamp | tail -40
```

Verify:

> **Thực thi trên:** `continux-imac`

```bash
psql -h localhost -p 4567 -d dev -U root -c \
    "SELECT borough, SUM(trip_count) FROM mv_zone_stats GROUP BY borough ORDER BY 2 DESC LIMIT 5;"

mc ls --recursive local/iceberg-data/nyc/zone_stats/ | head
```

Mở Grafana **Streaming Perf** → Consumer Lag tiệm cận 0 sau khi bắt kịp.

---

## 12. Triển khai Blue/Green Swap (Giai đoạn 4)

Khi MV Blue đã ổn định:

1. Tạo `sql/03-mv/mv_zone_stats_green.sql` với logic mới.
2. Commit & push — ArgoCD sync → `mv-swap-runner` Job (PostSync Hook) sẽ:
   - `CREATE MATERIALIZED VIEW mv_zone_stats_green`
   - Poll metric `rw_consumer_lag` qua VictoriaMetrics API
   - Khi `lag ≤ 2s` duy trì ≥ 60s → `ALTER MATERIALIZED VIEW mv_zone_stats SWAP WITH mv_zone_stats_green`
   - Drop MV cũ sau `retention=10m`

Chi tiết cơ chế Job xem [ARCHITECTURE.md §3 — Quy ước GitOps](./ARCHITECTURE.md#3-quy-ước-nhánh-git--commit).

---

## 13. Chạy các kịch bản thực nghiệm

> **Thực thi trên:** `continux-imac`

Sau khi §11 verify được dữ liệu và Grafana có metric, chạy kịch bản thực nghiệm. Nếu cụm vừa OOM, dừng Vector trước rồi chỉ chạy lại khi `kubectl get pods -A` đã ổn định.

```bash
test -x experiments/runners/run_stress.sh
test -x experiments/runners/run_swap.sh
test -f experiments/runners/verify_integrity.py

bash experiments/runners/run_stress.sh --rate=medium --duration=15m
bash experiments/runners/run_swap.sh --repeat=5

# Data integrity
python experiments/runners/verify_integrity.py \
    --vector-events experiments/results/vector_count.csv \
    --iceberg-table nyc.zone_stats
```

Kết quả thô → `experiments/results/` → biểu đồ cho [REPORT.md Chương 4](./REPORT.md#chương-4--kết-quả-thực-nghiệm).

---

## 14. Backup & chuyển vùng

### 14.1. Backup dữ liệu quan trọng

> **Thực thi trên:** `continux-imac`

```bash
# Snapshot K3s embedded etcd
sudo k3s etcd-snapshot save --name pre-finalize

# Export toàn bộ manifest từ cluster (snapshot GitOps)
kubectl get all,cm,secret,pvc -A -o yaml > backup-$(date +%F).yaml

# Tar gzip dữ liệu MinIO (offline)
mc mirror local/iceberg-data ./backup-iceberg/
```

### 14.2. Xuất Grafana dashboards trước khi teardown

> **Thực thi trên:** `continux-vps`

```bash
cd ~/continux

# Dùng lại quy trình export bằng API ở §9.2 để ghi đè dashboards/*.json
# trước khi teardown Grafana hoặc reset cluster.
ls dashboards/*.json
```

---

## 15. Dọn dẹp / Reset

> **Thực thi trên:** `continux-imac` — xoá ArgoCD Applications trước

```bash
argocd app delete root-app --cascade
```

> **Thực thi trên:** `continux-imac` — reset K3s server #1

```bash
sudo /usr/local/bin/k3s-uninstall.sh
```

> **Thực thi trên:** `continux-vps` — reset K3s server #2

```bash
sudo /usr/local/bin/k3s-uninstall.sh
```

> **Thực thi trên:** `helios-wsl` — reset K3s server #3

```bash
sudo /usr/local/bin/k3s-uninstall.sh
```

> **Thực thi trên:** `nammn` — nếu worker đang join

```bash
sudo /usr/local/bin/k3s-agent-uninstall.sh
```

> **Thực thi trên:** `ba server` và worker đang bật — gỡ Tailscale nếu muốn

```bash
sudo tailscale down
sudo apt purge tailscale -y
```

> ⚠️ `k3s-uninstall.sh` xoá **toàn bộ** pod, PVC và thư mục `/var/lib/rancher/k3s`. Hãy backup trước (xem §14).

---

## 16. Gỡ lỗi thường gặp

| Triệu chứng | Nguyên nhân thường gặp | Cách xử lý |
|-------------|------------------------|------------|
| `kubectl get nodes` báo `permission denied` với `/etc/rancher/k3s/k3s.yaml` | User thường không có quyền đọc kubeconfig mặc định của K3s | Dùng `sudo kubectl ...`, hoặc copy kubeconfig sang `~/.kube/config` cho user; nếu muốn dùng chung, cài K3s với `--write-kubeconfig-mode=644` |
| `kubectl get nodes` chỉ thấy `continux-imac` | Server #2/#3 chưa join được qua Tailscale | `tailscale status` trên node cần join → ping `continux-imac`; kiểm tra `K3S_URL` đúng dạng `https://100.x.x.x:6443` và lệnh cài là `server` |
| Cài server #2/#3 báo lỗi datastore | Server #1 đang chạy SQLite (không có `--cluster-init`) | Re-bootstrap `continux-imac` theo §5.1 để bật embedded etcd rồi join lại §5.3-§5.4 |
| K3s API không kết nối được, journal có `failed to publish local member to cluster through raft` / `TLS handshake timeout` | Embedded etcd mất quorum, peer chậm/kẹt, hoặc Tailscale giữa các server lỗi. Cụm 3 server cần ít nhất `2/3` peer healthy | Kiểm tra `tailscale ping`, port `2379/2380/6443` giữa ba server; đảm bảo `helios-wsl` còn chạy; kiểm tra `free -h`, `df -h`; restart K3s từng server nếu cần |
| Pod bị `Pending` — `FailedScheduling` vì taint | Workload bị đẩy sang node có taint (`continux-vps` hoặc `helios-wsl`) | Đặt `nodeSelector` đúng vai trò. Workload nặng dùng `role=data-plane`; workload nhẹ dùng `role=control-plane` + toleration `dedicated=edge`; không schedule app lên `role=quorum` |
| RisingWave compute `OOMKilled` | Vượt `limits.memory=2.5Gi` của iMac 8GB | Giảm parallelism MV; tăng `compute.limits.memory` nếu còn chỗ; giảm load Vector |
| MinIO `ReadOnly` mode | Disk iMac gần đầy (200 GB) | `df -h`; xoá snapshot Iceberg cũ bằng `expire_snapshots` |
| Droplet CPU `100%` liên tục | ArgoCD app-controller ôm quá nhiều app | Giảm số App-of-Apps; hoặc resize droplet lên $24/mo (nếu chưa) |
| Tailscale ngắt kết nối sau vài giờ | NAT của modem kill session UDP | Trên iMac: `sudo tailscale up --reset --accept-routes --ssh` với systemd unit autorestart |
| `psql: SSL off error` | RisingWave v2.4 bật SSL mặc định | `PGSSLMODE=disable psql ...` hoặc `\set SSLMODE disable` |
| Vector làm cụm đơ ngay khi sync | Deployment Vector tự start trong lúc ArgoCD sync | Đặt `config/vector/deployment.yaml` `replicas: 0`; sync manifest trước, sau đó mới `kubectl -n pipeline scale deploy/vector --replicas=1` khi K3s API khỏe |
| Vector bị `OOMKilled` sau khi scale lên 1 | Memory limit cũ quá thấp so với full JSONL | `kubectl -n pipeline scale deploy/vector --replicas=0`; sync cấu hình mới có limit `1Gi` + disk buffer `512Mi`; sau đó chạy lại Vector |
| Redpanda `out of memory` khi stress | Container cap 1.5 GiB không đủ cho burst | Chạy JSONL nhỏ hơn trước, hoặc thêm `reserveMemory: 256Mi` |
| Iceberg sink ghi nhưng query không thấy dữ liệu | Commit snapshot chưa chạy | Đợi `compactor` (mặc định mỗi 60s) hoặc force `CALL rw_iceberg_commit()` |
| Grafana báo `ChunkLoadError: Loading chunk ... failed` | Browser hoặc Cloudflare cache còn giữ asset JS cũ sau khi Grafana upgrade/restart | Hard refresh `Ctrl+F5`; mở Incognito; xoá site data cho domain Grafana; nếu vẫn lỗi thì purge cache Cloudflare cho `continux-grafana.<domain>` và `kubectl -n observability rollout restart deploy/grafana` |
| Dashboard Grafana báo `No data` | `vmagent` không scrape được qua namespace khác | Kiểm tra `scrape-configs.yaml` có `role: endpoints` + namespace whitelist |
| Commit Git đã push nhưng ArgoCD không sync | Repo secret hết hạn (GH PAT) | `argocd repo add` lại với PAT mới (classic, scope `repo`) |

---

## 17. Checklist hoàn tất

- [ ] `kubectl get nodes` → 3 K3s server `Ready`, cả ba có `ROLES` chứa `control-plane,etcd`, node IP thuộc range `100.64.0.0/10` (Tailscale).
- [ ] `continux-imac` có `role=data-plane`, `continux-vps` có `role=control-plane`, `helios-wsl` có `role=quorum` và taint `dedicated=quorum:NoSchedule`.
- [ ] `tailscale status` hiển thị ba server, ping qua lại < 100 ms; port `2380` thông giữa các etcd peer.
- [ ] ArgoCD UI truy cập được qua Tailscale IP hoặc NodePort; `root-app` `Synced + Healthy`.
- [ ] MinIO có 3 bucket (`iceberg-data`, `rw-checkpoint`, `tlc-zone`), 3 access key riêng biệt.
- [ ] `rpk topic list` trả về `nyc-taxi-events` với 3 partitions.
- [ ] `psql` kết nối RisingWave OK; `SHOW SOURCES` và `SHOW MATERIALIZED VIEWS` có dữ liệu.
- [ ] Vector log không có lỗi parse JSONL/Kafka sink.
- [ ] Grafana 4 dashboard hiện số (không `No data`).
- [ ] `SELECT COUNT(*) FROM mv_zone_stats` > 0 và tăng theo thời gian.
- [ ] `mc ls local/iceberg-data/nyc/zone_stats/` có file Parquet + metadata `.json`.
- [ ] (Sau G4) Commit SQL Green → Swap tự động, downtime đo được ≤ 1s.

Khi toàn bộ checklist xanh → sẵn sàng Giai đoạn 5 (Thực nghiệm, xem [TIMELINE.md](./TIMELINE.md)).
