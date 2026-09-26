# Kind Setup (go-micro)

Recreate lab trên **EC2 Kind** (SSM). GitOps: Argo CD là source of truth.

- 3 cluster: `management`, `dev`, `prod`. **Không staging.**
- CNI: kindnet. Ingress: Traefik NodePort. **Không Cilium, không MetalLB.**
- Jenkins: EC2 **khác** (`jenkins/` docker compose). Không cài Jenkins trên máy Kind.
- Tool do cloud-init: `docker`, `kind`, `kubectl`, `helm`, `argocd`.

## 0) Vào máy

Từ laptop:

```bash
aws ssm start-session --target <KIND_INSTANCE_ID> --region ap-southeast-2
```

Trên EC2 (SSM hay ra `root`):

```bash
export HOME=/root
export KUBECONFIG=/root/.kube/config
go-micro-check-tools

git clone https://github.com/minhtri1612/go-micro-infra.git ~/go-micro-infra 2>/dev/null || true
git clone https://github.com/minhtri1612/go-micro-gitops.git ~/go-micro-gitops 2>/dev/null || true
git -C ~/go-micro-infra pull --ff-only origin main
git -C ~/go-micro-gitops pull --ff-only origin main
cd ~/go-micro-infra
```

UI Argo (SG `:18080`, IP nhà): `https://<KIND_EIP>:18080` — cert tự ký. Không `kubectl port-forward`. `management-kind-config.yaml` map host `18080` → NodePort `30443`.

---

## 1) Recreate 3 clusters

```bash
cd ~/go-micro-infra

kind delete cluster --name management || true
kind delete cluster --name dev || true
kind delete cluster --name prod || true

kind create cluster --name management --config kind/management-kind-config.yaml
kubectl config use-context kind-management
kubectl config set-cluster kind-management --server=https://127.0.0.1:33443

kind create cluster --name dev --config kind/dev-kind-config.yaml
kind create cluster --name prod --config kind/prod-kind-config.yaml
kubectl config set-cluster kind-dev --server=https://127.0.0.1:30443
kubectl config set-cluster kind-prod --server=https://127.0.0.1:31443
```

Không dùng `kind/staging-*.yaml`.

---

## 2) Install Argo CD on management

Không `kubectl wait --for=condition=Ready pods --all` — Job `redis-secret-init` Completed sẽ làm lệnh đó timeout.

```bash
kubectl config use-context kind-management
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update
helm upgrade --install argocd argo/argo-cd -n argocd \
  --version 8.3.2 \
  -f kind/argocd-values.yaml \
  --wait --timeout 10m

kubectl --context kind-management -n argocd wait --for=condition=Ready pod \
  -l app.kubernetes.io/name=argocd-server --timeout=300s
kubectl --context kind-management -n argocd wait --for=condition=Ready pod \
  -l app.kubernetes.io/name=argocd-repo-server --timeout=300s
kubectl --context kind-management -n argocd get svc argocd-server
# expect: 80:30080/TCP,443:30443/TCP

kubectl --context kind-management -n argocd patch configmap argocd-cmd-params-cm --type merge \
  -p '{"data":{"controller.repo.server.timeout.seconds":"180"}}'
kubectl --context kind-management -n argocd rollout restart deploy/argocd-repo-server
kubectl --context kind-management -n argocd rollout restart statefulset/argocd-application-controller
kubectl --context kind-management -n argocd rollout status deploy/argocd-repo-server --timeout=180s
kubectl --context kind-management -n argocd rollout status statefulset/argocd-application-controller --timeout=180s
```

**Bắt buộc login trước mọi lệnh `argocd`** (không thì `server address unspecified`):

```bash
rm -rf ~/.argocd
PASS=$(kubectl --context kind-management -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "$PASS"
argocd login localhost:18080 --insecure --grpc-web --username admin --password "$PASS"
argocd --grpc-web account get-user-info
```

### 2.1) Jenkins

Không nằm trên máy Kind. Xem `jenkins/README.md`.

### 2.2) Argo CD Rollout UI extension

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
```

UI: hard refresh. Resource Rollout → tab **Rollout**.

---

## 3) Register dev/prod clusters

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

Đã `argocd login`. `kubectl apply` tạo Application; `argocd app sync` mới đẩy sync.

```bash
kubectl config use-context kind-management
GITOPS=~/go-micro-gitops

argocd repo add https://github.com/minhtri1612/go-micro-gitops.git || true
argocd repo add https://github.com/minhtri1612/go-micro-infra.git || true
argocd repo add https://argoproj.github.io/argo-helm --type helm --name argo-helm || true
argocd repo add https://helm.traefik.io/traefik --type helm --name traefik || true
argocd repo add https://prometheus-community.github.io/helm-charts --type helm --name prometheus-community || true

kubectl apply -f "$GITOPS/argocd/bootstrap/01-projects.yaml"
argocd --grpc-web app sync argocd-projects
argocd --grpc-web proj list
sleep 3

kubectl apply -f "$GITOPS/argocd/bootstrap/05-monitoring-mgmt.yaml"
argocd --grpc-web app sync monitoring-management
argocd --grpc-web app wait monitoring-management --health --sync --timeout 300

kubectl apply -f "$GITOPS/argocd/bootstrap/06-monitoring-dev.yaml"
kubectl apply -f "$GITOPS/argocd/bootstrap/08-monitoring-prod.yaml"
argocd --grpc-web app terminate-op monitoring-dev || true
argocd --grpc-web app terminate-op monitoring-prod || true
argocd --grpc-web app sync monitoring-dev
argocd --grpc-web app sync monitoring-prod
argocd --grpc-web app wait monitoring-dev --health --sync --timeout 300 || true
argocd --grpc-web app wait monitoring-prod --health --sync --timeout 300 || true

kubectl apply -f "$GITOPS/argocd/bootstrap/12-argo-rollouts-dev.yaml"
kubectl apply -f "$GITOPS/argocd/bootstrap/14-argo-rollouts-prod.yaml"
kubectl apply -f "$GITOPS/argocd/bootstrap/19-traefik-dev.yaml"
kubectl apply -f "$GITOPS/argocd/bootstrap/21-traefik-prod.yaml"
argocd --grpc-web app sync argo-rollouts-dev argo-rollouts-prod traefik-dev traefik-prod

kubectl apply -f "$GITOPS/argocd/bootstrap/02-dev-microservices-stack.yaml"
kubectl apply -f "$GITOPS/argocd/bootstrap/04-prod-microservices-stack.yaml"
argocd --grpc-web app sync dev-microservices prod-microservices
```

Không apply `*-staging.yaml`.

---

## 5) Monitoring remote_write

Sau khi `monitoring-management` healthy.

```bash
cd ~/go-micro-infra
chmod +x scripts/sync-monitoring-remote-write-url.sh
./scripts/sync-monitoring-remote-write-url.sh
kubectl --context kind-management -n monitoring wait --for=condition=Ready pod -l app.kubernetes.io/name=prometheus --timeout=600s
./scripts/sync-monitoring-remote-write-url.sh --check
./scripts/sync-monitoring-remote-write-url.sh --commit-push

argocd --grpc-web app sync monitoring-dev monitoring-prod
```

---

## 6) ESO + AWS Secrets Manager

Kind 1.28: ghim chart ESO **0.19.2** (0.20+ cần K8s ≥ 1.31).

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

for ctx in kind-dev kind-prod; do
  helm upgrade --install external-secrets external-secrets/external-secrets \
    --version 0.19.2 \
    -n external-secrets --create-namespace \
    --kube-context "$ctx"
done

for ctx in kind-dev kind-prod; do
  kubectl --context "$ctx" -n external-secrets rollout status deployment/external-secrets-webhook --timeout=300s
  kubectl --context "$ctx" -n external-secrets wait --for=condition=Ready pods --all --timeout=300s
done
```

Secret AWS `go-micro/{dev,prod}/app-credentials` do Terraform `modules/app-credentials`. Secret **trong cluster** `external-secrets/aws-credentials` là IAM ESO (`go-micro-eso-secrets-multi`).

Lấy key từ máy có AWS + terraform (không init Terraform trên Kind host):

```bash
# laptop / máy có state S3
cd ~/go-micro-infra/terraform/environments/management
terraform output -raw eso_access_key_id
terraform output -raw eso_secret_access_key
```

Paste lên Kind EC2:

```bash
AWS_ACCESS_KEY_ID='...'
AWS_SECRET_ACCESS_KEY='...'

for ctx in kind-dev kind-prod; do
  kubectl --context "$ctx" -n external-secrets create secret generic aws-credentials \
    --from-literal=access-key-id="$AWS_ACCESS_KEY_ID" \
    --from-literal=secret-access-key="$AWS_SECRET_ACCESS_KEY" \
    --dry-run=client -o yaml | kubectl --context "$ctx" apply -f -
done

for ctx in kind-dev kind-prod; do
  env=${ctx#kind-}
  kubectl --context "$ctx" create namespace "databases-$env" --dry-run=client -o yaml | kubectl --context "$ctx" apply -f -
  kubectl --context "$ctx" create namespace "microservices-$env" --dry-run=client -o yaml | kubectl --context "$ctx" apply -f -
done

cd ~/go-micro-gitops
helm template external-secrets external-secrets/applications \
  -f external-secrets/applications/values.yaml \
  -f config/base/config.yaml \
  -f config/env/dev.yaml \
  | kubectl --context kind-dev apply -f -
helm template external-secrets external-secrets/applications \
  -f external-secrets/applications/values.yaml \
  -f config/base/config.yaml \
  -f config/env/prod.yaml \
  | kubectl --context kind-prod apply -f -

kubectl --context kind-dev get externalsecret,secret -n microservices-dev
kubectl --context kind-prod get externalsecret,secret -n microservices-prod
```

`remoteKey` phải là `go-micro/dev/app-credentials` và `go-micro/prod/app-credentials`.

---

## 7) Fast checks

```bash
argocd --grpc-web proj list
argocd --grpc-web app list

kubectl --context kind-dev -n kube-system get pods -l app=kindnet
kubectl --context kind-prod -n kube-system get pods -l app=kindnet
kubectl --context kind-management -n argocd get svc argocd-server
kubectl --context kind-management -n monitoring get pods
kubectl --context kind-dev -n external-secrets get pods
kubectl --context kind-prod -n external-secrets get pods
```

---

## 8) Ops notes

### 8.1 ESO `SecretSyncedError`

- `external-secrets/aws-credentials` trên **cả** `kind-dev` và `kind-prod`
- Secret AWS đúng tên `go-micro/<env>/app-credentials`
- JSON đủ property map trong `go-micro-gitops/config/env/*.yaml`

```bash
for ctx in kind-dev kind-prod; do
  ns="microservices-${ctx#kind-}"
  kubectl --context "$ctx" -n "$ns" annotate externalsecret --all force-sync="$(date +%s)" --overwrite
done
```

### 8.2 `ComparisonError` sau reboot

Hay gặp: NetworkPolicy chặn repo-server. Values `kind/argocd-values.yaml` đã `networkPolicy.create: false`.

```bash
kubectl --context kind-management -n argocd get pods -o wide
kubectl --context kind-management -n argocd get endpoints argocd-repo-server -o wide
helm upgrade --install argocd argo/argo-cd -n argocd --version 8.3.2 -f kind/argocd-values.yaml --wait --timeout 10m
argocd login localhost:18080 --insecure --grpc-web --username admin --password "$PASS"
argocd --grpc-web app list
```
