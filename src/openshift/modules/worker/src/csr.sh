#!/usr/bin/env bash

[[ -n "$KUBECONFIG" ]] || KUBECONFIG="$(realpath $0 | xargs dirname)/../../bootstrap/assets/dev/auth/kubeconfig"
export KUBECONFIG

_RETRY=0
[[ -n "$RETRIES" ]] || RETRIES=42

until oc get csr -o go-template='{{range .items}}{{if not .status}}{{.metadata.name}}{{"\n"}}{{end}}{{end}}' |
    xargs oc adm certificate approve || [[ $_RETRY -eq $RETRIES ]]; do ((_RETRY++)) && echo "Retry #$_RETRY"; done
