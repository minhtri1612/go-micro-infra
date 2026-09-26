# Kind Setup (go-micro)

Chạy theo đúng thứ tự bên dưới để recreate lab sau reboot, theo chuẩn GitOps (Argo CD là source of truth).

## 0) Preconditions

- Multi-repo: clone **`go-micro-infra`** (Kind/scripts) + **`go-micro-gitops`** (Argo bootstrap/apps)
- Contexts: `kind-management`, `kind-dev`, `kind-prod`
- Máy Kind: **Ubuntu / EC2** — chỉ cluster + Argo CD
- Jenkins: máy **khác**, `jenkins/` (docker compose). Không Helm, không Argo.
- Tool: `docker`, `kind`, `kubectl`, `helm`, `argocd`

> [!TIP]
> Neu tao EC2 bang stack trong `terraform/`, host da tu cai san tool. SSH vao may roi:
> ```bash
> go-micro-check-tools
> git clone https://github.com/minhtri1612/go-micro-infra.git ~/go-micro-infra
> git clone https://github.com/minhtri1612/go-micro-gitops.git ~/go-micro-gitops
> cd ~/go-micro-infra
> bash scripts/bootstrap-ubuntu-ec2-kind.sh
> ```

> [!IMPORTANT]
> README này da toi uu cho **Ubuntu / EC2** va chi dung **3 cluster**: `management`, `dev`, `prod`.
> **Khong dung staging**. CNI = kindnet. Ingress = Traefik NodePort. Khong Cilium, khong MetalLB.

---

## 1) Recreate 3 clusters

```bash
cd ~/Downloads/go-micro

kind delete cluster --name management || true
kind delete cluster --name dev || true
kind delete cluster --name prod || true

kind create cluster --name management --config kind/management-kind-config.yaml
kubectl config use-context kind-management
# Kind đôi khi ghi server=https://0.0.0.0:<port> → TLS fail; ép về 127.0.0.1.
kubectl config set-cluster kind-management --server=https://127.0.0.1:33443

kind create cluster --name dev --config kind/dev-kind-config.yaml
kind create cluster --name prod --config kind/prod-kind-config.yaml
kubectl config set-cluster kind-dev --server=https://127.0.0.1:30443
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

# NodePort 30443 -> EC2 :18080 (kind extraPortMappings). Khong port-forward.
kubectl --context kind-management -n argocd get svc argocd-server
```

UI: `https://<kind EIP>:18080` (SG :18080, IP nha). Cert tu ky.

Tren EC2:

```bash
rm -rf ~/.argocd
PASS=$(kubectl --context kind-management -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
argocd login localhost:18080 --insecure --grpc-web --username admin --password "$PASS"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
# verify
argocd --grpc-web account get-user-info
```

### 2.1) Jenkins — không nằm trên máy Kind

Jenkins dựng **trước / riêng**: `jenkins/docker-compose.yml` trên EC2 CI. Không Helm, không Argo Application, không port `18081`.

Xem `jenkins/README.md`. Argo CD: `https://<kind EIP>:18080` (NodePort, khong port-forward).

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

---

## 3) Register dev/prod clusters to Argo CD

```bash
kubectl --context kind-dev apply -f kind/dev-argocd-manager.yaml
kubectl --context kind-prod apply -f kind/prod-argocd-manager.yaml
sleep 5

DEV_TOKEN=$(kubectl --context kind-dev get secret argocd-manager-long-lived-token -n kube-system -o jsonpath='{.data.token}' | base64 -d)
PROD_TOKEN=$(kubectl --context kind-prod get secret argocd-manager-long-lived-token -n kube-system -o jsonpath='{.data.token}' | base64 -d)

kubectl config use-context kind-management
DEV_IP=$(docker inspect dev-control-plane --format '{{.NetworkSettings.Networks.kind.IPAddress}}')
PROD_IP=$(docker inspect prod-control-plane --format '{{.NetworkSettings.Networks.kind.IPAddress}}')

kubectl create secret generic cluster-dev -n argocd \
  --from-literal=name=dev \
  --from-literal=server=https://$DEV_IP:6443 \
  --from-literal=config="{\"bearerToken\":\"$DEV_TOKEN\",\"tlsClientConfig\":{\"insecure\":true}}" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl label secret cluster-dev -n argocd argocd.argoproj.io/secret-type=cluster --overwrite

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
GITOPS=~/go-micro-gitops
INFRA=~/go-micro-infra

# repos (apps + platform values; no Jenkins chart — CI on VPS)
argocd repo add https://github.com/minhtri1612/go-micro-gitops.git || true
argocd repo add https://github.com/minhtri1612/go-micro-infra.git || true
argocd repo add https://argoproj.github.io/argo-helm --type helm --name argo-helm || true
argocd repo add https://helm.traefik.io/traefik --type helm --name traefik || true
argocd repo add https://prometheus-community.github.io/helm-charts --type helm --name prometheus-community || true

# projects first (manifests live in gitops)
kubectl apply -f "$GITOPS/argocd/bootstrap/01-projects.yaml"
argocd --grpc-web app sync argocd-projects
argocd proj list
sleep 3

# management monitoring first (CRDs baseline)
kubectl apply -f "$GITOPS/argocd/bootstrap/05-monitoring-mgmt.yaml"
argocd --grpc-web app sync monitoring-management
argocd --grpc-web app wait monitoring-management --health --sync --timeout 300

# workload monitoring
kubectl apply -f "$GITOPS/argocd/bootstrap/06-monitoring-dev.yaml"
kubectl apply -f "$GITOPS/argocd/bootstrap/08-monitoring-prod.yaml"
argocd --grpc-web app terminate-op monitoring-dev || true
argocd --grpc-web app terminate-op monitoring-prod || true
argocd --grpc-web app sync monitoring-dev
argocd --grpc-web app sync monitoring-prod
argocd --grpc-web app wait monitoring-dev --health --sync --timeout 300 || true
argocd --grpc-web app wait monitoring-prod --health --sync --timeout 300 || true

# rollouts + traefik (NodePort, no MetalLB)
kubectl apply -f "$GITOPS/argocd/bootstrap/12-argo-rollouts-dev.yaml"
kubectl apply -f "$GITOPS/argocd/bootstrap/14-argo-rollouts-prod.yaml"
kubectl apply -f "$GITOPS/argocd/bootstrap/19-traefik-dev.yaml"
kubectl apply -f "$GITOPS/argocd/bootstrap/21-traefik-prod.yaml"
argocd --grpc-web app sync argo-rollouts-dev
argocd --grpc-web app sync argo-rollouts-prod
argocd --grpc-web app sync traefik-dev
argocd --grpc-web app sync traefik-prod

# microservices stacks
kubectl apply -f "$GITOPS/argocd/bootstrap/02-dev-microservices-stack.yaml"
kubectl apply -f "$GITOPS/argocd/bootstrap/04-prod-microservices-stack.yaml"
argocd --grpc-web app sync dev-microservices
argocd --grpc-web app sync prod-microservices
```

---

## 5) Monitoring remote_write sync

Chỉ chạy sau khi `monitoring-management` healthy.

```bash
cd ~/Downloads/go-micro
chmod +x scripts/sync-monitoring-remote-write-url.sh
./scripts/sync-monitoring-remote-write-url.sh
kubectl --context kind-management -n monitoring wait --for=condition=Ready pod -l app.kubernetes.io/name=prometheus --timeout=600s
./scripts/sync-monitoring-remote-write-url.sh --check
./scripts/sync-monitoring-remote-write-url.sh --commit-push

argocd --grpc-web app sync monitoring-dev
argocd --grpc-web app sync monitoring-prod
```

---

## 6) Secrets cho database + backend (sau khi recreate cluster)

### 6.1 External Secrets Operator + AWS Secrets Manager (thay cho "ESO giả")

Dùng khi máy/cluster có egress ra AWS và bạn đã có secret JSON trên Secrets Manager (cùng keys như Terraform `modules/secrets`: `POSTGRES_*`, `DATABASE_URL`, `NEXTAUTH_SECRET`).

**Trên từng workload cluster** (`kind-dev`, `kind-prod`) - lặp lại với đúng `--context` và file values tương ứng:

1. Cài External Secrets Operator (**một lần trên mỗi** cluster `kind-dev`, `kind-prod`):

   Config Kind của repo dùng **Kubernetes 1.28** (`kindest/node:v1.28.0`). Chart ESO **>= 0.20.1** kèm CRD có `selectableFields` (chỉ hợp lệ từ K8s ~1.31+) -> `helm install` báo lỗi kiểu `.spec.versions[0].selectableFields: field not declared in schema` và **CRD không được cài** -> apply `ExternalSecret` sẽ lỗi `no matches for kind "ExternalSecret"`.

   **Cách xử lý:** ghim chart **0.19.2** (bản 0.20.1 trở lên cần K8s mới hơn). Nếu lần trước cài hỏng: `helm uninstall external-secrets -n external-secrets` trên context tương ứng, rồi cài lại.

   ```bash
   helm repo add external-secrets https://charts.external-secrets.io
   helm repo update

   for ctx in kind-dev kind-prod; do
     helm upgrade --install external-secrets external-secrets/external-secrets \
       --version 0.19.2 \
       -n external-secrets --create-namespace \
       --kube-context "$ctx"
   done
   ```

   **Sau `helm install`, bắt buộc chờ pod ESO (webhook) Ready** rồi mới apply `ClusterSecretStore` / `ExternalSecret`. Nếu apply quá sớm, API server gọi validating webhook `external-secrets-webhook` trong khi pod chưa listen -> lỗi `connection refused` / `Internal error occurred: failed calling webhook`.

   ```bash
   for ctx in kind-dev kind-prod; do
     kubectl --context "$ctx" -n external-secrets rollout status deployment/external-secrets-webhook --timeout=300s
     kubectl --context "$ctx" -n external-secrets wait --for=condition=Ready pods --all --timeout=300s
   done
   ```

   (Nếu tên deployment webhook khác: `kubectl --context kind-dev -n external-secrets get deploy`.)

   (Muốn dùng ESO mới nhất: nâng image Kind lên **>= 1.31** trong `kind/*-kind-config.yaml` rồi bỏ `--version`.)

2. Tạo `aws-credentials` trong namespace `external-secrets` **trên từng cluster**

   **Không bỏ bước này** dù bạn đã tạo secret **trên AWS Secrets Manager** (Terraform / console) từ trước:

  - Secret **trên AWS** (`go-micro/dev/app-credentials`, `go-micro/prod/app-credentials`) chứa JSON app (`DB_USER`, `DB_PASSWORD`, `PRODUCT_DB_NAME`, `INVENTORY_DB_NAME`, `ORDER_DB_NAME`, `NOTIFICATION_DB_NAME`, `PAYMENT_DB_NAME`) - đích mà **ExternalSecret** đồng bộ vào K8s.
   - Secret **`aws-credentials` trong cluster** chứa **Access key IAM** để **controller ESO** gọi API AWS (`GetSecretValue`). Không có nó (hoặc không có auth tương đương), ESO không đọc được AWS.

   IAM cần `secretsmanager:GetSecretValue` trên prefix secret của project (IAM user ESO trong `terraform/environments/management`).

   ```bash
   # paste key thật vào 2 biến này rồi chạy 1 lần
   AWS_ACCESS_KEY_ID='YOUR_AWS_ACCESS_KEY_ID'
   AWS_SECRET_ACCESS_KEY='YOUR_AWS_SECRET_ACCESS_KEY'

   for ctx in kind-dev kind-prod; do
     kubectl --context "$ctx" -n external-secrets create secret generic aws-credentials \
       --from-literal=access-key-id="$AWS_ACCESS_KEY_ID" \
       --from-literal=secret-access-key="$AWS_SECRET_ACCESS_KEY" \
       --dry-run=client -o yaml | kubectl --context "$ctx" apply -f -
   done
   ```

   **Khuyen nghi (tranh nhap tay sai key): dong bo tu Terraform state**

   ```bash
   cd ~/go-micro-infra/terraform/environments/management
   TF_AKID="$(terraform output -raw eso_access_key_id)"
   TF_SAK="$(terraform output -raw eso_secret_access_key)"

   for ctx in kind-dev kind-prod; do
     kubectl --context "$ctx" -n external-secrets create secret generic aws-credentials \
       --from-literal=access-key-id="$TF_AKID" \
       --from-literal=secret-access-key="$TF_SAK" \
       --dry-run=client -o yaml | kubectl --context "$ctx" apply -f -
   done
   ```

   Force ESO reconcile ngay sau khi update credential:

   ```bash
   for ctx in kind-dev kind-prod; do
     ns="microservices-${ctx#kind-}"
     kubectl --context "$ctx" -n "$ns" annotate externalsecret --all force-sync="$(date +%s)" --overwrite
   done
   ```

3. Tạo namespace đích đúng của `go-micro`:

```bash
for ctx in kind-dev kind-prod; do
  env=${ctx#kind-}
  kubectl --context "$ctx" create namespace "databases-$env" --dry-run=client -o yaml | kubectl --context "$ctx" apply -f -
  kubectl --context "$ctx" create namespace "microservices-$env" --dry-run=client -o yaml | kubectl --context "$ctx" apply -f -
done
```

4. Apply `ClusterSecretStore` + `ExternalSecret` từ repo (từ thư mục gốc repo):

```bash
  cd ~/Downloads/go-micro

    # DEV
    helm template external-secrets external-secrets/applications \
      -f external-secrets/applications/values.yaml \
      -f config/base/config.yaml \
      -f config/env/dev.yaml \
      | kubectl --context kind-dev apply -f -

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
   rg "remoteKey:" config/env/dev.yaml config/env/prod.yaml
   # expected:
   # go-micro/dev/app-credentials
   # go-micro/prod/app-credentials

   # Verify ExternalSecret đã render đúng remote key
   kubectl --context kind-dev -n microservices-dev get externalsecret go-micro-inventory-secrets-dev -o yaml | rg "key:|property:"
   ```

   Nếu `remoteKey` không đúng với secret bạn đã tạo trên AWS, sửa tại `config/env/*.yaml` rồi re-apply chart ESO.

6. Kiểm tra sync:

```bash
kubectl --context kind-dev get externalsecret,secret -n microservices-dev
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

kubectl --context kind-dev -n kube-system get pods -l app=kindnet
kubectl --context kind-prod -n kube-system get pods -l app=kindnet

kubectl --context kind-management -n monitoring get pods
kubectl --context kind-dev -n external-secrets get pods
kubectl --context kind-prod -n external-secrets get pods
```

---

## 8) Ops notes

### 8.1 Secrets AWS / ESO

Loi hay gap:

- `ExternalSecret` ra `SecretSyncedError`
- Pod app bi `CreateContainerConfigError` vi missing secret

Xem muc `6.1`: tao `external-secrets/aws-credentials` tu Terraform output, force ESO reconcile.

### 8.2 Recovery ArgoCD `ComparisonError` sau reboot

Trieu chung:

- `argocd app list` thay nhieu app `STATUS: Unknown`, `CONDITIONS: ComparisonError`
- `argocd app get <app>` co loi `dial tcp <argocd-repo-server-cluster-ip>:8081: connect: operation not permitted`
- `kubectl -n argocd get endpoints argocd-repo-server` ra rong

Nguyen nhan hay gap: NetworkPolicy trong namespace `argocd` chan probe; repo-server/controller khong `Ready`.

```bash
kubectl --context kind-management -n argocd get pods -o wide
kubectl --context kind-management -n argocd get endpoints argocd-repo-server -o wide
kubectl --context kind-management -n argocd describe pod -l app.kubernetes.io/name=argocd-repo-server | tail -20
kubectl --context kind-management -n argocd describe pod -l app.kubernetes.io/name=argocd-application-controller | tail -20
```

Neu readiness timeout:

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

```bash
argocd --grpc-web app list -o name | xargs -n1 argocd --grpc-web app get --hard-refresh >/tmp/argocd-refresh.log 2>&1 || true
argocd --grpc-web app list
```
