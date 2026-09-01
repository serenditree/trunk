#!/usr/bin/env bash
########################################################################################################################
# Wait for nodes
########################################################################################################################
echo "Waiting for nodes..."
until kubectl wait --for condition=ready --all node 2>/dev/null; do sleep 1s; done
########################################################################################################################
# Argocd setup
########################################################################################################################
_ARGOCD_NEW_PASSWORD="$(pass serenditree/cicd/terraArgocd.password)"
_GHCR_PKG_READ="$(pass serenditree/ext/ghcr.io)"
_SUCCESS=0

until [[ $_SUCCESS -eq 4 ]]; do
########################################################################################################################
# Get argocd password
########################################################################################################################
    if [[ -z "$_ARGOCD_INITIAL_PASSWORD" ]]; then
        _ARGOCD_INITIAL_PASSWORD="$(
            kubectl get secret/argocd-initial-admin-secret \
                --namespace terra-argocd  \
                --output jsonpath='{.data.password}' | base64 --decode
        )"
    fi
########################################################################################################################
# Start port-forwarding
########################################################################################################################
    if [[ -n "$_PORT_FORWARD_PID" ]]; then
        kill "$_PORT_FORWARD_PID" 2>/dev/null || true
    fi
    kubectl port-forward --namespace terra-argocd svc/terra-argocd-server 9098:443 &>/tmp/argocd-server.log &
    _PORT_FORWARD_PID=$!
    sleep 2s
########################################################################################################################
# Update argocd password
########################################################################################################################
    [[ $_SUCCESS -eq 0 ]] &&
        argocd login localhost:9098 \
            --insecure \
            --username admin \
            --password "$_ARGOCD_INITIAL_PASSWORD" &&
            (( ++_SUCCESS ))

    [[ $_SUCCESS -eq 1 ]] &&
        argocd account update-password \
            --account admin \
            --current-password "$_ARGOCD_INITIAL_PASSWORD" \
            --new-password "$_ARGOCD_NEW_PASSWORD" &&
            (( ++_SUCCESS ))
########################################################################################################################
# Add git repository
########################################################################################################################
    [[ $_SUCCESS -eq 2 ]] &&
        argocd repo add "$_ST_GIT" \
            --ssh-private-key-path "$_ST_GIT_SSH" \
            --project default \
            --name serenditree-trunk &&
            (( ++_SUCCESS ))
########################################################################################################################
# Add ghcr helm repository
########################################################################################################################
    [[ $_SUCCESS -eq 3 ]] &&
        argocd repo add 'ghcr.io' \
            --username "${_GHCR_PKG_READ%:*}" \
            --password "${_GHCR_PKG_READ#*:}" \
            --type helm \
            --enable-oci \
            --project default \
            --name github-helm &&
            (( ++_SUCCESS ))
done
