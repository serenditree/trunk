#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

: "${KUBECONFIG:?}" "${EXPECTED_NODE_COUNT:?}" "${BOOTSTRAP_IP:?}"
export KUBECONFIG

_TIMEOUT="${TIMEOUT:-2700}"
_INTERVAL="${INTERVAL:-20}"

echo "Waiting for etcd to run on the control plane (timeout ${_TIMEOUT}s)."

_DEADLINE=$((SECONDS + _TIMEOUT))
while ((SECONDS < _DEADLINE)); do
    _READY="$(
        kubectl get nodes -l node-role.kubernetes.io/master -o json 2>/dev/null |
        jq '[.items[] | select(.status.conditions[]? | .type == "Ready" and .status == "True")] | length' ||
        echo 0
    )"
    _READY="$(tail -1 <<<"$_READY")"
    _READY="${_READY:-0}"

    _STATUS="$(
        kubectl get etcd cluster -o json 2>/dev/null |
        jq -r '(.status.conditions // [])[] | select(.type == "EtcdRunningInCluster") | .status' ||
        true
    )"

    if [[ "$_STATUS" == "True" ]]; then
        echo "EtcdRunningInCluster=True with ${_READY}/${EXPECTED_NODE_COUNT} control plane nodes Ready."
        break
    fi

    echo "${_READY}/${EXPECTED_NODE_COUNT} control plane nodes Ready, EtcdRunningInCluster=${_STATUS:-Unknown}, waiting..."
    sleep "$_INTERVAL"
done

if [[ "$_STATUS" != "True" ]]; then
    echo "Timed out waiting for the etcd handover. Check 'kubectl get etcd cluster -o yaml' and the bootkube journal on" >&2
    echo "the bootstrap node: ssh core@bootstrap.<cluster_domain> 'journalctl -u bootkube.service'." >&2
    exit 1
fi
########################################################################################################################
# Teardown
########################################################################################################################
echo "Waiting for bootkube to tear the bootstrap control plane down (${BOOTSTRAP_IP}:6443)."

while ((SECONDS < _DEADLINE)); do
    if ! timeout 5 bash -c "exec 3<>/dev/tcp/${BOOTSTRAP_IP}/6443" 2>/dev/null; then
        echo "Bootstrap kube-apiserver is gone - bootkube has finished. Phase 2 can repoint api-int now."
        exit 0
    fi

    echo "Bootstrap kube-apiserver still serving, waiting..."
    sleep "$_INTERVAL"
done

echo "Timed out waiting for the bootstrap control plane to stop serving :6443. Check the bootkube journal:" >&2
echo "ssh core@${BOOTSTRAP_IP} 'journalctl -u bootkube.service'." >&2
exit 1
