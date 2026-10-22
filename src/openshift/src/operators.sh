#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

: "${KUBECONFIG:?}" "${OPERATORS:?}"
export KUBECONFIG

_RC_DIR="$(realpath "$(dirname "$0")/../rc/operators")"
_CATALOG_NAMESPACE="${CATALOG_NAMESPACE:-openshift-marketplace}"
_TIMEOUT="${TIMEOUT:-1800}"
_INTERVAL="${INTERVAL:-15}"
#OPERATORS="$(cat "${_RC_DIR}/operators.json")"
########################################################################################################################
# Helpers
########################################################################################################################
function waiting_for() {
    local _description="$1"
    shift

    local _deadline=$((SECONDS + _TIMEOUT))
    while ((SECONDS < _deadline)); do
        if "$@"; then
            return 0
        fi

        echo "Waiting for ${_description}..."
        sleep "$_INTERVAL"
    done

    echo "Timed out after ${_TIMEOUT}s ${_description}." >&2
    return 1
}

function package_available() {
    kubectl get packagemanifest "$1" -n "$_CATALOG_NAMESPACE" >/dev/null 2>&1
}

function csv_succeeded() {
    local _package="$1" _namespace="$2"

    local _csv
    _csv="$(
        kubectl get subscription "$_package" -n "$_namespace" -o jsonpath='{.status.installedCSV}' 2>/dev/null ||
        true
    )"
    [[ -n "$_csv" ]] || return 1

    local _phase
    _phase="$(kubectl get csv "$_csv" -n "$_namespace" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    [[ "$_phase" == "Succeeded" ]]
}

function operand_ready() {
    local _resource="$1" _name="$2" _namespace="$3" _jsonpath="$4" _value="$5"

    local _args=(get "$_resource" "$_name" -o "jsonpath=${_jsonpath}")
    if [[ -n "$_namespace" ]]; then
        _args+=(-n "$_namespace")
    fi

    local _current
    _current="$(kubectl "${_args[@]}" 2>/dev/null || true)"
    [[ "$_current" == "$_value" ]]
}
########################################################################################################################
# Subscriptions
########################################################################################################################
_ENTRIES="$(jq -c '.[]' <<<"$OPERATORS")" || {
    echo "OPERATORS is not a JSON array of operator objects." >&2
    exit 1
}

[[ -n "$_ENTRIES" ]] || {
    echo "No operators requested."
    exit 0
}

while read -r _operator; do
    OPERATOR_PACKAGE="$(jq -r '.package' <<<"$_operator")"
    OPERATOR_NAMESPACE="$(jq -r '.namespace' <<<"$_operator")"
    OPERATOR_CATALOG="$(jq -r '.catalog' <<<"$_operator")"
    OPERATOR_CHANNEL="$(jq -r '.channel' <<<"$_operator")"
    CATALOG_NAMESPACE="$_CATALOG_NAMESPACE"
    export OPERATOR_PACKAGE OPERATOR_NAMESPACE OPERATOR_CATALOG OPERATOR_CHANNEL CATALOG_NAMESPACE

    echo "==> ${OPERATOR_PACKAGE} in ${OPERATOR_NAMESPACE}"

    # The catalog pods start with everything else, so right after install-complete the package can still be missing.
    waiting_for "${OPERATOR_PACKAGE} to appear in catalog ${OPERATOR_CATALOG}" \
        package_available "$OPERATOR_PACKAGE" || {
        echo "Package ${OPERATOR_PACKAGE} is not offered by any catalog. Check 'kubectl get catalogsource -n" >&2
        echo "${_CATALOG_NAMESPACE}' and 'kubectl get packagemanifest -n ${_CATALOG_NAMESPACE}'." >&2
        exit 1
    }

    if [[ -z "$OPERATOR_CHANNEL" ]]; then
        OPERATOR_CHANNEL="$(
            kubectl get packagemanifest "$OPERATOR_PACKAGE" -n "$_CATALOG_NAMESPACE" \
                -o jsonpath='{.status.defaultChannel}'
        )"
        [[ -n "$OPERATOR_CHANNEL" ]] || {
            echo "Package ${OPERATOR_PACKAGE} reports no default channel, pin one in the operators variable. The" >&2
            echo "choices: kubectl get packagemanifest ${OPERATOR_PACKAGE} -n ${_CATALOG_NAMESPACE} -o" >&2
            echo "jsonpath='{.status.channels[*].name}'." >&2
            exit 1
        }

        echo "Channel not pinned, using the package default: ${OPERATOR_CHANNEL}."
    fi

    # openshift-operators comes with the global-operators OperatorGroup; any other namespace has to be created and
    # given one, and GitOps wants its own (openshift-gitops-operator) rather than the shared namespace.
    if ! kubectl get namespace "$OPERATOR_NAMESPACE" >/dev/null 2>&1 ||
        [[ -z "$(kubectl get operatorgroup -n "$OPERATOR_NAMESPACE" -o name 2>/dev/null)" ]]; then
        envsubst '${OPERATOR_NAMESPACE}' <"${_RC_DIR}/operator-group.yaml" | kubectl apply -f -
    fi

    envsubst '${OPERATOR_PACKAGE} ${OPERATOR_NAMESPACE} ${OPERATOR_CHANNEL} ${OPERATOR_CATALOG} ${CATALOG_NAMESPACE}' \
        <"${_RC_DIR}/subscription.yaml" | kubectl apply -f -

    waiting_for "the ${OPERATOR_PACKAGE} CSV to reach Succeeded" \
        csv_succeeded "$OPERATOR_PACKAGE" "$OPERATOR_NAMESPACE" || {
        echo "The ${OPERATOR_PACKAGE} install did not complete. Check 'kubectl describe subscription" >&2
        echo "${OPERATOR_PACKAGE} -n ${OPERATOR_NAMESPACE}' and 'kubectl get csv -n ${OPERATOR_NAMESPACE}'." >&2
        exit 1
    }

    echo "${OPERATOR_PACKAGE} installed."
    ####################################################################################################################
    # Operand
    ####################################################################################################################
    # A Succeeded CSV only means the operator itself is running.
    _RESOURCE="$(jq -r '.operand.resource // ""' <<<"$_operator")"
    [[ -n "$_RESOURCE" ]] || continue

    _NAME="$(jq -r '.operand.name' <<<"$_operator")"
    _NAMESPACE="$(jq -r '.operand.namespace // ""' <<<"$_operator")"
    _JSONPATH="$(jq -r '.operand.jsonpath' <<<"$_operator")"
    _VALUE="$(jq -r '.operand.value' <<<"$_operator")"

    waiting_for "${_RESOURCE}/${_NAME} to report ${_VALUE}" \
        operand_ready "$_RESOURCE" "$_NAME" "$_NAMESPACE" "$_JSONPATH" "$_VALUE" || {
        echo "${_RESOURCE}/${_NAME} never reported ${_VALUE}. Check 'kubectl describe ${_RESOURCE} ${_NAME}" >&2
        echo "${_NAMESPACE:+-n $_NAMESPACE}'." >&2
        exit 1
    }

    echo "${_RESOURCE}/${_NAME} is ${_VALUE}."

    if [[ -n "$_NAMESPACE" ]]; then
        kubectl get route -n "$_NAMESPACE" \
            -o custom-columns='ROUTE:.metadata.name,HOST:.spec.host' --no-headers 2>/dev/null |
            while read -r _route _host; do
                echo "${_route}: https://${_host}"
            done
    fi
done <<<"$_ENTRIES"
########################################################################################################################
# Console plugins
########################################################################################################################
_PLUGINS="$(kubectl get consoleplugins.console.openshift.io -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)"

if [[ -z "$_PLUGINS" ]]; then
    echo "No console plugins to enable."
elif ! kubectl get console.operator.openshift.io cluster >/dev/null 2>&1; then
    echo "No console operator, leaving the console plugins alone." >&2
else
    _ENABLED="$(kubectl get console.operator.openshift.io cluster -o jsonpath='{.spec.plugins[*]}' 2>/dev/null || true)"
    # shellcheck disable=SC2086
    _MERGED="$(jq -cn --args '$ARGS.positional | unique' $_ENABLED $_PLUGINS)"

    echo "Console plugins ${_MERGED}"
    kubectl patch console.operator.openshift.io cluster \
        --type=merge \
        --patch "{\"spec\":{\"plugins\":${_MERGED}}}"
fi

echo "All operators installed."
