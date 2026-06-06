#!/bin/bash
set -e

echo "Generating internal kubeconfig for Jenkins..."

TMP_KUBECONFIG=$(mktemp)
# Copy host kubeconfig
cp ~/.kube/config $TMP_KUBECONFIG

# Get internal Docker IPs of the control plane nodes
MGMT_IP=$(docker inspect management-control-plane --format '{{.NetworkSettings.Networks.kind.IPAddress}}')
DEV_IP=$(docker inspect dev-control-plane --format '{{.NetworkSettings.Networks.kind.IPAddress}}')
STAGING_IP=$(docker inspect staging-control-plane --format '{{.NetworkSettings.Networks.kind.IPAddress}}')
PROD_IP=$(docker inspect prod-control-plane --format '{{.NetworkSettings.Networks.kind.IPAddress}}')

echo "Management IP: $MGMT_IP"
echo "Dev IP: $DEV_IP"
echo "Staging IP: $STAGING_IP"
echo "Prod IP: $PROD_IP"

# Replace localhost addresses with internal Docker addresses
sed -i "s/127.0.0.1:33443/$MGMT_IP:6443/g" $TMP_KUBECONFIG
sed -i "s/127.0.0.1:30443/$DEV_IP:6443/g" $TMP_KUBECONFIG
sed -i "s/127.0.0.1:32443/$STAGING_IP:6443/g" $TMP_KUBECONFIG
sed -i "s/127.0.0.1:31443/$PROD_IP:6443/g" $TMP_KUBECONFIG

echo "Creating/Updating Secret 'jenkins-internal-kubeconfig' in kind-management cluster..."

kubectl --context kind-management create namespace jenkins --dry-run=client -o yaml | kubectl --context kind-management apply -f -
kubectl --context kind-management -n jenkins create secret generic jenkins-internal-kubeconfig \
  --from-file=config=$TMP_KUBECONFIG \
  --dry-run=client -o yaml | kubectl --context kind-management apply -f -

rm $TMP_KUBECONFIG
echo "Done! The internal kubeconfig has been securely stored in the 'jenkins' namespace."
