#!/bin/bash
# Map EC2 :32000/:32090 → Kind management NodePorts (Grafana / Prometheus).
# Argo already has extraPortMappings at kind create (18080→30443). Grafana
# NodePorts exist in-cluster but were never published on this live cluster.
# Do not kind-delete management. This proxy is the equivalent of extraPortMappings.
set -euo pipefail
command -v socat >/dev/null || apt-get install -y socat
MGMT=$(docker inspect management-control-plane --format '{{.NetworkSettings.Networks.kind.IPAddress}}')
: "${MGMT:?management-control-plane has no kind IP}"
echo "proxy Grafana :32000 and Prometheus :32090 -> ${MGMT}"
socat TCP-LISTEN:32000,fork,reuseaddr TCP:"${MGMT}":32000 &
socat TCP-LISTEN:32090,fork,reuseaddr TCP:"${MGMT}":32090 &
wait
