# SETUP

Dựng Continux từ máy sạch đến trạng thái hạ tầng sẵn sàng. Sau khi hoàn tất tài liệu này, hệ thống chưa tải bộ dữ liệu thực nghiệm và có thể chuyển thẳng sang [DEMO.md](./DEMO.md).

## 0. Bố Trí Hạ Tầng, Biến Thay Thế Và Nguyên Tắc Secret

Bố trí chuẩn gồm 3 K3s server qua Tailscale:

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

Tạo file `.env` riêng tư từ `.env.example`, điền giá trị thật và chỉ cho chủ file
đọc. Không in nội dung file này ra terminal, log hoặc bằng chứng:

```bash
cd ~/continux
chmod 600 .env
set -a
. ./.env
set +a
```

`CLOUDFLARE_TUNNEL_TOKEN` và `MINIO_ROOT_PASSWORD` là bắt buộc.
`GRAFANA_DOMAIN` và `ARGOCD_DOMAIN` chỉ dùng khi cần xác minh URL ngoài.

Nguyên tắc bảo mật:

- Không commit token, mật khẩu, kubeconfig, file `.env`, bộ dữ liệu lớn hoặc bằng chứng.
- Secret runtime tạo bằng `kubectl create secret ... --dry-run=client -o yaml | kubectl apply -f -`.
- Repo GitHub của dự án là public; Argo CD đọc repo mà không cần GitHub token.
- Domain Cloudflare chỉ dùng để truy cập từ ngoài. Bootstrap dùng port-forward nội bộ nên không phụ thuộc DNS public.

## 1. Phiên Bản Chuẩn Của Stack

| Thành phần | Phiên bản |
|------------|-----------|
| Continux | `2.1.1` |
| K3s | `v1.35.5+k3s1` |
| Helm | `v4.2.0` |
| Argo CD | app `v3.4.3`, chart `argo-cd` `9.5.17` |
| Tailscale | `v1.98.4` |
| Redpanda | app `v26.1.9`, chart `26.1.4` |
| RisingWave | app `v2.8.4`, chart `0.2.52` |
| Vector | `0.55.0-alpine` |
| VictoriaMetrics | app `v1.144.0`, chart `0.81.0` |
| Grafana | image `13.0.1-security-01`, chart `10.5.15` |
| MinIO | chart `5.4.0` |
| cloudflared | `2026.5.2` |

Phiên bản hệ thống Continux nằm trong file `VERSION` ở root repo.

### 1.1. Cấu Trúc Paper LaTeX

Bản paper song ngữ dùng cấu trúc LaTeX module:

| File/thư mục | Vai trò |
|--------------|---------|
| `paper/main_vi.tex` | Wrapper bản tiếng Việt, format `article` hai cột |
| `paper/main_en.tex` | Wrapper bản tiếng Anh, format `article` hai cột |
| `paper/src/vi/` | Nội dung từng section của paper tiếng Việt |
| `paper/src/en/` | Nội dung từng section của paper tiếng Anh |
| `paper/main_vi.pdf` | PDF tiếng Việt được build từ wrapper và module |
| `paper/main_en.pdf` | PDF tiếng Anh được build từ wrapper và module |

Khi chỉnh nội dung paper, sửa file trong `paper/src/<ngôn-ngữ>/` thay vì nhồi toàn bộ nội dung vào wrapper. Wrapper chỉ giữ preamble, thứ tự `\input{...}` và cấu hình layout. Nếu máy đã có TeX Live và `latexmk`, build lại PDF bằng:

```bash
cd ~/continux/paper
latexmk -pdf -interaction=nonstopmode main_vi.tex
latexmk -pdf -interaction=nonstopmode main_en.tex
```

Các artifact phụ của LaTeX trong `paper/` được ignore; chỉ commit `.tex`, `.bib`, figures và PDF cuối.

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

Khởi động lại WSL rồi chuẩn bị hệ điều hành:

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

#### 2.3.4. Xác Minh Cluster

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

Sau khi clone repo, chuẩn hóa host bằng script idempotent. Script chỉ cập nhật
CLI/symlink và không cài lại hoặc khởi động lại K3s.

Trên `imac`:

```bash
cd ~/continux
sudo bash scripts/host-update.sh admin
```

Trên `continux-vps`:

```bash
cd ~/continux
sudo bash scripts/host-update.sh server
```

Trên WSL `helios-pc`:

```bash
cd ~/continux
sudo bash scripts/host-update.sh wsl-server
```

Kiểm tra lại trên `imac`:

```bash
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
  --version 9.5.17 \
  -f config/argocd/helm-values.yaml

kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
```

#### 2.5.2. Tạo Secret Cloudflare Tunnel

```bash
cd ~/continux

kubectl -n argocd create secret generic cloudflare-tunnel-token \
  --from-literal=token="${CLOUDFLARE_TUNNEL_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -

```

Route Cloudflare cần trỏ về service nội bộ:

| Domain | Service nội bộ |
|--------|----------------|
| `<argocd-domain>` | `http://argocd-server.argocd:80` |
| `<grafana-domain>` | `http://grafana.observability:80` |

#### 2.5.3. Đăng Nhập Argo CD Qua Port-Forward Nội Bộ

Mở terminal riêng và giữ lệnh sau hoạt động:

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:80
```

Trong terminal khác:

```bash
cd ~/continux

ARGOCD_INITIAL_PASSWORD="$(
  kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath='{.data.password}' | base64 -d
)"

argocd login localhost:8080 \
  --username admin \
  --password "${ARGOCD_INITIAL_PASSWORD}" \
  --grpc-web \
  --plaintext \
  --skip-test-tls
```

Repo GitHub là public nên Argo CD tự clone khi sync app; không cần lưu GitHub
token trong Argo CD.

#### 2.5.4. Sync Root App

```bash
cd ~/continux

kubectl apply -f gitops/apps/root-app.yaml
argocd app sync root-app --grpc-web
argocd app wait root-app --health --sync --grpc-web
argocd app sync cloudflared --grpc-web
argocd app wait cloudflared --health --sync --grpc-web
kubectl -n argocd rollout status deploy/cloudflared --timeout=300s
argocd app list --grpc-web
```

### 2.6. Triển Khai MinIO, Redpanda Và RisingWave

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

helm upgrade --install minio minio/minio \
  --namespace minio \
  --version 5.4.0 \
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

helm upgrade --install redpanda redpanda/redpanda \
  --namespace redpanda --create-namespace \
  --version 26.1.4 \
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

helm upgrade --install risingwave risingwavelabs/risingwave \
  --namespace risingwave --create-namespace \
  --version 0.2.52 \
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

### 2.7. Triển Khai VictoriaMetrics, Grafana Và Dashboard

#### 2.7.1. VictoriaMetrics

```bash
cd ~/continux

helm repo add vm https://victoriametrics.github.io/helm-charts/
helm repo update

helm show crds vm/victoria-metrics-k8s-stack | kubectl apply -f - --server-side
kubectl wait --for condition=Established crd/vmagents.operator.victoriametrics.com --timeout=120s

helm upgrade --install victoria-metrics vm/victoria-metrics-k8s-stack \
  --namespace observability --create-namespace \
  --version 0.81.0 \
  -f config/victoria-metrics/helm-values.yaml

argocd app sync victoria-scrapes --grpc-web
argocd app wait victoria-scrapes --health --sync --grpc-web
```

#### 2.7.2. Grafana

```bash
cd ~/continux

helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

argocd app sync grafana-dashboards --grpc-web
argocd app wait grafana-dashboards --health --sync --grpc-web
kubectl -n observability get configmap continux-grafana-dashboards

helm upgrade --install grafana grafana/grafana \
  --namespace observability --create-namespace \
  --version 10.5.15 \
  -f config/grafana/helm-values.yaml

kubectl -n observability rollout status deploy/grafana --timeout=300s
kubectl -n observability get secret grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d && echo
```

Mở `https://<grafana-domain>`, đăng nhập `admin`, đổi mật khẩu và mở thư mục
`Continux`. Bốn dashboard trong `dashboards/*.json` được cấp phát duy nhất
bằng app `grafana-dashboards`.

#### 2.7.3. Metrics Exporter

```bash
cd ~/continux

argocd app sync metrics-exporter --grpc-web
argocd app wait metrics-exporter --health --sync --grpc-web

kubectl -n pipeline get deploy,pod,svc -l app=continux-metrics
kubectl -n observability get vmservicescrape continux-metrics
```

### 2.8. Đồng Bộ Vector Ở Trạng Thái Nền

Vector phải tồn tại để runner kiểm tra preflight, nhưng giữ `replicas=0` cho tới
khi replay bắt đầu:

```bash
cd ~/continux

argocd app sync vector --grpc-web
argocd app wait vector --health --sync --grpc-web

kubectl --request-timeout=10s -n pipeline scale deploy/vector --replicas=0
kubectl -n pipeline get deploy/vector \
  -o jsonpath='{.spec.replicas}{" desired\n"}'
```

### 2.9. Checklist Hạ Tầng Sẵn Sàng

- [x] `kubectl get nodes -o wide` có `imac`, `continux-vps`, `helios-pc` đều `Ready`.
- [x] `continux-vps` có taint `dedicated=edge:NoSchedule`.
- [x] `helios-pc` có taint `dedicated=quorum:NoSchedule`.
- [x] Argo CD đăng nhập được qua port-forward nội bộ; URL ngoài chỉ là bước xác minh tùy chọn.
- [x] `root-app` và các app con cần thiết đã được tạo.
- [x] MinIO có bucket `rw-checkpoint`, `iceberg-data`, `tlc-zone`.
- [x] Redpanda topic `nyc-taxi-events` tồn tại với `3` partition, `1` replica.
- [x] RisingWave `SHOW CLUSTER` có 4 worker `RUNNING`.
- [x] Grafana đọc datasource VictoriaMetrics.
- [x] Metrics exporter chạy và VictoriaMetrics scrape được `continux_exporter_up`.
- [x] App `grafana-dashboards` tạo ConfigMap `continux-grafana-dashboards`.
- [x] Vector mặc định ở `replicas=0`, profile `smoke=2 events/s`; benchmark chỉ chạy khi opt-in.
- [x] Chưa tải bộ dữ liệu cục bộ, chưa upload Taxi Zone CSV và chưa sync app `pipeline` cho lượt thực nghiệm.

Sau khi đạt checklist này, hệ thống đã sẵn sàng để chạy một lượt thực nghiệm
theo [DEMO.md](./DEMO.md).

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

Vector mặc định ở `replicas=0` khi không chạy thực nghiệm và chỉ được scale lên `1` khi replay. TOML trong `pipelines/vector/vector.toml` đọc `VECTOR_THROUGHPUT_EVENTS_PER_SEC`; trạng thái nền GitOps dùng profile `smoke=2 events/s`. Ba profile `benchmark-low`, `benchmark-medium`, `benchmark-high` tương ứng `1000`, `5000`, `10000 events/s` và chỉ dùng khi chọn rõ. Khi chạy, Vector đọc từng dòng từ `/data/*.jsonl`, tuần tự hóa event, gửi qua Kafka sink có giới hạn tốc độ và buffer vào Redpanda topic `nyc-taxi-events` (`partitions=3`, `replicas=1`, `retention.ms=86400000`).

### 3.4. Xử Lý Trong RisingWave

Các object SQL được pipeline khởi tạo:

| Object | Nguồn vào | Vai trò | Output |
|--------|-----------|---------|--------|
| `tlc_zone` | CSV trong MinIO | Bảng lookup tĩnh | `location_id -> borough, zone` |
| `nyc_taxi_src` | Redpanda topic | Source stream | Dòng taxi liên tục |
| `mv_zone_stats_blue` | Source + lookup | Logic trạng thái nền | Tổng hợp Blue |
| `mv_zone_stats` | Source + lookup | Tên public phục vụ query | Tổng hợp đang công bố |
| `mv_zone_stats_green` | Source + lookup, logic mới | Bản thử nghiệm cutover | Tổng hợp Green |
| `sink_zone_stats` | Public MV | Ghi lakehouse | Đầu ra Iceberg |

Một event taxi có `pu_location_id` được join với `tlc_zone.location_id`. Sau join, RisingWave gom nhóm theo `borough, zone` và cập nhật `trip_count`, `total_fare`, `avg_distance`.

### 3.5. Ghi Lakehouse Trên MinIO/Iceberg

MinIO phục vụ nhiều loại dữ liệu:

| Prefix/bucket | Dữ liệu | Nguồn ghi/đọc |
|---------------|---------|---------------|
| `tlc-zone/` | Taxi Zone CSV | Upload trước pipeline, RisingWave đọc |
| `rw-checkpoint/` | Trạng thái/checkpoint | RisingWave ghi và đọc |
| `iceberg-data/nyc/zone_stats/` | Iceberg table data/metadata | `sink_zone_stats` ghi |

Khi public MV thay đổi, sink ghi kết quả xuống Iceberg, sinh data Parquet, equality-delete Parquet, position-delete Parquet và metadata. Đây là bằng chứng pipeline không chỉ query được dữ liệu đang chạy, mà còn tạo ra đầu ra lakehouse kiểm chứng được trên lưu trữ đối tượng.

### 3.6. Quan Sát

`continux-metrics` query RisingWave catalog/MV theo chu kỳ và expose metrics tại `/metrics`:

| Metric | Mô tả đầu ra |
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

## Chuyển Sang Thực Nghiệm

Khi checklist hạ tầng đã đạt, tiếp tục với [DEMO.md](./DEMO.md). Bước đầu tiên
của lượt thực nghiệm là tạo `RUN_ID` mới và tải dataset; không cần lặp lại
thiết lập.
