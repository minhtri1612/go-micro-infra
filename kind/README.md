# Kind Setup (go-micro)

Chạy theo đúng thứ tự bên dưới để recreate lab sau reboot, theo chuẩn GitOps (Argo CD là source of truth).

## 0) Preconditions

- Repos: `~/Downloads/go-microservices/go-micro-infra`, `~/Downloads/go-microservices/go-micro-gitops`
- Contexts dùng: `kind-management`, `kind-dev`, `kind-staging`, `kind-prod`
- API host ports:
  - management: `127.0.0.1:33443`
  - dev: `127.0.0.1:30443`
  - staging: `127.0.0.1:32443`
  - prod: `127.0.0.1:31443`

---

## 1) Recreate 4 clusters

```bash
cd ~/Downloads/go-microservices/go-micro-infra

kind delete cluster --name management || true
kind delete cluster --name dev || true
kind delete cluster --name staging || true
kind delete cluster --name prod || true

kind create cluster --name management --config kind/management-kind-config.yaml
kubectl config use-context kind-management
kubectl config set-cluster kind-management --server=https://127.0.0.1:33443

helm repo add cilium https://helm.cilium.io 2>/dev/null || true
helm repo update
# Bắt buộc dùng cả 2 file: bootstrap override 2 thứ chưa có lúc này:
# 1) ServiceMonitor CRD chưa có (Prometheus Operator chưa cài) → nếu không tắt, Helm lỗi "no matches for kind ServiceMonitor"
# 2) clustermesh-apiserver service type NodePort thay vì LoadBalancer (MetalLB chưa cài) → nếu không override, Helm --wait treo chờ EXTERNAL-IP mãi
# Sau khi Argo sync monitoring (05) + metallb-management (18) + cilium-management, ArgoCD tự dùng cilium-values-management.yaml (ServiceMonitor bật, LoadBalancer + MetalLB IP tĩnh).
# → Đây là cách phòng ngừa deadlock bootstrap (node NotReady + monitoring Pending chờ nhau), không cần patch tay sau.
helm upgrade --install cilium cilium/cilium -n kube-system --create-namespace \
  --version 1.19.2 \
  -f cilium/cilium-values-management.yaml \
  -f cilium/cilium-values-management-bootstrap.yaml \
  --wait --timeout 10m

kind create cluster --name dev --config kind/dev-kind-config.yaml
kind create cluster --name staging --config kind/staging-kind-config.yaml
kind create cluster --name prod --config kind/prod-kind-config.yaml

kubectl config set-cluster kind-dev --server=https://127.0.0.1:30443
kubectl config set-cluster kind-staging --server=https://127.0.0.1:32443
kubectl config set-cluster kind-prod --server=https://127.0.0.1:31443
```

---

## 2) Install Argo CD on management

```bash
kubectl config use-context kind-management
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update
helm upgrade --install argocd argo/argo-cd -n argocd \
  --version 8.3.2 \
  -f kind/argocd-values.yaml \
  --wait --timeout 10m
kubectl -n argocd wait --for=condition=Ready pods --all --timeout=300s

# Tang timeout de tranh repo-server timeout khi render chart lon (vd kube-prometheus-stack)
kubectl --context kind-management -n argocd patch configmap argocd-cmd-params-cm --type merge -p '{"data":{"controller.repo.server.timeout.seconds":"180"}}'
kubectl --context kind-management -n argocd rollout restart deploy/argocd-repo-server
kubectl --context kind-management -n argocd rollout restart statefulset/argocd-application-controller
kubectl --context kind-management -n argocd rollout status deploy/argocd-repo-server --timeout=180s
kubectl --context kind-management -n argocd rollout status statefulset/argocd-application-controller --timeout=180s

kubectl -n argocd port-forward svc/argocd-server 8080:443
```

Terminal khác:

```bash
rm -rf ~/.argocd
PASS=$(kubectl --context kind-management -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
argocd login localhost:8080 --insecure --grpc-web --username admin --password "$PASS"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
# verify
argocd --grpc-web account get-user-info
```

### 2.1) Jenkins (management, tuỳ chọn)

Application: `argocd/bootstrap/22-jenkins-mgmt.yaml` → Service **`jenkins-management`** (không phải `jenkins`). Chưa có MetalLB thì `EXTERNAL-IP` trống là **bình thường** — dùng port-forward.

**Chỉ để mở UI trên laptop (đừng nhầm cổng):**

| Công cụ | URL trong trình duyệt | `port-forward` (ví dụ) |
|--------|-------------------------|-------------------------|
| **Argo CD** | **`http://localhost:8080`** | `8080:443` |
| **Jenkins** | **`http://localhost:8081`** | `8081:8080` |

**Jenkins không bao giờ mở bằng `localhost:8080`** — **8080 trên máy là Argo.** Phần **`8081:8080`** nghĩa là: máy bạn dùng cổng **8081**, còn số **8080** sau dấu hai chấm là **cổng của Jenkins trong cluster** (target của Service), không phải URL trên Chrome. Debug **bên trong pod** Jenkins (không phải trình duyệt) khi đó mới gọi process Jenkins qua cổng **8080** trong container.

**Mật khẩu đăng nhập Jenkins (port 8081 trên máy):** Cổng **8081 chỉ là port-forward** — **không “nằm ở” 8081, cũng không lưu password ở đó.** Lấy pass từ Secret **`jenkins-management`** / key **`jenkins-admin-password`** (lệnh trong block dưới). User: **`admin`**. Pass hiển thị trong Secret **có thể không khớp** PVC nếu đã đổi pass trên UI hoặc home cũ — xem khối **“Đăng nhập vẫn báo sai…”** ngay sau block bash.

Job mẫu **go-micro** (kết nối GitHub) được khai báo bằng **JCasC + Job DSL** trong `jenkins/jenkins-values.yaml` (`configScripts`); pipeline thật nằm ở **`Jenkinsfile`** ở root repo. Repo **private** cần thêm **credentials** trong JCasC + `remote { credentials('id') }` (không commit token).

> [!IMPORTANT]
> **Bắt buộc** trước khi deploy/sync Jenkins:
> 1. Secret `jenkins-internal-kubeconfig` (kubeconfig)
> 2. Secret `jenkins-ci-env` (Docker Hub + GitHub PAT cho pipeline — **không** dùng AWS key ESO)

```bash
kubectl config use-context kind-management
bash scripts/jenkins-generate-internal-kubeconfig.sh

# CI credentials (KHÁC ESO aws-credentials — xem scripts/jenkins-ci.env.example)
cp scripts/jenkins-ci.env.example scripts/jenkins-ci.env
# Sửa: DOCKERHUB_TOKEN = Hub Access Token; GITHUB_PAT = GitHub PAT
source scripts/jenkins-ci.env && bash scripts/jenkins-setup-ci-secrets.sh

kubectl apply -f argocd/bootstrap/22-jenkins-mgmt.yaml
argocd --grpc-web app sync jenkins-management && argocd --grpc-web app wait jenkins-management --sync --timeout 300
kubectl -n jenkins get svc,pods
# Jenkins: cổng máy 8081 (tránh đụng Argo 8080). Đăng nhập user admin + password lệnh dưới.
kubectl -n jenkins port-forward svc/jenkins-management 8081:8080
kubectl -n jenkins get secret jenkins-management -o jsonpath='{.data.jenkins-admin-password}' | base64 -d && echo
```


**Đăng nhập vẫn báo sai dù đã decode Secret đúng:** Jenkins không đọc pass trực tiếp từ Secret mỗi lần đăng nhập — pass thật nằm trong **`/var/jenkins_home`** (PVC). Secret chỉ khớp **lần khởi tạo đầu** (hoặc khi home trống). PVC cũ / đã đổi pass trên UI → hash trong PVC **lệch** Secret → decode Secret **không** vào được.

**Cách làm sạch lab (xóa home Jenkins — mất job/config trên volume):** scale StatefulSet về 0, xóa PVC, bật lại pod; bootstrap lại dùng pass trong Secret hiện tại.

Sau khi **xóa PVC**, init `jenkins-plugin-cli` tải lại toàn bộ plugin — trên Kind thường **15–30 phút** mới **Ready 2/2** (10 phút vẫn bình thường nếu vẫn `Init:0/1` / `0/2`). **Đừng dùng `wait --timeout=600s`** rồi tưởng hỏng; tăng timeout hoặc `get pods -w` tới khi **2/2 Running**.

```bash
kubectl -n jenkins scale statefulset jenkins-management --replicas=0
kubectl -n jenkins wait --for=delete pod/jenkins-management-0 --timeout=180s
kubectl -n jenkins delete pvc jenkins-management
kubectl -n jenkins scale statefulset jenkins-management --replicas=1
# Chờ Ready tối đa 40 phút (lần đầu sau wipe hay lâu hơn 10p):
kubectl -n jenkins wait --for=condition=ready pod/jenkins-management-0 --timeout=2400s
# Hoặc bỏ dòng wait, tự theo dõi:  kubectl -n jenkins get pods -w
kubectl -n jenkins get secret jenkins-management -o jsonpath='{.data.jenkins-admin-password}' | base64 -d && echo   # pass cho http://localhost:8081 — user admin
```

Pod **`Init:CrashLoopBackOff`**: thường do init tên **`init`** (cài plugin). Chart còn init **`config-reload-init`** (sidecar) — **không dùng `initContainers[0]`** (sẽ lộn sang sidecar, log sẽ là JSON “Starting collector”).

```bash
kubectl -n jenkins describe pod jenkins-management-0 | tail -50
kubectl -n jenkins logs jenkins-management-0 -c init --tail=100
kubectl -n jenkins logs jenkins-management-0 -c init --previous --tail=100
# --previous lỗi "not found" nếu sidecar chưa từng terminate — bỏ qua, chỉ cần -c init
```

Nếu vẫn crash: xem `describe` dòng **Last State: OOMKilled** — tăng `controller.initContainerResources` trong `jenkins/jenkins-values.yaml` (repo đã set sẵn limit RAM cho init).

Hay gặp: **version plugin không khớp image/chart** → init `jenkins-plugin-cli` fail (log kiểu `requires a greater version of Jenkins (2.479.x)`). Tăng **`controller.image.tag`** trong `jenkins/jenkins-values.yaml` cho ≥ version đó (repo đang pin **`2.479.3-lts-jdk17`** với chart `5.1.20`). Sau khi push + sync, xem `describe pod` / Events: nếu init vẫn **Pulling `jenkins:2.452.1-*`** thì pod cũ chưa lên spec mới — `kubectl -n jenkins delete pod jenkins-management-0 --wait=false` rồi đợi pod mới (init phải dùng cùng tag với main container). Vẫn CrashLoop / volume hỏng: xóa PVC `jenkins-management` trong `jenkins` (**mất home Jenkins**) rồi để Argo tạo lại.

**`app wait --health`**: Argo chỉ Healthy khi StatefulSet xong; Jenkins + plugin có thể Progressing lâu — đừng hard-code expect Healthy trong vài phút.

### 2.2) ArgoCD Rollout UI Extension (xem % traffic ngay trên Argo UI)

Để thấy tab **Rollout** trực tiếp trong ArgoCD (không cần mở dashboard riêng), cần cài UI extension vào `argocd-server`.

> [!NOTE]
> Chỉ thêm `extension.config` trong `argocd-cm` là chưa đủ; cần có initContainer tải `extension.tar` vào `/tmp/extensions`.

```bash
kubectl --context kind-management -n argocd patch configmap argocd-cm --type merge -p '{
  "data":{
    "extension.config":"extensions:\n  - name: rollout-extension\n    url: https://github.com/argoproj-labs/rollout-extension/releases/download/v0.3.7/extension.tar\n",
    "resource.customizations":"argoproj.io/Rollout:\n  ui.extensions: |\n    - name: rollout-extension\n"
  }
}'

kubectl --context kind-management -n argocd patch deployment argocd-server --type strategic -p '{
  "spec":{"template":{"spec":{
    "volumes":[{"name":"extensions","emptyDir":{}}],
    "initContainers":[
      {"name":"rollout-extension","image":"quay.io/argoprojlabs/argocd-extension-installer:v0.0.8",
       "env":[{"name":"EXTENSION_URL","value":"https://github.com/argoproj-labs/rollout-extension/releases/download/v0.3.7/extension.tar"}],
       "volumeMounts":[{"name":"extensions","mountPath":"/tmp/extensions/"}],
       "securityContext":{"runAsUser":1000,"allowPrivilegeEscalation":false}}
    ],
    "containers":[{"name":"server","volumeMounts":[{"name":"extensions","mountPath":"/tmp/extensions/"}]}]
  }}}
}'

kubectl --context kind-management -n argocd rollout status deploy/argocd-server --timeout=240s
kubectl --context kind-management -n argocd logs deploy/argocd-server -c rollout-extension --tail=50
```

Sau khi cài:

- Hard refresh Argo UI (`Ctrl+Shift+R`) hoặc mở private tab.
- Vào app -> bấm resource `Rollout` (icon `R`) -> sẽ có tab **Rollout**.
- Có thể soi `%` tại:
  - `status.currentWeight` (Rollout),
  - hoặc `TraefikService` weighted services (`stable/canary`).

### 2.3) Jenkins external quality gate (manual Promote/Rollback)

Pipeline `Jenkinsfile` đã hỗ trợ gate thủ công sau khi test pass:

- Gate hiển thị lựa chọn:
  - `Promote to stable`
  - `Rollback now`
- Khi fail và `AUTO_ABORT=false`, có thêm fail gate:
  - `Rollback now`
  - `Do nothing`

Để chắc chắn nút gate xuất hiện:

```text
PIPELINE_SCOPE=full
AUTO_PROMOTE=false
ENABLE_MANUAL_ROLLOUT_GATE=true
ROLLOUT_SERVICE=<service cụ thể, ví dụ product>   # tránh để auto khi DEP/BIZ = all
```

> [!IMPORTANT]
> Không dùng **Restart from stage: Promote Rollout** nếu muốn giữ đúng quy trình gate; thao tác này có thể bỏ qua phần test/gate trước đó. Hãy dùng `Build with Parameters` cho run mới.

---

## 3) Register dev/staging/prod clusters to Argo CD

```bash
cd ~/Downloads/go-microservices/go-micro-infra
kubectl --context kind-dev apply -f kind/dev-argocd-manager.yaml
kubectl --context kind-staging apply -f kind/staging-argocd-manager.yaml
kubectl --context kind-prod apply -f kind/prod-argocd-manager.yaml
sleep 5

DEV_TOKEN=$(kubectl --context kind-dev get secret argocd-manager-long-lived-token -n kube-system -o jsonpath='{.data.token}' | base64 -d)
STAGING_TOKEN=$(kubectl --context kind-staging get secret argocd-manager-long-lived-token -n kube-system -o jsonpath='{.data.token}' | base64 -d)
PROD_TOKEN=$(kubectl --context kind-prod get secret argocd-manager-long-lived-token -n kube-system -o jsonpath='{.data.token}' | base64 -d)

kubectl config use-context kind-management
DEV_IP=$(docker inspect dev-control-plane --format '{{.NetworkSettings.Networks.kind.IPAddress}}')
STAGING_IP=$(docker inspect staging-control-plane --format '{{.NetworkSettings.Networks.kind.IPAddress}}')
PROD_IP=$(docker inspect prod-control-plane --format '{{.NetworkSettings.Networks.kind.IPAddress}}')

kubectl create secret generic cluster-dev -n argocd \
  --from-literal=name=dev \
  --from-literal=server=https://$DEV_IP:6443 \
  --from-literal=config="{\"bearerToken\":\"$DEV_TOKEN\",\"tlsClientConfig\":{\"insecure\":true}}" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl label secret cluster-dev -n argocd argocd.argoproj.io/secret-type=cluster --overwrite

kubectl create secret generic cluster-staging -n argocd \
  --from-literal=name=staging \
  --from-literal=server=https://$STAGING_IP:6443 \
  --from-literal=config="{\"bearerToken\":\"$STAGING_TOKEN\",\"tlsClientConfig\":{\"insecure\":true}}" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl label secret cluster-staging -n argocd argocd.argoproj.io/secret-type=cluster --overwrite

kubectl create secret generic cluster-prod -n argocd \
  --from-literal=name=prod \
  --from-literal=server=https://$PROD_IP:6443 \
  --from-literal=config="{\"bearerToken\":\"$PROD_TOKEN\",\"tlsClientConfig\":{\"insecure\":true}}" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl label secret cluster-prod -n argocd argocd.argoproj.io/secret-type=cluster --overwrite
```

---

## 4) Bootstrap apps (golden order)

```bash
kubectl config use-context kind-management
cd ~/Downloads/go-microservices/go-micro-gitops

# repos (GitOps + Infra — bắt buộc cho multi-source Application)
argocd repo add https://github.com/minhtri1612/go-micro-gitops.git || true
argocd repo add https://github.com/minhtri1612/go-micro-infra.git || true
argocd repo add https://argoproj.github.io/argo-helm --type helm --name argo-helm || true
argocd repo add https://metallb.github.io/metallb --type helm --name metallb || true
argocd repo add https://helm.cilium.io/ --type helm --name cilium || true
argocd repo add https://helm.traefik.io/traefik --type helm --name traefik || true
argocd repo add https://charts.jenkins.io --type helm --name jenkins || true

# projects first
kubectl apply -f argocd/bootstrap/01-projects.yaml
argocd --grpc-web app sync argocd-projects
argocd proj list
sleep 3

# management monitoring first (CRDs baseline)
kubectl apply -f argocd/bootstrap/05-monitoring-mgmt.yaml
argocd --grpc-web app sync monitoring-management
argocd --grpc-web app wait monitoring-management --health --sync --timeout 300

# workload monitoring
kubectl apply -f argocd/bootstrap/06-monitoring-dev.yaml
kubectl apply -f argocd/bootstrap/07-monitoring-staging.yaml
kubectl apply -f argocd/bootstrap/08-monitoring-prod.yaml
argocd --grpc-web app terminate-op monitoring-dev || true
argocd --grpc-web app terminate-op monitoring-staging || true
argocd --grpc-web app terminate-op monitoring-prod || true
argocd --grpc-web app sync monitoring-dev
argocd --grpc-web app sync monitoring-staging
argocd --grpc-web app sync monitoring-prod
# Khong wait monitoring workload o day: monitoring-dev/staging/prod can node Ready (co CNI) moi
# schedule duoc pod, nhung node chua Ready vi Cilium chua len. Đây là điểm cực kỳ dễ gây DEADLOCK.

> [!IMPORTANT]
> **NẾU GẶP LỖI:** Node `NotReady` + Monitoring `Pending` + Cilium sync fail (thiếu ServiceMonitor CRD)
> Hãy chạy ngay block lệnh dưới đây để phá deadlock (đã test thành công):
> ```bash
> # 1. Patch tắt ServiceMonitor để Cilium không đòi CRD nữa
 for env in dev staging prod; do
   kubectl --context kind-management -n argocd patch application cilium-$env --type json -p='[{"op":"add","path":"/spec/sources/0/helm/valuesObject","value":{"hubble":{"metrics":{"serviceMonitor":{"enabled":false}}},"prometheus":{"serviceMonitor":{"enabled":false}},"operator":{"prometheus":{"serviceMonitor":{"enabled":false}}}}}]'
 done
> # 2. Sync Cilium trước để node lên Ready
 argocd --grpc-web app sync cilium-dev cilium-staging cilium-prod --grpc-web
 argocd --grpc-web app wait cilium-dev cilium-staging cilium-prod --health --timeout 600 --grpc-web
> # 3. Bây giờ mới sync Monitoring
 argocd --grpc-web app sync monitoring-dev monitoring-staging monitoring-prod --grpc-web
> ```

# cilium workload

# cilium workload
kubectl apply -f argocd/bootstrap/09-cilium-dev.yaml
kubectl apply -f argocd/bootstrap/10-cilium-staging.yaml
kubectl apply -f argocd/bootstrap/11-cilium-prod.yaml
sleep 3
argocd --grpc-web app terminate-op cilium-dev || true
argocd --grpc-web app terminate-op cilium-staging || true
argocd --grpc-web app terminate-op cilium-prod || true
argocd --grpc-web app sync cilium-dev
argocd --grpc-web app sync cilium-staging
argocd --grpc-web app sync cilium-prod

# cilium management
kubectl apply -f argocd/bootstrap/18-cilium-management.yaml
argocd --grpc-web app sync cilium-management

# metallb
kubectl apply -f argocd/bootstrap/15-metallb-dev.yaml
kubectl apply -f argocd/bootstrap/16-metallb-staging.yaml
kubectl apply -f argocd/bootstrap/17-metallb-prod.yaml
kubectl apply -f argocd/bootstrap/18-metallb-management.yaml
argocd --grpc-web app sync metallb-management
argocd --grpc-web app sync metallb-dev
argocd --grpc-web app sync metallb-staging
argocd --grpc-web app sync metallb-prod
argocd --grpc-web app wait metallb-management --health --sync --timeout 300
argocd --grpc-web app wait metallb-dev --health --sync --timeout 300
argocd --grpc-web app wait metallb-staging --health --sync --timeout 300
argocd --grpc-web app wait metallb-prod --health --sync --timeout 300

# sau khi MetalLB da cap EXTERNAL-IP cho clustermesh-apiserver, cho cilium on dinh
argocd --grpc-web app sync cilium-management
argocd --grpc-web app sync cilium-dev
argocd --grpc-web app sync cilium-staging
argocd --grpc-web app sync cilium-prod
argocd --grpc-web app wait cilium-management --health --sync --timeout 300
argocd --grpc-web app wait cilium-dev --health --sync --timeout 300
argocd --grpc-web app wait cilium-staging --health --sync --timeout 300
argocd --grpc-web app wait cilium-prod --health --sync --timeout 300


# rollouts + traefik
kubectl apply -f argocd/bootstrap/12-argo-rollouts-dev.yaml
kubectl apply -f argocd/bootstrap/13-argo-rollouts-staging.yaml
kubectl apply -f argocd/bootstrap/14-argo-rollouts-prod.yaml
kubectl apply -f argocd/bootstrap/19-traefik-dev.yaml
kubectl apply -f argocd/bootstrap/20-traefik-staging.yaml
kubectl apply -f argocd/bootstrap/21-traefik-prod.yaml
argocd --grpc-web app sync argo-rollouts-dev
argocd --grpc-web app sync argo-rollouts-staging
argocd --grpc-web app sync argo-rollouts-prod
argocd --grpc-web app sync traefik-dev
argocd --grpc-web app sync traefik-staging
argocd --grpc-web app sync traefik-prod

# microservices stacks
kubectl apply -f argocd/bootstrap/02-dev-microservices-stack.yaml
kubectl apply -f argocd/bootstrap/03-staging-microservices-stack.yaml
kubectl apply -f argocd/bootstrap/04-prod-microservices-stack.yaml
argocd --grpc-web app sync dev-microservices
argocd --grpc-web app sync staging-microservices
argocd --grpc-web app sync prod-microservices
```

### 4.1 Recovery nếu Cilium fail vì ServiceMonitor CRD

Binh thuong KHONG can patch tay. Neu gap loi hiem `could not find monitoring.coreos.com/ServiceMonitor`,
co the patch tam de unblock CNI roi sync lai:

```bash
kubectl --context kind-management -n argocd patch application cilium-dev --type json -p='[{"op":"add","path":"/spec/sources/0/helm/valuesObject","value":{"hubble":{"metrics":{"serviceMonitor":{"enabled":false}}},"prometheus":{"serviceMonitor":{"enabled":false}},"operator":{"prometheus":{"serviceMonitor":{"enabled":false}}}}}]'
kubectl --context kind-management -n argocd patch application cilium-staging --type json -p='[{"op":"add","path":"/spec/sources/0/helm/valuesObject","value":{"hubble":{"metrics":{"serviceMonitor":{"enabled":false}}},"prometheus":{"serviceMonitor":{"enabled":false}},"operator":{"prometheus":{"serviceMonitor":{"enabled":false}}}}}]'
kubectl --context kind-management -n argocd patch application cilium-prod --type json -p='[{"op":"add","path":"/spec/sources/0/helm/valuesObject","value":{"hubble":{"metrics":{"serviceMonitor":{"enabled":false}}},"prometheus":{"serviceMonitor":{"enabled":false}},"operator":{"prometheus":{"serviceMonitor":{"enabled":false}}}}}]'
argocd --grpc-web app sync cilium-dev
argocd --grpc-web app sync cilium-staging
argocd --grpc-web app sync cilium-prod
```

### 4.2 Recovery nhanh khi bi deadlock (node NotReady + monitoring Pending)

Trieu chung thuong gap:

- `kubectl --context kind-dev get nodes` -> `NotReady`
- `kps-wl-admission-create-*` o `monitoring` bi `Pending`
- `argocd app sync cilium-dev` fail voi loi thieu `ServiceMonitor` CRD

Nguyen nhan:

- Monitoring workload chua schedule duoc khi node chua co CNI
- Cilium workload lai bi chan boi `ServiceMonitor` CRD chua co
- Hai ben cho nhau -> deadlock bootstrap

Lenh pha deadlock (copy/chay):

```bash
# Patch tam tren 3 app Cilium workload de tat ServiceMonitor
kubectl --context kind-management -n argocd patch application cilium-dev --type json -p='[{"op":"add","path":"/spec/sources/0/helm/valuesObject","value":{"hubble":{"metrics":{"serviceMonitor":{"enabled":false}}},"prometheus":{"serviceMonitor":{"enabled":false}},"operator":{"prometheus":{"serviceMonitor":{"enabled":false}}}}}]'
kubectl --context kind-management -n argocd patch application cilium-staging --type json -p='[{"op":"add","path":"/spec/sources/0/helm/valuesObject","value":{"hubble":{"metrics":{"serviceMonitor":{"enabled":false}}},"prometheus":{"serviceMonitor":{"enabled":false}},"operator":{"prometheus":{"serviceMonitor":{"enabled":false}}}}}]'
kubectl --context kind-management -n argocd patch application cilium-prod --type json -p='[{"op":"add","path":"/spec/sources/0/helm/valuesObject","value":{"hubble":{"metrics":{"serviceMonitor":{"enabled":false}}},"prometheus":{"serviceMonitor":{"enabled":false}},"operator":{"prometheus":{"serviceMonitor":{"enabled":false}}}}}]'

# Sync Cilium truoc de node len Ready
argocd --grpc-web app sync cilium-dev
argocd --grpc-web app sync cilium-staging
argocd --grpc-web app sync cilium-prod
argocd --grpc-web app wait cilium-dev --health --sync --timeout 900
argocd --grpc-web app wait cilium-staging --health --sync --timeout 900
argocd --grpc-web app wait cilium-prod --health --sync --timeout 900

# Node da Ready thi sync lai monitoring
argocd --grpc-web app sync monitoring-dev
argocd --grpc-web app sync monitoring-staging
argocd --grpc-web app sync monitoring-prod
```

---

## 5) Monitoring remote_write sync

Chỉ chạy sau khi `monitoring-management` healthy.

```bash
cd ~/Downloads/go-microservices/go-micro-infra
chmod +x scripts/sync-monitoring-remote-write-url.sh
./scripts/sync-monitoring-remote-write-url.sh
kubectl --context kind-management -n monitoring wait --for=condition=Ready pod -l app.kubernetes.io/name=prometheus --timeout=600s
./scripts/sync-monitoring-remote-write-url.sh --check
./scripts/sync-monitoring-remote-write-url.sh --commit-push

argocd --grpc-web app sync monitoring-dev
argocd --grpc-web app sync monitoring-staging
argocd --grpc-web app sync monitoring-prod
```

---

## 6) Secrets cho database + backend (sau khi recreate cluster)

### 6.1 External Secrets Operator + AWS Secrets Manager (thay cho "ESO giả")

Dùng khi máy/cluster có egress ra AWS và bạn đã có secret JSON trên Secrets Manager (cùng keys như Terraform `modules/secrets`: `POSTGRES_*`, `DATABASE_URL`, `NEXTAUTH_SECRET`).

**Trên từng workload cluster** (`kind-dev`, `kind-staging`, `kind-prod`) - lặp lại với đúng `--context` và file values tương ứng:

1. Cài External Secrets Operator (**một lần trên mỗi** cluster `kind-dev`, `kind-staging`, `kind-prod`):

   Config Kind của repo dùng **Kubernetes 1.28** (`kindest/node:v1.28.0`). Chart ESO **>= 0.20.1** kèm CRD có `selectableFields` (chỉ hợp lệ từ K8s ~1.31+) -> `helm install` báo lỗi kiểu `.spec.versions[0].selectableFields: field not declared in schema` và **CRD không được cài** -> apply `ExternalSecret` sẽ lỗi `no matches for kind "ExternalSecret"`.

   **Cách xử lý:** ghim chart **0.19.2** (bản 0.20.1 trở lên cần K8s mới hơn). Nếu lần trước cài hỏng: `helm uninstall external-secrets -n external-secrets` trên context tương ứng, rồi cài lại.

   ```bash
   helm repo add external-secrets https://charts.external-secrets.io
   helm repo update

   for ctx in kind-dev kind-staging kind-prod; do
     helm upgrade --install external-secrets external-secrets/external-secrets \
       --version 0.19.2 \
       -n external-secrets --create-namespace \
       --kube-context "$ctx"
   done
   ```

   **Sau `helm install`, bắt buộc chờ pod ESO (webhook) Ready** rồi mới apply `ClusterSecretStore` / `ExternalSecret`. Nếu apply quá sớm, API server gọi validating webhook `external-secrets-webhook` trong khi pod chưa listen -> lỗi `connection refused` / `Internal error occurred: failed calling webhook`.

   ```bash
   for ctx in kind-dev kind-staging kind-prod; do
     kubectl --context "$ctx" -n external-secrets rollout status deployment/external-secrets-webhook --timeout=300s
     kubectl --context "$ctx" -n external-secrets wait --for=condition=Ready pods --all --timeout=300s
   done
   ```

   (Nếu tên deployment webhook khác: `kubectl --context kind-dev -n external-secrets get deploy`.)

   (Muốn dùng ESO mới nhất: nâng image Kind lên **>= 1.31** trong `kind/*-kind-config.yaml` rồi bỏ `--version`.)

2. Tạo `aws-credentials` trong namespace `external-secrets` **trên từng cluster**

   **Không bỏ bước này** dù bạn đã tạo secret **trên AWS Secrets Manager** (Terraform / console) từ trước:

  - Secret **trên AWS** (`go-micro/dev/app-credentials`, `go-micro/staging/app-credentials`, `go-micro/prod/app-credentials`) chứa JSON app (`DB_USER`, `DB_PASSWORD`, `PRODUCT_DB_NAME`, `INVENTORY_DB_NAME`, `ORDER_DB_NAME`, `NOTIFICATION_DB_NAME`, `PAYMENT_DB_NAME`) - đích mà **ExternalSecret** đồng bộ vào K8s.
   - Secret **`aws-credentials` trong cluster** chứa **Access key IAM** để **controller ESO** gọi API AWS (`GetSecretValue`). Không có nó (hoặc không có auth tương đương), ESO không đọc được AWS.

   IAM cần `secretsmanager:GetSecretValue` trên prefix secret của project (giống user ESO trong `terraform_secret` hoặc `terraform/modules/iam`).

   ```bash
   # paste key thật vào 2 biến này rồi chạy 1 lần
   AWS_ACCESS_KEY_ID='YOUR_AWS_ACCESS_KEY_ID'
   AWS_SECRET_ACCESS_KEY='YOUR_AWS_SECRET_ACCESS_KEY'

   for ctx in kind-dev kind-staging kind-prod; do
     kubectl --context "$ctx" -n external-secrets create secret generic aws-credentials \
       --from-literal=access-key-id="$AWS_ACCESS_KEY_ID" \
       --from-literal=secret-access-key="$AWS_SECRET_ACCESS_KEY" \
       --dry-run=client -o yaml | kubectl --context "$ctx" apply -f -
   done
   ```

   **Khuyen nghi (tranh nhap tay sai key): dong bo tu Terraform state**

   ```bash
   cd ~/Downloads/go-microservices/go-micro-infra/terraform_secret
   TF_AKID="$(terraform output -raw eso_access_key_id)"
   TF_SAK="$(terraform output -raw eso_secret_access_key)"

   for ctx in kind-dev kind-staging kind-prod; do
     kubectl --context "$ctx" -n external-secrets create secret generic aws-credentials \
       --from-literal=access-key-id="$TF_AKID" \
       --from-literal=secret-access-key="$TF_SAK" \
       --dry-run=client -o yaml | kubectl --context "$ctx" apply -f -
   done
   ```

   Force ESO reconcile ngay sau khi update credential:

   ```bash
   for ctx in kind-dev kind-staging kind-prod; do
     ns="microservices-${ctx#kind-}"
     kubectl --context "$ctx" -n "$ns" annotate externalsecret --all force-sync="$(date +%s)" --overwrite
   done
   ```

3. Tạo namespace đích đúng của `go-micro`:

```bash
for ctx in kind-dev kind-staging kind-prod; do
  env=${ctx#kind-}
  kubectl --context "$ctx" create namespace "databases-$env" --dry-run=client -o yaml | kubectl --context "$ctx" apply -f -
  kubectl --context "$ctx" create namespace "microservices-$env" --dry-run=client -o yaml | kubectl --context "$ctx" apply -f -
done
```

4. Apply `ClusterSecretStore` + `ExternalSecret` từ repo (từ thư mục gốc **go-micro-gitops**):

```bash
  cd ~/Downloads/go-microservices/go-micro-gitops

    # DEV
    helm template external-secrets external-secrets/applications \
      -f external-secrets/applications/values.yaml \
      -f config/base/config.yaml \
      -f config/env/dev.yaml \
      | kubectl --context kind-dev apply -f -

    # STAGING
    helm template external-secrets external-secrets/applications \
      -f external-secrets/applications/values.yaml \
      -f config/base/config.yaml \
      -f config/env/staging.yaml \
      | kubectl --context kind-staging apply -f -

    # PROD
    helm template external-secrets external-secrets/applications \
      -f external-secrets/applications/values.yaml \
      -f config/base/config.yaml \
      -f config/env/prod.yaml \
      | kubectl --context kind-prod apply -f -
```

5. Kiểm tra mapping ESO -> AWS Secret Manager trước khi sync app:

   ```bash
   # Verify AWS secret path từ file config của repo
   rg "remoteKey:" config/env/dev.yaml config/env/staging.yaml config/env/prod.yaml
   # expected:
   # go-micro/dev/app-credentials
   # go-micro/staging/app-credentials
   # go-micro/prod/app-credentials

   # Verify ExternalSecret đã render đúng remote key
   kubectl --context kind-dev -n microservices-dev get externalsecret go-micro-inventory-secrets-dev -o yaml | rg "key:|property:"
   ```

   Nếu `remoteKey` không đúng với secret bạn đã tạo trên AWS, sửa tại `config/env/*.yaml` rồi re-apply chart ESO.

6. Kiểm tra sync:

```bash
kubectl --context kind-dev get externalsecret,secret -n microservices-dev
kubectl --context kind-staging get externalsecret,secret -n microservices-staging
kubectl --context kind-prod get externalsecret,secret -n microservices-prod
```

**Lưu ý:** nếu `ExternalSecret` báo `SecretSyncedError`, kiểm tra lại:
- `external-secrets/aws-credentials` trên cluster (đúng access key/secret key chưa)
- secret path trên AWS có tồn tại đúng tên `go-micro/<env>/app-credentials` chưa
- JSON trong secret AWS có đủ các property được map trong `config/env/*.yaml` chưa

---

## 7) Fast checks

```bash
argocd proj list
argocd app list

kubectl --context kind-dev -n kube-system get pods -l k8s-app=cilium
kubectl --context kind-staging -n kube-system get pods -l k8s-app=cilium
kubectl --context kind-prod -n kube-system get pods -l k8s-app=cilium

kubectl --context kind-management -n monitoring get pods
kubectl --context kind-dev -n external-secrets get pods
kubectl --context kind-staging -n external-secrets get pods
kubectl --context kind-prod -n external-secrets get pods
```

---

## 8) ClusterMesh runbook (bat buoc doc)

### 8.1 Argo `Healthy` khong dong nghia ClusterMesh da noi

- `argocd app list` chi cho thay app/state resource.
- Kiem tra that bang:

```bash
for ctx in kind-management kind-dev kind-staging kind-prod; do
  echo "=== $ctx ==="
  cilium clustermesh status --context "$ctx"
done
```

### 8.2 Thu tu on dinh de tranh race: sync → script → verify

Dung thu tu nay de giam toi da race condition (Argo reconcile vs runtime cert patch):

```bash
# 1) Sync Cilium apps truoc (dua runtime ve dung Git)
argocd app sync cilium-management --grpc-web
argocd app sync cilium-dev --grpc-web
argocd app sync cilium-staging --grpc-web
argocd app sync cilium-prod --grpc-web
argocd app wait cilium-management --health --sync --timeout 600 --grpc-web
argocd app wait cilium-dev --health --sync --timeout 600 --grpc-web
argocd app wait cilium-staging --health --sync --timeout 600 --grpc-web
argocd app wait cilium-prod --health --sync --timeout 600 --grpc-web

# 2) Chay recovery script (CA bundle + restart)
cd ~/Downloads/go-microservices/go-micro-infra
./scripts/kind-clustermesh-sync-spoke-from-hub.sh

# 3) Verify
for ctx in kind-management kind-dev kind-staging kind-prod; do
  echo "=== $ctx ==="
  cilium clustermesh status --context "$ctx"
done
```

Neu van con loi sau buoc verify, KHONG restart tung context ngau nhien. Xu ly theo `8.3` / `8.8`.

### 8.3 Tai sao "chay script roi" van sai?

Thuong la do chay script khong dung bo cua repo hien tai, hoac chay script nhung khong sync lai ArgoCD theo thu tu.
Voi `go-micro`, dung dung bo script sau:

```bash
chmod +x scripts/kind-clustermesh-peer-ip.sh scripts/kind-clustermesh-sync-spoke-from-hub.sh
```

Luu y: script nay dong bo CA/cert, nhung neu endpoint peer trong secret `cilium-clustermesh` bi drift thi can them buoc fix endpoint (xem `8.8`).

### 8.4 Khi nao chi can `argocd app sync`?

Chi can sync khi ban da sua Git va khong co cert drift:

```bash
argocd app sync cilium-management --grpc-web
argocd app sync cilium-dev --grpc-web
argocd app sync cilium-staging --grpc-web
argocd app sync cilium-prod --grpc-web
```

### 8.5 Khi nao phai chay recovery script?

Chay recovery neu thay dau hieu:

- `KVStoreMesh ... 0/1 connected`
- `x509: certificate signed by unknown authority`
- Recreate cluster / doi IP LB / rotate cert

```bash
cd ~/Downloads/go-microservices/go-micro-infra
./scripts/kind-clustermesh-sync-spoke-from-hub.sh

argocd app sync cilium-management --grpc-web
argocd app sync cilium-dev --grpc-web
argocd app sync cilium-staging --grpc-web
argocd app sync cilium-prod --grpc-web
```

### 8.6 Secrets AWS sai co can ghi vao README khong?

Co. Do la loi hay gap nhat lam ESO fail:

- `ExternalSecret` ra `SecretSyncedError`
- Pod app bi `CreateContainerConfigError` vi missing secret

Da co runbook o muc `6.1` de:

- lay key dung tu Terraform output
- tao lai `external-secrets/aws-credentials`
- force ESO reconcile

### 8.7 Recovery ArgoCD `ComparisonError` sau reboot

Trieu chung thuong gap:

- `argocd app list` thay nhieu app `STATUS: Unknown`, `CONDITIONS: ComparisonError`
- `argocd app get <app>` co loi `dial tcp <argocd-repo-server-cluster-ip>:8081: connect: operation not permitted`
- `kubectl -n argocd get endpoints argocd-repo-server` ra rong

Nguyen nhan hay gap tren local Kind + Cilium:

- NetworkPolicy trong namespace `argocd` chan probe tu kubelet (node/host network) den `/healthz`
- `argocd-repo-server` hoac `argocd-application-controller` khong bao gio `Ready`
- Controller khong noi duoc repo-server => tat ca app thanh `ComparisonError`

Chan doan nhanh:

```bash
kubectl --context kind-management -n argocd get pods -o wide
kubectl --context kind-management -n argocd get endpoints argocd-repo-server -o wide
kubectl --context kind-management -n argocd describe pod -l app.kubernetes.io/name=argocd-repo-server | tail -20
kubectl --context kind-management -n argocd describe pod -l app.kubernetes.io/name=argocd-application-controller | tail -20
```

Neu thay readiness/liveness timeout den `:8084` (repo-server) hoac `:8082` (application-controller), fix nhanh cho local:

```bash
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update
helm upgrade --install argocd argo/argo-cd -n argocd \
  --version 8.3.2 \
  -f kind/argocd-values.yaml \
  --wait --timeout 10m

kubectl --context kind-management -n argocd rollout restart deploy/argocd-repo-server
kubectl --context kind-management -n argocd rollout restart statefulset/argocd-application-controller
kubectl --context kind-management -n argocd rollout restart deploy/argocd-notifications-controller
```

Clear cache `ComparisonError`:

```bash
argocd --grpc-web app list -o name | xargs -n1 argocd --grpc-web app get --hard-refresh >/tmp/argocd-refresh.log 2>&1 || true
argocd --grpc-web app list
```

### 8.8 Fix dut diem khi `KVStoreMesh connected` nhung `cilium-agent not connected`

Trieu chung:

- `cilium clustermesh status` tren spoke/management bao:
  - `KVStoreMesh ... connected`
  - nhung `cilium-xxxxx is not connected ... remote cluster configuration required but not found`
    hoac `Waiting for initial connection to be established`

Nguyen nhan goc hay gap:

- Secret `cilium-kvstoremesh` co endpoint remote DUNG (`https://dev.mesh.cilium.io:2379`, ...)
- Nhung secret `cilium-clustermesh` lai bi endpoint local (`https://clustermesh-apiserver.kube-system.svc:2379`)
- Cilium agent doc `cilium-clustermesh` -> quay vao local endpoint -> ket noi peer that bi ket

Fix runtime ngay (khong can hardcode cert/key vao Git):

```bash
for ctx in kind-management kind-dev kind-staging kind-prod; do
  echo "=== $ctx ==="
  keys=$(kubectl --context "$ctx" -n kube-system get secret cilium-kvstoremesh -o go-template='{{range $k,$v := .data}}{{printf "%s\n" $k}}{{end}}')
  while IFS= read -r k; do
    [ -z "$k" ] && continue
    v=$(kubectl --context "$ctx" -n kube-system get secret cilium-kvstoremesh -o jsonpath="{.data.$k}")
    kubectl --context "$ctx" -n kube-system patch secret cilium-clustermesh --type merge -p "{\"data\":{\"$k\":\"$v\"}}"
  done <<< "$keys"
done

for ctx in kind-management kind-dev kind-staging kind-prod; do
  kubectl --context "$ctx" -n kube-system rollout restart ds/cilium
  kubectl --context "$ctx" -n kube-system rollout status ds/cilium --timeout=300s
done
```

Verify lai:

```bash
for ctx in kind-management kind-dev kind-staging kind-prod; do
  echo "=== $ctx ==="
  cilium clustermesh status --context "$ctx"
done
```

Ky vong ket qua:

- management: `3/3 configured, 3/3 connected`
- dev/staging/prod: `1/1 configured, 1/1 connected`

---
```bash

echo "http://$(docker inspect management-control-plane --format '{{.NetworkSettings.Networks.kind.IPAddress}}'):32000"

```
