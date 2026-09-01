#!/usr/bin/env bash
########################################################################################################################
# KUBERNETES LOCAL
# Installs, upgrades, configures and resets minishift.
########################################################################################################################

function sc_kubernetes_local_up() {
    if minikube profile list | grep -q "$_ST_CONTEXT_KUBERNETES_LOCAL"; then
        minikube profile "$_ST_CONTEXT_KUBERNETES_LOCAL"
        minikube start --namespace serenditree
    else
        minikube start --profile "$_ST_CONTEXT_KUBERNETES_LOCAL" \
            --namespace serenditree \
            --driver kvm2 \
            --kubernetes-version "v$_ST_VERSION_KUBERNETES" \
            --cpus 8 \
            --memory 32000 \
            --disk-size 32000 \
            --addons metrics-server \
            --addons dashboard 2>&1 | sed '/#8426/d'
    fi
}

function sc_kubernetes_local_down() {
    if minikube status --profile "$_ST_CONTEXT_KUBERNETES_LOCAL" | grep -Eq "Stopped|not found"; then
        echo "Nothing to shut down."
    else
        until minikube stop --profile "$_ST_CONTEXT_KUBERNETES_LOCAL" --keep-context-active; do :; done
        sudo sed -i '/serenditree.io/d' /etc/hosts
        killall kubectl &>/dev/null
    fi
}

function sc_kubernetes_local_reset() {
    sc_heading 2 "Deleting profile..."
    minikube delete --profile "$_ST_CONTEXT_KUBERNETES_LOCAL"
    sc_heading 2 "Resetting context..."
    sc_context_init
}
