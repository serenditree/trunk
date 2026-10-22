#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

_TIMEOUT="${TIMEOUT:-1800}"
_INTERVAL="${INTERVAL:-15}"
_DEADLINE=$((SECONDS + _TIMEOUT))
_READY=0

echo "Signing certificate signing requests..."

while ((_READY < EXPECTED_NODE_COUNT)) && ((SECONDS < _DEADLINE)); do
    # CSR is pending when it carries no condition yet.
    _PENDING="$(
        kubectl get csr -o json 2>/dev/null |
        jq -r '.items[] | select((.status.conditions // []) | length == 0) | .metadata.name' ||
        true
    )"

    if [[ -n "$_PENDING" ]]; then
        echo "$_PENDING" | xargs -r kubectl certificate approve || true
    fi

    _READY="$(
        kubectl get nodes -o json 2>/dev/null |
        jq '[.items[] | select(.status.conditions[]? | .type == "Ready" and .status == "True")] | length'
    )" || _READY=0

    if ((_READY < EXPECTED_NODE_COUNT)); then
        echo "${_READY}/${EXPECTED_NODE_COUNT} nodes Ready."
        sleep "$_INTERVAL"
    fi
done

if ((_READY < EXPECTED_NODE_COUNT)); then
    echo "Timed out waiting for ${EXPECTED_NODE_COUNT} nodes." >&2
    exit 1
else
    echo "${_READY}/${EXPECTED_NODE_COUNT} nodes Ready. Proceeding..."
    exit 0
fi
