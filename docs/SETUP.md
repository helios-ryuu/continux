# SETUP — HƯỚNG DẪN THIẾT LẬP TOÀN DIỆN

## 0. Tổng quan hạ tầng

### 0.1. Hai node chính của cluster

| Vai trò | Máy | Cấu hình | OS | Vị trí mạng |
|---------|-----|----------|----|-------------|
| `continux-imac` (K3s **server #1**) | iMac19,2 | Intel i5-8500, 6 cores, 8 GB DDR4, 200 GB SSD | **Ubuntu Server 24.04.4 LTS** (đã cài sẵn) | LAN nhà — sau NAT |
| `continux-vps` (K3s **server #2**) | DigitalOcean Droplet — gói **$12/mo** (nâng lên **$24/mo** khi cần) | 1 vCPU, 2 GB RAM, 50 GB SSD, 2 TB transfer → 2 vCPU, 4 GB RAM, 80 GB SSD, 4 TB transfer | **Ubuntu 24.04 LTS** | Public IPv4/IPv6 |

> **Chiến lược chọn gói:** Bắt đầu với gói **$12/mo** (1 vCPU, 2 GB RAM) — đủ RAM để chạy ArgoCD + VictoriaMetrics hoặc Grafana riêng lẻ trong giai đoạn phát triển. Nâng lên **$24/mo** (2 vCPU, 4 GB RAM) khi cần chạy đầy đủ cả ba service cùng lúc liên tục (~800 MB + ~512 MB + ~256 MB = ~1.6 GB). Việc resize Droplet trên DigitalOcean chỉ mất 1–2 phút và giữ nguyên IP, không cần cấu hình lại cluster.
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
                              │  Tailscale (chỉ khi cần burst)
                  ┌───────────┴───────────┐
                  ▼                       ▼
      ┌─── helios (WSL2, 16 GB) ──┐  ┌─── nammn (WSL2, 32 GB) ──┐
      │  K3s worker phụ trợ       │  │  K3s worker phụ trợ        │
      │  (bật khi cần)            │  │  (bật khi OOM hoặc burst)  │
      └───────────────────────────┘  └────────────────────────────┘
```

### 0.3. Hai node phụ trợ (WSL2 Ubuntu 24.04 — bật khi cần)

| Node | Máy chủ | CPU | RAM | GPU rời | Vai trò |
|------|---------|-----|-----|---------|---------|
| **`nammn`** | Laptop Nam — Windows 11 (SINISTER) | AMD Ryzen 5 7640HS — 8C/16T, boost 4.3 GHz | 32 GB DDR5 5600 MHz (2×16 GB Hynix) | NVIDIA GeForce RTX 3050 6 GB | K3s worker burst — bật khi `continux-imac` OOM hoặc cần > 10 k events/s |
| **`helios`** | Laptop Helios — Windows 11 (HELIOS-PC) | Intel Core i5-12500H — 12C/16T, max 4.5 GHz | 16 GB DDR5 4800 MHz (2×8 GB Samsung) | NVIDIA GeForce RTX 3050 Ti 4 GB | K3s worker dự phòng — bật khi thực nghiệm song song hoặc cần node bổ sung |

Cả hai máy cài **WSL2 Ubuntu 24.04** — K3s agent chạy trong WSL2, join cluster qua Tailscale (xem §5.5).

> **Khi nào bật:** chỉ trong Giai đoạn 4–5 (stress test, thực nghiệm). Không bật thường xuyên để tránh overhead etcd và tiết kiệm điện.

Mọi lệnh quản trị (`kubectl`, `helm`, `argocd`, `rpk`, `mc`, `psql`) chạy trực tiếp trên `continux-imac`.

### 0.4. Ký hiệu máy dùng trong tài liệu này

| Ký hiệu | Máy | Nghĩa trong hướng dẫn |
|---------|-----|----------------------|
| **`[continux-imac]`** | iMac Ubuntu 24.04 | Chạy lệnh trực tiếp trên data plane — nơi mọi quản trị cluster diễn ra |
| **`[continux-vps]`** | DigitalOcean Droplet Ubuntu 24.04 | Chạy lệnh trên observability/control plane |
| **`[cả hai máy]`** | `continux-imac` + `continux-vps` | Chạy lần lượt trên cả hai node chính |
| **`[helios]`** | Laptop Helios — WSL2 Ubuntu 24.04 | Chạy khi `helios` đang là K3s worker (§5.5) |
| **`[nammn]`** | Laptop Nam — WSL2 Ubuntu 24.04 | Chạy khi `nammn` đang là K3s worker (§5.5) |
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
| K3s | **v1.34.6+k3s1** trở lên (dựa trên Kubernetes 1.32) | `k3s --version` |
| Helm | **v4.1.1+** | `helm version` |
| Argo CD | **v3.3+** | `argocd version` |
| RisingWave | **v2.4+** (stable, hỗ trợ Iceberg Hosted Catalog) | `psql` → `SELECT version();` |
| Redpanda | **v26.1+** (không JVM, không ZooKeeper — dùng Raft tự thân) | `rpk version` |
| Vector | **0.45+** | `vector --version` |
| MinIO | RELEASE bản mới nhất (tối thiểu **RELEASE.2025-08-13** trở về sau) | `mc admin info` |
| VictoriaMetrics | **1.110+** | `/metrics` endpoint |
| Grafana | **11.6+** hoặc v12 nếu đã phát hành GA | Giao diện |
| Tailscale | **1.80+** | `tailscale version` |
| Apache Iceberg spec | v2 bắt buộc, v3 thử nghiệm | Metadata file |

---

## 2. Bản đồ 10 bước (Quickstart)

```
1. Chuẩn bị hai máy (iMac Ubuntu + Droplet Ubuntu) & bật SSH khoá công khai
2. Cài Tailscale trên hai máy, nối chúng vào một tailnet
3. Cài K3s server #1 trên iMac (cluster-init, dùng Tailscale IP làm node IP)
4. Join Droplet làm K3s server #2 qua Tailscale
5. Cài CLI trên continux-imac (kubectl, helm, argocd, rpk, mc, psql)
6. Cài Argo CD lên continux-vps và kết nối repo GitOps
7. Deploy hạ tầng: MinIO → Redpanda → RisingWave (continux-imac)
8. Deploy observability: VictoriaMetrics + Grafana (continux-vps)
9. Chuẩn bị dataset NYC TLC + cấu hình Vector
10. Apply SQL Blue + Iceberg Sink → verify end-to-end
```

Nếu đủ 10 bước, Grafana dashboard cho Consumer Lag ≤ 2s, và `SELECT COUNT(*) FROM mv_zone_stats` trả về số dương và tăng liên tục.

---

## 3. Chuẩn bị hai máy

### 3.1. iMac `continux-imac` (Ubuntu 24.04 đã cài)

Đã có `helios@helios-imac-ubuntu` chạy sẵn. Thêm các bước sau:

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

---

## 4. Tailscale mesh — nối iMac ↔ Droplet

### 4.1. Cài Tailscale trên cả hai máy

> **Thực thi trên:** `cả hai máy` — lần lượt trên `continux-imac` rồi `continux-vps`

```bash
curl -fsSL https://tailscale.com/install.sh | sh
```

### 4.2. Đăng ký vào cùng một tailnet

> **Thực thi trên:** `cả hai máy` — lần lượt trên `continux-imac` rồi `continux-vps`

```bash
sudo tailscale up
# Đăng nhập bằng Google/GitHub trên URL được in ra
```

Verify ở cả hai máy:

> **Thực thi trên:** `cả hai máy`

```bash
tailscale status
# Kết quả mong đợi:
# 100.x.x.x    continux-imac             username@  linux    -
# 100.x.x.x    continux-vps              username@  linux    active; direct [<IPv6>]:41641, tx 1187744 rx 729784
```

Ghi lại hai IP Tailscale — ta sẽ dùng làm **node IP của K3s** ở bước 5.

### 4.3. Kiểm tra kết nối

> **Thực thi trên:** `continux-vps`

```bash
ping -c 3 continux-imac     # Magic DNS giải IP tailscale
```

> **Thực thi trên:** `continux-imac`

```bash
ping -c 3 continux-vps
```

Nếu cả hai ping được thì mesh đã hoạt động.

---

## 5. Bootstrap cụm K3s

### 5.1. Cài K3s server #1 trên iMac (cluster-init)

> **Thực thi trên:** `continux-imac`

[SCRIPTS.md — k3s-install-server-init.sh](./SCRIPTS.md#k3s-install-server-initsh)

### 5.2. Cài K3s server #2 trên Droplet

> **Thực thi trên:** `continux-vps`

[SCRIPTS.md — k3s-install-server.sh](./SCRIPTS.md#k3s-install-serversh)

### 5.3. Gán label phân biệt vai trò cho hai node chính

> **Thực thi trên:** `continux-imac`

```bash
kubectl label node continux-imac workload=heavy role=data-plane
kubectl label node continux-vps  workload=light role=control-plane
kubectl taint node continux-vps  dedicated=edge:NoSchedule
# Chỉ pod có toleration { key: dedicated, value: edge } mới chạy trên continux-vps
```

Helm values sử dụng:
- Workload nặng (MinIO, Redpanda, RisingWave, Vector) → `nodeSelector: { role: data-plane }`
- Workload nhẹ (ArgoCD, VictoriaMetrics, Grafana) → `nodeSelector: { role: control-plane }` + `tolerations: [{key: dedicated, value: edge, effect: NoSchedule}]`

### 5.4. Verify cụm 2 node chính

> **Thực thi trên:** `continux-imac`

[SCRIPTS.md — k3s-check.sh](./SCRIPTS.md#k3s-checksh)

### 5.5. Join node phụ trợ `helios` hoặc `nammn` (chỉ khi cần burst)

Bật WSL2 Ubuntu 24.04 trên máy tương ứng, sau đó chạy:

> **Thực thi trên:** `helios` hoặc `nammn` (WSL2 Ubuntu 24.04)

[SCRIPTS.md — k3s-install.sh](./SCRIPTS.md#k3s-installsh)

Sau khi script chạy xong, gán label từ node quản trị:

> **Thực thi trên:** `continux-imac`

```bash
kubectl label node helios workload=heavy role=data-plane  # hoặc nammn
kubectl get nodes -o wide
```

**Gỡ worker khi xong:**

> **Thực thi trên:** `continux-imac`

```bash
kubectl drain <tên-node> --ignore-daemonsets --delete-emptydir-data
kubectl delete node <tên-node>
```

> **Thực thi trên:** `helios` hoặc `nammn` (WSL2)

```bash
sudo /usr/local/bin/k3s-agent-uninstall.sh
```

---

## 6. Công cụ CLI trên continux-imac

Tất cả lệnh quản trị cluster chạy trực tiếp trên `continux-imac`.

### 6.1. Cài CLI

> **Thực thi trên:** `continux-imac`

```bash
sudo apt install -y unzip postgresql-client

# helm 4.1+
sudo apt install curl gpg apt-transport-https --yes
curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install helm

# argocd CLI 3.3+
VERSION=$(curl -L -s https://raw.githubusercontent.com/argoproj/argo-cd/stable/VERSION)
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

Verify:

> **Thực thi trên:** `continux-imac`

[SCRIPTS.md — k3s-check.sh](./SCRIPTS.md#k3s-checksh)

### 6.3. Cập nhật phần mềm (Maintenance)

Chạy đầu mỗi giai đoạn hoặc khi có CVE nghiêm trọng. **Không nâng cấp** K3s, rpk, mc khi đang chạy thực nghiệm (Giai đoạn 5).

**Nguyên tắc chọn phiên bản:** ưu tiên stable release. Nếu phiên bản mới nhất có hậu tố `-alpha`, `-beta`, `-rc` → bỏ qua, dùng bản stable liền trước.

Kiểm tra trạng thái trước khi cập nhật:

> **Thực thi trên:** `continux-imac` hoặc `continux-vps`

[SCRIPTS.md — tool-version.sh](./SCRIPTS.md#tool-versionsh)

Các lệnh cập nhật cần sudo — chạy trong SSH session tương tác trực tiếp trên máy đích:

> **Thực thi trên:** `cả hai máy` — lần lượt `continux-imac` rồi `continux-vps`

```bash
sudo apt update && sudo apt -y upgrade && sudo apt -y autoremove
sudo tailscale update --track=stable
```

> **Thực thi trên:** `continux-imac`

```bash
# K3s
curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=stable sh -

# Helm (qua APT repo đã đăng ký ở §6.1)
sudo apt-get update && sudo apt-get install --only-upgrade -y helm

# rpk — KHÔNG chạy khi đang thực nghiệm
sudo apt-get update && sudo apt-get install --only-upgrade -y redpanda
```

Cập nhật không cần sudo (có thể chạy qua SSH pipe từ Windows):

> **Thực thi trên:** `continux-imac` hoặc `continux-vps`

```bash
# ArgoCD CLI — cài vào ~/.local/bin
VERSION=$(curl -Ls https://raw.githubusercontent.com/argoproj/argo-cd/stable/VERSION | tr -d '\n')
curl -sSL -o /tmp/argocd-linux-amd64 \
    "https://github.com/argoproj/argo-cd/releases/download/v${VERSION}/argocd-linux-amd64"
mkdir -p ~/.local/bin
install -m 755 /tmp/argocd-linux-amd64 ~/.local/bin/argocd && rm -f /tmp/argocd-linux-amd64
argocd version --client

# mc (MinIO client) — KHÔNG chạy khi đang thực nghiệm
wget -q "https://dl.min.io/client/mc/release/linux-amd64/mc" -O ~/.local/bin/mc
chmod +x ~/.local/bin/mc
mc --version
```

---

### 6.2. Tạo K8s Secrets cho credentials (bắt buộc trước §8)

MinIO và RisingWave đọc credentials từ K8s Secret thay vì hardcode vào Helm values — tạo trước khi ArgoCD sync.

> **Thực thi trên:** `continux-imac`

```bash
# Namespace cần tạo trước
kubectl create namespace minio      --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace risingwave --dry-run=client -o yaml | kubectl apply -f -

# Secret cho MinIO (chart đọc key: rootUser, rootPassword)
kubectl -n minio create secret generic minio-credentials \
    --from-literal=rootUser=adminuser \
    --from-literal=rootPassword=<minio-root-password>

# Secret cho RisingWave state store S3/MinIO (chart đọc key: AccessKeyID, SecretAccessKey)
kubectl -n risingwave create secret generic risingwave-s3-credentials \
    --from-literal=AccessKeyID=<rw-access-key> \
    --from-literal=SecretAccessKey=<rw-secret-key>
```

> ⚠️ Thay `<minio-root-password>`, `<rw-access-key>`, `<rw-secret-key>` bằng giá trị thực trước khi chạy. Hai key MinIO này phải khớp với access key tạo ở §8.1.

---

## 7. Cài Argo CD trên continux-vps

### 7.1. Deploy ArgoCD

Helm values: [`config/argocd/helm-values.yaml`](../config/argocd/helm-values.yaml)

> **Thực thi trên:** `continux-imac` — kubectl/helm quản lý cluster từ đây

```bash
kubectl create namespace argocd
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm install argocd argo/argo-cd \
    --namespace argocd \
    --version '^7.0.0' \
    -f config/argocd/helm-values.yaml
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
```

### 7.2. Expose UI qua Cloudflare Tunnel

ArgoCD UI và Grafana được expose qua Cloudflare Tunnel — không cần port-forward hay NodePort. **Yêu cầu:** domain đã quản lý bởi Cloudflare.

**a. Tạo tunnel trên Cloudflare dashboard:**

1. Vào [Cloudflare Zero Trust](https://one.dash.cloudflare.com) → **Networks → Tunnels → Create a tunnel**
2. Chọn **Cloudflared** → đặt tên `continux` → **Save tunnel**
3. Sao chép **tunnel token** hiển thị trên màn hình
4. Tab **Public Hostnames** → thêm 2 hostname:
   - `argocd.<domain>` → Service `HTTP` · `argocd-server.argocd:80`
   - `grafana.<domain>` → Service `HTTP` · `grafana.observability:80`

**b. Lưu token vào K8s Secret:**

> **Thực thi trên:** `continux-imac`

```bash
kubectl -n argocd create secret generic cloudflare-tunnel-token \
    --from-literal=token=<TOKEN_FROM_DASHBOARD>
```

**c. Deploy cloudflared trong cluster** ([`config/argocd/cloudflared.yaml`](../config/argocd/cloudflared.yaml)):

> **Thực thi trên:** `continux-imac`

```bash
kubectl apply -f config/argocd/cloudflared.yaml
kubectl -n argocd rollout status deploy/cloudflared
```

**d. Lấy password admin lần đầu:**

> **Thực thi trên:** `continux-imac`

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d && echo
```

Mở `https://argocd.<domain>` → đăng nhập `admin` / password trên, **đổi password ngay** (NFR-17).

### 7.3. Kết nối repo GitOps

> **Thực thi trên:** `continux-imac`

```bash
argocd login argocd.<domain> --username admin --password <new>

argocd repo add https://github.com/<org>/continux-gitops.git \
    --username <gh-user> \
    --password <gh-PAT>     # Personal Access Token, scope: repo

# Áp App-of-Apps
kubectl apply -f gitops/apps/root-app.yaml
argocd app sync root-app
argocd app list
```

---

## 8. Deploy hạ tầng trên `continux-imac`

Tất cả Helm values dưới đây đều có sẵn trong repo GitOps; ArgoCD sẽ sync tự động. Các giá trị này **đã được tinh chỉnh cho iMac 8 GB** — tránh OOM.

### 8.1. MinIO

Helm values: [`config/minio/helm-values.yaml`](../config/minio/helm-values.yaml)

Tạo access key riêng cho từng service (least-privilege, NFR-15):

> **Thực thi trên:** `continux-imac`

```bash
kubectl -n minio port-forward svc/minio-console 9001:9001
# UI: http://localhost:9001 → Identity → Service Accounts
# Tạo 3 keys: key-vector (write tlc-zone), key-risingwave (rw iceberg-data + rw-checkpoint)
```

### 8.2. Redpanda

Helm values: [`config/redpanda/helm-values.yaml`](../config/redpanda/helm-values.yaml)

Apply xong:

> **Thực thi trên:** `continux-imac`

```bash
argocd app sync redpanda

# Tạo topic
kubectl -n redpanda exec -it redpanda-0 -- \
    rpk topic create nyc-taxi-events -p 3 -r 1
```

### 8.3. RisingWave

RisingWave v2.4+ gồm 4 thành phần: **meta**, **compute**, **frontend**, **compactor**. Với 8 GB RAM cần giới hạn chặt.

Helm values: [`config/risingwave/helm-values.yaml`](../config/risingwave/helm-values.yaml)

Sync:

> **Thực thi trên:** `continux-imac`

```bash
argocd app sync risingwave
kubectl -n risingwave rollout status statefulset/risingwave-compute --timeout=300s

# Kết nối qua psql
kubectl -n risingwave port-forward svc/risingwave-frontend 4566:4566
psql -h localhost -p 4566 -d dev -U root
# dev=> SHOW CLUSTER;
```

### 8.4. Vector (load generator)

Manifest: [`config/vector/deployment.yaml`](../config/vector/deployment.yaml) · PVC: [`config/vector/pvc.yaml`](../config/vector/pvc.yaml)

Cấu hình Vector: [`pipelines/vector/vector.toml`](../pipelines/vector/vector.toml) — xem §10.2.

`vector/deployment.yaml` mount ConfigMap `vector-config` — phải tạo trước khi apply Deployment:

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

> **Lưu ý:** Grafana datasource URL hardcode service name `vmsingle-victoria-metrics` — service name này được tạo từ Helm release name `victoria-metrics`. Phải dùng đúng release name khi `helm install`:
>
> ```bash
> helm install victoria-metrics vm/victoria-metrics-k8s-stack \
>     --namespace observability --create-namespace \
>     -f config/victoria-metrics/helm-values.yaml
> ```

### 9.2. Grafana

Helm values: [`config/grafana/helm-values.yaml`](../config/grafana/helm-values.yaml)

Import 4 dashboard JSON từ `dashboards/*.json`:
- `01-streaming-perf.json`
- `02-resource-util.json`
- `03-cutover.json`
- `04-data-integrity.json`

### 9.3. Truy cập Grafana

Grafana đã được expose qua Cloudflare Tunnel cấu hình ở §7.2 — truy cập `https://grafana.<domain>`.

Đăng nhập mặc định: `admin` / `admin` (đổi password ngay lần đầu).

---

## 10. Dataset & Vector

### 10.1. Tải NYC TLC + upload Taxi Zone

> **Thực thi trên:** `continux-imac`

```bash
mkdir -p ~/continux-data/raw ~/continux-data/zone
cd ~/continux-data/raw
wget https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2024-01.parquet

cd ~/continux-data/zone
wget https://d37ci6vzurychx.cloudfront.net/misc/taxi_zone_lookup.csv

# Upload Zone lookup vào MinIO bucket
mc alias set local http://<tailscale-ip-compute>:9000 adminuser <root-password>
mc cp taxi_zone_lookup.csv local/tlc-zone/taxi_zone_lookup.csv
mc ls local/tlc-zone
```

Mount thư mục raw vào pod Vector bằng PVC `hostPath: /home/helios/continux-data/raw` (xem `config/vector/pvc.yaml`).

### 10.2. Vector pipeline config

Cấu hình nguồn → transform → sink: [`pipelines/vector/vector.toml`](../pipelines/vector/vector.toml)

Điều chỉnh tải bằng biến môi trường `VECTOR_THROUGHPUT_EVENTS_PER_SEC` — preset có sẵn trong [`pipelines/vector/rates/`](../pipelines/vector/rates/) (`low.env` / `medium.env` / `high.env`).

---

## 11. Apply SQL Blue và Iceberg Sink

> ⚠️ **Trước khi apply SQL:** `sql/02-tables/tlc-taxi-zone.sql` và `sql/04-sinks/iceberg-zone-stats.sql` chứa placeholder `<replace: key-risingwave secret từ MinIO console §8.1>`. Phải thay bằng secret key thực của service account `key-risingwave` (lấy từ MinIO console ở §8.1) rồi mới chạy các file này.

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

Verify:

> **Thực thi trên:** `continux-imac`

```bash
psql -h localhost -p 4566 -d dev -U root -c \
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

```bash
# Stress test ở các mức tải
bash experiments/runners/run_stress.sh --rate=medium --duration=15m

# Swap lặp 5 lần
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

> **Thực thi trên:** `continux-imac`

```bash
grafana-cli --configOverrides 'paths.data=./grafana-export' \
    admin export-dashboard --dir ./dashboards/
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

> **Thực thi trên:** `cả hai máy` — gỡ Tailscale nếu muốn

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
| `kubectl get nodes` chỉ thấy `continux-imac` | Server #2 chưa join được qua Tailscale | `tailscale status` trên droplet → ping `continux-imac`; kiểm tra `K3S_URL` đúng dạng `https://100.x.x.x:6443` và lệnh cài là `server` |
| Cài server #2 báo lỗi datastore | Server #1 đang chạy SQLite (không có `--cluster-init`) | Re-bootstrap `continux-imac` theo §5.1 để bật embedded etcd rồi join lại §5.2 |
| Pod bị `Pending` — `FailedScheduling` vì taint | Workload nặng bị đẩy sang continux-vps (taint) | Đặt `nodeSelector: workload=heavy` cho workload đó |
| RisingWave compute `OOMKilled` | Vượt `limits.memory=2.5Gi` của iMac 8GB | Giảm parallelism MV; tăng `compute.limits.memory` nếu còn chỗ; giảm load Vector |
| MinIO `ReadOnly` mode | Disk iMac gần đầy (200 GB) | `df -h`; xoá snapshot Iceberg cũ bằng `expire_snapshots` |
| Droplet CPU `100%` liên tục | ArgoCD app-controller ôm quá nhiều app | Giảm số App-of-Apps; hoặc resize droplet lên $24/mo (nếu chưa) |
| Tailscale ngắt kết nối sau vài giờ | NAT của modem kill session UDP | Trên iMac: `sudo tailscale up --reset --accept-routes --ssh` với systemd unit autorestart |
| `psql: SSL off error` | RisingWave v2.4 bật SSL mặc định | `PGSSLMODE=disable psql ...` hoặc `\set SSLMODE disable` |
| Redpanda `out of memory` khi stress | Container cap 1.5 GiB không đủ cho burst | Giảm `VECTOR_THROUGHPUT_EVENTS_PER_SEC`, hoặc thêm `reserveMemory: 256Mi` |
| Iceberg sink ghi nhưng query không thấy dữ liệu | Commit snapshot chưa chạy | Đợi `compactor` (mặc định mỗi 60s) hoặc force `CALL rw_iceberg_commit()` |
| Dashboard Grafana báo `No data` | `vmagent` không scrape được qua namespace khác | Kiểm tra `scrape-configs.yaml` có `role: endpoints` + namespace whitelist |
| Commit Git đã push nhưng ArgoCD không sync | Repo secret hết hạn (GH PAT) | `argocd repo add` lại với PAT mới (classic, scope `repo`) |

---

## 17. Checklist hoàn tất

- [ ] `kubectl get nodes` → 2 node `Ready`, cả hai node có `ROLES` chứa `control-plane,etcd`, node IP thuộc range `100.64.0.0/10` (Tailscale).
- [ ] `tailscale status` hiển thị cả hai máy, ping qua lại < 100 ms.
- [ ] ArgoCD UI truy cập được qua Tailscale IP hoặc NodePort; `root-app` `Synced + Healthy`.
- [ ] MinIO có 3 bucket (`iceberg-data`, `rw-checkpoint`, `tlc-zone`), 3 access key riêng biệt.
- [ ] `rpk topic list` trả về `nyc-taxi-events` với 3 partitions.
- [ ] `psql` kết nối RisingWave OK; `SHOW SOURCES` và `SHOW MATERIALIZED VIEWS` có dữ liệu.
- [ ] Vector log hiển thị số event/s khớp với `VECTOR_THROUGHPUT_EVENTS_PER_SEC`.
- [ ] Grafana 4 dashboard hiện số (không `No data`).
- [ ] `SELECT COUNT(*) FROM mv_zone_stats` > 0 và tăng theo thời gian.
- [ ] `mc ls local/iceberg-data/nyc/zone_stats/` có file Parquet + metadata `.json`.
- [ ] (Sau G4) Commit SQL Green → Swap tự động, downtime đo được ≤ 1s.

Khi toàn bộ checklist xanh → sẵn sàng Giai đoạn 5 (Thực nghiệm, xem [TIMELINE.md](./TIMELINE.md)).
