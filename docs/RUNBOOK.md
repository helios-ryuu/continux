# RUNBOOK

Runbook hợp nhất cho Continux: dựng hệ thống từ máy sạch, khởi chạy một lượt thực nghiệm end-to-end, và dọn dẹp để có thể chạy lại từ đầu (bắt đầu từ bước tải dataset) một cách đúng đắn. Các lệnh được viết theo trình tự thực thi thực tế trên node quản trị `imac`; khi lệnh phụ thuộc repo, luôn bắt đầu bằng `cd ~/continux`.

## 0. Topology, Biến Thay Thế Và Nguyên Tắc Secret

Topology chuẩn gồm 3 K3s server qua Tailscale:

| Node | Máy | Vai trò |
|------|-----|---------|
| `imac` | Ubuntu 26.04, iMac19,2, Intel i5-8500, 6 cores, 8 GB RAM, 200 GB SSD | Server #1, `--cluster-init`, data plane |
| `continux-vps` | Ubuntu 24.04, 2 vCPU, 4 GB RAM, 80 GB SSD | Server #2, control/observability |
| `helios-pc` | WSL2 Ubuntu 26.04 trên Windows host `Helios-PC` | Server #3, quorum-only |

Tailscale inventory:

| Tailscale IP | Device | Dùng cho |
|--------------|--------|----------|
| `100.120.64.5` | `imac` | K3s server #1 |
| `100.113.151.56` | `continux-vps` | K3s server #2 |
| `100.78.46.87` | `helios-pc-wsl` | K3s server #3, Kubernetes node `helios-pc` |
| `100.125.106.89` | `helios-pc` | Windows host, không join K3s |

Các giá trị phải thay trước khi chạy:

```bash
export CLOUDFLARE_TUNNEL_TOKEN="<cloudflare-tunnel-token>"
export GRAFANA_DOMAIN="<grafana-domain>"
export ARGOCD_DOMAIN="<argocd-domain>"
export GITHUB_TOKEN="<github-token>"
export MINIO_ROOT_PASSWORD="<minio-root-password>"
```

Nguyên tắc bảo mật:

- Không commit token, password, kubeconfig, file `.env`, dataset lớn hoặc evidence.
- Secret runtime tạo bằng `kubectl create secret ... --dry-run=client -o yaml | kubectl apply -f -`.
- Các domain trong tài liệu là domain thật của môi trường triển khai hoặc giá trị thay thế dạng `<argocd-domain>`, `<grafana-domain>`.

## 1. Phiên Bản Chuẩn Của Stack

| Thành phần | Phiên bản |
|------------|-----------|
| K3s | `v1.35.5+k3s1` |
| Helm | `v4.1.4` |
| Argo CD | app `v3.4.2`, chart `argo-cd` `9.5.14` |
| Tailscale | `v1.98.2` |
| Redpanda | `v26.1.8` |
| RisingWave | `v2.8.3` |
| Vector | `0.55.0-alpine` |
| VictoriaMetrics | `v1.143.0` |
| Grafana | `v13.0.1+security-01` |
| cloudflared | `2026.5.0` |

Phiên bản hệ thống Continux nằm trong file `VERSION` ở root repo.

## 2. Dựng Hệ Thống Từ Máy Sạch

### 2.1. Chuẩn Bị OS

#### 2.1.1. `imac`

```bash
sudo hostnamectl set-hostname imac

sudo apt update
sudo apt -y upgrade
sudo apt install -y curl wget git ca-certificates jq netcat-openbsd unzip postgresql-client python3-venv

sudo swapoff -a
sudo sed -i '/\sswap\s/s/^/#/' /etc/fstab
echo 'net.ipv4.ip_forward = 1' | sudo tee /etc/sysctl.d/99-k3s.conf
sudo sysctl --system

git clone https://github.com/helios-ryuu/continux.git ~/continux
cd ~/continux
```

#### 2.1.2. `continux-vps`

Lần đầu đăng nhập bằng `root`:

```bash
adduser helios
usermod -aG sudo helios
rsync --archive --chown=helios:helios ~/.ssh /home/helios
hostnamectl set-hostname continux-vps
exit
```

Đăng nhập lại bằng user `helios`:

```bash
sudo apt update
sudo apt -y upgrade
sudo apt install -y curl wget git ca-certificates jq netcat-openbsd unzip

sudo swapoff -a
sudo sed -i '/\sswap\s/s/^/#/' /etc/fstab
echo 'net.ipv4.ip_forward = 1' | sudo tee /etc/sysctl.d/99-k3s.conf
sudo sysctl --system

git clone https://github.com/helios-ryuu/continux.git ~/continux
```

#### 2.1.3. `helios-pc` WSL

Trên Windows PowerShell Admin:

```powershell
wsl --install -d Ubuntu-26.04
wsl --set-default-version 2
wsl -d Ubuntu-26.04
```

Trong WSL:

```bash
sudo tee /etc/wsl.conf >/dev/null <<'EOF'
[boot]
systemd=true
EOF
exit
```

Restart WSL rồi chuẩn bị OS:

```powershell
wsl --shutdown
wsl -d Ubuntu-26.04
```

```bash
sudo apt update
sudo apt -y upgrade
sudo apt install -y curl wget git ca-certificates jq netcat-openbsd

sudo swapoff -a
sudo sed -i '/\sswap\s/s/^/#/' /etc/fstab
echo 'net.ipv4.ip_forward = 1' | sudo tee /etc/sysctl.d/99-k3s.conf
sudo sysctl --system

git clone https://github.com/helios-ryuu/continux.git ~/continux
```

#### 2.1.4. Firewall Khi Dùng UFW

Chạy trên từng Linux node nếu UFW đang bật:

```bash
sudo apt install -y ufw
sudo ufw allow OpenSSH comment 'ssh'

TAILSCALE_CIDR=100.64.0.0/10
sudo ufw allow from "${TAILSCALE_CIDR}" to any port 6443 proto tcp comment 'k3s apiserver via tailscale'
sudo ufw allow from "${TAILSCALE_CIDR}" to any port 2379:2380 proto tcp comment 'k3s embedded etcd'
sudo ufw allow from "${TAILSCALE_CIDR}" to any port 10250 proto tcp comment 'kubelet via tailscale'
sudo ufw allow from "${TAILSCALE_CIDR}" to any port 8472 proto udp comment 'flannel vxlan via tailscale'
sudo ufw allow from 10.42.0.0/16 to any comment 'k3s pods'
sudo ufw allow from 10.43.0.0/16 to any comment 'k3s services'

sudo ufw reload
sudo ufw status verbose
```

### 2.2. Tailscale Và Kiểm Tra Kết Nối

Chạy trên cả 3 máy:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --ssh
tailscale status
tailscale ip -4
```

Kiểm tra MagicDNS và độ trễ:

```bash
ping -c 3 imac
ping -c 3 continux-vps
ping -c 3 helios-pc-wsl
```

Trên `imac`, ghi lại IP Tailscale:

```bash
IMAC_TS_IP="$(tailscale ip -4)"
echo "${IMAC_TS_IP}"
```

### 2.3. Khởi Tạo K3s HA

#### 2.3.1. Init Server #1 Trên `imac`

```bash
cd ~/continux

sudo bash scripts/k3s-install-server-init.sh

mkdir -p ~/.kube
sudo k3s kubectl config view --raw > ~/.kube/config
chmod 600 ~/.kube/config
grep -qxF 'export KUBECONFIG=$HOME/.kube/config' ~/.bashrc || echo 'export KUBECONFIG=$HOME/.kube/config' >> ~/.bashrc
export KUBECONFIG=$HOME/.kube/config

bash scripts/k3s-token.sh
```

Lưu token in ra để join server #2 và #3.

#### 2.3.2. Join `continux-vps`

```bash
cd ~/continux

sudo bash scripts/k3s-install-server.sh <imac-tailscale-ip> <k3s-token> continux-vps edge
```

#### 2.3.3. Join `helios-pc`

```bash
cd ~/continux

sudo bash scripts/k3s-install-server.sh <imac-tailscale-ip> <k3s-token> helios-pc quorum
sudo bash scripts/wsl-enable-shared-root.sh
```

#### 2.3.4. Verify Cluster

Trên `imac`:

```bash
cd ~/continux

kubectl get nodes -o wide
kubectl get --raw='/readyz?verbose' | grep -E 'readyz|etcd|ok'
nc -vz continux-vps 2380
nc -vz helios-pc-wsl 2380
```

Output mong đợi:

```text
imac           Ready
continux-vps   Ready
helios-pc      Ready
[+]etcd ok
readyz check passed
```

### 2.4. Cài CLI Quản Trị

Chạy trên `imac`:

```bash
cd ~/continux

HELM_VERSION=v4.1.4
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 -o /tmp/get-helm.sh
chmod 700 /tmp/get-helm.sh
DESIRED_VERSION="${HELM_VERSION}" /tmp/get-helm.sh
rm -f /tmp/get-helm.sh

ARGOCD_VERSION=v3.4.2
curl -sSL -o /tmp/argocd-linux-amd64 \
  "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64"
sudo install -m 755 /tmp/argocd-linux-amd64 /usr/local/bin/argocd
rm -f /tmp/argocd-linux-amd64

curl -1sLf 'https://dl.redpanda.com/nzc4ZYQK3WRGd9sy/redpanda/cfg/setup/bash.deb.sh' | sudo -E bash
sudo apt install -y redpanda

wget -O /tmp/mc https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x /tmp/mc
sudo mv /tmp/mc /usr/local/bin/mc

bash scripts/tool-version.sh
```

### 2.5. Argo CD, Cloudflare Tunnel Và GitOps

#### 2.5.1. Cài Argo CD

```bash
cd ~/continux

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --version 9.5.14 \
  -f config/argocd/helm-values.yaml

kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
```

#### 2.5.2. Tạo Secret Cloudflare Tunnel

```bash
cd ~/continux

kubectl -n argocd create secret generic cloudflare-tunnel-token \
  --from-literal=token="${CLOUDFLARE_TUNNEL_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f config/argocd/cloudflared.yaml
kubectl -n argocd rollout status deploy/cloudflared --timeout=300s
```

Route Cloudflare cần trỏ về service nội bộ:

| Domain | Service nội bộ |
|--------|----------------|
| `<argocd-domain>` | `http://argocd-server.argocd:80` |
| `<grafana-domain>` | `http://grafana.observability:80` |

#### 2.5.3. Đăng Nhập Argo CD Và Đăng Ký Repo

```bash
cd ~/continux

ARGOCD_INITIAL_PASSWORD="$(
  kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath='{.data.password}' | base64 -d
)"

argocd login "${ARGOCD_DOMAIN}" \
  --username admin \
  --password "${ARGOCD_INITIAL_PASSWORD}" \
  --grpc-web

argocd repo add https://github.com/helios-ryuu/continux.git \
  --username <github-user> \
  --password "${GITHUB_TOKEN}" \
  --grpc-web
```

#### 2.5.4. Sync Root App

```bash
cd ~/continux

kubectl apply -f gitops/apps/root-app.yaml
argocd app sync root-app --grpc-web
argocd app wait root-app --health --sync --grpc-web
argocd app list --grpc-web
```

### 2.6. Deploy MinIO, Redpanda Và RisingWave

#### 2.6.1. Secrets

```bash
cd ~/continux

kubectl create namespace minio --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace risingwave --dry-run=client -o yaml | kubectl apply -f -

kubectl -n minio create secret generic minio-credentials \
  --from-literal=rootUser=adminuser \
  --from-literal=rootPassword="${MINIO_ROOT_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n risingwave create secret generic risingwave-s3-credentials \
  --from-literal=AWS_ACCESS_KEY_ID=adminuser \
  --from-literal=AWS_SECRET_ACCESS_KEY="${MINIO_ROOT_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -
```

#### 2.6.2. MinIO

```bash
cd ~/continux

helm repo add minio https://charts.min.io/
helm repo update

MINIO_CHART_VERSION="$(helm search repo minio/minio -o json | jq -r '.[0].version')"
helm upgrade --install minio minio/minio \
  --namespace minio \
  --version "${MINIO_CHART_VERSION}" \
  -f config/minio/helm-values.yaml

kubectl -n minio rollout status deploy/minio --timeout=300s
```

Terminal riêng để tạo bucket qua MinIO API:

```bash
kubectl -n minio port-forward --address 127.0.0.1 svc/minio 9000:9000
```

Terminal khác:

```bash
cd ~/continux

mc alias set local http://127.0.0.1:9000 adminuser "${MINIO_ROOT_PASSWORD}"
mc mb --ignore-existing local/rw-checkpoint
mc mb --ignore-existing local/iceberg-data
mc mb --ignore-existing local/tlc-zone
mc ls local
```

#### 2.6.3. Redpanda

```bash
cd ~/continux

helm repo add redpanda https://charts.redpanda.com
helm repo update

REDPANDA_CHART_VERSION="$(helm search repo redpanda/redpanda -o json | jq -r '.[0].version')"
helm upgrade --install redpanda redpanda/redpanda \
  --namespace redpanda --create-namespace \
  --version "${REDPANDA_CHART_VERSION}" \
  -f config/redpanda/helm-values.yaml

kubectl -n redpanda rollout status statefulset/redpanda --timeout=300s

argocd app sync redpanda-topics --grpc-web
argocd app wait redpanda-topics --health --sync --grpc-web

kubectl -n redpanda exec redpanda-0 -c redpanda -- \
  rpk topic describe nyc-taxi-events \
  --brokers redpanda.redpanda.svc.cluster.local:9093
```

Output mong đợi: topic `nyc-taxi-events`, `PARTITIONS 3`, `REPLICAS 1`.

#### 2.6.4. RisingWave

```bash
cd ~/continux

helm repo add risingwavelabs https://risingwavelabs.github.io/helm-charts/
helm repo update

RISINGWAVE_CHART_VERSION="$(helm search repo risingwavelabs/risingwave -o json | jq -r '.[0].version')"
helm upgrade --install risingwave risingwavelabs/risingwave \
  --namespace risingwave --create-namespace \
  --version "${RISINGWAVE_CHART_VERSION}" \
  -f config/risingwave/helm-values.yaml

kubectl -n risingwave rollout status statefulset/risingwave-meta --timeout=300s
kubectl -n risingwave rollout status statefulset/risingwave-compute --timeout=300s
kubectl -n risingwave get pods,svc -o wide
```

Terminal riêng để dùng SQL:

```bash
kubectl -n risingwave port-forward svc/risingwave 4567:4567
```

Terminal khác:

```bash
psql -h localhost -p 4567 -d dev -U root -c 'SHOW CLUSTER;'
```

Output mong đợi: meta, compute, compactor và frontend đều `RUNNING`.

### 2.7. Deploy VictoriaMetrics, Grafana Và Dashboard

#### 2.7.1. VictoriaMetrics

```bash
cd ~/continux

helm repo add vm https://victoriametrics.github.io/helm-charts/
helm repo update

VICTORIA_CHART_VERSION="$(helm search repo vm/victoria-metrics-k8s-stack -o json | jq -r '.[0].version')"
helm show crds vm/victoria-metrics-k8s-stack | kubectl apply -f - --server-side
kubectl wait --for condition=Established crd/vmagents.operator.victoriametrics.com --timeout=120s

helm upgrade --install victoria-metrics vm/victoria-metrics-k8s-stack \
  --namespace observability --create-namespace \
  --version "${VICTORIA_CHART_VERSION}" \
  -f config/victoria-metrics/helm-values.yaml

argocd app sync victoria-scrapes --grpc-web
argocd app wait victoria-scrapes --health --sync --grpc-web
```

#### 2.7.2. Grafana

```bash
cd ~/continux

helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

GRAFANA_CHART_VERSION="$(helm search repo grafana/grafana -o json | jq -r '.[0].version')"
helm upgrade --install grafana grafana/grafana \
  --namespace observability --create-namespace \
  --version "${GRAFANA_CHART_VERSION}" \
  -f config/grafana/helm-values.yaml

kubectl -n observability rollout status deploy/grafana --timeout=300s
kubectl -n observability get secret grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d && echo
```

Mở `https://<grafana-domain>`, đăng nhập `admin`, đổi mật khẩu, import các file `dashboards/*.json` với datasource `VictoriaMetrics`.

#### 2.7.3. Metrics Exporter

```bash
cd ~/continux

argocd app sync metrics-exporter --grpc-web
argocd app wait metrics-exporter --health --sync --grpc-web

kubectl -n pipeline get deploy,pod,svc -l app=continux-metrics
kubectl -n observability get vmservicescrape continux-metrics
```

### 2.8. Checklist Hạ Tầng Sẵn Sàng

- [ ] `kubectl get nodes -o wide` có `imac`, `continux-vps`, `helios-pc` đều `Ready`.
- [ ] `continux-vps` có taint `dedicated=edge:NoSchedule`.
- [ ] `helios-pc` có taint `dedicated=quorum:NoSchedule`.
- [ ] Argo CD đăng nhập được qua `<argocd-domain>` và repo GitHub đã đăng ký.
- [ ] `root-app` và các app con cần thiết đã được tạo.
- [ ] MinIO có bucket `rw-checkpoint`, `iceberg-data`, `tlc-zone`.
- [ ] Redpanda topic `nyc-taxi-events` tồn tại với `3` partition, `1` replica.
- [ ] RisingWave `SHOW CLUSTER` có 4 worker `RUNNING`.
- [ ] Grafana đọc datasource VictoriaMetrics.
- [ ] Metrics exporter chạy và VictoriaMetrics scrape được `continux_exporter_up`.
- [ ] Vector mặc định ở `replicas=0` và chỉ scale thủ công khi replay.

Sau khi đạt checklist này, hệ thống đã sẵn sàng để chạy một lượt thực nghiệm theo §4.

## 3. Quy Trình Dữ Liệu Vận Hành

### 3.1. Ba Luồng Hoạt Động Đồng Thời

#### Luồng dữ liệu

```text
Dataset -> Converter -> Vector -> Redpanda -> RisingWave -> MinIO/Iceberg
```

Luồng tạo kết quả phân tích: bản ghi taxi đi từ file nguồn tới materialized view và object lakehouse.

#### Luồng điều khiển GitOps

```text
GitHub Repository -> Argo CD -> Kubernetes Applications
```

Luồng quyết định workload nào được triển khai và cấu hình nào được áp dụng. Nó không chở dữ liệu taxi, mà chở trạng thái mong muốn của hệ thống.

#### Luồng quan sát

```text
Workloads + metrics-exporter -> VictoriaMetrics -> Grafana
```

Luồng này không thay đổi dữ liệu nghiệp vụ. Nó thu metric để chứng minh hệ thống sẵn sàng, MV có dữ liệu, cutover thành công và tài nguyên còn trong ngưỡng kiểm soát.

### 3.2. Chuẩn Bị Dữ Liệu

| Thành phần | Vai trò |
|------------|---------|
| NYC TLC Yellow Taxi (Parquet) | Nguồn dữ liệu chuyến xe |
| `scripts/partojsonl.py` | Đọc Parquet, chỉ xuất các field pipeline cần (`pickup_time`, `pu_location_id`, `do_location_id`, `fare_amount`, `trip_distance`) sang JSONL |
| Taxi Zone lookup CSV | Dữ liệu tham chiếu để chuyển `location_id` thành `borough/zone` |
| `data/raw/yellow_tripdata_<yyyy-mm>.jsonl` | File JSONL Vector đọc |
| `tlc-zone/taxi_zone_lookup.csv` | File CSV trên MinIO để RisingWave nạp vào table `tlc_zone` |

Dữ liệu lookup không chạy qua Redpanda. RisingWave đọc nó trực tiếp từ MinIO để join với stream chuyến xe.

### 3.3. Ingest Vector → Redpanda

Vector mặc định ở `replicas=0` khi không chạy thực nghiệm và chỉ được scale lên `1` khi replay. Khi chạy, Vector đọc từng dòng từ `/data/*.jsonl`, serialize event, gửi qua Kafka sink có rate limit/buffer vào Redpanda topic `nyc-taxi-events` (`partitions=3`, `replicas=1`, `retention.ms=86400000`).

### 3.4. Xử Lý Trong RisingWave

Các object SQL được pipeline khởi tạo:

| Object | Nguồn vào | Vai trò | Output |
|--------|-----------|---------|--------|
| `tlc_zone` | CSV trong MinIO | Bảng lookup tĩnh | `location_id -> borough, zone` |
| `nyc_taxi_src` | Redpanda topic | Source stream | Dòng taxi liên tục |
| `mv_zone_stats_blue` | Source + lookup | Logic baseline | Tổng hợp Blue |
| `mv_zone_stats` | Source + lookup | Tên public phục vụ query | Tổng hợp đang công bố |
| `mv_zone_stats_green` | Source + lookup, logic mới | Bản thử nghiệm cutover | Tổng hợp Green |
| `sink_zone_stats` | Public MV | Ghi lakehouse | Iceberg output |

Một event taxi có `pu_location_id` được join với `tlc_zone.location_id`. Sau join, RisingWave gom nhóm theo `borough, zone` và cập nhật `trip_count`, `total_fare`, `avg_distance`.

### 3.5. Ghi Lakehouse Trên MinIO/Iceberg

MinIO phục vụ nhiều loại dữ liệu:

| Prefix/bucket | Dữ liệu | Nguồn ghi/đọc |
|---------------|---------|---------------|
| `tlc-zone/` | Taxi Zone CSV | Upload trước pipeline, RisingWave đọc |
| `rw-checkpoint/` | State/checkpoint | RisingWave ghi và đọc |
| `iceberg-data/nyc/zone_stats/` | Iceberg table data/metadata | `sink_zone_stats` ghi |

Khi public MV thay đổi, sink ghi kết quả xuống Iceberg, sinh data Parquet, equality-delete Parquet, position-delete Parquet và metadata. Đây là bằng chứng pipeline không chỉ query được dữ liệu đang chạy, mà còn tạo ra output lakehouse kiểm chứng được trên object storage.

### 3.6. Quan Sát

`continux-metrics` query RisingWave catalog/MV theo chu kỳ và expose metrics tại `/metrics`:

| Metric | Mô tả output |
|--------|--------------|
| `continux_exporter_up` | Exporter hoạt động |
| `continux_mv_rows{view="..."}` | Số nhóm zone của mỗi MV |
| `continux_mv_trips{view="..."}` | Tổng trips của mỗi MV |
| `continux_events_processed_total` | Proxy số event đã phản ánh ở public MV |
| `continux_green_ready` | Green MV đã có dữ liệu |
| `continux_cutover_duration_seconds` | Thời gian swap đã ghi |
| `continux_last_swap_timestamp_seconds` | Tuổi lần swap |
| `continux_query_errors_total` | Lỗi query trong lúc cutover |
| `continux_checksum_mismatch_total` | Cờ mismatch khi so cùng logic |
| `continux_records_rejected_total` | Bản ghi bị loại |
| `continux_iceberg_last_commit_timestamp_seconds` | RisingWave Iceberg catalog nếu có |

VictoriaMetrics scrape exporter + Redpanda + RisingWave + node-exporter, lưu time-series và phục vụ Grafana hiển thị bốn nhóm dashboard: `streaming-perf`, `resource-util`, `cutover`, `data-integrity`.

## 4. Khởi Chạy Một Lượt Thực Nghiệm Từ Đầu

Quy trình này giả định hệ thống đã được dựng theo §2 và đang ở baseline runtime sạch (không có dataset cũ, không có state demo cũ). Nếu lượt trước đã chạy, hãy hoàn tất §5 trước khi bắt đầu §4.

### 4.1. Trạng Thái Khởi Đầu Và Bố Trí Terminal

**Điều kiện đầu vào:**

| Hạng mục | Yêu cầu |
|----------|---------|
| Cluster | Ba node `imac`, `continux-vps`, `helios-pc` ở `Ready` |
| Argo CD | Các app chính `Synced/Healthy` |
| Vector | `Deployment pipeline/vector` có `replicas=0` |
| Repo local | `git status --porcelain --untracked-files=all` không in thay đổi |
| Dataset local | Chưa có `data/raw/`, `.venv/` từ lượt trước |
| MinIO `tlc-zone/` | Chưa upload, hoặc đã upload bởi lượt này |
| Redpanda topic | `nyc-taxi-events` tồn tại với cấu hình chuẩn |
| RisingWave | Có thể chưa có object pipeline; sẽ apply ở §4.3 hoặc đã có baseline blue sạch sau §5 |

**Terminal layout (giữ mở suốt buổi chạy):**

| Terminal | Mục đích | Lệnh chạy và giữ mở |
|----------|----------|----------------------|
| 1 | Điều khiển chính, thu evidence | Các lệnh ở từng bước phía dưới |
| 2 | Kết nối SQL tới RisingWave | `kubectl -n risingwave port-forward svc/risingwave 4567:4567` |
| 3 | Kết nối API tới MinIO | `kubectl -n minio port-forward --address 127.0.0.1 svc/minio 9000:9000` |
| 4 | Đọc metrics exporter | `kubectl -n pipeline port-forward svc/continux-metrics 9108:9108` |
| 5 | Query VictoriaMetrics | `kubectl -n observability port-forward svc/vmsingle-victoria-metrics 8428:8428` |
| 6 | Chạy query loop khi cutover | Chỉ dùng tại §4.7 |

**Khai báo biến và evidence dir:**

```bash
cd ~/continux

export DATA_MONTH=2026-03
export DATA_DIR="$PWD/data/raw"
export DATA_PARQUET="${DATA_DIR}/yellow_tripdata_${DATA_MONTH}.parquet"
export DATA_JSONL="data/raw/yellow_tripdata_${DATA_MONTH}.jsonl"
export ZONE_CSV="${DATA_DIR}/taxi_zone_lookup.csv"
export ZONE_RW_CSV="${DATA_DIR}/taxi_zone_lookup_risingwave.csv"
export DATA_URL="https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_${DATA_MONTH}.parquet"
export ZONE_URL="https://d37ci6vzurychx.cloudfront.net/misc/taxi_zone_lookup.csv"
export BROKERS="redpanda.redpanda.svc.cluster.local:9093"

RUN_ID="$(date +%Y%m%d-%H%M%S)"
EVIDENCE_DIR="$HOME/continux-demo-evidence/${RUN_ID}"
export RUN_ID EVIDENCE_DIR
mkdir -p "${EVIDENCE_DIR}"

printf 'export RUN_ID=%q\nexport EVIDENCE_DIR=%q\n' "${RUN_ID}" "${EVIDENCE_DIR}" \
  > /tmp/continux-demo-env.sh

printf 'RUN_ID=%s\nEVIDENCE_DIR=%s\n' "${RUN_ID}" "${EVIDENCE_DIR}" \
  | tee "${EVIDENCE_DIR}/00-run-id.txt"
```

Evidence nằm tại `~/continux-demo-evidence/<RUN_ID>/`, ngoài repo. Không ghi password, token hoặc nội dung secret vào evidence.

### 4.2. Chuẩn Bị Dataset

Đây là bước tạo dữ liệu đầu tiên của lượt mới. Mọi file sinh trên máy nằm trong `data/raw/`, đã được `.gitignore` bỏ qua.

```bash
cd ~/continux

kubectl -n pipeline get deploy/vector \
  -o jsonpath='{.spec.replicas}{" desired\n"}'

test ! -e "${DATA_DIR}"
test ! -e .venv
```

Vector phải là `0 desired` và chưa có thư mục dữ liệu/môi trường Python từ lượt trước.

```bash
cd ~/continux

mkdir -p "${DATA_DIR}"

wget -c -O "${DATA_PARQUET}" "${DATA_URL}" \
  2>&1 | tee "${EVIDENCE_DIR}/01-download-yellow-taxi.txt"
wget -c -O "${ZONE_CSV}" "${ZONE_URL}" \
  2>&1 | tee "${EVIDENCE_DIR}/01-download-taxi-zone.txt"

{ printf 'location_id,borough,zone,service_zone\n'; tail -n +2 "${ZONE_CSV}"; } \
  > "${ZONE_RW_CSV}"

python3 -m venv .venv
. .venv/bin/activate
python -m pip install --upgrade pip pyarrow \
  2>&1 | tee "${EVIDENCE_DIR}/01-install-pyarrow.txt"

python scripts/partojsonl.py "${DATA_PARQUET}" "${DATA_JSONL}" \
  | tee "${EVIDENCE_DIR}/01-convert-jsonl.txt"

wc -l "${DATA_JSONL}" \
  | tee "${EVIDENCE_DIR}/01-jsonl-lines.txt"
find "${DATA_DIR}" -maxdepth 1 -type f -printf '%f\n' \
  | sort | tee "${EVIDENCE_DIR}/01-local-data-files.txt"
```

Upload lookup lên MinIO:

```bash
cd ~/continux

mc alias set local http://127.0.0.1:9000 adminuser "${MINIO_ROOT_PASSWORD}"
mc cp "${ZONE_RW_CSV}" local/tlc-zone/taxi_zone_lookup.csv \
  | tee "${EVIDENCE_DIR}/01-upload-taxi-zone.txt"
mc ls local/tlc-zone \
  | tee "${EVIDENCE_DIR}/01-minio-tlc-zone.txt"

JSONL_COUNT="$(find "${DATA_DIR}" -maxdepth 1 -type f -name '*.jsonl' | wc -l | tr -d ' ')"
printf 'JSONL_COUNT=%s\n' "${JSONL_COUNT}" \
  | tee "${EVIDENCE_DIR}/01-jsonl-count.txt"
test "${JSONL_COUNT}" -eq 1
test -s "${DATA_JSONL}"

GIT_STATUS="$(git status --porcelain --untracked-files=all)"
printf '%s' "${GIT_STATUS}" | tee "${EVIDENCE_DIR}/01-git-after-data.txt"
test -z "${GIT_STATUS}"
```

**Kết quả mong đợi:**

- Parquet, JSONL, hai file Taxi Zone (CSV gốc + CSV cho RisingWave) đều nằm trong `data/raw/`.
- `JSONL_COUNT=1` — Vector sẽ phát toàn bộ file `/data/*.jsonl`, nên một lượt sạch chỉ được có một file JSONL.
- MinIO liệt kê `taxi_zone_lookup.csv`.
- `git status` rỗng vì mọi tệp sinh ra nằm trong đường dẫn Git bỏ qua.

### 4.3. Sync Vector Và Apply SQL Pipeline

Vector luôn được sync ở `replicas=0` để không phát event ngoài ý muốn.

```bash
cd ~/continux

argocd app sync vector --grpc-web
argocd app wait vector --health --sync --grpc-web

kubectl --request-timeout=10s -n pipeline scale deploy/vector --replicas=0
kubectl -n pipeline get deploy/vector -o jsonpath='{.spec.replicas}{" desired\n"}'
```

Apply SQL pipeline (Argo CD hook `mv-apply-job` có thể bị xóa sau khi `Succeeded` — verify bằng catalog thay vì tìm Job còn tồn tại):

```bash
cd ~/continux

argocd app sync pipeline --grpc-web
argocd app wait pipeline --health --sync --grpc-web

psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT 'table' AS kind, name FROM rw_catalog.rw_tables WHERE name = 'tlc_zone'
   UNION ALL
   SELECT 'source' AS kind, name FROM rw_catalog.rw_sources WHERE name = 'nyc_taxi_src'
   UNION ALL
   SELECT 'mv' AS kind, name FROM rw_catalog.rw_materialized_views WHERE name IN ('mv_zone_stats_blue', 'mv_zone_stats')
   UNION ALL
   SELECT 'sink' AS kind, name FROM rw_catalog.rw_sinks WHERE name = 'sink_zone_stats'
   ORDER BY kind, name;" \
  | tee "${EVIDENCE_DIR}/02-risingwave-catalog-objects.txt"

psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT COUNT(*) AS tlc_zone_rows FROM tlc_zone;" \
  | tee "${EVIDENCE_DIR}/02-tlc-zone-count.txt"
```

**Kết quả mong đợi:** catalog có `tlc_zone`, `nyc_taxi_src`, `mv_zone_stats_blue`, `mv_zone_stats`, `sink_zone_stats`; `tlc_zone` có số dòng bằng số dòng của Taxi Zone lookup vừa upload.

Không dùng `\dt public.*` hoặc `\dm public.*` để verify RisingWave; meta-command có pattern có thể sinh collation regex không tương thích.

### 4.4. Verify Topic, SQL Và Quan Sát

```bash
cd ~/continux

kubectl -n redpanda exec redpanda-0 -c redpanda -- \
  rpk topic describe nyc-taxi-events --brokers "${BROKERS}" \
  | tee "${EVIDENCE_DIR}/02-redpanda-topic.txt"

psql -h localhost -p 4567 -d dev -U root -c 'SHOW CLUSTER;' \
  | tee "${EVIDENCE_DIR}/02-risingwave-cluster.txt"

curl -fsS http://127.0.0.1:9108/metrics \
  | grep '^continux_exporter_up' \
  | tee "${EVIDENCE_DIR}/02-exporter-up.txt"

curl -fsSG 'http://127.0.0.1:8428/api/v1/query' \
  --data-urlencode 'query=continux_exporter_up' \
  | tee "${EVIDENCE_DIR}/02-vm-exporter-up.json"
```

**Kết quả mong đợi:** topic `nyc-taxi-events` có `3` partition, `1` replica; RisingWave báo các worker `RUNNING`; exporter trả `continux_exporter_up 1`; VictoriaMetrics trả series.

### 4.5. Dựng Baseline Blue Sạch (Khi Cần)

Bước này cần thiết nếu cluster còn dữ liệu runtime từ một lượt trước chưa được dọn. Nếu vừa hoàn thành §5 trong cùng phiên, có thể bỏ qua §4.5.

> Cảnh báo: phần này xóa bản tin trong topic, đối tượng SQL pipeline, đầu ra Iceberg hiện hành và metric cutover hiện thời. Không xóa cluster, PVC, dataset, lookup CSV, bucket hoặc secret.

Lưu trạng thái trước khi xóa:

```bash
cd ~/continux

{
  date -Is
  kubectl -n pipeline get deploy/vector -o wide
  kubectl -n redpanda exec redpanda-0 -c redpanda -- \
    rpk topic describe nyc-taxi-events --brokers "${BROKERS}"
} | tee "${EVIDENCE_DIR}/03-before-reset-runtime.txt"

psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT name FROM rw_catalog.rw_materialized_views
   WHERE name IN ('mv_zone_stats_blue', 'mv_zone_stats', 'mv_zone_stats_green')
   ORDER BY name;" \
  | tee "${EVIDENCE_DIR}/03-before-reset-mvs.txt"

mc ls --recursive local/iceberg-data/nyc/zone_stats/ | sed -n '1,50p' \
  | tee "${EVIDENCE_DIR}/03-before-reset-iceberg.txt"
```

Dừng Vector và xác nhận:

```bash
cd ~/continux

kubectl -n pipeline get deploy/vector \
  -o jsonpath='{.spec.replicas}{" desired\n"}'

read -r -p "Nhập RESET-DEMO để xóa trạng thái khi chạy và tạo baseline sạch: " CONFIRM
test "${CONFIRM}" = "RESET-DEMO"

kubectl --request-timeout=10s -n pipeline scale deploy/vector --replicas=0
kubectl -n pipeline wait --for=delete pod -l app=vector --timeout=120s || true

kubectl -n pipeline get deploy/vector \
  -o jsonpath='{.spec.replicas}{" desired\n"}' \
  | tee "${EVIDENCE_DIR}/03-vector-stopped.txt"
```

Xóa object SQL pipeline (sink trước, MV, source, table):

```bash
cd ~/continux

psql -h localhost -p 4567 -d dev -U root <<'SQL' \
  | tee "${EVIDENCE_DIR}/03-drop-sql-state.txt"
DROP SINK IF EXISTS sink_zone_stats;
DROP MATERIALIZED VIEW IF EXISTS mv_zone_stats_green;
DROP MATERIALIZED VIEW IF EXISTS mv_zone_stats;
DROP MATERIALIZED VIEW IF EXISTS mv_zone_stats_blue;
DROP SOURCE IF EXISTS nyc_taxi_src;
DROP TABLE IF EXISTS tlc_zone;
SQL
```

Xóa và tái tạo topic sạch:

```bash
cd ~/continux

{
  if kubectl -n redpanda exec redpanda-0 -c redpanda -- \
    rpk topic list --brokers "${BROKERS}" | grep -q 'nyc-taxi-events'; then
    kubectl -n redpanda exec redpanda-0 -c redpanda -- \
      rpk topic delete nyc-taxi-events --brokers "${BROKERS}"
  else
    echo "Topic nyc-taxi-events đã không tồn tại; tiếp tục tạo lại."
  fi
} | tee "${EVIDENCE_DIR}/03-topic-delete.txt"

argocd app sync redpanda-topics --grpc-web
argocd app wait redpanda-topics --health --sync --grpc-web

kubectl -n redpanda exec redpanda-0 -c redpanda -- \
  rpk topic describe nyc-taxi-events --brokers "${BROKERS}" \
  | tee "${EVIDENCE_DIR}/03-topic-recreated.txt"
```

Dọn đầu ra Iceberg và metric cutover hiện thời:

```bash
cd ~/continux

mc rm --recursive --force local/iceberg-data/nyc/zone_stats/ \
  | tee "${EVIDENCE_DIR}/03-clear-iceberg.txt"

kubectl -n pipeline exec deploy/continux-metrics -- \
  rm -f /state/cutover.prom

sleep 12
curl -fsS http://127.0.0.1:9108/metrics \
  | grep -E '^continux_(cutover_duration_seconds|last_swap_timestamp_seconds|query_errors_total)' \
  | tee "${EVIDENCE_DIR}/03-cutover-metrics-cleared.txt"
```

MinIO có thể hiển thị delete marker nếu bucket bật lưu phiên bản; đây là hành vi bình thường, không phải lỗi.

Apply lại pipeline blue và xác nhận baseline:

```bash
cd ~/continux

argocd app sync pipeline --grpc-web
argocd app wait pipeline --health --sync --grpc-web

psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT 'table' AS kind, name FROM rw_catalog.rw_tables WHERE name = 'tlc_zone'
   UNION ALL
   SELECT 'source' AS kind, name FROM rw_catalog.rw_sources WHERE name = 'nyc_taxi_src'
   UNION ALL
   SELECT 'mv' AS kind, name FROM rw_catalog.rw_materialized_views
     WHERE name IN ('mv_zone_stats_blue', 'mv_zone_stats', 'mv_zone_stats_green')
   UNION ALL
   SELECT 'sink' AS kind, name FROM rw_catalog.rw_sinks WHERE name = 'sink_zone_stats'
   ORDER BY kind, name;" \
  | tee "${EVIDENCE_DIR}/03-baseline-objects.txt"

psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT COUNT(*) AS tlc_zone_rows FROM tlc_zone;
   SELECT 'public' AS view_name, COUNT(*) AS zones, COALESCE(SUM(trip_count),0) AS trips FROM mv_zone_stats
   UNION ALL
   SELECT 'blue', COUNT(*), COALESCE(SUM(trip_count),0) FROM mv_zone_stats_blue;
   SELECT COUNT(*) AS green_objects FROM rw_catalog.rw_materialized_views
     WHERE name = 'mv_zone_stats_green';" \
  | tee "${EVIDENCE_DIR}/03-baseline-counts.txt"

if mc ls --recursive local/iceberg-data/nyc/zone_stats/ | grep -q '\.parquet$'; then
  echo "FAIL: baseline vẫn còn file Parquet Iceberg." | tee "${EVIDENCE_DIR}/03-baseline-iceberg-check.txt"
  exit 1
else
  echo "OK: baseline chưa có tệp Parquet của replay." | tee "${EVIDENCE_DIR}/03-baseline-iceberg-check.txt"
fi
```

**Kết quả mong đợi cho baseline:**

| Kiểm tra | Kết quả |
|----------|---------|
| Object SQL | Có `tlc_zone`, `nyc_taxi_src`, `mv_zone_stats_blue`, `mv_zone_stats`, `sink_zone_stats` |
| Green MV | `green_objects = 0` |
| Lookup | `tlc_zone` có dòng bằng số dòng Taxi Zone CSV |
| Public và blue | `trips = 0` trước replay sạch |
| Vector | `0 desired` |
| Iceberg | Chưa có tệp dữ liệu Parquet của replay mới |

### 4.6. Replay End-To-End

```bash
cd ~/continux

REPLAY_START_EPOCH="$(date +%s)"
printf 'REPLAY_START_EPOCH=%s\n' "${REPLAY_START_EPOCH}" \
  | tee "${EVIDENCE_DIR}/04-replay-start.txt"

kubectl -n pipeline scale deploy/vector --replicas=1
kubectl -n pipeline rollout status deploy/vector --timeout=300s

kubectl -n pipeline logs deploy/vector --tail=120 \
  | tee "${EVIDENCE_DIR}/04-vector-startup-logs.txt"
```

**Dừng khẩn cấp nếu Vector gây tải cao:**

```bash
kubectl --request-timeout=10s -n pipeline scale deploy/vector --replicas=0
kubectl -n pipeline wait --for=delete pod -l app=vector --timeout=120s || true
```

Quan sát dữ liệu đi theo pipeline:

```bash
# Vector đang phát dữ liệu
kubectl -n pipeline logs deploy/vector --tail=120 \
  | tee "${EVIDENCE_DIR}/04-observe-vector.txt"

# Redpanda đang nhận sự kiện
kubectl -n redpanda exec redpanda-0 -c redpanda -- \
  rpk topic describe nyc-taxi-events --brokers "${BROKERS}" \
  | tee "${EVIDENCE_DIR}/04-observe-topic.txt"

# RisingWave cập nhật MV
for i in $(seq 1 12); do
  date -Is
  psql -h localhost -p 4567 -d dev -U root -At -c \
    "SELECT COUNT(*) AS zones, COALESCE(SUM(trip_count),0) AS trips FROM mv_zone_stats;"
  sleep 5
done | tee "${EVIDENCE_DIR}/04-mv-progress.txt"

# Exporter phản ánh kết quả
curl -fsS http://127.0.0.1:9108/metrics \
  | grep -E '^continux_(events_processed_total|mv_rows|mv_trips|green_ready)' \
  | tee "${EVIDENCE_DIR}/04-exporter-progress.txt"

# Iceberg có đầu ra mới
mc ls --recursive local/iceberg-data/nyc/zone_stats/ | sed -n '1,50p' \
  | tee "${EVIDENCE_DIR}/04-iceberg-progress.txt"
```

Mở Grafana với time range `Last 15 minutes` hoặc bắt đầu từ `REPLAY_START_EPOCH`; dashboard `streaming-perf` và `resource-util` phải có activity trong khoảng replay.

Dừng replay và chốt kết quả:

```bash
cd ~/continux

psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT COUNT(*) AS zones, COALESCE(SUM(trip_count),0) AS trips FROM mv_zone_stats;" \
  | tee "${EVIDENCE_DIR}/04-mv-before-stop.txt"

kubectl --request-timeout=10s -n pipeline scale deploy/vector --replicas=0
kubectl -n pipeline wait --for=delete pod -l app=vector --timeout=120s || true

sleep 15

psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT COUNT(*) AS zones, COALESCE(SUM(trip_count),0) AS trips FROM mv_zone_stats;
   SELECT borough, SUM(trip_count) AS trips
   FROM mv_zone_stats GROUP BY borough ORDER BY trips DESC LIMIT 10;" \
  | tee "${EVIDENCE_DIR}/04-mv-final.txt"

mc ls --recursive local/iceberg-data/nyc/zone_stats/ | sed -n '1,50p' \
  | tee "${EVIDENCE_DIR}/04-iceberg-final.txt"

bash scripts/k3s-check.sh overview \
  | tee "${EVIDENCE_DIR}/04-health-after-replay.txt"
```

**Kết quả mong đợi:** Vector về `0`, `mv_zone_stats` có trips lớn hơn `0`, Iceberg có tệp Parquet/metadata mới, cluster vẫn khỏe.

### 4.7. Blue/Green Cutover

Tạo green MV và kiểm tra sẵn sàng:

```bash
cd ~/continux

kubectl -n pipeline get deploy/vector \
  -o jsonpath='{.spec.replicas}{" desired\n"}'

psql -h localhost -p 4567 -d dev -U root <<'SQL' \
  | tee "${EVIDENCE_DIR}/05-create-green.txt"
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_zone_stats_green AS
SELECT
    z.borough,
    z.zone,
    COUNT(*)             AS trip_count,
    SUM(t.fare_amount)   AS total_fare,
    AVG(t.trip_distance) AS avg_distance
FROM nyc_taxi_src t
JOIN tlc_zone     z ON t.pu_location_id = z.location_id
WHERE t.fare_amount >= 0
  AND t.trip_distance >= 0
GROUP BY z.borough, z.zone;
SQL

for i in $(seq 1 20); do
  date -Is
  psql -h localhost -p 4567 -d dev -U root -At -c \
    "SELECT 'public', COUNT(*), COALESCE(SUM(trip_count),0) FROM mv_zone_stats
     UNION ALL
     SELECT 'blue', COUNT(*), COALESCE(SUM(trip_count),0) FROM mv_zone_stats_blue
     UNION ALL
     SELECT 'green', COUNT(*), COALESCE(SUM(trip_count),0) FROM mv_zone_stats_green;"
  sleep 5
done | tee "${EVIDENCE_DIR}/05-green-ready-samples.txt"
```

**Kết quả mong đợi trước swap:** public và blue có cùng số liệu; green có dữ liệu và có thể có ít trips hơn blue (cố ý loại sự kiện `fare_amount < 0` hoặc `trip_distance < 0`).

**Terminal 6 — query loop trong lúc swap:**

```bash
cd ~/continux
source /tmp/continux-demo-env.sh

QUERY_LOG="${EVIDENCE_DIR}/05-query-loop-during-cutover.txt"
: > "${QUERY_LOG}"

while true; do
  TS="$(date -Is)"
  if RESULT="$(psql -h localhost -p 4567 -d dev -U root -AtX -c \
    "SELECT COUNT(*), COALESCE(SUM(trip_count),0) FROM mv_zone_stats;" 2>&1)"; then
    printf '%s OK %s\n' "${TS}" "${RESULT}" | tee -a "${QUERY_LOG}"
  else
    printf '%s ERROR %s\n' "${TS}" "${RESULT}" | tee -a "${QUERY_LOG}"
  fi
  sleep 0.5
done
```

Giữ vòng lặp chạy, chuyển về Terminal 1 để swap:

```bash
cd ~/continux

test -s "${EVIDENCE_DIR}/05-query-loop-during-cutover.txt"
grep -q ' OK ' "${EVIDENCE_DIR}/05-query-loop-during-cutover.txt"

CUTOVER_START_NS="$(date +%s%N)"

psql -h localhost -p 4567 -d dev -U root -c \
  "ALTER MATERIALIZED VIEW mv_zone_stats SWAP WITH mv_zone_stats_green;" \
  | tee "${EVIDENCE_DIR}/05-swap.txt"

CUTOVER_END_NS="$(date +%s%N)"
CUTOVER_DURATION="$(
  python3 -c 'import sys; print(f"{(int(sys.argv[2]) - int(sys.argv[1])) / 1_000_000_000:.6f}")' \
    "${CUTOVER_START_NS}" "${CUTOVER_END_NS}"
)"
SWAP_TIMESTAMP="$((CUTOVER_END_NS / 1000000000))"

printf 'continux_cutover_duration_seconds %s\ncontinux_last_swap_timestamp_seconds %s\n' \
  "${CUTOVER_DURATION}" "${SWAP_TIMESTAMP}" \
  | tee "${EVIDENCE_DIR}/05-duration.txt"
```

Sau khi Terminal 6 có thêm vài dòng `OK` sau swap, dừng vòng lặp bằng `Ctrl+C`. Tính query errors và verify:

```bash
cd ~/continux

QUERY_ERRORS="$(grep -c ' ERROR ' "${EVIDENCE_DIR}/05-query-loop-during-cutover.txt" || true)"
printf 'continux_query_errors_total %s\n' "${QUERY_ERRORS}" \
  | tee "${EVIDENCE_DIR}/05-query-errors.txt"

psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT 'public' AS view_name, COUNT(*) AS zones, COALESCE(SUM(trip_count),0) AS trips FROM mv_zone_stats
   UNION ALL
   SELECT 'green_name_after_swap', COUNT(*), COALESCE(SUM(trip_count),0) FROM mv_zone_stats_green
   UNION ALL
   SELECT 'blue', COUNT(*), COALESCE(SUM(trip_count),0) FROM mv_zone_stats_blue;" \
  | tee "${EVIDENCE_DIR}/05-after-swap-counts.txt"

kubectl -n risingwave get pods \
  | tee "${EVIDENCE_DIR}/05-risingwave-after-swap.txt"
```

**Kết quả mong đợi:**

- Public MV sau swap mang kết quả green.
- `mv_zone_stats_green` sau swap giữ logic public cũ (hai MV đã đổi tên cho nhau).
- `continux_query_errors_total = 0`.
- Các pod RisingWave vẫn `Running`.

Ghi metric cutover vào exporter và xem dashboard:

```bash
cd ~/continux

kubectl -n pipeline exec -i deploy/continux-metrics -- sh -c 'cat > /state/cutover.prom' <<EOF
# HELP continux_cutover_duration_seconds Latest measured blue/green swap duration.
# TYPE continux_cutover_duration_seconds gauge
continux_cutover_duration_seconds ${CUTOVER_DURATION}
# HELP continux_last_swap_timestamp_seconds Unix timestamp of the last blue/green swap.
# TYPE continux_last_swap_timestamp_seconds gauge
continux_last_swap_timestamp_seconds ${SWAP_TIMESTAMP}
# HELP continux_query_errors_total Query errors observed during cutover.
# TYPE continux_query_errors_total counter
continux_query_errors_total ${QUERY_ERRORS}
EOF

sleep 20

curl -fsS http://127.0.0.1:9108/metrics \
  | grep -E '^continux_(cutover|last_swap|query_errors|green_ready|mv_rows|mv_trips|checksum)' \
  | tee "${EVIDENCE_DIR}/05-exporter-cutover.txt"

curl -fsSG 'http://127.0.0.1:8428/api/v1/query' \
  --data-urlencode 'query=continux_cutover_duration_seconds' \
  | tee "${EVIDENCE_DIR}/05-vm-duration.json"

curl -fsSG 'http://127.0.0.1:8428/api/v1/query' \
  --data-urlencode 'query=continux_query_errors_total' \
  | tee "${EVIDENCE_DIR}/05-vm-query-errors.json"
```

Dashboard `cutover` phải có green ready, duration của lượt vừa chạy, query errors `0`. Dashboard `data-integrity` cho thấy public đã chuyển sang logic green. `Checksum mismatch = 1` sau swap có thể là kết quả mong đợi vì dashboard đang so public mang logic mới với view mang logic cũ.

### 4.8. Verify SQL, Iceberg Và Sức Khỏe Cluster

```bash
cd ~/continux

psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT COUNT(*) AS zones, COALESCE(SUM(trip_count), 0) AS trips FROM mv_zone_stats;"

psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT borough, SUM(trip_count) AS trips FROM mv_zone_stats GROUP BY borough ORDER BY trips DESC LIMIT 10;"

mc ls --recursive local/iceberg-data/nyc/zone_stats/ | head

bash scripts/k3s-check.sh
argocd app list --grpc-web
```

**Tiêu chí kết thúc lượt thực nghiệm:**

- `Nodes Ready = 3/3`, workloads còn `Available` sau replay.
- Argo CD không còn drift không giải thích được.
- Vector dừng ở `0 desired` sau replay.
- `mv_zone_stats` mang logic green sau swap, query errors `0`.
- Iceberg có data Parquet, equality-delete Parquet và position-delete Parquet trong `iceberg-data/nyc/zone_stats/`.

## 5. Dọn Dẹp Để Chạy Lại Từ Đầu

Mục đích: đưa trạng thái khi chạy về baseline blue sạch mà không phá hạ tầng, để lượt tiếp theo bắt đầu lại từ §4 (Bước "Chuẩn bị dataset"). Hành động cleanup nằm trong cluster (Redpanda topic, RisingWave object SQL, Iceberg prefix, metric cutover) và trên máy local (`data/raw/`, `.venv/`, file tạm).

> Cảnh báo: phần này xóa kết quả replay và cutover của lượt vừa chạy. Hãy chắc chắn evidence đã đủ trước khi dọn. Tài liệu này **không** xóa K3s cluster, Helm release, PVC, bucket MinIO, hoặc secret.

### 5.1. Thu Evidence Cuối Trước Cleanup

```bash
cd ~/continux

{
  date -Is
  kubectl get nodes -o wide
  argocd app list --grpc-web
  kubectl -n pipeline get deploy/vector -o wide
} | tee "${EVIDENCE_DIR}/06-before-cleanup-health.txt"

psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT name FROM rw_catalog.rw_materialized_views
   WHERE name IN ('mv_zone_stats_blue', 'mv_zone_stats', 'mv_zone_stats_green')
   ORDER BY name;
   SELECT 'public' AS view_name, COUNT(*) AS zones, COALESCE(SUM(trip_count),0) AS trips FROM mv_zone_stats
   UNION ALL
   SELECT 'blue', COUNT(*), COALESCE(SUM(trip_count),0) FROM mv_zone_stats_blue;" \
  | tee "${EVIDENCE_DIR}/06-before-cleanup-counts.txt"

curl -fsS http://127.0.0.1:9108/metrics \
  | grep -E '^continux_(mv_rows|mv_trips|green_ready|cutover|last_swap|query_errors)' \
  | tee "${EVIDENCE_DIR}/06-before-cleanup-metrics.txt"

mc ls --recursive local/iceberg-data/nyc/zone_stats/ | sed -n '1,50p' \
  | tee "${EVIDENCE_DIR}/06-before-cleanup-iceberg.txt"
```

### 5.2. Dừng Vector Và Xác Nhận

```bash
cd ~/continux

read -r -p "Nhập CLEAN-DEMO để xóa kết quả lượt này và sẵn sàng chạy lại: " CONFIRM
test "${CONFIRM}" = "CLEAN-DEMO"

kubectl --request-timeout=10s -n pipeline scale deploy/vector --replicas=0
kubectl -n pipeline wait --for=delete pod -l app=vector --timeout=120s || true
kubectl -n pipeline get deploy/vector \
  -o jsonpath='{.spec.replicas}{" desired\n"}' \
  | tee "${EVIDENCE_DIR}/06-vector-stopped.txt"
```

### 5.3. Xóa State Của Lượt Demo

```bash
cd ~/continux

psql -h localhost -p 4567 -d dev -U root <<'SQL' \
  | tee "${EVIDENCE_DIR}/06-drop-sql-state.txt"
DROP SINK IF EXISTS sink_zone_stats;
DROP MATERIALIZED VIEW IF EXISTS mv_zone_stats_green;
DROP MATERIALIZED VIEW IF EXISTS mv_zone_stats;
DROP MATERIALIZED VIEW IF EXISTS mv_zone_stats_blue;
DROP SOURCE IF EXISTS nyc_taxi_src;
DROP TABLE IF EXISTS tlc_zone;
SQL

{
  if kubectl -n redpanda exec redpanda-0 -c redpanda -- \
    rpk topic list --brokers "${BROKERS}" | grep -q 'nyc-taxi-events'; then
    kubectl -n redpanda exec redpanda-0 -c redpanda -- \
      rpk topic delete nyc-taxi-events --brokers "${BROKERS}"
  else
    echo "Topic nyc-taxi-events đã không tồn tại; tiếp tục tạo lại."
  fi
} | tee "${EVIDENCE_DIR}/06-topic-delete.txt"

argocd app sync redpanda-topics --grpc-web
argocd app wait redpanda-topics --health --sync --grpc-web

mc rm --recursive --force local/iceberg-data/nyc/zone_stats/ \
  | tee "${EVIDENCE_DIR}/06-clear-iceberg.txt"

kubectl -n pipeline exec deploy/continux-metrics -- \
  rm -f /state/cutover.prom
```

### 5.4. Dựng Lại Baseline Blue

```bash
cd ~/continux

argocd app sync pipeline --grpc-web
argocd app wait pipeline --health --sync --grpc-web

sleep 20

bash scripts/k3s-check.sh overview \
  | tee "${EVIDENCE_DIR}/06-clean-baseline-health.txt"

argocd app list --grpc-web \
  | tee "${EVIDENCE_DIR}/06-clean-baseline-apps.txt"

kubectl -n pipeline get deploy/vector \
  -o jsonpath='{.spec.replicas}{" desired\n"}' \
  | tee "${EVIDENCE_DIR}/06-clean-baseline-vector.txt"

kubectl -n redpanda exec redpanda-0 -c redpanda -- \
  rpk topic describe nyc-taxi-events --brokers "${BROKERS}" \
  | tee "${EVIDENCE_DIR}/06-clean-baseline-topic.txt"

psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT COUNT(*) AS tlc_zone_rows FROM tlc_zone;
   SELECT 'public' AS view_name, COUNT(*) AS zones, COALESCE(SUM(trip_count),0) AS trips FROM mv_zone_stats
   UNION ALL
   SELECT 'blue', COUNT(*), COALESCE(SUM(trip_count),0) FROM mv_zone_stats_blue;
   SELECT COUNT(*) AS green_objects FROM rw_catalog.rw_materialized_views
     WHERE name = 'mv_zone_stats_green';" \
  | tee "${EVIDENCE_DIR}/06-clean-baseline-counts.txt"

curl -fsS http://127.0.0.1:9108/metrics \
  | grep -E '^continux_(cutover_duration_seconds|last_swap_timestamp_seconds|query_errors_total|green_ready)' \
  | tee "${EVIDENCE_DIR}/06-clean-baseline-metrics.txt"

if mc ls --recursive local/iceberg-data/nyc/zone_stats/ | grep -q '\.parquet$'; then
  echo "FAIL: cleanup vẫn còn file Parquet Iceberg." | tee "${EVIDENCE_DIR}/06-clean-baseline-iceberg.txt"
  exit 1
else
  echo "OK: cleanup đã loại bỏ tệp Parquet của lượt demo." | tee "${EVIDENCE_DIR}/06-clean-baseline-iceberg.txt"
fi
```

### 5.5. Xóa File Local Sinh Trong Lượt Chạy

Đưa checkout `~/continux` về hình dạng ban đầu của một repo vừa clone: không có dataset tải về và không có `.venv`. Evidence không mất vì đã được lưu ở `~/continux-demo-evidence/<RUN_ID>` ngoài repo.

> Cảnh báo: lệnh dưới đây xóa dataset local và virtual environment tạo tại §4.2. Chỉ chạy sau khi Vector đã dừng và evidence cần giữ đã nằm ngoài repo.

```bash
cd ~/continux

test "$PWD" = "$HOME/continux"
test "${EVIDENCE_DIR#"$PWD"/}" = "${EVIDENCE_DIR}"
test "${DATA_DIR}" = "$PWD/data/raw"

VECTOR_REPLICAS="$(
  kubectl -n pipeline get deploy/vector -o jsonpath='{.spec.replicas}'
)"
test "${VECTOR_REPLICAS}" = "0"

test -z "$(git ls-files -- data/raw .venv)"

read -r -p "Nhập CLEAN-LOCAL để xóa data/raw và .venv do demo tạo: " CONFIRM
test "${CONFIRM}" = "CLEAN-LOCAL"

deactivate 2>/dev/null || true
rm -rf -- "${DATA_DIR}" "$PWD/.venv"
rm -f -- /tmp/continux-demo-env.sh

test ! -e "${DATA_DIR}"
test ! -e "$PWD/.venv"

GIT_STATUS="$(git status --porcelain --untracked-files=all)"
printf '%s' "${GIT_STATUS}" | tee "${EVIDENCE_DIR}/06-git-after-local-cleanup.txt"
test -z "${GIT_STATUS}"
```

Các CSV taxi zone tải về ở `data/zone/` cũng được xóa nếu là file chưa theo dõi:

```bash
cd ~/continux

for generated_csv in \
  data/zone/taxi_zone_lookup.csv \
  data/zone/taxi_zone_lookup_risingwave.csv
do
  if [ -e "${generated_csv}" ] && ! git ls-files --error-unmatch -- "${generated_csv}" >/dev/null 2>&1; then
    rm -f -- "${generated_csv}"
  fi
done

GIT_STATUS="$(git status --porcelain --untracked-files=all)"
test -z "${GIT_STATUS}"
```

### 5.6. Checklist Runtime Đã Sạch

| Thứ tự | Điều kiện | Kết quả yêu cầu |
|--------|-----------|-----------------|
| 1 | Nodes và Argo CD apps | `Ready`, `Synced/Healthy` |
| 2 | Vector | `0 desired` |
| 3 | Redpanda topic | `nyc-taxi-events` tồn tại với `3` partition, `1` replica |
| 4 | Lookup baseline | `tlc_zone` có số dòng bằng Taxi Zone CSV vừa apply |
| 5 | Logic public/blue | `trips = 0` trong baseline mới |
| 6 | Logic green | `green_objects = 0` |
| 7 | Metric cutover hiện thời | duration, timestamp, query errors và green readiness bằng `0` |
| 8 | Đầu ra Iceberg | Không có tệp dữ liệu Parquet của lượt demo vừa dọn |
| 9 | Checkout local | Không có `data/raw/`, `.venv/`, hai CSV taxi zone tạm; `git status` rỗng |

Khi toàn bộ checklist đạt, trạng thái đã trở lại baseline sạch. Lịch sử metric cũ vẫn có thể xuất hiện trong Grafana do VictoriaMetrics lưu lịch sử bảy ngày; chọn khoảng thời gian của lượt mới để tránh nhầm lẫn.

Từ trạng thái này, lượt thực nghiệm tiếp theo bắt đầu lại từ **§4.1** (khai báo `RUN_ID` mới và terminal layout), tiếp tục **§4.2** (tải lại dataset). Không cần lặp lại §2 vì hạ tầng chưa thay đổi.

## 6. Troubleshooting

### 6.1. Vector Làm Máy Nóng Hoặc Replay Quá Nặng

Luôn dừng phát sự kiện trước:

```bash
kubectl --request-timeout=10s -n pipeline scale deploy/vector --replicas=0
kubectl -n pipeline logs -l app=vector --tail=200 2>/dev/null || true
kubectl -n pipeline wait --for=delete pod -l app=vector --timeout=120s || true
```

Sau đó giảm `rate_limit_num` hoặc `max_events` trong `config/vector/vector-config.yaml`, commit, push và sync lại app `vector`. Không tiếp tục replay cho tới khi cluster khỏe lại.

### 6.2. Pod `redpanda-configuration-*` Có Một Bản `Failed`

Nếu Redpanda StatefulSet Ready, console Ready và có một pod configuration mới `Succeeded`, pod configuration cũ `Failed` chỉ là dấu vết lịch sử của hook/configuration. Không dùng nó làm baseline lỗi chính.

```bash
kubectl -n redpanda get sts/redpanda deploy/redpanda-console
kubectl -n redpanda get pods | grep redpanda-configuration
```

### 6.3. Không Thấy Job Apply SQL Của Argo CD

`mv-apply-job` là hook, tức job chạy tại thời điểm sync rồi có thể được Argo CD xóa sau khi thành công. Xác nhận bằng catalog RisingWave thay vì yêu cầu Job vẫn còn:

```bash
psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT name FROM rw_catalog.rw_materialized_views
   WHERE name IN ('mv_zone_stats_blue', 'mv_zone_stats', 'mv_zone_stats_green')
   ORDER BY name;"
```

### 6.4. Thiếu Object SQL Pipeline

```bash
cd ~/continux

argocd app sync pipeline --grpc-web
argocd app wait pipeline --health --sync --grpc-web
argocd app get pipeline --grpc-web
```

Sau đó query lại `rw_catalog`.

### 6.5. Metrics Exporter Không Healthy

```bash
kubectl -n pipeline get pod,svc -l app=continux-metrics
kubectl -n pipeline logs deploy/continux-metrics --tail=100
kubectl -n observability describe vmservicescrape continux-metrics
```

Exporter serve `/metrics` bằng BusyBox `nc`.

### 6.6. VictoriaMetrics Chưa Thấy Metric Mới

Exporter render theo chu kỳ và VictoriaMetrics scrape định kỳ. Chờ ít nhất `20` giây rồi query lại:

```bash
sleep 20
curl -fsSG 'http://127.0.0.1:8428/api/v1/query' \
  --data-urlencode 'query=continux_exporter_up'
```

Kiểm tra selector:

```bash
kubectl -n pipeline get svc continux-metrics --show-labels
kubectl -n observability get vmservicescrape continux-metrics -o yaml
```

### 6.7. Không Reset Được Topic Hoặc Iceberg

Dừng demo ở trạng thái an toàn:

```bash
kubectl --request-timeout=10s -n pipeline scale deploy/vector --replicas=0
kubectl -n pipeline wait --for=delete pod -l app=vector --timeout=120s || true
```

Không bắt đầu replay nếu topic cũ hoặc đầu ra Iceberg cũ chưa được xử lý theo mục tiêu của lượt demo sạch.

### 6.8. Cần Phá Môi Trường

Không đặt lệnh reset trong luồng vận hành chính. Nếu thật sự cần reset cluster hoặc xóa K3s, đọc cảnh báo trong [SCRIPTS.md](./SCRIPTS.md) trước khi dùng `scripts/k3s-purge.sh`.
