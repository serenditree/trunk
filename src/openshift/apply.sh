#!/usr/bin/env bash
########################################################################################################################
# Apply
########################################################################################################################
set -o errexit
set -o nounset
set -o pipefail

cd "$(dirname "$(realpath "$0")")"
source ./environment.sh

function apply() {
    local -r _bootstrap="$1"
    local -r _plan="serenditree.tfplan"
    shift

    echo "Apply with bootstrap_enabled=${_bootstrap}"
    tofu plan \
        -var="bootstrap_enabled=${_bootstrap}" \
        -var="base_domain=${_ST_DOMAIN}" \
        -var="api_cidr=[\"${_API_CIDR}\"]" \
        "$@" \
        -out="$_plan"

    tofu apply "$_plan"
    rm -f "$_plan"
}

tofu init -upgrade
# bootstrap
apply true "$@"
# complete
apply false "$@"
