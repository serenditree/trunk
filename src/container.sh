#!/usr/bin/env bash
########################################################################################################################
# CONTAINER/IMAGE
# Common routines for image and container manipulation.
########################################################################################################################
# shellcheck disable=SC2155

# Stops and removes the given container.
# $1: Container id or name.
function sc_container_rm() {
    local -r _container=$1
    echo "Removing container ${_container}..."
    podman container ls | grep -q $_container && podman container stop $_container
    podman container exists $_container && podman container rm $_container
}
export -f sc_container_rm

# Removes inherited labels.
# $1: Base image identifier for retrieving existing labels.
# $2: Reference to the temporary container for label removal.
function sc_label_rm() {
    local -r _from=$1
    local -r _reference=$2
    echo "Removing inherited labels..."
    buildah inspect $_from | jq -r '.OCIv1.config.Labels | to_entries[] | "\(.key)-"' |
        xargs -I{} buildah config --label {} $_reference
}
export -f sc_label_rm

# Removes a predefined set of inherited environment variables.
# $1: Reference to the temporary container for environment variable removal.
function sc_env_rm() {
    local -r _reference=$1
    echo "Removing inherited environment variables..."
    buildah config \
        --env SUMMARY- \
        --env DESCRIPTION- \
        --env STI_SCRIPTS_URL- \
        --env STI_SCRIPTS_PATH- \
        $_reference
}
export -f sc_env_rm

# Retrieves the given environment variable from the given image.
# $1: Image identifier.
# $2: Environment variable of interest.
function sc_env_get() {
    local -r _image=$1
    local -r _env=$2
    podman inspect $_image | sed -En "s/.*${_env}=([^\"]+).*/\1/p"
}
export -f sc_env_get

# Builds all or defined images based on the build block of the corresponding plot.
# $*: Optional list of images to build. Images are selected by grep pattern matching.
function sc_build() {
    local -r _plots="$(sc_args_to_pattern "$*")"
    if [[ -z "$_ST_CONTEXT_TKN" ]] && [[ "node-base" =~ $_plots ]]; then
        sc_heading 1 "Checking preconditions"
        sc_status_build_node
    fi
    sc_plots_do "${_plots}" build
}

# Upgrades images.
# $1: Package manager {dnf | dnf-host | apt}.
# $2: Container or mount reference.
function sc_image_upgrade() {
    local -r _pkg_mgr=$1
    local -r _reference=$2

    case "$_pkg_mgr" in
        "dnf")
            buildah run --user 0:0 $_reference -- dnf distro-sync --assumeyes --noplugins
            buildah run --user 0:0 $_reference -- dnf clean all --noplugins
            ;;
        "dnf-host")
            $_ST_DNF_HOST distro-sync --installroot ${_reference:?} $_ST_DNF_OPTS_HOST
            $_ST_DNF_HOST clean all --installroot ${_reference:?} --noplugins
            ;;
        "apt")
            buildah run --user 0:0 $_reference -- apt update
            buildah run --user 0:0 $_reference -- apt upgrade -y
            buildah run --user 0:0 $_reference -- apt clean
            buildah run --user 0:0 $_reference -- rm -rf /var/lib/apt/lists/*
            ;;
    esac
}
export -f sc_image_upgrade

# Unified, OCI formatted buildah image commit.
# $1: Image identifier.
# $2: Image tag.
# $3: Reference to the temporary container.
# $4: Flag to add platform config.
function sc_image_commit() {
    local -r _image=$1
    local -r _tag=$2
    local -r _reference=$3
    local -r _platform_config=$4

    if [[ "$_platform_config" == "on" ]]; then
        _OS_NAME="linux"
        _OS_VERSION="$(uname -r)"
        _PLATFORM_ARCH="amd64"
        buildah config \
            --os "$_OS_NAME" \
            --os-version "$_OS_VERSION" \
            --arch "$_PLATFORM_ARCH" \
            --env OS_NAME="$_OS_NAME" \
            --env OS_VERSION="$_OS_VERSION" \
            --env PLATFORM_ARCH="$_PLATFORM_ARCH" \
            $_reference
    fi

    buildah commit --format oci $_reference ${_image}:${_tag}

    buildah inspect $_reference | jq '.OCIv1.config'
    buildah umount $_reference &>/dev/null
    buildah rm $_reference
}
export -f sc_image_commit

# Unified, OCI formatted buildah image commit with additional labels and environment variables to set. Used for
# services by now.
# $1: Name of the service the image defines.
# $2: Image identifier.
# $3: Version of the service.
# $4: Image tag.
# $5: Ordinal for sorting and build/deployment order.
# $6: Reference to the temporary container.
# $7: Flag to add platform config.
function sc_image_config_commit() {
    local -r _service=$1
    local -r _image=$2
    local -r _version=$3
    local -r _tag=$4
    local -r _ordinal=$5
    local -r _reference=$6
    local -r _platform_config=$7

    buildah config \
        --label serenditree.io/service=$_service \
        --label serenditree.io/version=$_version \
        --label serenditree.io/ordinal=$_ordinal \
        --label serenditree.io/stage=$_ST_STAGE \
        --env SERENDITREE_SERVICE=$_service \
        --env SERENDITREE_VERSION=$_version \
        --env SERENDITREE_ORDINAL=$_ordinal \
        --env SERENDITREE_STAGE=$_ST_STAGE \
        --env SERENDITREE_BUILD="$(date --iso-8601=seconds)" \
        $_reference

    sc_image_commit "$_image" "$_tag" "$_reference" "$_platform_config"
}
export -f sc_image_config_commit

# Tags and pushes an image to $_ST_REGISTRY.
# $1: Image identifier.
# $2: Image tag.
function sc_push() {
    local -r _image=$1
    local -r _tag=$2
    local -r _target="${_ST_REGISTRY}/${_image}:${_tag}"

    if [[ -z "$_ST_CONTEXT_TKN" ]]; then
        # Copy using skopeo in local context.
        echo "Copying to ${_target}..."
        if [[ -z "$_ST_CONTEXT_OPENSHIFT" ]]; then
            local -r _skopeo_args='--dest-tls-verify=false'
        fi
        skopeo copy $_skopeo_args \
            containers-storage:localhost/${_image}:${_tag} \
            docker://${_target}
    else
        # Tag and push using buildah in CI environment.
        echo "Tagging ${_image}:${_tag} > ${_target}..."
        buildah tag "${_image}:${_tag}" "$_target"

        echo "Pushing ${_target}..."
        if [[ -z "$_ST_CONTEXT_OPENSHIFT" ]]; then
            local -r _buildah_args='--tls-verify=false'
        fi
        buildah push --digestfile /tmp/digestfile $_buildah_args "$_target"
        echo "${_target}@$(</tmp/digestfile)" | tee -a "$_ST_BUILD_RESULTS_PATH"
    fi
}
export -f sc_push

# Tags and pushes all or selected images defined in plots to $_ST_REGISTRY.
# $1: Pattern to select images.
function sc_push_plots() {
    #${_ORDINAL} ${_SERVICE} ${_IMAGE} ${_TAG} $(realpath $0)
    sc_plots "$1" | while read -r -a _plot; do
        local _image=${_plot[2]}
        local _tag=${_plot[3]}
        if [[ -n "${_image/-/}" ]]; then
            sc_heading 1 "Pushing ${_image}:${_tag} (${_ST_STAGE})"
            [[ -z "$_ARG_DRYRUN" ]] && sc_push $_image $_tag
        fi
    done
}
export -f sc_push_plots

# Inspects images in remote registries.
# $1: Pattern to select images.
function sc_registry_inspect() {
    # Serenditree images
    sc_plots "$1" |
       cut -d' ' -f3 |
       grep serenditree |
       xargs -I{} bash -c "sc_heading 1 {} && skopeo inspect ${_ARG_VERBOSE//1/--config} docker://quay.io/{} | jq"
    # Base images
    while read -r _image; do
        sc_heading 1 "$_image"
        skopeo inspect ${_ARG_VERBOSE//1/--config} docker://${_image} | jq 'del(.RepoTags)'
        [[ -n "${_ARG_VERBOSE}" ]] && sc_heading 2 Tags && skopeo inspect docker://${_image} |
            jq -r '.RepoTags[]' |
            cut -d'.' -f1,2 |
            cut -d'-' -f1 |
            sort -Vu |
            sed '/latest/,$d'
    done < <(env | grep -E '^_ST_FROM' | grep -E "$1" | cut -d'=' -f2)
}

# Shows scan results of images in remote registries.
# $1: Pattern to select images.
function sc_registry_scan() {
    local -r _endpoint=https://quay.io/api/v1/repository
    while read -r _repo; do
        sc_heading $(( 2 - _ARG_VERBOSE )) "${_repo}"
        local _manifest=$(curl -s "${_endpoint}/${_repo}/tag/?onlyActiveTags=true" | jq -r '.tags[].manifest_digest')
        local _result=$(curl -s "${_endpoint}/${_repo}/manifest/${_manifest}/security?vulnerabilities=true")

        if [[ "$(jq -r '.status' <<<"$_result")" == "scanned" ]]; then
            # Select packages with vulnerabilities
            _result=$(
                jq '.data.Layer.Features[] | select(.Vulnerabilities | length > 0)' <<<"$_result"
            )
            if [[ -n "$_result" ]]; then
                if [[ -n "$_ARG_VERBOSE" ]]; then
                    if [[ $_ARG_VERBOSE -eq 1 ]]; then
                        # Select only packages with vulnerabilities "Critical" or "High"
                        _result=$(
                            echo "$_result" |
                                jq -s '.[] | .Vulnerabilities |= map(select(.Severity | IN("Critical", "High")))' |
                                jq -s  '.[] | select(.Vulnerabilities | length > 0)'
                        )
                    fi
                    jq '{Name, Vulnerabilities} | del(.Vulnerabilities[].Metadata)' <<<"$_result"
                else
                    echo "$_result" |
                        jq -r '.Vulnerabilities[].Severity' |
                        sort |
                        uniq -c |
                        sed -E 's/^ +//' |
                        sed -e 's/Critical/\0 0/' \
                            -e 's/High/\0 1/' \
                            -e 's/Medium/\0 2/' \
                            -e 's/Low/\0 3/' \
                            -e 's/Unknown/\0 4/' |
                        sort -nk3 |
                        cut -d' ' -f1-2 |
                        column -t
                fi
            else
                echo "None Detected"
            fi
        else
            echo "Queued"
        fi
    done < <(sc_plots "$1" | awk '{print $3}')
}

# Prints the age of images in remote registries.
function sc_registry_age {
    local -r _endpoint='https://quay.io/api/v1/repository?namespace=serenditree&public=true&last_modified=true'
    local -r _now=$(date +%s)
    while read -r _repo _date; do
        echo "$_repo $(( (_now - _date) / 86400 ))"
    done < <(curl -s "$_endpoint"  | jq -r '.repositories[] | "\(.name) \(.last_modified)"') |
        sort -nk2 |
        column -tN REPO,DAYS
}
