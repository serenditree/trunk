#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

: "${KUBECONFIG:?}" "${CSI_API_KEY:?}" "${CSI_API_SECRET:?}"

_RC_DIR="$(realpath "$(dirname "$0")/../rc/csi")"
_STORAGE_CLASS="${CSI_STORAGE_CLASS:-exoscale-sbs}"
_DEFAULT_CLASS="${CSI_DEFAULT_CLASS:-true}"
_NAMESPACE="${CSI_NAMESPACE:-kube-system}"
_TIMEOUT="${TIMEOUT:-600}"
########################################################################################################################
# Credentials
########################################################################################################################
echo "Installing exoscale-credentials for the csi-driver..."
kubectl apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: exoscale-credentials
  namespace: ${_NAMESPACE}
type: Opaque
stringData:
  EXOSCALE_API_KEY: "${CSI_API_KEY}"
  EXOSCALE_API_SECRET: "${CSI_API_SECRET}"
EOF
########################################################################################################################
# Driver
########################################################################################################################
echo "Installing exoscale-csi-driver from ${_RC_DIR}..."
kubectl apply -k "$_RC_DIR"

kubectl rollout status deployment/exoscale-csi-controller -n "$_NAMESPACE" --timeout="${_TIMEOUT}s"
kubectl rollout status daemonset/exoscale-csi-node -n "$_NAMESPACE" --timeout="${_TIMEOUT}s"
########################################################################################################################
# Default Storage Class
########################################################################################################################
kubectl patch storageclass "$_STORAGE_CLASS" \
    --patch "{\"metadata\":{\"annotations\":{\"storageclass.kubernetes.io/is-default-class\":\"${_DEFAULT_CLASS}\"}}}"
