# SETUP

> Phiên bản dự án: `v0.2.1`.

## 0. Topology

Mục này chốt tên node, IP Tailscale và vai trò trước khi chạy bất kỳ lệnh nào. Các tên trong bảng phải được dùng nhất quán trong `kubectl`, script cài K3s và lệnh kiểm tra mạng; nếu đổi tên thiết bị trên Tailscale thì cập nhật ở đây trước.

| Node | Máy | OS | Vai trò |
|------|-----|----|---------|
| `imac` | user `helios`, iMac19,2, Intel i5-8500, 6 cores, 8 GB RAM, 200 GB SSD | Ubuntu 26.04 | K3s server #1, `--cluster-init`, data plane |
| `continux-vps` | user `helios`, VPS 2 vCPU, 4 GB RAM, 80 GB SSD, 4 TB transfer | Ubuntu 24.04 | K3s server #2, control/observability plane |
| `helios-pc` | Windows host `Helios-PC`, WSL Ubuntu 26.04, Intel i5-12500H, 16 GB RAM | WSL2 Ubuntu 26.04 | K3s server #3, quorum-only |

Tailscale inventory chuẩn:

| Tailscale IP | Tailscale device | Tailnet user | OS | Dùng trong setup |
|--------------|------------------|--------------|----|------------------|
| `100.120.64.5` | `imac` | `ngotiensy2005@` | Linux | K3s server #1 |
| `100.113.151.56` | `continux-vps` | `ngotiensy2005@` | Linux | K3s server #2 |
| `100.78.46.87` | `helios-pc-wsl` | `ngotiensy2005@` | Linux | K3s server #3; shell hostname `Helios-PC`, Kubernetes node `helios-pc` |
| `100.125.106.89` | `helios-pc` | `ngotiensy2005@` | Windows | Windows host, không join K3s |

WSL trên `Helios-PC` dùng Tailscale device `helios-pc-wsl` để tránh trùng tên với Windows host. Shell prompt vẫn dạng `helios@Helios-PC`; trong các lệnh `kubectl` dùng node `helios-pc`, còn trong các lệnh ping/nc qua Tailscale dùng `helios-pc-wsl` hoặc `100.78.46.87`.

Placement chuẩn:

```bash
# Chạy sau khi 3 node đã join; script init/join cũng gán sẵn các label này.
kubectl label node imac workload=heavy role=data-plane --overwrite
kubectl label node continux-vps workload=light role=control-plane --overwrite
kubectl taint node continux-vps dedicated=edge:NoSchedule --overwrite

# Node WSL chỉ giữ quorum, không nhận workload ứng dụng mặc định.
kubectl label node helios-pc workload=quorum role=quorum --overwrite
kubectl taint node helios-pc dedicated=quorum:NoSchedule --overwrite
```

## 1. Phiên bản

Mục này pin phiên bản mục tiêu cho báo cáo và kiểm thử. Một số Helm chart được resolve tại thời điểm cài nhưng vẫn truyền `--version` vào lệnh install để lần chạy đó có dấu vết tái lập.

Pin ứng dụng dùng cho lần triển khai này:

| Thành phần | Phiên bản |
|------------|-----------|
| K3s | stable channel, `v1.35.5+k3s1` |
| Helm | `v4.1.4` |
| Argo CD | app `v3.4.2`, chart `argo-cd` `9.5.14` |
| Tailscale | `v1.98.2` |
| Redpanda | `v26.1.8` |
| RisingWave | `v2.8.3` |
| Vector | `0.55.0-alpine` |
| VictoriaMetrics | `v1.143.0` |
| Grafana | release `v13.0.1+security-01`, image `13.0.1-security-01` |
| cloudflared | `2026.5.0` |

Các Helm chart trong lệnh setup đều được resolve bằng `helm search repo ... -o json` rồi truyền lại bằng `--version`, để lệnh cài đặt dùng đúng chart mới nhất tại thời điểm chạy và vẫn pin được version trong release.

Kiểm tra CLI sau khi cài:

```bash
# Chạy sau §5 để xác nhận CLI local khớp bảng version.
bash scripts/tool-version.sh
# Output đã xác nhận 2026-05-21:
# tailscale 1.98.2 ✓ cập nhật
# k3s v1.35.5+k3s1 ✓ cập nhật
# kubectl v1.35.5+k3s1 ✓ cập nhật
# helm v4.1.4 ↑ có bản stable mới hơn v4.2.0
# argocd CLI v3.4.2 ✓ cập nhật
# rpk v26.1.8 ✓ cập nhật
# mc RELEASE.2025-08-13T08-35-41Z ✓ cập nhật
# psql 18.3 (APT)
```

## 2. Chuẩn bị OS

Mục này chuẩn hóa từng máy trước khi đưa vào cluster: hostname, gói nền, swap, IP forwarding và firewall. Hoàn tất mục này thì mỗi Linux node đã sẵn sàng để cài Tailscale và K3s.

### 2.1. `imac`

`imac` là server đầu tiên và data plane chính, nên cần thêm `postgresql-client` và `python3-venv` để query RisingWave và convert dataset ngay trên máy này.

```bash
# Node name phải khớp topology Kubernetes.
sudo hostnamectl set-hostname imac

# Gói nền để cài K3s, kiểm tra mạng, chạy psql và convert dataset.
sudo apt update
sudo apt -y upgrade
sudo apt install -y curl wget git ca-certificates jq netcat-openbsd unzip postgresql-client python3-venv

# Kubernetes cần tắt swap và bật IPv4 forwarding cho pod networking.
sudo swapoff -a
sudo sed -i '/\sswap\s/s/^/#/' /etc/fstab
echo 'net.ipv4.ip_forward = 1' | sudo tee /etc/sysctl.d/99-k3s.conf
sudo sysctl --system
# Output mong đợi: net.ipv4.ip_forward = 1
```

### 2.2. `continux-vps`

`continux-vps` chạy control/observability plane. Bước root chỉ dùng để tạo user vận hành; các bước còn lại chạy bằng user `helios`.

Tạo VPS Ubuntu 24.04 với plan 2 vCPU, 4 GB RAM, 80 GB SSD, 4 TB transfer. Lần đầu SSH bằng `root`, tạo user `helios`:

```bash
# Tạo user vận hành, tránh dùng root cho các bước sau.
adduser helios
usermod -aG sudo helios
rsync --archive --chown=helios:helios ~/.ssh /home/helios

# Hostname phải khớp node name khi join cluster.
hostnamectl set-hostname continux-vps
exit
```

SSH lại bằng user `helios`:

```bash
# Gói nền tối thiểu cho K3s server #2.
sudo apt update
sudo apt -y upgrade
sudo apt install -y curl wget git ca-certificates jq netcat-openbsd unzip

# Kubernetes cần tắt swap và bật IPv4 forwarding cho pod networking.
sudo swapoff -a
sudo sed -i '/\sswap\s/s/^/#/' /etc/fstab
echo 'net.ipv4.ip_forward = 1' | sudo tee /etc/sysctl.d/99-k3s.conf
sudo sysctl --system
# Output đã xác nhận trên continux-vps:
# net.ipv4.ip_forward = 1
```

### 2.3. `helios-pc`

Máy này là WSL Ubuntu trên Windows host `Helios-PC`. Tailscale device của WSL là `helios-pc-wsl`, nhưng node Kubernetes vẫn phải join bằng tên `helios-pc`.

Trên Windows PowerShell Admin:

```powershell
# Cài distro WSL dùng cho K3s server #3.
wsl --install -d Ubuntu-26.04
wsl --set-default-version 2
wsl -d Ubuntu-26.04
```

Trong WSL:

```bash
# WSL cần systemd để chạy tailscaled/k3s ổn định.
sudo tee /etc/wsl.conf >/dev/null <<'EOF'
[boot]
systemd=true
EOF
exit
```

Restart WSL, rồi chuẩn bị OS:

```powershell
# Restart để systemd trong /etc/wsl.conf có hiệu lực.
wsl --shutdown
wsl -d Ubuntu-26.04
```

Giữ hostname WSL là `Helios-PC`; khi join K3s ở bước sau, truyền node name `helios-pc` cho script.

```bash
# Giữ hostname WSL là Helios-PC; script join sẽ đặt Kubernetes node là helios-pc.
hostname
# Helios-PC
sudo apt update
sudo apt -y upgrade
sudo apt install -y curl wget git ca-certificates jq netcat-openbsd

# Kubernetes cần tắt swap và bật IPv4 forwarding cho pod networking.
sudo swapoff -a
sudo sed -i '/\sswap\s/s/^/#/' /etc/fstab
echo 'net.ipv4.ip_forward = 1' | sudo tee /etc/sysctl.d/99-k3s.conf
sudo sysctl --system
# Output đã xác nhận trên Helios-PC/WSL:
# net.ipv4.ip_forward = 1

# WSL root mount mặc định có thể là private; chạy script fix ở §4.2 sau khi K3s đã cài.
```

### 2.4. UFW firewall

Nếu UFW tắt và node chỉ nằm trong lab riêng, có thể để mục này như checklist tham khảo. Nếu bật UFW, áp dụng trước khi cài K3s để apiserver, etcd, kubelet và overlay network không bị chặn.

Chạy trên cả 3 máy nếu UFW đang bật hoặc muốn bật UFW trước khi cài K3s:

```bash
sudo apt install -y ufw

# Giữ SSH trước khi enable UFW, đặc biệt trên VPS.
sudo ufw allow OpenSSH comment 'ssh'
sudo ufw enable

# Chỉ mở control-plane qua Tailscale, tránh expose public 6443/etcd trên VPS.
TAILSCALE_CIDR=100.64.0.0/10
sudo ufw allow from "${TAILSCALE_CIDR}" to any port 6443 proto tcp comment 'k3s apiserver via tailscale'
sudo ufw allow from "${TAILSCALE_CIDR}" to any port 2379:2380 proto tcp comment 'k3s embedded etcd'
sudo ufw allow from "${TAILSCALE_CIDR}" to any port 10250 proto tcp comment 'kubelet api via tailscale'
sudo ufw allow from "${TAILSCALE_CIDR}" to any port 8472 proto udp comment 'flannel vxlan via tailscale'

# Cho phép traffic nội bộ sau khi packet đã vào pod/service CIDR.
sudo ufw allow from 10.42.0.0/16 to any comment 'k3s pods'
sudo ufw allow from 10.43.0.0/16 to any comment 'k3s services'

sudo ufw reload
sudo ufw status verbose
# Output đã xác nhận trên continux-vps và helios-pc:
# Status: active
# 22/tcp (OpenSSH) ALLOW IN Anywhere # ssh
# 6443/tcp ALLOW IN 100.64.0.0/10 # k3s apiserver via tailscale
# 2379:2380/tcp ALLOW IN 100.64.0.0/10 # k3s embedded etcd
# 10250/tcp ALLOW IN 100.64.0.0/10 # kubelet api via tailscale
# 8472/udp ALLOW IN 100.64.0.0/10 # flannel vxlan via tailscale
# Anywhere ALLOW IN 10.42.0.0/16 # k3s pods
# Anywhere ALLOW IN 10.43.0.0/16 # k3s services

# Chỉ enable sau khi đã chắc SSH/Tailscale vẫn vào được.
# sudo ufw enable
```

## 3. Tailscale

Tailscale là mạng liên node của cụm. K3s sẽ dùng Tailscale IPv4 làm `--node-ip`, `--advertise-address` và đường đi cho etcd/flannel giữa 3 server.

Chạy trên cả 3 máy:

```bash
# Cài Tailscale và bật Tailscale SSH cho quản trị qua tailnet.
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --ssh
tailscale status
tailscale ip -4
```

Verify từ từng máy:

```bash
# MagicDNS phải resolve đúng 3 máy Linux liên quan đến cluster.
ping -c 3 imac
ping -c 3 continux-vps
ping -c 3 helios-pc-wsl
```

Ghi lại `IMAC_TS_IP=$(tailscale ip -4)` trên `imac`.

## 4. K3s HA

Mục này dựng cụm K3s 3 server với embedded etcd. Sau khi hoàn tất, `kubectl get nodes` phải thấy `imac`, `continux-vps`, `helios-pc` đều `Ready`.

### 4.1. Init server #1

Chạy trên `imac` để tạo cluster đầu tiên bằng `--cluster-init`, rồi copy kubeconfig cho user thường. Token in ra ở cuối dùng cho hai server còn lại.

Trên `imac`:

```bash
cd ~/continux

# Script tự lấy Tailscale IPv4, init embedded etcd và gán label data-plane.
sudo bash scripts/k3s-install-server-init.sh

# Copy kubeconfig raw để user helios dùng kubectl/helm không cần sudo.
mkdir -p ~/.kube
sudo k3s kubectl config view --raw > ~/.kube/config
chmod 600 ~/.kube/config
export KUBECONFIG=$HOME/.kube/config
grep -qxF 'export KUBECONFIG=$HOME/.kube/config' ~/.bashrc || echo 'export KUBECONFIG=$HOME/.kube/config' >> ~/.bashrc
bash scripts/k3s-token.sh
```

### 4.2. Join server #2 và #3

Mỗi node join bằng Tailscale IP của `imac`, token từ §4.1 và node name cố định. Profile `edge` gán label/taint cho `continux-vps`; profile `quorum` gán label/taint cho `helios-pc`.

Trên `continux-vps`:

```bash
# Server #2: control/observability plane, có taint dedicated=edge.
sudo bash scripts/k3s-install-server.sh <IMAC_TS_IP> <K3S_TOKEN> continux-vps edge
# Output đã xác nhận 2026-05-21:
# Tailscale IP local: 100.113.151.56
# Node name: continux-vps
# Profile: edge
# Label: workload=light, role=control-plane
# Taint: dedicated=edge:NoSchedule
# continux-vps Ready, version v1.35.5+k3s1, INTERNAL-IP 100.113.151.56
```

Trên `helios-pc`:

```bash
# Server #3: quorum-only, Kubernetes node name là helios-pc.
sudo bash scripts/k3s-install-server.sh <IMAC_TS_IP> <K3S_TOKEN> helios-pc quorum
# Output đã xác nhận 2026-05-21:
# Tailscale IP local: 100.78.46.87
# Node name: helios-pc
# Profile: quorum
# Label: workload=quorum, role=quorum
# Taint: dedicated=quorum:NoSchedule
# helios-pc Ready, version v1.35.5+k3s1, INTERNAL-IP 100.78.46.87

# Sau khi join K3s trên WSL, bật shared root để node-exporter/hostPath mount chạy được.
sudo bash scripts/wsl-enable-shared-root.sh
# Output đã xác nhận trên Helios-PC/WSL:
# Root mount hiện tại đã là shared/rshared.
# k3s đã restart sau khi root mount được chuyển sang rshared.
# / shared
```

Trên `imac`, verify:

```bash
# Node list phải có đủ 3 server và IP nội bộ là dải 100.x.x.x.
kubectl get nodes -o wide
kubectl get nodes -l role=quorum -o wide
# Output đã xác nhận:
# continux-vps Ready control-plane,etcd v1.35.5+k3s1 100.113.151.56
# helios-pc Ready control-plane,etcd v1.35.5+k3s1 100.78.46.87
# imac Ready control-plane,etcd v1.35.5+k3s1 100.120.64.5

# readyz cần có etcd/readyz ok; nc kiểm tra peer port etcd qua Tailscale.
kubectl get --raw='/readyz?verbose' | grep -E 'readyz|etcd|ok'
nc -vz continux-vps 2380
nc -vz helios-pc-wsl 2380
# Output đã xác nhận:
# [+]etcd ok
# [+]etcd-readiness ok
# readyz check passed
```

## 5. CLI quản trị

Mục này cài các CLI cần để vận hành cluster từ `imac`: Helm, Argo CD CLI, Redpanda CLI và MinIO client. Chạy xong mục này thì các bước GitOps, topic, bucket và verify có đủ công cụ local.

Chạy trên `imac`; lặp lại phần Helm/Argo CLI trên `continux-vps` nếu muốn thao tác observability trực tiếp từ VPS.

```bash
cd ~/continux

HELM_VERSION=v4.1.4

# Pin Helm để report và setup tái lập được.
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 -o /tmp/get-helm.sh
chmod 700 /tmp/get-helm.sh
DESIRED_VERSION="${HELM_VERSION}" /tmp/get-helm.sh
rm -f /tmp/get-helm.sh

ARGOCD_VERSION=v3.4.2

# Cài Argo CD CLI đúng version đang ghi trong tài liệu.
curl -sSL -o /tmp/argocd-linux-amd64 \
  "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64"
sudo install -m 755 /tmp/argocd-linux-amd64 /usr/local/bin/argocd
rm -f /tmp/argocd-linux-amd64

# Redpanda CLI dùng để inspect topic.
curl -1sLf 'https://dl.redpanda.com/nzc4ZYQK3WRGd9sy/redpanda/cfg/setup/bash.deb.sh' | sudo -E bash
sudo apt install -y redpanda

# MinIO client dùng để upload zone lookup và verify Iceberg output.
wget -O /tmp/mc https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x /tmp/mc
sudo mv /tmp/mc /usr/local/bin/mc
# Output đã xác nhận:
# /tmp/mc saved [30535864/30535864]

bash scripts/tool-version.sh
# Output đã xác nhận:
# OS Ubuntu 26.04 LTS, kernel 7.0.0-15-generic
# tailscale 1.98.2 ✓
# k3s v1.35.5+k3s1 ✓
# kubectl v1.35.5+k3s1 ✓
# helm v4.1.4 ↑ latest stable v4.2.0
# argocd CLI v3.4.2 ✓
# rpk v26.1.8 ✓
# mc RELEASE.2025-08-13T08-35-41Z ✓
# psql 18.3
```

## 6. Argo CD và GitOps

Mục này đưa repo vào vòng GitOps: cài Argo CD, bật Cloudflare Tunnel cho UI cần expose, rồi apply App-of-Apps. Sau mục này, Argo CD sẽ quản lý các app trong `gitops/apps/`.

### 6.1. Cài Argo CD

Argo CD chạy trên cluster và đọc manifest/Helm values từ repo. Chart được pin version để tránh tự đổi hành vi giữa các lần setup.

```bash
cd ~/continux

# Namespace trước, chart sau: lệnh apply idempotent nên chạy lại an toàn.
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
# Output đã xác nhận:
# namespace/argocd created
# "argo" has been added to your repositories

# Dùng values trong repo để giữ resource/placement thống nhất với topology.
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --version 9.5.14 \
  -f config/argocd/helm-values.yaml
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
# Output đã xác nhận:
# Release "argocd" does not exist. Installing it now.
# STATUS: deployed
# REVISION: 1
# deployment "argocd-server" successfully rolled out
```

### 6.2. Cloudflare Tunnel

Tunnel chỉ dùng cho UI cần truy cập ngoài tailnet. Token là secret runtime, không commit vào Git.

Tạo tunnel `continux` trong Cloudflare Zero Trust, lấy token, rồi tạo Secret:

```bash
TOKEN=<cloudflare-tunnel-token>

# Secret không commit vào Git; tạo trực tiếp trong cluster.
kubectl -n argocd create secret generic cloudflare-tunnel-token \
  --from-literal=token="${TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -

# Manifest cloudflared đọc secret trên và route traffic vào service nội bộ.
kubectl apply -f config/argocd/cloudflared.yaml
kubectl -n argocd rollout status deploy/cloudflared --timeout=300s
# Output đã xác nhận:
# secret/cloudflare-tunnel-token created
# deployment.apps/cloudflared created
# deployment "cloudflared" successfully rolled out
```

Publish route:

- `continux-argo.<domain>` -> `http://argocd-server.argocd:80`
- `continux-grafana.<domain>` -> `http://grafana.observability:80`

Lấy mật khẩu admin ban đầu:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d && echo
# Output đã xác nhận:
# <argocd-initial-admin-password>
```

### 6.3. Đăng ký repo

Đăng ký repo để Argo CD có quyền đọc manifest, sau đó apply root app. Từ đây các app con có thể được sync bằng `argocd app sync`.

```bash
# Đăng nhập qua domain tunnel; --grpc-web cần thiết khi đi qua HTTP proxy/tunnel.
argocd login continux-argo.<domain> --username admin --password <new-password> --grpc-web
# Output đã xác nhận:
# 'admin:login' logged in successfully
# Context 'continux-argo.<domain>' updated

# PAT GitHub chỉ cần quyền đọc repo nếu repo public; repo private cần scope repo phù hợp.
argocd repo add https://github.com/helios-ryuu/continux.git \
  --username <github-user> \
  --password <github-token> \
  --grpc-web
# Output đã xác nhận:
# Repository 'https://github.com/helios-ryuu/continux.git' added

# Root app quản lý các app con trong gitops/apps/.
kubectl apply -f gitops/apps/root-app.yaml
argocd app sync root-app --grpc-web
argocd app list --grpc-web
# Output đã xác nhận:
# application.argoproj.io/root-app created
# root-app Synced, Healthy
# cloudflared, redpanda-topics, victoria-scrapes, pipeline, vector applications created
# redpanda-topics Synced Healthy
# cloudflared/vector/victoria-scrapes OutOfSync ban đầu là bình thường trước khi sync từng app con
```

## 7. Storage và streaming core

Mục này dựng phần lõi dữ liệu: MinIO làm S3-compatible storage, Redpanda làm Kafka-compatible broker, RisingWave làm streaming database. Hoàn tất mục này thì cluster đã có storage, topic và SQL frontend.

### 7.1. Secrets

Secrets chứa credential runtime cho MinIO và RisingWave. Không commit secret thật vào repo; các lệnh dưới tạo hoặc cập nhật secret trực tiếp trên cluster.

```bash
# Namespace và secret đều apply kiểu idempotent để chạy lại không lỗi.
kubectl create namespace minio --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace risingwave --dry-run=client -o yaml | kubectl apply -f -
# Output đã xác nhận:
# namespace/minio created
# namespace/risingwave created

kubectl -n minio create secret generic minio-credentials \
  --from-literal=rootUser=adminuser \
  --from-literal=rootPassword=<minio-root-password> \
  --dry-run=client -o yaml | kubectl apply -f -
# Output đã xác nhận:
# secret/minio-credentials created
```

### 7.2. MinIO

MinIO lưu checkpoint RisingWave, file Iceberg và lookup CSV. Sau khi rollout xong, mở console để tạo bucket và access key cho RisingWave.

```bash
helm repo add minio https://charts.min.io/
helm repo update
# Output đã xác nhận:
# "minio" has been added to your repositories

# Resolve chart version tại lúc setup rồi pin vào lệnh install.
MINIO_CHART_VERSION=$(helm search repo minio/minio -o json | jq -r '.[0].version')
helm upgrade --install minio minio/minio \
  --namespace minio \
  --version "${MINIO_CHART_VERSION}" \
  -f config/minio/helm-values.yaml
kubectl -n minio rollout status deploy/minio --timeout=300s
# Output đã xác nhận:
# Release "minio" does not exist. Installing it now.
# STATUS: deployed
# REVISION: 1
# deployment "minio" successfully rolled out
```

Mở console, tạo hoặc xác nhận buckets `iceberg-data`, `rw-checkpoint`, `tlc-zone`, rồi tạo access key `key-risingwave`.

```bash
# Terminal 1: giữ port-forward chạy trong lúc mở MinIO console.
# --address 0.0.0.0 cho phép mở console từ máy khác qua IP node; đổi 127.0.0.1 nếu chỉ dùng local.
kubectl -n minio port-forward --address 0.0.0.0 svc/minio-console 9001:9001
```

Tạo Secret cho RisingWave. Secret này được Helm chart dùng cho state store và được inject vào RisingWave meta/compute pods để SQL S3/Iceberg connector đọc credential qua default AWS credential provider chain.

```bash
read -r -s -p "MinIO key-risingwave secret: " RISINGWAVE_S3_SECRET
echo

# Secret này ở namespace risingwave, không commit vào Git.
kubectl -n risingwave create secret generic risingwave-s3-credentials \
  --from-literal=AWS_ACCESS_KEY_ID=key-risingwave \
  --from-literal=AWS_SECRET_ACCESS_KEY="${RISINGWAVE_S3_SECRET}" \
  --dry-run=client -o yaml | kubectl apply -f -
unset RISINGWAVE_S3_SECRET

# Output đã xác nhận:
# secret/risingwave-s3-credentials created
```

### 7.3. Redpanda

Redpanda nhận event JSON từ Vector qua topic `nyc-taxi-events`. App `redpanda-topics` tạo topic theo manifest trong `pipelines/redpanda/`.

```bash
helm repo add redpanda https://charts.redpanda.com
helm repo update
# Output đã xác nhận:
# "redpanda" has been added to your repositories

# Resolve chart version tại lúc setup rồi pin vào lệnh install.
REDPANDA_CHART_VERSION=$(helm search repo redpanda/redpanda -o json | jq -r '.[0].version')
helm upgrade --install redpanda redpanda/redpanda \
  --namespace redpanda --create-namespace \
  --version "${REDPANDA_CHART_VERSION}" \
  -f config/redpanda/helm-values.yaml
kubectl -n redpanda rollout status statefulset/redpanda --timeout=600s
# Output đã xác nhận:
# Release "redpanda" does not exist. Installing it now.
# STATUS: deployed
# statefulset rolling update complete 1 pods at revision redpanda-...

# Tạo/verify topic bằng GitOps app riêng.
argocd app sync redpanda-topics --grpc-web
argocd app wait redpanda-topics --health --sync --grpc-web
kubectl -n redpanda exec redpanda-0 -c redpanda -- \
  rpk topic describe nyc-taxi-events --brokers redpanda.redpanda.svc.cluster.local:9093
# Output đã xác nhận:
# redpanda-topic-bootstrap Succeeded
# redpanda-topics Synced, Healthy
# NAME nyc-taxi-events
# PARTITIONS 3
# REPLICAS 1
# cleanup.policy delete
# retention.ms 86400000
```

### 7.4. RisingWave

RisingWave đọc Redpanda, xử lý SQL streaming và ghi Iceberg sink xuống MinIO. Với topology này, các component chạy trên `role=data-plane`. File `config/risingwave/helm-values.yaml` trỏ tới Secret `risingwave-s3-credentials` cho state store và set `DISABLE_DEFAULT_CREDENTIAL=false` cho meta/compute pods, để SQL dùng `enable_config_load = 'true'` mà không cần ghi access key/secret key vào Git.

```bash
helm repo add risingwavelabs https://risingwavelabs.github.io/helm-charts/
helm repo update
# Output đã xác nhận:
# "risingwavelabs" has been added to your repositories

# Resolve chart version tại lúc setup rồi pin vào lệnh install.
RISINGWAVE_CHART_VERSION=$(helm search repo risingwavelabs/risingwave -o json | jq -r '.[0].version')
helm upgrade --install risingwave risingwavelabs/risingwave \
  --namespace risingwave --create-namespace \
  --version "${RISINGWAVE_CHART_VERSION}" \
  -f config/risingwave/helm-values.yaml
kubectl -n risingwave get pods,svc -o wide
kubectl -n risingwave rollout status statefulset/risingwave-compute --timeout=300s
# Output đã xác nhận:
# Release "risingwave" does not exist. Installing it now.
# STATUS: deployed
# risingwave-compactor 1/1 Running
# risingwave-compute-0 1/1 Running
# risingwave-frontend 1/1 Running
# risingwave-meta-0 1/1 Running
# statefulset/risingwave-compute rollout complete
```

Nếu meta pod crash với lỗi `Data directory is already used by another cluster`, nghĩa là prefix state store trong MinIO đã gắn với cluster ID cũ nhưng metastore SQLite local đã bị tạo lại sau restart. Với môi trường demo chưa cần giữ checkpoint cũ, đổi `stateStore.dataDirectory` trong `config/risingwave/helm-values.yaml` sang prefix mới, ví dụ `hummock002`, rồi chạy lại Helm upgrade. Không xóa prefix cũ nếu chưa chắc chắn.

Kết nối SQL:

```bash
# Terminal 1: giữ port-forward chạy trong lúc dùng psql.
kubectl -n risingwave port-forward svc/risingwave 4567:4567
```

```bash
# Terminal 2: kiểm tra frontend SQL.
psql -h localhost -p 4567 -d dev -U root -c 'SHOW CLUSTER;'
# Output đã xác nhận:
# Id | Addr                                                                 | Type                     | State   | Parallelism | Is Streaming | Is Serving | Is Unschedulable
# 0  | risingwave-meta-0.risingwave-meta-headless.risingwave.svc:5690       | WORKER_TYPE_META         | RUNNING |             |              |            |
# 1  | risingwave-compute-0.risingwave-compute-headless.risingwave.svc:5688 | WORKER_TYPE_COMPUTE_NODE | RUNNING | 2           | t            | t          | f
# 2  | 10.42.0.13:6660                                                      | WORKER_TYPE_COMPACTOR    | RUNNING | 3           | f            | f          | f
# 3  | 10.42.0.16:4567                                                      | WORKER_TYPE_FRONTEND     | RUNNING |             | f            | f          | f
# (4 rows)
```

## 8. Observability

Mục này dựng lớp quan sát: VictoriaMetrics scrape metrics và Grafana hiển thị dashboard. Sau mục này, dashboard có thể đọc datasource `VictoriaMetrics` và theo dõi tài nguyên, lag, throughput.

### 8.1. VictoriaMetrics

VictoriaMetrics stack cần CRD trước khi chart tạo custom resources. App `victoria-scrapes` bổ sung scrape config riêng cho workload trong repo.

```bash
helm repo add vm https://victoriametrics.github.io/helm-charts/
helm repo update
# Output đã xác nhận:
# "vm" has been added to your repositories

# CRD phải apply trước chart để operator nhận được custom resources.
VICTORIA_CHART_VERSION=$(helm search repo vm/victoria-metrics-k8s-stack -o json | jq -r '.[0].version')
helm show crds vm/victoria-metrics-k8s-stack | kubectl apply -f - --server-side
kubectl wait --for condition=Established crd/vmagents.operator.victoriametrics.com --timeout=120s
helm upgrade --install victoria-metrics vm/victoria-metrics-k8s-stack \
  --namespace observability --create-namespace \
  --version "${VICTORIA_CHART_VERSION}" \
  -f config/victoria-metrics/helm-values.yaml
# Output đã xác nhận:
# vmagents.operator.victoriametrics.com condition met
# Release "victoria-metrics" does not exist. Installing it now.
# STATUS: deployed
# REVISION: 1

# Sync scrape config do repo quản lý sau khi operator đã sẵn sàng.
argocd app sync victoria-scrapes --grpc-web
argocd app wait victoria-scrapes --health --sync --grpc-web
# Output đã xác nhận:
# VMServiceScrape/risingwave created
# VMServiceScrape/redpanda created
# VMServiceScrape/etcd created
# victoria-scrapes Synced, Healthy
```

### 8.2. Grafana

Grafana dùng datasource VictoriaMetrics và dashboard JSON trong `dashboards/`. Password admin ban đầu lấy từ Kubernetes Secret rồi đổi ngay sau lần đăng nhập đầu.

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
# Output đã xác nhận:
# "grafana" has been added to your repositories

# Resolve chart version tại lúc setup rồi pin vào lệnh install.
GRAFANA_CHART_VERSION=$(helm search repo grafana/grafana -o json | jq -r '.[0].version')
helm upgrade --install grafana grafana/grafana \
  --namespace observability --create-namespace \
  --version "${GRAFANA_CHART_VERSION}" \
  -f config/grafana/helm-values.yaml
kubectl -n observability rollout status deploy/grafana --timeout=300s
kubectl -n observability get secret grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d && echo
# Output đã xác nhận:
# Release "grafana" does not exist. Installing it now.
# STATUS: deployed
# REVISION: 1
# deployment "grafana" successfully rolled out
# <grafana-admin-password>
```

Mở `https://continux-grafana.<domain>`, đăng nhập `admin`, đổi password, import dashboard trong `dashboards/*.json` với datasource `VictoriaMetrics`.

## 9. Dataset và Vector

Mục này là nơi bắt đầu chạm vào dữ liệu thật: tải Parquet/CSV, convert JSONL, upload lookup CSV và chuẩn bị Vector. Cụm chưa phát event cho tới khi bạn chạy phần **Bật ingest thủ công**. Vector mặc định `replicas: 0`, nên pipeline chỉ phát event khi bạn scale thủ công sau khi preflight xanh.

Tạo dataset trên `imac`:

```bash
cd ~/continux

# Chọn tháng đã có file TLC, ví dụ 2026-03.
DATA_MONTH=<yyyy-mm>
DATA_URL="https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_${DATA_MONTH}.parquet"
ZONE_URL="https://d37ci6vzurychx.cloudfront.net/misc/taxi_zone_lookup.csv"

mkdir -p data/raw data/zone

# File parquet lớn nằm trong data/raw và không commit.
wget -c -O "data/raw/yellow_tripdata_${DATA_MONTH}.parquet" "$DATA_URL"
# Output đã xác nhận với DATA_MONTH=2026-03:
# data/raw/yellow_tripdata_2026-03.parquet saved [67891249/67891249] (~64.75 MiB)

# Lookup CSV nhỏ được upload vào bucket tlc-zone để RisingWave join.
wget -c -O data/zone/taxi_zone_lookup.csv "$ZONE_URL"
# Output đã xác nhận:
# data/zone/taxi_zone_lookup.csv saved [12331/12331] (~12 KiB)

python3 -m venv .venv
. .venv/bin/activate
pip install --upgrade pip pyarrow
# Output đã xác nhận:
# Successfully installed pip-26.1.1 pyarrow-24.0.0

# Vector đọc JSONL, nên convert Parquet trước khi sync Deployment.
python scripts/partojsonl.py \
  "data/raw/yellow_tripdata_${DATA_MONTH}.parquet" \
  "data/raw/yellow_tripdata_${DATA_MONTH}.jsonl"
# Output đã xác nhận:
# Wrote 3952451 rows to data/raw/yellow_tripdata_2026-03.jsonl
```

Upload zone lookup:

```bash
# Terminal 1: giữ MinIO API port-forward chạy.
kubectl -n minio port-forward --address 127.0.0.1 svc/minio 9000:9000
```

```bash
# Terminal 2: upload qua API local vừa forward.
mc alias set local http://127.0.0.1:9000 adminuser <minio-root-password>
mc cp data/zone/taxi_zone_lookup.csv local/tlc-zone/taxi_zone_lookup.csv
mc ls local/tlc-zone
# Output đã xác nhận:
# Added `local` successfully.
# taxi_zone_lookup.csv uploaded, 12.04 KiB
# local/tlc-zone/taxi_zone_lookup.csv exists
```

Preflight Vector:

```bash
# Kiểm tra file, topic và manifest trước khi bật ingest.
ls -lh "data/raw/yellow_tripdata_${DATA_MONTH}.jsonl"
# Output đã xác nhận:
# -rw-rw-r-- ... 450M ... data/raw/yellow_tripdata_2026-03.jsonl

# Topic phải tồn tại trước, nếu không Vector publish sẽ lỗi.
kubectl -n redpanda exec redpanda-0 -c redpanda -- \
  rpk topic describe nyc-taxi-events --brokers redpanda.redpanda.svc.cluster.local:9093
# Output đã xác nhận:
# NAME nyc-taxi-events
# PARTITIONS 3
# REPLICAS 1
# retention.ms 86400000

# Kiểm tra image/tag, path input, Kafka backpressure, buffer và memory guardrail trong manifest render.
kubectl kustomize config/vector | grep -E '0.55.0|/data/\*.jsonl|rate_limit_num|rate_limit_duration_secs|max_events|when_full|sizeLimit|memory:' -n
# Output mong đợi sau khi cập nhật v0.2.1:
# include = ["/data/*.jsonl"]
# rate_limit_num = 2
# rate_limit_duration_secs = 1
# max_events = 250
# when_full = "block"
# image: timberio/vector:0.55.0-alpine
# memory: 1Gi / 256Mi
# sizeLimit: 1Gi
```

Sync manifest ở trạng thái dừng:

```bash
# Manifest để replicas=0; sync trước, scale sau.
argocd app sync vector --grpc-web
argocd app wait vector --health --sync --grpc-web
kubectl -n pipeline get deploy/vector -o jsonpath='{.spec.replicas}{" desired\n"}'
# Output đã xác nhận:
# namespace/pipeline created
# configmap/vector-config created
# persistentvolume/vector-data-pv created
# persistentvolumeclaim/vector-data created
# deployment.apps/vector created
# vector Synced, Healthy
# 0 desired
```

Bật ingest thủ công:

```bash
# Scale lên 1 chỉ khi preflight xanh.
kubectl -n pipeline scale deploy/vector --replicas=1
kubectl -n pipeline rollout status deploy/vector --timeout=300s
kubectl -n pipeline logs deploy/vector --tail=100
# Output đã xác nhận:
# deployment.apps/vector scaled
# deployment "vector" successfully rolled out
# Vector has started. version="0.55.0"
# Found new file to watch. file=/data/yellow_tripdata_2026-03.jsonl
# Healthcheck passed.

# Nếu Grafana/Redpanda/RisingWave bắt đầu nghẽn trong lúc ingest, tắt ngay rồi giảm rate_limit_num hoặc max_events.
kubectl --request-timeout=10s -n pipeline scale deploy/vector --replicas=0
# Output đã xác nhận sau khi thêm --request-timeout:
# deployment.apps/vector scaled
```

Tắt ingest khi cần:

```bash
kubectl -n pipeline scale deploy/vector --replicas=0
```

Kiểm tra tổng hợp sau khi hoàn tất §1-9:

```bash
./scripts/k3s-check.sh
# Output đã xác nhận 2026-05-21:
# Nodes Ready 100% 3/3
# Pods Healthy 96% 27/28
# PVC Bound 100% 5/5
# Workloads Ready 100% 22/22
# Node exporter DaemonSet 3/3 ready, gồm cả helios-pc sau wsl-enable-shared-root.sh
# Vector 1/1 Running trên imac
# Grafana 1/1 Running sau khi tăng resource, restart mới = 0
# HOT LIST chỉ còn redpanda-configuration-cdk5k Failed và redpanda-console restart 1
# Nhận định: redpanda-configuration-cdk5k là pod job/configuration cũ, không chặn workload vì redpanda-configuration-vl774 đã Succeeded và Workloads Ready 100%.
```

## 10. SQL và verify

Mục này là nơi bắt đầu phần streaming/tính toán/truy vấn đầy đủ: RisingWave tạo Kafka source, materialized view, Iceberg sink, rồi bạn verify bằng SQL query và object output trên MinIO. Nếu Vector đã bật ở §9, RisingWave sẽ đọc lại topic từ đầu do `scan.startup.mode = 'earliest'`; nếu Vector chưa bật, hãy apply SQL xong rồi scale Vector lên `1`.

Không thay secret thật vào SQL. SQL chỉ bật `enable_config_load = 'true'`; RisingWave tự đọc `AWS_ACCESS_KEY_ID` và `AWS_SECRET_ACCESS_KEY` từ Kubernetes Secret `risingwave/risingwave-s3-credentials` đã được inject vào meta/compute pods ở §7.4.

Nếu cụm đã cài RisingWave trước khi `config/risingwave/helm-values.yaml` có `DISABLE_DEFAULT_CREDENTIAL=false` hoặc đổi `stateStore.dataDirectory`, chạy lại Helm upgrade để rollout cấu hình mới vào pods:

```bash
RISINGWAVE_CHART_VERSION=$(helm search repo risingwavelabs/risingwave -o json | jq -r '.[0].version')
helm upgrade --install risingwave risingwavelabs/risingwave \
  --namespace risingwave --create-namespace \
  --version "${RISINGWAVE_CHART_VERSION}" \
  -f config/risingwave/helm-values.yaml
kubectl -n risingwave rollout status statefulset/risingwave-meta --timeout=300s
kubectl -n risingwave rollout status statefulset/risingwave-compute --timeout=300s
```

Commit và sync:

```bash
# Commit SQL, Job apply và RisingWave Helm values để Git ghi lại flow secret runtime.
git add sql/ gitops/pipeline/ config/risingwave/
git commit -m "feat(sql): apply streaming lakehouse pipeline"
git push

# Sync app pipeline để chạy Job apply SQL.
argocd app sync pipeline --grpc-web
argocd app wait pipeline --health --sync --grpc-web
```

Verify:

Giữ port-forward RisingWave ở §7.4 đang chạy, hoặc mở lại `kubectl -n risingwave port-forward svc/risingwave 4567:4567` trong terminal riêng trước khi chạy các lệnh `psql`.

```bash
# MV phải có dữ liệu sau khi Vector đã ingest đủ event và RisingWave xử lý xong.
psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT COUNT(*) FROM mv_zone_stats;"

psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT borough, SUM(trip_count) FROM mv_zone_stats GROUP BY borough ORDER BY 2 DESC LIMIT 5;"

# Iceberg sink phải sinh metadata/data files trong bucket iceberg-data.
mc ls --recursive local/iceberg-data/nyc/zone_stats/ | head

# Health check tổng hợp cluster, workload, storage và image.
bash scripts/k3s-check.sh
```

## 11. Clear demo ingest để chạy lại

Mục này dùng khi muốn quay lại mốc cuối §9/đầu §10 để demo ingest thêm một lần từ trạng thái sạch, nhưng vẫn giữ cluster, Helm releases, bucket và dataset local. Thứ tự quan trọng là dừng Vector trước, rồi xóa state downstream, sau đó tạo lại topic/SQL và bật ingest lại.

Dừng Vector để không còn event mới vào Redpanda trong lúc clear:

```bash
kubectl --request-timeout=10s -n pipeline scale deploy/vector --replicas=0
kubectl -n pipeline wait --for=delete pod -l app=vector --timeout=120s || true
```

Xóa state xử lý trong RisingWave. Giữ port-forward RisingWave ở §7.4 đang chạy, hoặc mở lại `kubectl -n risingwave port-forward svc/risingwave 4567:4567` trong terminal riêng.

```bash
psql -h localhost -p 4567 -d dev -U root <<'SQL'
DROP SINK IF EXISTS sink_zone_stats;
DROP MATERIALIZED VIEW IF EXISTS mv_zone_stats;
DROP MATERIALIZED VIEW IF EXISTS mv_zone_stats_blue;
DROP SOURCE IF EXISTS nyc_taxi_src;
DROP TABLE IF EXISTS tlc_zone;
SQL
```

Xóa topic Redpanda để bỏ toàn bộ event cũ, rồi để GitOps tạo lại topic `nyc-taxi-events`:

```bash
kubectl -n redpanda exec redpanda-0 -c redpanda -- \
  rpk topic delete nyc-taxi-events --brokers redpanda.redpanda.svc.cluster.local:9093

argocd app sync redpanda-topics --grpc-web
argocd app wait redpanda-topics --health --sync --grpc-web
```

Nếu muốn output Iceberg cũng sạch, xóa prefix sink trong MinIO. Giữ MinIO API port-forward ở §9 đang chạy, hoặc mở lại `kubectl -n minio port-forward --address 127.0.0.1 svc/minio 9000:9000` trong terminal riêng.

```bash
mc rm --recursive --force local/iceberg-data/nyc/zone_stats/
```

Quay lại mốc khởi chạy: apply lại SQL, rồi bật Vector ingest:

```bash
argocd app sync pipeline --grpc-web
argocd app wait pipeline --health --sync --grpc-web

kubectl -n pipeline scale deploy/vector --replicas=1
kubectl -n pipeline rollout status deploy/vector --timeout=300s
kubectl -n pipeline logs deploy/vector --tail=100
```

## 12. Reset

Mục này chỉ dùng khi cần làm sạch môi trường. `k3s-purge.sh` giữ K3s và node membership; `--nuke` xóa K3s khỏi node hiện tại nên phải dùng có chủ đích.

Reset cluster về trạng thái vừa cài K3s, giữ K3s và 3 node:

```bash
# Xóa workload/namespaces do project tạo, giữ cụm K3s.
bash scripts/k3s-purge.sh
```

Xóa dấu vết K3s khỏi node hiện tại:

```bash
# Chạy trên từng node khi cần phá cụm hoàn toàn.
sudo bash scripts/k3s-purge.sh --nuke
```

Chạy `--nuke` lần lượt trên `imac`, `continux-vps`, `helios-pc` khi cần phá cụm hoàn toàn.

## 13. Checklist

Checklist này là trạng thái tối thiểu để xem setup hoàn tất. Nếu một dòng chưa xanh, quay lại section tương ứng thay vì tiếp tục benchmark hoặc viết báo cáo kết quả.

- [x] `kubectl get nodes` có `imac`, `continux-vps`, `helios-pc` đều `Ready`.
- [x] `helios-pc` có taint `dedicated=quorum:NoSchedule`.
- [x] `argocd app list` có `root-app`, `cloudflared`, `redpanda-topics`, `victoria-scrapes`, `vector`, `pipeline`.
- [x] MinIO có runtime path/bucket cần cho `rw-checkpoint`, `tlc-zone`; `iceberg-data` dùng ở §10.
- [x] Redpanda topic `nyc-taxi-events` tồn tại.
- [x] Vector chỉ chạy khi scale thủ công; v0.2.1 đã thêm rate limit cho demo ingest.
- [ ] RisingWave query `mv_zone_stats` trả dữ liệu.
- [ ] Grafana import được dashboard và đọc datasource VictoriaMetrics bằng panel thực nghiệm.
