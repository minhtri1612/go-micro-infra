# CI — `PIPELINE_SCOPE=auto`

## Không sửa tay `env/dev.yaml` khi deploy service

Khi anh **sửa code** `payment-service/` (hoặc service khác) và Jenkins build xong:

1. **Bump** tag mới = max trên **Docker Hub** + 1 (không lấy số cũ trong yaml để quyết định build).
2. **Build/push** image đúng tag đó lên Hub.
3. **Ghi** `env/dev.yaml` tag **chính xác** vừa có trên Hub (`write-service-tag.sh`).
4. **Push Git** `ci: bump tags in env/dev.yaml [skip ci]` → Argo CD sync.

Anh **không** cần mở file env và gõ `v1.0.4` bằng tay. File trên máy local có thể cũ hơn GitHub — `git pull` hoặc:

```bash
./scripts/sync-env-from-hub.sh env/dev.yaml payment   # khớp Hub cho payment
```

Chỉ service **được build** trong job mới đổi tag trong env (scope `auto`).

## Build tay mà log báo `SKIP all` / `ci: bump ... [skip ci]`

Commit **mới nhất trên `main`** là Jenkins tự push (`ci: bump tags in env/dev.yaml [skip ci]`). Webhook/SCM chạy lại commit đó → **cố ý skip** (không build/test lại vòng vòng).

| Cách chạy | Kết quả |
|-----------|---------|
| **Build Now** (Jenkins UI, Started by user) trên HEAD đó | **Test + promote** với tag trong `env/dev.yaml` (vd payment `v1.0.4`), **không** build image lại |
| Push code `payment-service/` | Build image mới + bump env + test |
| `DEPLOY_EXISTING_ENV_TAGS=true` | Test/promote tag trong env (khi commit không phải `[skip ci]`) |
| `PIPELINE_SCOPE=full` | Chỉ test/promote, bỏ qua detect commit |

Muốn **image mới** → phải có commit đổi `*-service/`, không chỉ bấm Build trên commit CI.

## Chỉ sửa `env/dev.yaml` (tag đã build sẵn trên Hub, ví dụ rollback v1.0.3)

1. Push `env/dev.yaml` lên `main` **hoặc** đã push rồi → Jenkins Build:
   - `PIPELINE_SCOPE=auto` **hoặc**
   - bật **`DEPLOY_EXISTING_ENV_TAGS=true`** (khi commit hiện tại chỉ Jenkinsfile)
2. Pipeline: **verify tag có trên Hub** → **skip** Build + Push Git → **chạy** Prepare + test + promote
3. Argo sync Git (tag trong env/) — Jenkins không push Git lại nếu không build

## Sửa code `order-service/`

- Build **chỉ order** (bump tag) → nếu tag mới **đã có Hub** thì skip docker build → Push Git → test + promote

## Commit chỉ Jenkinsfile / scripts/ci

- `auto` → **skip build**, vẫn **chạy Parallel tests** với tag trong `env/dev.yaml` (verify Hub).
- Hoặc bật **`DEPLOY_EXISTING_ENV_TAGS=true`** (cùng ý).

## Test trước Promote (canary pause)

Sau Argo sync tag mới: rollout **Paused**, stable Endpoints trống, canary có pod. Jenkins **tự** `X-Canary:true` — không cần `kubectl promote` trước test. Pass test → **Rollout Decision Gate** → Promote.

## Rollback tự động (`PIPELINE_SCOPE=rollback`)

Không sửa tay `env/` — Jenkins đọc tag **hiện tại trong Git**, patch **−1**, verify image có trên Hub, ghi yaml + push → Argo sync.

| Param | Ý nghĩa |
|-------|---------|
| `PIPELINE_SCOPE=rollback` | Chỉ stage Rollback (checkout + decrement + push Git) |
| `ROLLBACK_SERVICE` | `payment` = một service; để trống = product, inventory, order, payment, noti (không client) |
| `TARGET_ENV` | `dev` → `env/dev.yaml` |
| `PUSH_GIT` | Mặc định true — push commit `ci: rollback tags ...` |

Ví dụ: yaml `payment-service-v1.0.4` → rollback → `v1.0.3` (phải còn trên Hub).

**Giới hạn:** rollback = **một bậc patch** so với tag trong `env/` (Git), không phải “latest Hub − 1” nếu yaml lệch cluster.

## Override

| Param / scope | Ý nghĩa |
|---------------|---------|
| `DEPLOY_EXISTING_ENV_TAGS` | Luôn dùng tag trong env/, verify Hub, test+promote |
| `build-only` | Chỉ build, không test |
| `full` | Chỉ test/promote |
