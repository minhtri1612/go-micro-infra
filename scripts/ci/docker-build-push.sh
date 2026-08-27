#!/usr/bin/env bash
# Usage: docker-build-push.sh <service> <full-tag>
# Example: docker-build-push.sh payment payment-service-v1.0.5
set -euo pipefail
SERVICE="${1:?}"
TAG="${2:?}"
REPO="${DOCKER_REPO:-minhtri1612/go-microservice}"
IMAGE="${REPO}:${TAG}"

case "$SERVICE" in
  product)   docker build -t "$IMAGE" -f ./product-service/Dockerfile . ;;
  inventory) docker build -t "$IMAGE" -f ./inventory-service/Dockerfile . ;;
  order)     docker build -t "$IMAGE" -f ./order-service/Dockerfile . ;;
  payment)   docker build -t "$IMAGE" -f ./payment-service/Dockerfile . ;;
  noti)      docker build -t "$IMAGE" -f ./notification-service/Dockerfile . ;;
  client)    docker build -t "$IMAGE" -f ./client/Dockerfile ./client ;;
  *) echo "Unknown service: $SERVICE" >&2; exit 1 ;;
esac
docker push "$IMAGE"
echo "Pushed $IMAGE"
