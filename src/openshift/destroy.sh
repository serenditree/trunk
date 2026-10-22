#!/usr/bin/env bash
########################################################################################################################
# Destroy
########################################################################################################################
set -o errexit
set -o pipefail

cd "$(dirname "$(realpath "$0")")"
########################################################################################################################
# Collect
########################################################################################################################
source ./environment.sh
_API_CIDR="$(tofu output -json api_cidr 2>/dev/null || echo "[\"${_API_CIDR}\"]")"
_ASSETS_DIR="$(tofu output -raw assets_dir 2>/dev/null || true)"
_TEMPLATE_NAME="$(tofu output -raw template_name 2>/dev/null || true)"
_TEMPLATE_BUCKET="$(tofu output -raw template_bucket 2>/dev/null || echo "$_TEMPLATE_NAME")"
_ZONE="$(tofu output -raw zone 2>/dev/null || echo "${EXOSCALE_ZONE:-at-vie-2}")"

echo "Saving persistent volumes..."
kubectl get pv --output=custom-columns='name:.metadata.name' --no-headers | tee /tmp/serenditree-pv
########################################################################################################################
# Infrastructure
########################################################################################################################
tofu destroy \
    -var="bootstrap_enabled=false" \
    -var="base_domain=${_ST_DOMAIN}" \
    -var="api_cidr=${_API_CIDR}" \
    "${_ARGS[@]}"
########################################################################################################################
# Leftovers
########################################################################################################################
echo "Deleting volumes..."
xargs -I{} -P0 -r bash -c \
    'echo "Deleting {}..." && exo compute block-storage delete --force --quiet {} && echo "Deleted {}"' \
    </tmp/serenditree-pv

if [[ -n "$_ARG_RESET" ]]; then
    if [[ -n "$_TEMPLATE_NAME" ]]; then
        exo storage delete --force "sos://${_TEMPLATE_BUCKET}/${_TEMPLATE_NAME}" || true
    fi

    _TEMPLATE_ID="$(
        exo compute instance-template show \
            --zone "$_ZONE" \
            --visibility private \
            --output-format json \
            "$_TEMPLATE_NAME" 2>/dev/null | jq -r '.id' || true
    )"

    if [[ -n "$_TEMPLATE_ID" && "$_TEMPLATE_ID" != "null" ]]; then
        exo compute instance-template delete --zone "$_ZONE" --force "$_TEMPLATE_ID" || true
    fi

    if [[ -n "$_ASSETS_DIR" && -d "$_ASSETS_DIR" ]]; then
        rm -rfv "$_ASSETS_DIR"
    fi
fi
