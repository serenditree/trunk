#!/usr/bin/env bash
########################################################################################################################
# Patch storage class
########################################################################################################################
kubectl patch storageclass exoscale-sbs \
    --namespace kube-system \
    --patch '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
########################################################################################################################
# Install extracted CRDs
########################################################################################################################
kubectl apply --server-side --filename "$CRDS"
########################################################################################################################
# Install gateway CRDs
########################################################################################################################
case "$GATEWAY" in
traefik)
    kubectl apply --server-side --filename \
        https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.2/standard-install.yaml
    ;;
envoy)
    helm template eg-crds oci://docker.io/envoyproxy/gateway-crds-helm \
        --set 'crds.envoyGateway.enabled=true' \
        --set 'crds.gatewayAPI.enabled=true' \
        --set 'crds.gatewayAPI.channel=standard' \
        --version "$(grep -A1 envoyproxy "$GATEWAY_CHART" | grep -Eo "v[0-9.]+")" |
        grep -Ev '^(Pulled|Digest):' |
        kubectl apply --server-side --filename -
    ;;
*)
    echo "Gateway must be one of traefik or envoy. Got [${GATEWAY}]."
    exit 1
    ;;
esac
