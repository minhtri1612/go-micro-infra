# Prometheus Queries By Environment

Tai lieu nay tach rieng query cho `dev`, `staging`, `prod` de de copy/paste va doc nhanh khi rollout canary.

Service regex dung chung:

```promql
(product|inventory|order|payment|noti|client)-.*
```

---

## DEV

### P95 latency theo pod
```promql
histogram_quantile(
  0.95,
  sum(rate(gin_request_duration_bucket{cluster="dev", pod=~"(product|inventory|order|payment|noti|client)-.*"}[1m])) by (le, pod)
)
```

### Success rate (%) theo pod (1 - 5xx/total)
```promql
100 * (
  1 - (
    sum(rate(gin_request_total{cluster="dev", pod=~"(product|inventory|order|payment|noti|client)-.*", code=~"5.."}[2m])) by (pod)
    /
    sum(rate(gin_request_total{cluster="dev", pod=~"(product|inventory|order|payment|noti|client)-.*"}[2m])) by (pod)
  )
)
```

### RPS theo pod
```promql
sum(rate(gin_request_total{cluster="dev", pod=~"(product|inventory|order|payment|noti|client)-.*"}[1m])) by (pod)
```

### Top API loi (khong phai 2xx)
```promql
sum(rate(gin_uri_request_total{cluster="dev", pod=~"(product|inventory|order|payment|noti|client)-.*", code!~"2.."}[1m])) by (pod, uri, code)
```

### CPU/RAM theo pod
```promql
sum(node_namespace_pod_container:container_cpu_usage_seconds_total:sum_irate{namespace="microservices-dev", pod=~"(product|inventory|order|payment|noti|client)-.*"}) by (pod)
```

```promql
sum(container_memory_working_set_bytes{namespace="microservices-dev", pod=~"(product|inventory|order|payment|noti|client)-.*"}) by (pod)
```

---

## STAGING

### P95 latency theo pod
```promql
histogram_quantile(
  0.95,
  sum(rate(gin_request_duration_bucket{cluster="staging", pod=~"(product|inventory|order|payment|noti|client)-.*"}[1m])) by (le, pod)
)
```

### Success rate (%) theo pod
```promql
100 * (
  1 - (
    sum(rate(gin_request_total{cluster="staging", pod=~"(product|inventory|order|payment|noti|client)-.*", code=~"5.."}[2m])) by (pod)
    /
    sum(rate(gin_request_total{cluster="staging", pod=~"(product|inventory|order|payment|noti|client)-.*"}[2m])) by (pod)
  )
)
```

### RPS theo pod
```promql
sum(rate(gin_request_total{cluster="staging", pod=~"(product|inventory|order|payment|noti|client)-.*"}[1m])) by (pod)
```

### Top API loi (khong phai 2xx)
```promql
sum(rate(gin_uri_request_total{cluster="staging", pod=~"(product|inventory|order|payment|noti|client)-.*", code!~"2.."}[1m])) by (pod, uri, code)
```

### CPU/RAM theo pod
```promql
sum(node_namespace_pod_container:container_cpu_usage_seconds_total:sum_irate{namespace="microservices-staging", pod=~"(product|inventory|order|payment|noti|client)-.*"}) by (pod)
```

```promql
sum(container_memory_working_set_bytes{namespace="microservices-staging", pod=~"(product|inventory|order|payment|noti|client)-.*"}) by (pod)
```

---

## PROD

### P95 latency theo pod
```promql
histogram_quantile(
  0.95,
  sum(rate(gin_request_duration_bucket{cluster="prod", pod=~"(product|inventory|order|payment|noti|client)-.*"}[1m])) by (le, pod)
)
```

### Success rate (%) theo pod
```promql
100 * (
  1 - (
    sum(rate(gin_request_total{cluster="prod", pod=~"(product|inventory|order|payment|noti|client)-.*", code=~"5.."}[2m])) by (pod)
    /
    sum(rate(gin_request_total{cluster="prod", pod=~"(product|inventory|order|payment|noti|client)-.*"}[2m])) by (pod)
  )
)
```

### RPS theo pod
```promql
sum(rate(gin_request_total{cluster="prod", pod=~"(product|inventory|order|payment|noti|client)-.*"}[1m])) by (pod)
```

### Top API loi (khong phai 2xx)
```promql
sum(rate(gin_uri_request_total{cluster="prod", pod=~"(product|inventory|order|payment|noti|client)-.*", code!~"2.."}[1m])) by (pod, uri, code)
```

### CPU/RAM theo pod
```promql
sum(node_namespace_pod_container:container_cpu_usage_seconds_total:sum_irate{namespace="microservices-prod", pod=~"(product|inventory|order|payment|noti|client)-.*"}) by (pod)
```

```promql
sum(container_memory_working_set_bytes{namespace="microservices-prod", pod=~"(product|inventory|order|payment|noti|client)-.*"}) by (pod)
```

---

## Stress Test Thu Cong (Optional)

Khong bat buoc neu rollout da co `synthetic-load`, nhung van huu ich de debug nhanh.

### wget trong pod (DEV)
```bash
kubectl --context kind-dev -n microservices-dev exec $(kubectl --context kind-dev -n microservices-dev get pod -l app.kubernetes.io/name=product -o name | head -n 1) -- \
sh -c "seq 500 | xargs -I{} -P 20 wget -qO- http://localhost:8080/health"
```

### Apache Benchmark (DEV)
```bash
# sudo apt install apache2-utils
ab -n 1000 -c 100 http://dev.go-micro.local/api/v1/products/health
```
