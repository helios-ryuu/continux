# SETUP v1.0.0

Tài liệu này là runbook triển khai Continux từ máy sạch đến pipeline Data Lakehouse chạy end-to-end. Các lệnh được viết theo trình tự thực thi thực tế; khi lệnh phụ thuộc repo, luôn bắt đầu bằng `cd ~/continux`.

## 0. Topology, Biến Thay Thế Và Nguyên Tắc Secret

Topology chuẩn của `v1.0.0` gồm 3 K3s server qua Tailscale:

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

## 1. Phiên Bản Chuẩn

| Thành phần | Phiên bản |
|------------|-----------|
| Continux | `1.0.0` |
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

## 2. Chuẩn Bị OS

### 2.1. `imac`

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

### 2.2. `continux-vps`

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

### 2.3. `helios-pc` WSL

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

### 2.4. Firewall Khi Dùng UFW

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

## 3. Tailscale Và Kiểm Tra Kết Nối

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

## 4. Khởi Tạo K3s HA

### 4.1. Init Server #1 Trên `imac`

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

### 4.2. Join `continux-vps`

```bash
cd ~/continux

sudo bash scripts/k3s-install-server.sh <imac-tailscale-ip> <k3s-token> continux-vps edge
```

### 4.3. Join `helios-pc`

```bash
cd ~/continux

sudo bash scripts/k3s-install-server.sh <imac-tailscale-ip> <k3s-token> helios-pc quorum
sudo bash scripts/wsl-enable-shared-root.sh
```

### 4.4. Verify Cluster

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

## 5. Cài CLI Quản Trị

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

## 6. Argo CD, Cloudflare Tunnel Và GitOps

### 6.1. Cài Argo CD

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

### 6.2. Tạo Secret Cloudflare Tunnel

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

### 6.3. Đăng Nhập Argo CD Và Đăng Ký Repo

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

### 6.4. Sync Root App

```bash
cd ~/continux

kubectl apply -f gitops/apps/root-app.yaml
argocd app sync root-app --grpc-web
argocd app wait root-app --health --sync --grpc-web
argocd app list --grpc-web
```

## 7. Deploy MinIO, Redpanda Và RisingWave

### 7.1. Secrets

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

### 7.2. MinIO

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

### 7.3. Redpanda

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

### 7.4. RisingWave

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

## 8. Deploy VictoriaMetrics, Grafana Và Dashboard

### 8.1. VictoriaMetrics

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

### 8.2. Grafana

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

## 9. Tải Dataset, Convert JSONL Và Upload Taxi Zone Lookup

Chạy trên `imac`:

```bash
cd ~/continux

DATA_MONTH=2026-03
DATA_URL="https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_${DATA_MONTH}.parquet"
ZONE_URL="https://d37ci6vzurychx.cloudfront.net/misc/taxi_zone_lookup.csv"

mkdir -p data/raw data/zone
wget -c -O "data/raw/yellow_tripdata_${DATA_MONTH}.parquet" "${DATA_URL}"
wget -c -O data/zone/taxi_zone_lookup.csv "${ZONE_URL}"

{ printf 'location_id,borough,zone,service_zone\n'; tail -n +2 data/zone/taxi_zone_lookup.csv; } \
  > data/zone/taxi_zone_lookup_risingwave.csv

python3 -m venv .venv
. .venv/bin/activate
pip install --upgrade pip pyarrow

python scripts/partojsonl.py \
  "data/raw/yellow_tripdata_${DATA_MONTH}.parquet" \
  "data/raw/yellow_tripdata_${DATA_MONTH}.jsonl"
```

Kết quả đã xác nhận cho tháng `2026-03`: `3,952,451` dòng JSONL, file khoảng `450M`.

Upload lookup CSV:

```bash
cd ~/continux

mc alias set local http://127.0.0.1:9000 adminuser "${MINIO_ROOT_PASSWORD}"
mc cp data/zone/taxi_zone_lookup_risingwave.csv local/tlc-zone/taxi_zone_lookup.csv
mc ls local/tlc-zone
```

## 10. Sync Vector, Apply SQL, Bật Ingest Và Verify End-To-End

### 10.1. Sync Vector Ở Trạng Thái Dừng

```bash
cd ~/continux

kubectl kustomize config/vector | grep -E '0.55.0|/data/\*.jsonl|rate_limit_num|rate_limit_duration_secs|max_events|when_full|sizeLimit|memory:' -n

argocd app sync vector --grpc-web
argocd app wait vector --health --sync --grpc-web

kubectl --request-timeout=10s -n pipeline scale deploy/vector --replicas=0
kubectl -n pipeline get deploy/vector -o jsonpath='{.spec.replicas}{" desired\n"}'
```

Output mong đợi: `0 desired`.

### 10.2. Apply SQL Pipeline

```bash
cd ~/continux

argocd app sync pipeline --grpc-web
argocd app wait pipeline --health --sync --grpc-web
```

Hook `mv-apply-job` có thể bị xóa sau khi `Succeeded`; verify bằng catalog thay vì tìm Job còn tồn tại:

```bash
psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT 'table' AS kind, name FROM rw_catalog.rw_tables WHERE name = 'tlc_zone'
   UNION ALL
   SELECT 'source' AS kind, name FROM rw_catalog.rw_sources WHERE name = 'nyc_taxi_src'
   UNION ALL
   SELECT 'mv' AS kind, name FROM rw_catalog.rw_materialized_views WHERE name IN ('mv_zone_stats_blue', 'mv_zone_stats')
   UNION ALL
   SELECT 'sink' AS kind, name FROM rw_catalog.rw_sinks WHERE name = 'sink_zone_stats'
   ORDER BY kind, name;"

psql -h localhost -p 4567 -d dev -U root -c \
  "SELECT COUNT(*) AS tlc_zone_rows FROM tlc_zone;"
```

Output mong đợi: `tlc_zone_rows = 265`.

Không dùng `\dt public.*` hoặc `\dm public.*` để verify RisingWave trong bản này; query meta-command có pattern có thể sinh collation regex không tương thích.

### 10.3. Bật Ingest Thủ Công

```bash
cd ~/continux

kubectl -n pipeline scale deploy/vector --replicas=1
kubectl -n pipeline rollout status deploy/vector --timeout=300s
kubectl -n pipeline logs deploy/vector --tail=120
```

Dừng ingest khi đã đủ dữ liệu demo hoặc trước khi chuyển sang finalize:

```bash
kubectl --request-timeout=10s -n pipeline scale deploy/vector --replicas=0
kubectl -n pipeline wait --for=delete pod -l app=vector --timeout=120s || true
```

### 10.4. Verify SQL Và Iceberg

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

Baseline end-to-end đã xác nhận trước finalize:

```text
tlc_zone_rows = 265
mv_zone_stats = 260 rows
top boroughs: Manhattan, Queens, Brooklyn, Bronx, Unknown
Iceberg prefix có data Parquet, equality-delete Parquet và position-delete Parquet
Nodes Ready 3/3, PVC Bound 5/5, Workloads Ready 100%
```

## 11. Checklist Setup Hoàn Tất

- [x] `kubectl get nodes -o wide` có `imac`, `continux-vps`, `helios-pc` đều `Ready`.
- [x] `continux-vps` có taint `dedicated=edge:NoSchedule`.
- [x] `helios-pc` có taint `dedicated=quorum:NoSchedule`.
- [x] Argo CD đăng nhập được qua `<argocd-domain>` và repo GitHub đã đăng ký.
- [x] `root-app` và các app con cần thiết đã được tạo.
- [x] MinIO có bucket `rw-checkpoint`, `iceberg-data`, `tlc-zone`.
- [x] Redpanda topic `nyc-taxi-events` tồn tại.
- [x] RisingWave `SHOW CLUSTER` có 4 worker `RUNNING`.
- [x] Grafana đọc datasource VictoriaMetrics.
- [x] Vector mặc định ở `replicas=0` và chỉ scale thủ công khi replay.
- [x] `tlc_zone` có `265` dòng.
- [x] `mv_zone_stats` có dữ liệu sau ingest.
- [x] MinIO có object Iceberg trong `iceberg-data/nyc/zone_stats/`.

## 12. Troubleshooting Ngắn

### Pod `redpanda-configuration-*` Có Một Bản `Failed`

Nếu Redpanda StatefulSet Ready, console Ready và có một pod configuration mới `Succeeded`, pod configuration cũ `Failed` chỉ là dấu vết lịch sử của hook/configuration. Không dùng nó làm baseline lỗi chính.

```bash
kubectl -n redpanda get sts/redpanda deploy/redpanda-console
kubectl -n redpanda get pods | grep redpanda-configuration
```

### Vector Gây Tải Cao

```bash
kubectl --request-timeout=10s -n pipeline scale deploy/vector --replicas=0
kubectl -n pipeline logs deploy/vector --tail=200
```

Sau đó giảm `rate_limit_num` hoặc `max_events` trong `config/vector/vector-config.yaml`, commit, push và sync lại app `vector`.

### RisingWave Không Thấy Object SQL

```bash
cd ~/continux

argocd app sync pipeline --grpc-web
argocd app wait pipeline --health --sync --grpc-web
argocd app get pipeline --grpc-web
```

Verify lại bằng `rw_catalog`.

### Cần Phá Môi Trường

Không đặt lệnh reset trong luồng setup chính. Nếu thật sự cần reset hoặc xóa K3s, đọc cảnh báo trong [SCRIPTS.md](./SCRIPTS.md) trước khi dùng `scripts/k3s-purge.sh`.
