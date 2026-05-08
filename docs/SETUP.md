# SETUP — HƯỚNG DẪN THIẾT LẬP TOÀN DIỆN

> **Mục đích:** giúp một thành viên mới (hoặc GVHD) dựng lại toàn bộ hệ thống từ con số không, đúng theo kiến trúc trong [PROPOSE.md](./PROPOSE.md), [STRUCTURE.md](./STRUCTURE.md) và đáp ứng [REQUIREMENT.md](./REQUIREMENT.md).

---

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
┌────────────────────── continux-imac (iMac, K3s server #1, 8GB) ─────────────────────┐
│                                                                                     │
│   Vector ─▶ Redpanda ─▶ RisingWave (Compute + Meta + Frontend) ─▶ MinIO           │
│                              │                                    (iceberg-data)    │
│                              └─ state ──▶ MinIO (rw-checkpoint)                    │
└───────────────────────────────────────────────────────────────────────────────────┘
                                  │  (Tailscale overlay)
                                  ▼
┌─────────────────── continux-vps (DigitalOcean Droplet, K3s server #2, 2GB→4GB) ─────────────────────┐
│                                                                                   │
│   ArgoCD  ──  VictoriaMetrics  ──  Grafana                                        │
│     (public UI, điều phối GitOps, dashboard truy cập từ internet)                 │
└───────────────────────────────────────────────────────────────────────────────────┘
```

### 0.3. Máy phụ trợ (tuỳ chọn)

| Máy | Vai trò | Khi nào dùng |
|-----|---------|-------------|
| Desktop i7 (32 GB DDR5) — Win | **Dự phòng cụm** | Join thêm làm K3s worker thứ 3 khi cần burst; chạy WSL2 Ubuntu 24.04 |

Mọi lệnh quản trị (`kubectl`, `helm`, `argocd`, `rpk`, `mc`, `psql`) chạy trực tiếp trên `continux-imac`.

### 0.4. Ký hiệu máy dùng trong tài liệu này

| Ký hiệu | Nghĩa |
|---------|-------|
| **`[continux-imac]`** | iMac Ubuntu — data plane, lệnh quản trị cluster |
| **`[continux-vps]`** | DigitalOcean Droplet — observability, ArgoCD |
| **`[cả hai máy]`** | Chạy trên cả `continux-imac` lẫn `continux-vps` |
| **`[local]`** | Máy phát triển cục bộ (Windows/Mac) — git push, SSH vào VPS |

### 0.5. Liên kết mạng (Tailscale)

- **Tailscale Mesh VPN** (miễn phí tier cá nhân đến 100 thiết bị). K3s từ **v1.27+** hỗ trợ tham số `--vpn-auth` dùng Tailscale làm node IP.
- Ưu điểm: mã hoá end-to-end, stable IP trong range `100.x.x.x`, không cần cấu hình firewall phức tạp.

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

```bash
TAILSCALE_IP_COMPUTE=$(tailscale ip -4)

curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=stable sh -s - server \
    --cluster-init \
    --write-kubeconfig-mode=644 \
    --disable=traefik \
    --disable=servicelb \
    --disable=local-storage \
    --disable=metrics-server \
    --node-name=continux-imac \
    --node-ip=${TAILSCALE_IP_COMPUTE} \
    --advertise-address=${TAILSCALE_IP_COMPUTE} \
    --flannel-iface=tailscale0 \
    --tls-san=${TAILSCALE_IP_COMPUTE} \
    --etcd-expose-metrics=true
```

#### Giải thích chi tiết các tham số cấu hình K3s (Flags Explanation)

| Tham số | Ý nghĩa kỹ thuật | Vai trò trong đồ án |
|:---|:---|:---|
| `--cluster-init` | Kích hoạt chế độ Cluster Initialization sử dụng **embedded etcd**. | Cho phép cụm chạy ở chế độ High Availability (HA). Giúp em có thể thêm các node `server` khác (như VPS) vào chung một control-plane. |
| `--write-kubeconfig-mode=644` | Thiết lập quyền hạn cho file cấu hình `/etc/rancher/k3s/k3s.yaml`. | Quyền **644** cho phép người dùng không phải root (non-root users) có thể đọc file config, giúp em chạy lệnh `kubectl` dễ dàng hơn. |
| `--disable=traefik` | Vô hiệu hóa Ingress Controller mặc định (Traefik). | Tối ưu tài nguyên (RAM) cho VPS/iMac. Thay thế bằng **Cloudflare Tunnel** để mở kết nối ra Internet an toàn hơn. |
| `--disable=servicelb` | Tắt bộ cân bằng tải nội bộ (Klipper LB) của K3s. | Tránh xung đột port và tiết kiệm tài nguyên, vì đồ án tập trung dùng **Port-forward** và **Cloudflare Tunnel**. |
| `--disable=local-storage` | Tắt trình quản lý lưu trữ local mặc định của K3s. | Phù hợp với kiến trúc **Data Lakehouse** khi em sử dụng **MinIO** làm Object Storage thay vì lưu trữ file system truyền thống. |
| `--disable=metrics-server` | Tắt dịch vụ thu thập chỉ số mặc định của K3s. | Tránh lãng phí RAM. Em sẽ thay thế bằng bộ **VictoriaMetrics + Grafana** mạnh mẽ và chi tiết hơn. |
| `--node-name` | Định danh tên duy nhất cho Node trong cụm. | Giúp em phân biệt rõ ràng giữa `continux-imac` (xử lý dữ liệu) và `continux-vps` (điều phối/giám sát). |
| `--node-ip` | Chỉ định địa chỉ IP chính xác cho Node sử dụng. | Ép K3s sử dụng **IP Tailscale**, đảm bảo tính ổn định của mạng mesh ngay cả khi địa chỉ LAN (`192.168.x.x`) thay đổi. |
| `--advertise-address` | Địa chỉ IP mà Node dùng để quảng bá tới các Node khác. | Đảm bảo các node khác (như VPS) biết chính xác IP Tailscale nào để kết nối vào API Server của iMac. |
| `--flannel-iface=tailscale0` | Chỉ định Interface mạng cho Flannel (CNI). | Buộc lưu lượng **Pod-to-Pod** (traffic giữa các container) phải đi qua đường ống mã hóa của **Tailscale**, giúp kết nối iMac và VPS an toàn. |
| `--tls-san` | Thêm IP/Hostname vào Subject Alternative Name của chứng chỉ SSL. | Cho phép em gọi API Server từ xa thông qua IP Tailscale mà không bị lỗi bảo mật chứng chỉ (`certificate signed by unknown authority`). |
| `--etcd-expose-metrics=true` | Mở cổng để truy xuất các chỉ số vận hành của database etcd. | Phục vụ cho việc **Monitoring**. Em có thể dùng VictoriaMetrics để theo dõi sức khỏe database, tránh tình trạng "treo" cụm. |

Lấy join token & kubeconfig:

> **Thực thi trên:** `continux-imac`

```bash
sudo cat /var/lib/rancher/k3s/server/node-token # → copy lại
```

### 5.2. Cài K3s server #2 trên Droplet

> **Thực thi trên:** `continux-vps`

```bash
TAILSCALE_IP_EDGE=$(tailscale ip -4)
K3S_URL="https://<tailscale-ip-compute>:6443"
K3S_TOKEN="<token-lấy-từ-iMac>"

curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=stable sh -s - server \
    --server="${K3S_URL}" \
    --token="${K3S_TOKEN}" \
    --write-kubeconfig-mode=644 \
    --disable=traefik \
    --disable=servicelb \
    --disable=local-storage \
    --disable=metrics-server \
    --node-name=continux-vps \
    --node-ip="${TAILSCALE_IP_EDGE}" \
    --advertise-address="${TAILSCALE_IP_EDGE}" \
    --flannel-iface=tailscale0
```

### 5.3. Gán label phân biệt vai trò

> **Thực thi trên:** `continux-imac`

```bash
kubectl label node continux-imac workload=heavy role=data-plane
kubectl label node continux-vps  workload=light  role=control-plane
kubectl taint node continux-vps dedicated=edge:NoSchedule # chỉ pod có toleration mới chạy trên edge
```

Sau này Helm values sẽ dùng:
- Workload nặng (MinIO, Redpanda, RisingWave, Vector): `nodeSelector: { workload: heavy }`
- Workload nhẹ (ArgoCD, VM, Grafana): `nodeSelector: { workload: light }` + `tolerations` cho `dedicated=edge`.

### 5.4. Verify

> **Thực thi trên:** `continux-imac`

```bash
kubectl get nodes -o wide
# NAME            STATUS   ROLES                AGE     VERSION        INTERNAL-IP       EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION      CONTAINER-RUNTIME
# continux-imac   Ready    control-plane,etcd   7m53s   v1.34.6+k3s1   100.102.51.39     <none>        Ubuntu 24.04.4 LTS   6.8.0-110-generic   containerd://2.2.2-bd1.34
# continux-vps    Ready    control-plane,etcd   30s     v1.34.6+k3s1   100.121.142.117   <none>        Ubuntu 24.04.4 LTS   6.8.0-110-generic   containerd://2.2.2-bd1.34

kubectl get pods -A
# NAMESPACE     NAME                       READY   STATUS    RESTARTS   AGE
# kube-system   coredns-76c974cb66-69wvj   1/1     Running   0          8m23s
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

```bash
kubectl version --short
# Client Version: v1.34.6+k3s1
# Kustomize Version: v5.7.1
# Server Version: v1.34.6+k3s1

kubectl get nodes
# NAME            STATUS   ROLES                AGE     VERSION
# continux-imac   Ready    control-plane,etcd   9m27s   v1.34.6+k3s1
# continux-vps    Ready    control-plane,etcd   2m4s    v1.34.6+k3s1

helm version
# version.BuildInfo{Version:"v4.1.1", GitCommit:"5caf0044d4ef3d62a955440272999e139aafbbed", GitTreeState:"clean", GoVersion:"go1.25.7", KubeClientVersion:"v1.35"}

argocd version --client
# argocd: v3.3.7+035e855
#   BuildDate: 2026-04-16T15:58:07Z
#   GitCommit: 035e8556c451196e203078160a5c01f43afdb92f
#   GitTreeState: clean
#   GoVersion: go1.25.5
#   Compiler: gc
#   Platform: linux/amd64

rpk version
# rpk version: v26.1.5
# Git ref:     3a6d76e28d0d7776e15957c132a0873d73f3c34b
# Build date:  2026 Apr 15 13 07 54 Wed
# OS/Arch:     linux/amd64
# Go version:  go1.26.2

mc --version
# mc version RELEASE.2025-08-13T08-35-41Z (commit-id=7394ce0dd2a80935aded936b09fa12cbb3cb8096)
# Runtime: go1.24.6 linux/amd64
# Copyright (c) 2015-2025 MinIO, Inc.
# License GNU AGPLv3 <https://www.gnu.org/licenses/agpl-3.0.html>

psql --version
# psql (PostgreSQL) 16.13 (Ubuntu 16.13-0ubuntu0.24.04.1)
```

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

Chi tiết Job xem [WBS.md §4](./WBS.md#4-bluegreen-mv-swap--gitops-automation--m5).

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
