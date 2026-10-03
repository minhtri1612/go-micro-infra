#!/usr/bin/env python3
"""Generate Grafana ConfigMaps. Run from this directory."""
from __future__ import annotations

import json
from pathlib import Path

DS = {"type": "prometheus", "uid": "prometheus"}


def templating():
    return {
        "list": [
            {
                "name": "cluster",
                "type": "query",
                "datasource": DS,
                "query": "label_values(up, cluster)",
                "includeAll": True,
                "multi": True,
                "allValue": ".*",
                "current": {"text": "All", "value": "$__all"},
                "refresh": 2,
            },
            {
                "name": "namespace",
                "type": "query",
                "datasource": DS,
                "query": 'label_values(kube_pod_info{cluster=~"$cluster"}, namespace)',
                "includeAll": True,
                "multi": True,
                "allValue": ".*",
                "current": {"text": "All", "value": "$__all"},
                "refresh": 2,
            },
            {
                "name": "service",
                "type": "custom",
                "includeAll": True,
                "multi": True,
                "allValue": "product|inventory|order|payment|noti|client",
                "options": [
                    {"text": "product", "value": "product"},
                    {"text": "inventory", "value": "inventory"},
                    {"text": "order", "value": "order"},
                    {"text": "payment", "value": "payment"},
                    {"text": "noti", "value": "noti"},
                    {"text": "client", "value": "client"},
                ],
                "current": {"text": "All", "value": "$__all"},
            },
        ]
    }


def row(pid, title, y):
    return {
        "collapsed": False,
        "gridPos": {"h": 1, "w": 24, "x": 0, "y": y},
        "id": pid,
        "title": title,
        "type": "row",
        "panels": [],
    }


def timeseries(pid, title, expr, y, x=0, w=12, h=8, unit="short", legend="{{instance}}"):
    return {
        "datasource": DS,
        "fieldConfig": {
            "defaults": {
                "color": {"mode": "palette-classic"},
                "custom": {
                    "drawStyle": "line",
                    "fillOpacity": 10,
                    "lineWidth": 1,
                    "showPoints": "never",
                    "spanNulls": True,
                },
                "unit": unit,
            },
            "overrides": [],
        },
        "gridPos": {"h": h, "w": w, "x": x, "y": y},
        "id": pid,
        "options": {"legend": {"displayMode": "list", "placement": "bottom", "showLegend": True}},
        "targets": [
            {
                "datasource": DS,
                "editorMode": "code",
                "expr": expr,
                "legendFormat": legend,
                "range": True,
                "refId": "A",
            }
        ],
        "title": title,
        "type": "timeseries",
    }


def stat(pid, title, expr, y, x, w=6, h=4, unit="none"):
    return {
        "datasource": DS,
        "fieldConfig": {
            "defaults": {
                "color": {"mode": "thresholds"},
                "thresholds": {
                    "mode": "absolute",
                    "steps": [
                        {"color": "green", "value": None},
                        {"color": "yellow", "value": 1},
                        {"color": "red", "value": 5},
                    ],
                },
                "unit": unit,
            },
            "overrides": [],
        },
        "gridPos": {"h": h, "w": w, "x": x, "y": y},
        "id": pid,
        "options": {
            "colorMode": "value",
            "graphMode": "area",
            "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
        },
        "pluginVersion": "11.1.0",
        "targets": [
            {
                "datasource": DS,
                "editorMode": "code",
                "expr": expr,
                "legendFormat": "__auto",
                "range": True,
                "refId": "A",
            }
        ],
        "title": title,
        "type": "stat",
    }


def table(pid, title, expr, y):
    return {
        "datasource": DS,
        "gridPos": {"h": 8, "w": 24, "x": 0, "y": y},
        "id": pid,
        "targets": [
            {
                "datasource": DS,
                "editorMode": "code",
                "expr": expr,
                "format": "table",
                "instant": True,
                "legendFormat": "__auto",
                "refId": "A",
            }
        ],
        "title": title,
        "transformations": [
            {"id": "organize", "options": {"excludeByName": {"Time": True}}}
        ],
        "type": "table",
    }


def dash(title, uid, desc, panels):
    return {
        "annotations": {"list": []},
        "description": desc,
        "editable": True,
        "fiscalYearStartMonth": 0,
        "graphTooltip": 1,
        "id": None,
        "links": [],
        "panels": panels,
        "schemaVersion": 39,
        "tags": ["go-micro", "rke2"],
        "templating": templating(),
        "time": {"from": "now-1h", "to": "now"},
        "timezone": "browser",
        "title": title,
        "uid": uid,
        "version": 1,
    }


def cluster_dash():
    c = 'cluster=~"$cluster"'
    ns = 'namespace=~"$namespace"'
    panels = [
        row(1, "Nodes", 0),
        timeseries(
            2,
            "Node CPU utilization %",
            f'100 - (avg by (cluster, instance) (rate(node_cpu_seconds_total{{mode="idle", {c}}}[5m])) * 100)',
            1,
            0,
            12,
            8,
            "percent",
            "{{cluster}} {{instance}}",
        ),
        timeseries(
            3,
            "Node memory usage %",
            f'(node_memory_MemTotal_bytes{{{c}}} - node_memory_MemAvailable_bytes{{{c}}}) / node_memory_MemTotal_bytes{{{c}}} * 100',
            1,
            12,
            12,
            8,
            "percent",
            "{{cluster}} {{instance}}",
        ),
        timeseries(
            4,
            "Node disk read B/s",
            f'sum by (cluster, instance) (rate(node_disk_read_bytes_total{{{c}}}[5m]))',
            9,
            0,
            12,
            7,
            "Bps",
            "{{cluster}} {{instance}}",
        ),
        timeseries(
            5,
            "Node disk write B/s",
            f'sum by (cluster, instance) (rate(node_disk_written_bytes_total{{{c}}}[5m]))',
            9,
            12,
            12,
            7,
            "Bps",
            "{{cluster}} {{instance}}",
        ),
        timeseries(
            6,
            "Cluster CPU saturation %",
            f'100 * (1 - avg by (cluster) (rate(node_cpu_seconds_total{{mode="idle", {c}}}[5m])))',
            16,
            0,
            12,
            7,
            "percent",
            "{{cluster}}",
        ),
        timeseries(
            7,
            "Cluster memory saturation %",
            f'100 * (1 - sum by (cluster) (node_memory_MemAvailable_bytes{{{c}}}) / sum by (cluster) (node_memory_MemTotal_bytes{{{c}}}))',
            16,
            12,
            12,
            7,
            "percent",
            "{{cluster}}",
        ),
        row(8, "Pod throttling & lifecycle", 23),
        timeseries(
            9,
            "CPU throttling % (empty on dev/prod until kubelet scrape)",
            f'100 * (sum by (cluster, pod) (rate(container_cpu_cfs_throttled_periods_total{{{c}, {ns}, container!="", container!="POD"}}[5m])) / clamp_min(sum by (cluster, pod) (rate(container_cpu_cfs_periods_total{{{c}, {ns}, container!="", container!="POD"}}[5m])), 1))',
            24,
            0,
            12,
            8,
            "percent",
            "{{cluster}} {{pod}}",
        ),
        timeseries(
            10,
            "Memory working set vs limit %",
            f'100 * (container_memory_working_set_bytes{{{c}, {ns}, container!="", container!="POD"}} / clamp_min(container_spec_memory_limit_bytes{{{c}, {ns}, container!="", container!="POD"}}, 1))',
            24,
            12,
            12,
            8,
            "percent",
            "{{cluster}} {{pod}}",
        ),
        stat(
            11,
            "Pending pods",
            f'sum(kube_pod_status_phase{{{c}, phase="Pending"}}) or vector(0)',
            32,
            0,
        ),
        stat(
            12,
            "OOMKilled + Evicted",
            f'sum(kube_pod_container_status_terminated_reason{{{c}, reason=~"OOMKilled|Evicted"}}) or vector(0)',
            32,
            6,
        ),
        row(13, "HPA", 36),
        timeseries(
            14,
            "HPA current replicas",
            f'sum by (cluster, horizontalpodautoscaler, namespace) (kube_horizontalpodautoscaler_status_current_replicas{{{c}}})',
            37,
            0,
            8,
            8,
            "short",
            "{{cluster}} {{namespace}}/{{horizontalpodautoscaler}}",
        ),
        timeseries(
            15,
            "HPA desired replicas",
            f'sum by (cluster, horizontalpodautoscaler, namespace) (kube_horizontalpodautoscaler_status_desired_replicas{{{c}}})',
            37,
            8,
            8,
            8,
            "short",
            "{{cluster}} {{namespace}}/{{horizontalpodautoscaler}}",
        ),
        timeseries(
            16,
            "HPA max replicas",
            f'sum by (cluster, horizontalpodautoscaler, namespace) (kube_horizontalpodautoscaler_spec_max_replicas{{{c}}})',
            37,
            16,
            8,
            8,
            "short",
            "{{cluster}} {{namespace}}/{{horizontalpodautoscaler}}",
        ),
    ]
    return dash(
        "Cluster & Infrastructure Health",
        "go-micro-cluster-health",
        "RKE2 nodes, saturation, HPA. Throttling/OOM need kubelet/cAdvisor (management only today; dev/prod kubelet scrape is off).",
        panels,
    )


def app_dash():
    c = 'cluster=~"$cluster"'
    svc = 'pod=~"($service)-.*"'
    panels = [
        row(1, "Service health", 0),
        stat(2, "Targets up", f'sum(up{{{c}, {svc}}}) or vector(0)', 1, 0),
        stat(
            3,
            "Ready pods",
            f'sum(kube_pod_status_ready{{{c}, {svc}, condition="true"}}) or vector(0)',
            1,
            6,
        ),
        stat(
            4,
            "Success rate 5m",
            f'100 * (1 - ((sum(increase(gin_request_total{{{c}, {svc}, code=~"5.."}}[5m])) or vector(0)) / clamp_min((sum(increase(gin_request_total{{{c}, {svc}}}[5m])) or vector(0)), 1)))',
            1,
            12,
            6,
            4,
            "percent",
        ),
        stat(
            5,
            "Requests / 5m",
            f'sum(increase(gin_request_total{{{c}, {svc}}}[5m])) or vector(0)',
            1,
            18,
        ),
        row(6, "Gin application", 5),
        timeseries(
            7,
            "RPS by pod",
            f'sum(rate(gin_request_total{{{c}, {svc}}}[1m])) by (cluster, pod)',
            6,
            0,
            12,
            8,
            "reqps",
            "{{cluster}} {{pod}}",
        ),
        timeseries(
            8,
            "P95 latency by pod",
            f'histogram_quantile(0.95, sum(increase(gin_request_duration_bucket{{{c}, {svc}}}[5m])) by (le, cluster, pod))',
            6,
            12,
            12,
            8,
            "s",
            "{{cluster}} {{pod}}",
        ),
        timeseries(
            9,
            "RPS by status code",
            f'sum(rate(gin_request_total{{{c}, {svc}}}[1m])) by (cluster, code)',
            14,
            0,
            12,
            8,
            "reqps",
            "{{cluster}} {{code}}",
        ),
        timeseries(
            10,
            "Error RPS by pod/code",
            f'sum(rate(gin_request_total{{{c}, {svc}, code!~"2.."}}[1m])) by (cluster, pod, code)',
            14,
            12,
            12,
            8,
            "reqps",
            "{{cluster}} {{pod}} {{code}}",
        ),
        table(
            11,
            "Top error routes (5m)",
            f'sum(increase(gin_request_total{{{c}, {svc}, code!~"2.."}}[5m])) by (cluster, pod, uri, code)',
            22,
        ),
        row(12, "Traefik ingress (needs metrics.prometheus on dest/prod)", 30),
        timeseries(
            13,
            "Ingress RPS by code",
            f'sum(rate(traefik_service_requests_total{{{c}}}[1m])) by (cluster, code)',
            31,
            0,
            8,
            8,
            "reqps",
            "{{cluster}} {{code}}",
        ),
        timeseries(
            14,
            "Ingress P95 latency",
            f'histogram_quantile(0.95, sum(rate(traefik_service_request_duration_seconds_bucket{{{c}}}[5m])) by (le, cluster))',
            31,
            8,
            8,
            8,
            "s",
            "{{cluster}} p95",
        ),
        timeseries(
            15,
            "Ingress open connections",
            f'sum(traefik_open_connections{{{c}}}) by (cluster, entrypoint)',
            31,
            16,
            8,
            8,
            "short",
            "{{cluster}} {{entrypoint}}",
        ),
    ]
    return dash(
        "Microservices & API Traffic",
        "go-micro-microservices-traffic",
        "Gin RPS/latency/errors + Traefik. Filter cluster=dev|prod|management and service.",
        panels,
    )


def wrap(name, filename, dashboard):
    body = json.dumps(dashboard, indent=2)
    indented = "\n".join("    " + line if line else "" for line in body.splitlines())
    return f"""apiVersion: v1
kind: ConfigMap
metadata:
  name: {name}
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  {filename}: |-
{indented}
"""


def main():
    here = Path(__file__).resolve().parent
    (here / "grafana-dashboard-cluster-health.yaml").write_text(
        wrap("grafana-dashboard-cluster-health", "cluster-health.json", cluster_dash())
    )
    (here / "grafana-dashboard-microservices-traffic.yaml").write_text(
        wrap(
            "grafana-dashboard-microservices-traffic",
            "microservices-traffic.json",
            app_dash(),
        )
    )
    print("wrote cluster-health + microservices-traffic")


if __name__ == "__main__":
    main()
