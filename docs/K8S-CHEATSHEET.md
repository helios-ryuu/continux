# K8S CHEATSHEET — LỆNH VẬN HÀNH KUBERNETES

Tài liệu này tổng hợp các lệnh Kubernetes thường dùng trong quá trình quản trị, debug và vận hành cluster. Mặc định dùng `kubectl`; với K3s có thể thay bằng `k3s kubectl` nếu chưa cài `kubectl` riêng.

> Khuyến nghị: luôn kiểm tra context trước khi chạy lệnh thay đổi trạng thái, đặc biệt là `delete`, `drain`, `scale`, `rollout undo` và thao tác với PVC/PV.

---

## 0. Quy ước nhanh

| Ký hiệu | Ý nghĩa |
|---------|---------|
| `<ns>` | Namespace |
| `<pod>` | Tên Pod |
| `<deploy>` | Tên Deployment |
| `<sts>` | Tên StatefulSet |
| `<ds>` | Tên DaemonSet |
| `<svc>` | Tên Service |
| `<cm>` | Tên ConfigMap |
| `<secret>` | Tên Secret |
| `<node>` | Tên Node |
| `<container>` | Tên container trong Pod |
| `<file.yaml>` | Manifest Kubernetes |

Tất cả lệnh có `-n <ns>` chỉ tác động trong namespace đó. Nếu bỏ `-n`, `kubectl` dùng namespace mặc định của current context, thường là `default`.

---

## 1. Lệnh phổ biến hằng ngày

Phần này đặt các lệnh hay dùng nhất trước các nhóm phân loại chi tiết. Khi mới vào cluster, đi từ trên xuống dưới là có thể nắm nhanh: đang trỏ vào cluster nào, node có khỏe không, pod nào lỗi, service/storage có đủ không, rồi mới sửa hoặc apply.

### 1.1. Cách đọc một lệnh `kubectl`

| Thành phần | Ví dụ | Ý nghĩa |
|------------|-------|---------|
| Verb | `get`, `describe`, `logs`, `apply`, `delete` | Hành động muốn làm |
| Resource | `pods`, `deploy`, `svc`, `pvc`, `nodes` | Loại tài nguyên Kubernetes |
| Name | `vector`, `redpanda-0` | Tên tài nguyên cụ thể; bỏ qua nếu muốn liệt kê nhiều tài nguyên |
| Namespace | `-n pipeline` | Phạm vi thao tác; pod/service/deploy thường nằm trong namespace |
| Output | `-o wide`, `-o yaml`, `-o jsonpath=...` | Cách in kết quả: bảng rộng, YAML đầy đủ, hoặc chỉ một field |
| Safety | `--dry-run=client`, `kubectl diff` | Kiểm tra trước khi apply/delete/sửa |

Quy tắc đọc nhanh:

```bash
kubectl <verb> <resource>/<name> -n <ns> <flags>
```

Ví dụ:

```bash
kubectl describe pod/vector-abc123 -n pipeline
```

Nghĩa là: xem chi tiết Pod `vector-abc123` trong namespace `pipeline`, đặc biệt là Events, image, env, volume mount, node scheduling và lý do container chưa Ready.

### 1.2. Checklist nhanh khi vừa mở terminal

| Lệnh | Dùng khi nào | Cần nhìn gì |
|------|--------------|-------------|
| `kubectl config current-context` | Trước mọi thao tác | Đúng cluster/context chưa |
| `kubectl get nodes -o wide` | Kiểm tra nền cluster | `Ready`, đúng node name, đúng internal IP/Tailscale IP |
| `kubectl get pods -A -o wide` | Quét toàn bộ workload | Pod `Pending`, `CrashLoopBackOff`, `ImagePullBackOff`, `RESTARTS` tăng |
| `kubectl get events -A --sort-by=.lastTimestamp` | Khi có lỗi chưa rõ nguyên nhân | Warning mới nhất, lỗi scheduling, pull image, mount volume |
| `kubectl get deploy,sts,ds -A` | Xem workload chính | `READY` có bằng desired replica không |
| `kubectl get svc -A -o wide` | Kiểm tra endpoint nội bộ | Service có đúng type/port/cluster IP không |
| `kubectl get pvc -A` | Kiểm tra storage | PVC phải `Bound`, size/storageClass đúng |
| `kubectl top nodes` | Khi nghi thiếu CPU/RAM | Node nào gần cạn tài nguyên; cần metrics-server |
| `kubectl top pods -A` | Khi pod OOM hoặc chậm | Pod nào ăn CPU/RAM bất thường; cần metrics-server |

### 1.3. Debug Pod lỗi nhanh

| Mục tiêu | Lệnh | Cách hiểu |
|----------|------|-----------|
| Xem trạng thái pod | `kubectl get pod <pod> -n <ns> -o wide` | `STATUS`, `READY`, `RESTARTS`, node đang chạy |
| Xem nguyên nhân chi tiết | `kubectl describe pod <pod> -n <ns>` | Đọc từ dưới lên ở phần `Events` |
| Xem log hiện tại | `kubectl logs <pod> -n <ns> --tail=100` | Lỗi app/runtime gần nhất |
| Xem log container trước | `kubectl logs <pod> -n <ns> --previous --tail=100` | Hữu ích khi `CrashLoopBackOff` |
| Vào shell trong pod | `kubectl exec -it <pod> -n <ns> -- sh` | Kiểm tra file, env, DNS, network từ trong pod |
| Xem manifest thực tế | `kubectl get pod <pod> -n <ns> -o yaml` | So sánh spec thực tế với Git/Helm values |

### 1.4. Deploy và rollback an toàn

| Mục tiêu | Lệnh | Cách hiểu |
|----------|------|-----------|
| Xem diff trước khi apply | `kubectl diff -f <file.yaml>` | Thấy cluster sẽ đổi gì |
| Render Kustomize | `kubectl kustomize <dir>` | Kiểm tra YAML sinh ra trước khi apply |
| Apply manifest | `kubectl apply -f <file.yaml>` | Tạo/cập nhật tài nguyên khai báo |
| Chờ rollout | `kubectl rollout status deploy/<deploy> -n <ns>` | Chỉ xong khi Deployment Available |
| Xem lịch sử rollout | `kubectl rollout history deploy/<deploy> -n <ns>` | Biết các revision |
| Rollback | `kubectl rollout undo deploy/<deploy> -n <ns>` | Quay về revision trước |
| Scale thủ công | `kubectl scale deploy/<deploy> -n <ns> --replicas=<n>` | Hữu ích cho Vector hoặc workload test |

### 1.5. Lệnh rất dễ gây mất dữ liệu

Chỉ chạy khi đã đọc đúng context, namespace và object:

```bash
kubectl delete namespace <ns>
kubectl delete pvc <pvc> -n <ns>
kubectl delete pv <pv>
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
kubectl replace --force -f <file.yaml>
```

Trước các lệnh này nên chạy:

```bash
kubectl config current-context
kubectl get <resource> <name> -n <ns> -o wide
kubectl describe <resource> <name> -n <ns>
```

---

## 2. Kubeconfig, context và thông tin cluster

### 2.1. Kiểm tra phiên bản và cluster

```bash
kubectl version
kubectl version --client
kubectl version --short
kubectl cluster-info
kubectl cluster-info dump
kubectl api-resources
kubectl api-versions
```

### 2.2. Kiểm tra và đổi context

```bash
kubectl config current-context
kubectl config get-contexts
kubectl config view
kubectl config view --minify
kubectl config view --raw
kubectl config use-context <context>
kubectl config rename-context <old-context> <new-context>
kubectl config delete-context <context>
```

### 2.3. Đặt namespace mặc định

```bash
kubectl config set-context --current --namespace=<ns>
kubectl config set-context <context> --namespace=<ns>
```

### 2.4. Dùng kubeconfig khác

```bash
kubectl --kubeconfig ./kubeconfig get nodes
export KUBECONFIG=./kubeconfig
```

PowerShell:

```powershell
$env:KUBECONFIG = ".\kubeconfig"
kubectl get nodes
```

---

## 3. Xem nhanh tài nguyên

### 3.1. Toàn cluster

```bash
kubectl get nodes
kubectl get nodes -o wide
kubectl get namespaces
kubectl get ns
kubectl get pods -A
kubectl get all -A
kubectl get events -A
kubectl get events -A --field-selector type=Warning
```

### 3.2. Trong một namespace

```bash
kubectl get all -n <ns>
kubectl get pods -n <ns>
kubectl get deploy -n <ns>
kubectl get sts -n <ns>
kubectl get ds -n <ns>
kubectl get jobs -n <ns>
kubectl get cronjobs -n <ns>
kubectl get svc -n <ns>
kubectl get ingress -n <ns>
kubectl get cm -n <ns>
kubectl get secret -n <ns>
kubectl get pvc -n <ns>
```

### 3.3. Xem chi tiết

```bash
kubectl describe node <node>
kubectl describe pod <pod> -n <ns>
kubectl describe deploy <deploy> -n <ns>
kubectl describe svc <svc> -n <ns>
kubectl describe ingress <ingress> -n <ns>
kubectl describe pvc <pvc> -n <ns>
```

### 3.4. Xuất YAML, JSON và wide

```bash
kubectl get pod <pod> -n <ns> -o yaml
kubectl get deploy <deploy> -n <ns> -o json
kubectl get pods -n <ns> -o wide
kubectl get nodes -o wide
```

---

## 4. Namespace

```bash
kubectl create namespace <ns>
kubectl get namespaces
kubectl describe namespace <ns>
kubectl label namespace <ns> env=dev
kubectl annotate namespace <ns> owner=platform
kubectl delete namespace <ns>
```

Manifest namespace:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: example
```

```bash
kubectl apply -f namespace.yaml
```

---

## 5. Manifest, apply, diff và dry-run

### 5.1. Áp dụng manifest

```bash
kubectl apply -f <file.yaml>
kubectl apply -f ./manifests/
kubectl apply -f https://example.com/manifest.yaml
kubectl apply -k ./overlays/dev
kubectl apply -f <file.yaml> --server-side
```

### 5.2. Kiểm tra trước khi áp dụng

```bash
kubectl diff -f <file.yaml>
kubectl diff -k ./overlays/prod
kubectl apply -f <file.yaml> --dry-run=client
kubectl apply -f <file.yaml> --dry-run=server
kubectl apply -f <file.yaml> --validate=true
kubectl explain pod
kubectl explain pod.spec
kubectl explain deployment.spec.template.spec.containers
```

### 5.3. Xóa theo manifest

```bash
kubectl delete -f <file.yaml>
kubectl delete -f ./manifests/
kubectl delete -k ./overlays/dev
```

---

## 6. Pod

### 6.1. Xem Pod

```bash
kubectl get pods -n <ns>
kubectl get pods -n <ns> -o wide
kubectl get pod <pod> -n <ns> -o yaml
kubectl describe pod <pod> -n <ns>
```

### 6.2. Tạo Pod nhanh

```bash
kubectl run nginx --image=nginx:1.27 -n <ns>
kubectl run busybox --image=busybox:1.36 -n <ns> -- sleep 3600
kubectl run curl --image=curlimages/curl:8.20.0 -n <ns> -- sleep 3600
kubectl run nginx --image=nginx:1.27 -n <ns> --dry-run=client -o yaml > pod.yaml
```

### 6.3. Logs

```bash
kubectl logs <pod> -n <ns>
kubectl logs <pod> -n <ns> -f
kubectl logs <pod> -n <ns> --tail=100
kubectl logs <pod> -n <ns> --since=10m
kubectl logs <pod> -n <ns> --previous
kubectl logs <pod> -n <ns> -c <container>
kubectl logs deploy/<deploy> -n <ns>
kubectl logs sts/<sts> -n <ns>
kubectl logs -n <ns> -l app=<app> --tail=100
kubectl logs -n <ns> -l app=<app> -f --max-log-requests=10
```

### 6.4. Exec vào container

```bash
kubectl exec -it <pod> -n <ns> -- sh
kubectl exec -it <pod> -n <ns> -- bash
kubectl exec -it <pod> -n <ns> -c <container> -- sh
kubectl exec <pod> -n <ns> -- env
kubectl exec <pod> -n <ns> -- cat /etc/resolv.conf
```

### 6.5. Copy file ra/vào Pod

```bash
kubectl cp <ns>/<pod>:/path/in/pod ./local-file
kubectl cp ./local-file <ns>/<pod>:/path/in/pod
kubectl cp <ns>/<pod>:/path/in/pod ./local-file -c <container>
```

`kubectl cp` cần `tar` trong container. Nếu image quá tối giản không có `tar`, dùng `kubectl exec` với stream hoặc thêm debug container.

### 6.6. Port-forward

```bash
kubectl port-forward pod/<pod> -n <ns> 8080:80
kubectl port-forward svc/<svc> -n <ns> 8080:80
kubectl port-forward deploy/<deploy> -n <ns> 8080:80
kubectl port-forward -n <ns> svc/<svc> 127.0.0.1:8080:80
```

### 6.7. Xóa và restart Pod

```bash
kubectl delete pod <pod> -n <ns>
kubectl delete pod <pod> -n <ns> --grace-period=0 --force
kubectl delete pod -n <ns> -l app=<app>
```

Nếu Pod thuộc Deployment, StatefulSet hoặc DaemonSet, controller sẽ tạo lại Pod mới.

---

## 7. Deployment

### 7.1. Tạo và xem Deployment

```bash
kubectl create deployment <deploy> --image=nginx:1.27 -n <ns>
kubectl create deployment <deploy> --image=nginx:1.27 --replicas=3 -n <ns>
kubectl create deployment <deploy> --image=nginx:1.27 -n <ns> --dry-run=client -o yaml > deployment.yaml
kubectl get deploy -n <ns>
kubectl get deploy <deploy> -n <ns> -o wide
kubectl describe deploy <deploy> -n <ns>
kubectl get rs -n <ns>
kubectl get pods -n <ns> -l app=<app>
```

### 7.2. Scale và autoscale

```bash
kubectl scale deploy/<deploy> -n <ns> --replicas=3
kubectl scale deploy <deploy> -n <ns> --replicas=0
kubectl autoscale deploy/<deploy> -n <ns> --min=2 --max=10 --cpu-percent=70
```

### 7.3. Cập nhật image và rollout

```bash
kubectl set image deploy/<deploy> <container>=<image>:<tag> -n <ns>
kubectl rollout status deploy/<deploy> -n <ns>
kubectl rollout history deploy/<deploy> -n <ns>
kubectl rollout history deploy/<deploy> -n <ns> --revision=2
kubectl rollout undo deploy/<deploy> -n <ns>
kubectl rollout undo deploy/<deploy> -n <ns> --to-revision=2
kubectl rollout restart deploy/<deploy> -n <ns>
kubectl rollout pause deploy/<deploy> -n <ns>
kubectl rollout resume deploy/<deploy> -n <ns>
```

### 7.4. Sửa trực tiếp

```bash
kubectl edit deploy/<deploy> -n <ns>
kubectl patch deploy/<deploy> -n <ns> -p '{"spec":{"replicas":3}}'
kubectl annotate deploy/<deploy> -n <ns> kubernetes.io/change-cause="upgrade image"
```

---

## 8. StatefulSet

StatefulSet dùng cho workload cần identity ổn định, thứ tự rollout và PVC riêng từng replica: database, queue, storage service.

```bash
kubectl get sts -n <ns>
kubectl describe sts/<sts> -n <ns>
kubectl get pods -n <ns> -l app=<app>
kubectl scale sts/<sts> -n <ns> --replicas=3
kubectl rollout status sts/<sts> -n <ns>
kubectl rollout restart sts/<sts> -n <ns>
kubectl rollout history sts/<sts> -n <ns>
kubectl delete sts/<sts> -n <ns>
kubectl delete sts/<sts> -n <ns> --cascade=orphan
kubectl get pvc -n <ns>
kubectl describe pvc <pvc> -n <ns>
```

---

## 9. DaemonSet

DaemonSet chạy Pod trên mỗi node hoặc một nhóm node: log agent, network plugin, node exporter.

```bash
kubectl get ds -A
kubectl get ds -n <ns>
kubectl describe ds/<ds> -n <ns>
kubectl rollout status ds/<ds> -n <ns>
kubectl rollout restart ds/<ds> -n <ns>
kubectl rollout history ds/<ds> -n <ns>
kubectl delete ds/<ds> -n <ns>
kubectl get pods -n <ns> -l app=<app> -o wide
```

---

## 10. Job và CronJob

### 10.1. Job

```bash
kubectl create job <job> --image=busybox:1.36 -n <ns> -- echo hello
kubectl create job <job> --from=cronjob/<cronjob> -n <ns>
kubectl get jobs -n <ns>
kubectl describe job/<job> -n <ns>
kubectl logs job/<job> -n <ns>
kubectl delete job/<job> -n <ns>
```

### 10.2. CronJob

```bash
kubectl create cronjob <cronjob> --image=busybox:1.36 --schedule="*/5 * * * *" -n <ns> -- echo hello
kubectl get cronjobs -n <ns>
kubectl describe cronjob/<cronjob> -n <ns>
kubectl get jobs -n <ns>
kubectl delete cronjob/<cronjob> -n <ns>
kubectl patch cronjob/<cronjob> -n <ns> -p '{"spec":{"suspend":true}}'
kubectl patch cronjob/<cronjob> -n <ns> -p '{"spec":{"suspend":false}}'
```

---

## 11. Service và endpoint

### 11.1. Loại Service

| Type | Mục đích |
|------|----------|
| `ClusterIP` | Chỉ truy cập nội bộ cluster |
| `NodePort` | Mở port trên mỗi node |
| `LoadBalancer` | Tạo load balancer bên ngoài nếu cluster có provider |
| `ExternalName` | Alias DNS tới hostname ngoài cluster |

### 11.2. Tạo và kiểm tra Service

```bash
kubectl expose deploy/<deploy> -n <ns> --port=80 --target-port=8080
kubectl expose deploy/<deploy> -n <ns> --type=NodePort --port=80 --target-port=8080
kubectl expose pod/<pod> -n <ns> --port=80 --target-port=8080
kubectl get svc -n <ns>
kubectl get svc <svc> -n <ns> -o wide
kubectl describe svc/<svc> -n <ns>
kubectl get endpoints -n <ns>
kubectl get endpointslice -n <ns>
kubectl describe endpoints/<svc> -n <ns>
```

Nếu Service không có endpoint, kiểm tra selector:

```bash
kubectl get svc <svc> -n <ns> -o yaml
kubectl get pods -n <ns> --show-labels
kubectl get pods -n <ns> -l app=<app>
```

---

## 12. Ingress và Gateway API

### 12.1. Ingress

```bash
kubectl get ingress -A
kubectl get ingress -n <ns>
kubectl describe ingress/<ingress> -n <ns>
kubectl get ingress/<ingress> -n <ns> -o yaml
kubectl delete ingress/<ingress> -n <ns>
kubectl get pods -A | grep ingress
kubectl get svc -A | grep ingress
kubectl logs -n <ingress-namespace> deploy/<ingress-controller>
```

### 12.2. Gateway API nếu cluster có CRD

```bash
kubectl get gatewayclass
kubectl get gateway -A
kubectl get httproute -A
kubectl describe gateway/<gateway> -n <ns>
kubectl describe httproute/<route> -n <ns>
```

---

## 13. ConfigMap và Secret

### 13.1. ConfigMap

```bash
kubectl create configmap <cm> -n <ns> --from-literal=KEY=value
kubectl create configmap <cm> -n <ns> --from-file=app.conf
kubectl create configmap <cm> -n <ns> --from-env-file=.env
kubectl get cm -n <ns>
kubectl describe cm/<cm> -n <ns>
kubectl get cm/<cm> -n <ns> -o yaml
kubectl delete cm/<cm> -n <ns>
```

### 13.2. Secret

```bash
kubectl create secret generic <secret> -n <ns> --from-literal=password='change-me'
kubectl create secret generic <secret> -n <ns> --from-file=tls.key --from-file=tls.crt
kubectl create secret tls <secret> -n <ns> --cert=tls.crt --key=tls.key
kubectl create secret docker-registry <secret> -n <ns> \
  --docker-server=<registry> \
  --docker-username=<user> \
  --docker-password=<password>
kubectl get secret -n <ns>
kubectl describe secret/<secret> -n <ns>
kubectl delete secret/<secret> -n <ns>
kubectl get secret <secret> -n <ns> -o jsonpath='{.data.password}' | base64 -d
```

PowerShell:

```powershell
$value = kubectl get secret <secret> -n <ns> -o jsonpath="{.data.password}"
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($value))
```

> Secret mặc định chỉ được base64 encode, không phải mã hóa đầu-cuối. Không commit Secret thật vào git trừ khi đã dùng SealedSecret, SOPS hoặc cơ chế mã hóa phù hợp.

---

## 14. Storage: PV, PVC và StorageClass

### 14.1. Xem storage

```bash
kubectl get storageclass
kubectl get sc
kubectl describe sc/<storage-class>
kubectl get pv
kubectl describe pv/<pv>
kubectl get pvc -A
kubectl get pvc -n <ns>
kubectl describe pvc/<pvc> -n <ns>
```

### 14.2. Kiểm tra mount volume

```bash
kubectl describe pod/<pod> -n <ns>
kubectl exec -it <pod> -n <ns> -- df -h
kubectl exec -it <pod> -n <ns> -- mount
```

### 14.3. Resize PVC nếu StorageClass cho phép

```bash
kubectl patch pvc/<pvc> -n <ns> -p '{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'
kubectl get pvc/<pvc> -n <ns> -w
```

Trước khi xóa PV/PVC, kiểm tra `reclaimPolicy`:

```bash
kubectl get pv <pv> -o jsonpath='{.spec.persistentVolumeReclaimPolicy}'
kubectl delete pvc/<pvc> -n <ns>
kubectl delete pv/<pv>
```

---

## 15. Node operations

### 15.1. Xem node và Pod trên node

```bash
kubectl get nodes
kubectl get nodes -o wide
kubectl describe node/<node>
kubectl top nodes
kubectl get pods -A -o wide --field-selector spec.nodeName=<node>
```

### 15.2. Label và taint node

```bash
kubectl label node <node> role=data
kubectl label node <node> disk=ssd
kubectl label node <node> role-
kubectl get nodes --show-labels
kubectl taint node <node> dedicated=data:NoSchedule
kubectl taint node <node> dedicated=data:NoSchedule-
kubectl describe node/<node> | grep -i taint
```

### 15.3. Cordon, drain và uncordon

```bash
kubectl cordon <node>
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
kubectl uncordon <node>
kubectl get pdb -A
```

---

## 16. Label, annotation và selector

```bash
kubectl label pod/<pod> -n <ns> app=api
kubectl label deploy/<deploy> -n <ns> env=prod
kubectl label pod/<pod> -n <ns> app-
kubectl get pods -n <ns> --show-labels
kubectl get pods -n <ns> -l app=api
kubectl get pods -n <ns> -l 'app in (api,worker)'
kubectl get pods -n <ns> -l 'env!=prod'
kubectl annotate pod/<pod> -n <ns> owner=platform
kubectl annotate deploy/<deploy> -n <ns> kubernetes.io/change-cause="change image"
kubectl annotate pod/<pod> -n <ns> owner-
```

---

## 17. Resource requests, limits và metrics

Metrics cần `metrics-server` hoặc hệ thống metrics tương đương.

```bash
kubectl describe pod/<pod> -n <ns>
kubectl get pod <pod> -n <ns> -o jsonpath='{.spec.containers[*].resources}'
kubectl top nodes
kubectl top pods -A
kubectl top pods -n <ns>
kubectl top pod <pod> -n <ns>
kubectl top pod <pod> -n <ns> --containers
kubectl get resourcequota -n <ns>
kubectl describe resourcequota/<quota> -n <ns>
kubectl get limitrange -n <ns>
kubectl describe limitrange/<limitrange> -n <ns>
```

---

## 18. Debug và troubleshooting

### 18.1. Quy trình debug Pod lỗi

```bash
kubectl get pod <pod> -n <ns> -o wide
kubectl describe pod <pod> -n <ns>
kubectl logs <pod> -n <ns> --previous
kubectl logs <pod> -n <ns> -c <container> --previous
kubectl get events -n <ns> --sort-by=.lastTimestamp
kubectl get pod <pod> -n <ns> -o yaml
```

### 18.2. Debug bằng ephemeral container

```bash
kubectl debug -it pod/<pod> -n <ns> --image=busybox:1.36 --target=<container>
kubectl debug -it pod/<pod> -n <ns> --image=nicolaka/netshoot --target=<container>
```

### 18.3. Tạo Pod debug riêng

```bash
kubectl run debug -n <ns> --image=nicolaka/netshoot -it --rm -- bash
kubectl run curl -n <ns> --image=curlimages/curl:8.20.0 -it --rm -- sh
kubectl run busybox -n <ns> --image=busybox:1.36 -it --rm -- sh
```

### 18.4. Debug DNS

```bash
kubectl run dns-test -n <ns> --image=busybox:1.36 -it --rm -- nslookup kubernetes.default
kubectl run dns-test -n <ns> --image=busybox:1.36 -it --rm -- nslookup <svc>.<ns>.svc.cluster.local
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns
```

### 18.5. Debug network

```bash
kubectl run netshoot -n <ns> --image=nicolaka/netshoot -it --rm -- bash
curl -v http://<svc>.<ns>.svc.cluster.local:<port>
dig <svc>.<ns>.svc.cluster.local
nc -vz <host> <port>
```

### 18.6. Pod Pending

```bash
kubectl describe pod/<pod> -n <ns>
kubectl get events -n <ns> --sort-by=.lastTimestamp
kubectl describe node/<node>
kubectl get pvc -n <ns>
kubectl get quota -n <ns>
```

Nguyên nhân thường gặp: thiếu CPU/RAM, PVC chưa bound, node selector sai, taint chưa có toleration, thiếu image pull secret hoặc hết quota.

### 18.7. CrashLoopBackOff

```bash
kubectl describe pod/<pod> -n <ns>
kubectl logs <pod> -n <ns> --previous
kubectl logs <pod> -n <ns> -c <container> --previous
kubectl get pod <pod> -n <ns> -o jsonpath='{.status.containerStatuses[*].lastState}'
```

### 18.8. ImagePullBackOff

```bash
kubectl describe pod/<pod> -n <ns>
kubectl get secret -n <ns>
kubectl get pod <pod> -n <ns> -o jsonpath='{.spec.imagePullSecrets}'
kubectl get events -n <ns> --sort-by=.lastTimestamp
```

---

## 19. Events

```bash
kubectl get events -A
kubectl get events -n <ns>
kubectl get events -n <ns> --sort-by=.lastTimestamp
kubectl get events -n <ns> --field-selector involvedObject.name=<pod>
kubectl get events -A --field-selector type=Warning
kubectl get events -n <ns> --watch
```

---

## 20. RBAC và ServiceAccount

### 20.1. ServiceAccount

```bash
kubectl create serviceaccount <sa> -n <ns>
kubectl get serviceaccount -n <ns>
kubectl describe serviceaccount/<sa> -n <ns>
kubectl delete serviceaccount/<sa> -n <ns>
```

### 20.2. Role, RoleBinding, ClusterRole

```bash
kubectl create role <role> -n <ns> --verb=get,list,watch --resource=pods
kubectl create rolebinding <binding> -n <ns> --role=<role> --serviceaccount=<ns>:<sa>
kubectl create clusterrole <role> --verb=get,list,watch --resource=nodes
kubectl create clusterrolebinding <binding> --clusterrole=<role> --serviceaccount=<ns>:<sa>
kubectl get role,rolebinding -n <ns>
kubectl get clusterrole,clusterrolebinding
kubectl describe role/<role> -n <ns>
kubectl describe rolebinding/<binding> -n <ns>
kubectl describe clusterrole/<role>
kubectl describe clusterrolebinding/<binding>
```

### 20.3. Kiểm tra quyền

```bash
kubectl auth can-i get pods -n <ns>
kubectl auth can-i create deployments -n <ns>
kubectl auth can-i '*' '*' --all-namespaces
kubectl auth can-i get pods -n <ns> --as=system:serviceaccount:<ns>:<sa>
kubectl auth can-i list nodes --as=<user>
```

---

## 21. NetworkPolicy

```bash
kubectl get networkpolicy -A
kubectl get netpol -n <ns>
kubectl describe netpol/<policy> -n <ns>
kubectl delete netpol/<policy> -n <ns>
```

NetworkPolicy chỉ có tác dụng khi CNI của cluster hỗ trợ enforcement. Nếu apply policy nhưng traffic vẫn đi qua, kiểm tra CNI đang dùng.

---

## 22. Autoscaling

```bash
kubectl autoscale deploy/<deploy> -n <ns> --min=2 --max=10 --cpu-percent=70
kubectl get hpa -n <ns>
kubectl describe hpa/<hpa> -n <ns>
kubectl delete hpa/<hpa> -n <ns>
kubectl get deploy/<deploy> -n <ns> -o jsonpath='{.spec.replicas}'
kubectl get deploy/<deploy> -n <ns> -o jsonpath='{.status.availableReplicas}'
```

---

## 23. CRD và custom resource

```bash
kubectl get crd
kubectl describe crd/<crd-name>
kubectl get <custom-resource> -A
kubectl get <custom-resource> -n <ns>
kubectl describe <custom-resource>/<name> -n <ns>
kubectl explain <custom-resource>.spec
kubectl delete <custom-resource>/<name> -n <ns>
```

Ví dụ với ArgoCD:

```bash
kubectl get applications -n argocd
kubectl describe application/<app> -n argocd
```

---

## 24. JSONPath, custom-columns và sort

```bash
kubectl get pods -n <ns> -o jsonpath='{.items[*].metadata.name}'
kubectl get pod <pod> -n <ns> -o jsonpath='{.status.podIP}'
kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'
kubectl get secret <secret> -n <ns> -o jsonpath='{.data.password}'
kubectl get pods -n <ns> -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,PHASE:.status.phase
kubectl get nodes -o custom-columns=NAME:.metadata.name,CPU:.status.capacity.cpu,MEM:.status.capacity.memory
kubectl get pods -n <ns> --sort-by=.metadata.creationTimestamp
kubectl get events -n <ns> --sort-by=.lastTimestamp
kubectl get pods -A --sort-by=.status.startTime
```

---

## 25. Patch nhanh

### 25.1. Strategic merge patch

```bash
kubectl patch deploy/<deploy> -n <ns> -p '{"spec":{"replicas":3}}'
```

### 25.2. JSON patch

```bash
kubectl patch deploy/<deploy> -n <ns> --type=json \
  -p='[{"op":"replace","path":"/spec/replicas","value":3}]'
```

### 25.3. Merge patch

```bash
kubectl patch svc/<svc> -n <ns> --type=merge \
  -p '{"spec":{"type":"NodePort"}}'
```

---

## 26. Kustomize

```bash
kubectl kustomize ./base
kubectl kustomize ./overlays/dev
kubectl apply -k ./overlays/dev
kubectl diff -k ./overlays/prod
kubectl delete -k ./overlays/dev
```

---

## 27. Helm

Helm không phải `kubectl`, nhưng thường dùng để cài ứng dụng vào Kubernetes.

### 27.1. Repo và chart

```bash
helm repo add <repo> <url>
helm repo update
helm search repo <keyword>
helm show values <repo>/<chart>
helm pull <repo>/<chart>
helm pull <repo>/<chart> --untar
```

### 27.2. Install, upgrade và rollback

```bash
helm install <release> <repo>/<chart> -n <ns> --create-namespace
helm install <release> ./chart -n <ns>
helm upgrade <release> <repo>/<chart> -n <ns>
helm upgrade --install <release> <repo>/<chart> -n <ns> --create-namespace
helm upgrade --install <release> <repo>/<chart> -n <ns> -f values.yaml
helm rollback <release> <revision> -n <ns>
helm uninstall <release> -n <ns>
```

### 27.3. Xem release

```bash
helm list -A
helm list -n <ns>
helm status <release> -n <ns>
helm history <release> -n <ns>
helm get values <release> -n <ns>
helm get manifest <release> -n <ns>
helm template <release> <repo>/<chart> -n <ns> -f values.yaml
```

---

## 28. K3s riêng cho dự án này

### 28.1. Kiểm tra K3s

```bash
sudo systemctl status k3s
sudo systemctl status k3s-agent
k3s --version
k3s kubectl get nodes
```

### 28.2. Kubeconfig K3s

```bash
sudo cat /etc/rancher/k3s/k3s.yaml
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown "$USER:$USER" ~/.kube/config
kubectl get nodes
```

### 28.3. Logs service K3s

```bash
sudo journalctl -u k3s -f
sudo journalctl -u k3s --since "1 hour ago"
sudo journalctl -u k3s-agent -f
sudo journalctl -u k3s-agent --since "1 hour ago"
```

### 28.4. Token join node

```bash
sudo cat /var/lib/rancher/k3s/server/node-token
```

### 28.5. CRI với K3s/containerd

```bash
sudo k3s crictl ps
sudo k3s crictl images
sudo k3s crictl logs <container-id>
sudo k3s crictl inspect <container-id>
```

---

## 29. Backup và restore liên quan Kubernetes

### 29.1. Export nhanh resource

```bash
kubectl get deploy/<deploy> -n <ns> -o yaml > deploy.yaml
kubectl get svc/<svc> -n <ns> -o yaml > svc.yaml
kubectl get cm/<cm> -n <ns> -o yaml > cm.yaml
kubectl get secret/<secret> -n <ns> -o yaml > secret.yaml
```

Trước khi commit manifest export từ cluster, nên loại bỏ các field runtime:

- `metadata.uid`
- `metadata.resourceVersion`
- `metadata.generation`
- `metadata.creationTimestamp`
- `metadata.managedFields`
- `status`

### 29.2. Backup etcd/K3s

Nếu K3s dùng embedded etcd:

```bash
sudo k3s etcd-snapshot save
sudo k3s etcd-snapshot ls
```

Kiểm tra cấu hình backup thực tế trong tài liệu SETUP của dự án trước khi restore.

---

## 30. Lệnh xóa cần thận trọng trong production

Các lệnh sau có thể gây downtime hoặc mất dữ liệu:

```bash
kubectl delete namespace <ns>
kubectl delete pvc/<pvc> -n <ns>
kubectl delete pv/<pv>
kubectl delete all --all -n <ns>
kubectl delete pod <pod> -n <ns> --grace-period=0 --force
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
```

Checklist trước khi chạy:

1. `kubectl config current-context`
2. `kubectl get ns`
3. `kubectl get all -n <ns>`
4. `kubectl get pvc -n <ns>`
5. `kubectl get pdb -A`
6. Có backup nếu thao tác liên quan storage.

---

## 31. Công thức debug nhanh theo triệu chứng

### 31.1. Pod không Ready

```bash
kubectl get pod <pod> -n <ns> -o wide
kubectl describe pod <pod> -n <ns>
kubectl logs <pod> -n <ns> --all-containers=true --tail=200
kubectl get events -n <ns> --sort-by=.lastTimestamp
```

### 31.2. Service không truy cập được

```bash
kubectl get svc <svc> -n <ns> -o yaml
kubectl get endpoints <svc> -n <ns>
kubectl get pods -n <ns> --show-labels
kubectl run curl -n <ns> --image=curlimages/curl:8.20.0 -it --rm -- sh
```

Trong Pod debug:

```bash
curl -v http://<svc>.<ns>.svc.cluster.local:<port>
nslookup <svc>.<ns>.svc.cluster.local
```

### 31.3. Ingress trả 404/502/503

```bash
kubectl describe ingress/<ingress> -n <ns>
kubectl get svc,endpoints -n <ns>
kubectl logs -n <ingress-namespace> deploy/<ingress-controller> --tail=200
kubectl get events -n <ns> --sort-by=.lastTimestamp
```

### 31.4. Rollout treo

```bash
kubectl rollout status deploy/<deploy> -n <ns>
kubectl describe deploy/<deploy> -n <ns>
kubectl get rs -n <ns>
kubectl get pods -n <ns> -l app=<app>
kubectl describe pod/<pod> -n <ns>
kubectl rollout undo deploy/<deploy> -n <ns>
```

### 31.5. Node NotReady

```bash
kubectl get nodes -o wide
kubectl describe node/<node>
kubectl get pods -A -o wide --field-selector spec.nodeName=<node>
kubectl get events -A --field-selector type=Warning
```

Trên node:

```bash
sudo systemctl status k3s
sudo systemctl status k3s-agent
sudo journalctl -u k3s --since "30 minutes ago"
sudo journalctl -u k3s-agent --since "30 minutes ago"
```

---

## 32. Alias hữu ích

Thêm vào shell profile nếu muốn thao tác nhanh:

```bash
alias k='kubectl'
alias kgp='kubectl get pods'
alias kga='kubectl get all'
alias kaf='kubectl apply -f'
alias kdf='kubectl delete -f'
alias kctx='kubectl config current-context'
```

PowerShell:

```powershell
Set-Alias k kubectl
function kgp { kubectl get pods @args }
function kga { kubectl get all @args }
function kaf { kubectl apply -f @args }
function kdf { kubectl delete -f @args }
```

---

## 33. Checklist trước và sau khi deploy

Trước deploy:

```bash
kubectl config current-context
kubectl diff -f <file.yaml>
kubectl apply -f <file.yaml> --dry-run=server
```

Deploy:

```bash
kubectl apply -f <file.yaml>
kubectl rollout status deploy/<deploy> -n <ns>
```

Sau deploy:

```bash
kubectl get pods -n <ns> -o wide
kubectl get svc,ingress -n <ns>
kubectl logs deploy/<deploy> -n <ns> --tail=100
kubectl get events -n <ns> --sort-by=.lastTimestamp
```

Rollback nếu cần:

```bash
kubectl rollout undo deploy/<deploy> -n <ns>
kubectl rollout status deploy/<deploy> -n <ns>
```
