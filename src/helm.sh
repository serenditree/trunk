#!/usr/bin/env bash
########################################################################################################################
# HELM
# Collection of helm helpers.
########################################################################################################################
# shellcheck disable=SC2155,SC2048

# Helm repo setup and initial dependencies update.
function sc_helm_setup() {
    sc_heading 1 "Setting up helm"
    if [[ -z "$_ARG_DRYRUN" ]]; then
        echo "Adding repos..."
        while IFS=";" read -r _repo _url; do
            echo -n "${_repo}..."
            if helm repo ls | grep -Eq "^${_repo}"; then
                sc_heading 2 "set"
            else
                helm repo add "$_repo" "$_url"
            fi
        done <"${_ST_HOME_TRUNK}/rc/config/helm-setup"
    fi
}

# Subroutine for pulling charts in parallel.
# $1: Chart to pull.
# $2: Pattern to filter charts.
function sc_helm_pull_sub() {
    local -r _chart=$1
    local -r _pattern=$2
    local -r _destination="./charts"

    if grep -Eq '^dependencies:' "$_chart" && grep -Eq "$_pattern" "$_chart"; then
        pushd "$(dirname "$_chart")" &>/dev/null || exit 1
        rm -rf $_destination
        mkdir $_destination
        while read -r _name _repo _version; do
            if [[ "$_repo" =~ ^oci:// ]]; then
                # OCI registry
                helm pull "${_repo}/${_name}" --version "$_version" --destination $_destination &>/dev/null
            else
                # Index-based repo
                helm pull "$_name" --repo "$_repo" --version "$_version" --destination $_destination
            fi

            if [[ $? -eq 0 ]]; then
                echo "Pulled ${_BOLD}${_name}:${_version}${_NORMAL} for ${_chart}."
            else
                echo "${_BOLD}Error${_NORMAL}: Could not pull ${_name}:${_version} for ${_chart}."
            fi
        done < <(sed -En 's/[- ]+(name|repository|version): (.*)/\2/'p "$_chart" | xargs -n3)
        popd &>/dev/null || exit 1
    fi
}
export -f sc_helm_pull_sub

# Pulls chart dependencies.
function sc_helm_pull() {
    [[ -n "$_ARG_INIT" ]] && sc_helm_setup
    sc_heading 1 "Pulling dependencies..."
    local -r _pattern="$(sc_args_to_pattern ${_ARG_LEFTOVERS[*]:1})"
    # shellcheck disable=SC2038
    find "${_ST_HOME_TRUNK}/charts" -name Chart.yaml |
        xargs -P4 -n1 bash -c 'sc_helm_pull_sub $2 $1' _ "$_pattern"
}

# Packages and pushes the named template library.
function sc_helm_push() {
    sc_heading 1 "Pushing dependencies..."
    # commons
    sc_heading 2 "Commons"
    pushd "${_ST_HOME_TRUNK}/charts/soil/commons" >/dev/null || exit 1
    rm -f ./*.tgz
    helm package .
    helm push "$(ls ./*.tgz)" oci://quay.io/serenditree/charts
    # crds
    sc_heading 2 "CRDs"
    pushd "${_ST_HOME_TRUNK}/charts/soil/crds" >/dev/null || exit 1
    echo "Extracting CRDs..."
    rm -fv ./*.tgz ./templates/*
    sc_helm_template crds
    helm package .
    helm push "$(ls ./*.tgz)" oci://quay.io/serenditree/charts
}

# Prepares helm values to set.
function sc_helm_values() {
    sc_terra_render |
        sed -E -e 's/value:\s*$/value: known-after-apply/' -e '/kustomize:/,/value:/d' |
        sed -En -e 's/.*(- name:|value:) (.*)/\2/p' |
        xargs -n2 echo '--set' |
        sed 's/service.beta.kubernetes.io\/exoscale-loadbalancer-id/exoscale-loadbalancer-id/' |
        tr ' ' '=' |
        sort -u
}

# Splits a YAML file into parts at document boundaries when it exceeds helm's 5MB file size limit.
# $1: File to split
function sc_helm_split_large() {
    local -r _file="$1"
    local -r _base="${_file%.yaml}"
    local -r _tmpdir=$(mktemp -d)
    local _part=1
    local _part_file="${_base}-${_part}.yaml"
    local _part_size=0

    # Split into one file per YAML document
    csplit \
        --prefix="${_tmpdir}/doc-" \
        --suffix-format='%04d.yaml' \
        --quiet \
        "$_file" '/^---$/' '{*}' 2>/dev/null

    # Merge documents into parts under helm's 5MB file size limit
    for _doc in "${_tmpdir}"/doc-*.yaml; do
        local _doc_size=$(wc -c <"$_doc")
        if (( _part_size > 0 && _part_size + _doc_size > 4500000 )); then
            ((_part++))
            _part_file="${_base}-${_part}.yaml"
            _part_size=0
        fi
        cat "$_doc" >>"$_part_file"
        (( _part_size += _doc_size ))
    done

    rm -rf "$_tmpdir" "$_file"
    echo "Split ${_file##*/} into ${_part} parts."
}

# Saves extracted CRDs with annotations needed by helm.
# $1: Values for helm
# $2: Name of the chart
function sc_helm_save_crds() {
    local -r _values="$1"
    local -r _name="$2"
    local -r _out="${_ST_HOME_TRUNK}/charts/soil/crds/templates/${_name}.yaml"
    local -r _crds="
        select(.kind == \"CustomResourceDefinition\") |
        .metadata.labels +=
        {\"app.kubernetes.io/managed-by\": \"Helm\"} |
        .metadata.annotations +=
        {\"meta.helm.sh/release-name\": \"${_name}\",
        \"meta.helm.sh/release-namespace\": \"${_name}\"}
    "

    echo "$_values" |
        xargs helm template --include-crds --namespace "$_name" "$_name" . |
        yq "$_crds" >"$_out"

    # Remove files without CRDs; split if larger than helm's 5MB file size limit
    if [[ ! -s "$_out" ]]; then
        rm "$_out"
    elif (( $(wc -c <"$_out") > 5242880 )); then
        sc_helm_split_large "$_out"
    fi
}

# Renders templates locally.
# $1: Flag to export CRDs
function sc_helm_template() {
    local _include_crds=--include-crds
    if [[ "$1" != "crds" ]]; then
        local -r _pattern="$(sc_args_to_pattern ${_ARG_LEFTOVERS[*]:1})"
        [[ -z "$_ARG_VERBOSE" ]] &&
            _include_crds= &&
            local -r _crds='select(.kind != "CustomResourceDefinition")' &&
            echo -e "Skipping CRDs\n" >&2
    else
        local -r _pattern="$(sc_args_to_pattern ${_ARG_LEFTOVERS[*]:1})"
    fi

    [[ -f "$_ST_CONTEXT_PLAN" ]] ||
        { echo "Plan (${_ST_CONTEXT_PLAN##*/}) does not exist. Aborting..." && exit 1; }
    [[ "$1" != "crds" ]] && echo -n "Preparing values..." >&2
    local -r _values=$(sc_helm_values | sed -E 's/\.parameters\././')
    [[ "$1" != "crds" ]] && echo -e "done\n\n${_values}\n" >&2

    while read -r _chart; do
        pushd "${_chart%/*}" >/dev/null || exit 1
        local _name="$(sed -En 's/^name: (.*)/\1/p' Chart.yaml)"
        if [[ $_name =~ $_pattern ]]; then
            if [[ "$1" != "crds" ]]; then
                sc_heading 1 "$_name" >&2
                echo "$_values" | xargs helm template $_include_crds --namespace "$_name" "$_name" . | yq "$_crds"
            else
                sc_helm_save_crds "$_values" "$_name"
            fi
        fi
        popd >/dev/null || exit 1
    done < <(find "${_ST_HOME_TRUNK}/charts" -type d -name soil -prune -o -name Chart.yaml -print)
}

# Prints chart information.
function sc_helm_charts() {
    while read -r _chart; do
        local _name="$(sed -En 's/^name: (.*)/\1/p' "$_chart")"
        if [[ -n "$_ARG_VERBOSE" ]]; then
            sc_heading 1 "$_name"
            yq "$_chart"
        else
            # Service, version, path
            echo "$_name" "$(sed -En 's/^version: ([0-9.]+).*/\1/p' "$_chart")" "${_chart%/*}"
        fi
    done < <(find "${_ST_HOME_TRUNK}/charts" -name Chart.yaml)
}

# Entrypoint for helm commands.
# $1: Subcommand
function sc_helm() {
    case $1 in
    charts)
        if [[ -n "$_ARG_VERBOSE" ]]; then
            sc_helm_charts
        else
            sc_helm_charts | nl | column -tN ORDINAL,SERVICE,VERSION,PATH
        fi
        ;;
    push)
        sc_helm_push
        ;;
    pull)
        sc_helm_pull
        ;;
    setup)
        sc_helm_setup
        ;;
    template)
        sc_helm_template
        ;;
    esac
}

