#!/usr/bin/env bash
argocd login "$ARGOCD_SERVER" \
    --username "$ARGOCD_USERNAME" \
    --password "$ARGOCD_PASSWORD" \
    --insecure

if [[ "$(params.action)" == "deploy" ]]; then
    argocd app actions run "$(params.app)" restart \
        --server "$ARGOCD_SERVER" \
        --kind "$(params.kind)" \
        --all
elif [[ "$(params.action)" == "sync" ]]; then
    argocd app sync "$(params.app)" \
        --server "$ARGOCD_SERVER"
else
    echo "Action must be 'deploy' or 'sync', but '$(params.action)' was passed."
    exit 1
fi

argocd app wait "$(params.app)" \
    --server "$ARGOCD_SERVER" \
    --health \
    --timeout "$(params.timeout)"
