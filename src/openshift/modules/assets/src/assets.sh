#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

: "${ASSETS_DIR:?}" "${INSTALL_CONFIG:?}" "${PULL_SECRET_FILE:?}" "${SSH_PUBLIC_KEY_FILE:?}"
: "${CONTROL_PLANE_SCHEDULABLE:?}" "${INGRESS_REPLICAS:?}"
: "${IGNITION_BUCKET:?}" "${IGNITION_URL_TTL:?}" "${EXOSCALE_ZONE:?}"
: "${EXOSCALE_API_KEY:?}" "${EXOSCALE_API_SECRET:?}"

_RC_DIR="$(realpath "$(dirname "$0")/../rc")"
########################################################################################################################
# Secrets
########################################################################################################################
[[ -r "$PULL_SECRET_FILE" ]] || {
    echo "Pull secret not readable at ${PULL_SECRET_FILE}."
    exit 1
}

jq -e . "$PULL_SECRET_FILE" >/dev/null 2>&1 || {
    echo "Pull secret at ${PULL_SECRET_FILE} is not valid JSON." >&2
    exit 1
}

[[ -r "$SSH_PUBLIC_KEY_FILE" ]] || {
    echo "SSH public key not readable at ${SSH_PUBLIC_KEY_FILE}." >&2
    exit 1
}
########################################################################################################################
# Config
########################################################################################################################
rm -rf "$ASSETS_DIR"
mkdir -p "$ASSETS_DIR"

jq -n \
    --argjson config "$INSTALL_CONFIG" \
    --rawfile pullSecret "$PULL_SECRET_FILE" \
    --rawfile sshKey "$SSH_PUBLIC_KEY_FILE" \
    '$config + {pullSecret: ($pullSecret | fromjson | tojson), sshKey: ($sshKey | rtrimstr("\n"))}' |
    yq --prettyPrint --output-format yaml >"${ASSETS_DIR}/install-config.yaml"

cp "${ASSETS_DIR}/install-config.yaml" "${ASSETS_DIR}/install-config.bak.yaml"
########################################################################################################################
# Manifests
########################################################################################################################
openshift-install --dir "$ASSETS_DIR" create manifests

yq --inplace ".spec.mastersSchedulable = ${CONTROL_PLANE_SCHEDULABLE}" \
    "${ASSETS_DIR}/manifests/cluster-scheduler-02-config.yml"

envsubst '${INGRESS_REPLICAS}' \
    <"${_RC_DIR}/cluster-ingress-default-ingresscontroller.yaml" \
    >"${ASSETS_DIR}/manifests/cluster-ingress-default-ingresscontroller.yaml"
########################################################################################################################
# Ignition
########################################################################################################################
openshift-install --dir "$ASSETS_DIR" create ignition-configs

exo storage mb --zone "$EXOSCALE_ZONE" "sos://${IGNITION_BUCKET}" 2>/dev/null || true
exo storage upload "${ASSETS_DIR}/bootstrap.ign" "sos://${IGNITION_BUCKET}/bootstrap.ign"

_URL="$(exo storage presign --expires "$IGNITION_URL_TTL" "sos://${IGNITION_BUCKET}/bootstrap.ign")"
_VERSION="$(jq -r '.ignition.version' "${ASSETS_DIR}/bootstrap.ign")"
_DIGEST="sha512-$(sha512sum "${ASSETS_DIR}/bootstrap.ign" | cut -d' ' -f1)"

jq -n \
    --arg version "$_VERSION" \
    --arg source "$_URL" \
    --arg digest "$_DIGEST" \
    '{ignition: {version: $version, config: {replace: {source: $source, verification: {hash: $digest}}}}}' |
    tee "${ASSETS_DIR}/bootstrap.remote.ign"
