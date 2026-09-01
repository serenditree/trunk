#!/usr/bin/env bash
########################################################################################################################
# LEAF
########################################################################################################################
_SERVICE=leaf
_ORDINAL=15

_IMAGE=serenditree/leaf
_VERSION=${_ST_STAGE//dev/latest}
_TAG=$_VERSION
if [[ -n "$_ARG_COMPOSE" ]]; then
    _NGINX_CONFIG="./rc/serenditree.compose.conf"
    _CONFIG='compose'
    _TAG+=-$_CONFIG
else
    _NGINX_CONFIG="./rc/serenditree.conf"
    _CONFIG='prod'
fi
_CONTAINER=$_SERVICE
_VOLUME_SRC=$_ST_HOME_LEAF
_VOLUME_DST=${_ST_CONTAINER_ROOT}/src
_VOLUME_DST_CONFIG=${_ST_CONTAINER_ROOT}/template

if [[ -n "$_ST_CONTEXT_TKN" ]]; then
    _QUALIFIED="${_ST_REGISTRY}/"
fi

if [[ " $* " =~ " info " ]] || [[ -n "$_ARG_DRYRUN" ]]; then
    echo "${_ORDINAL} ${_SERVICE} ${_IMAGE} ${_TAG} $(realpath $0)"
fi
########################################################################################################################
# BUILD
########################################################################################################################
if [[ " $* " =~ " build " ]]; then
    sc_heading 1 "Building ${_IMAGE}:${_TAG}"
    [[ -n "$_ARG_DRYRUN" ]] && exit 0
    _DESCRIPTION="Production image for leaf."
    _BUILDAH_ARGS="--volume ${_VOLUME_SRC}:${_VOLUME_DST}:rw,z "
    #-------------------------------------------------------------------------------------------------------------------
    # STEP BUILDER
    #-------------------------------------------------------------------------------------------------------------------
    _BUILD_CONTAINER_REF=$(buildah from $_BUILDAH_ARGS ${_QUALIFIED}serenditree/node-builder)

    sc_heading 2 "Building project..."
    buildah run $_BUILD_CONTAINER_REF -- yarn
    buildah run $_BUILD_CONTAINER_REF -- yarn run build --configuration="$_CONFIG"
    #-------------------------------------------------------------------------------------------------------------------
    # STEP PACKAGE
    #-------------------------------------------------------------------------------------------------------------------
    _CONTAINER_REF=$(buildah from ${_QUALIFIED}serenditree/nginx)
    _MOUNT_REF=$(buildah mount $_CONTAINER_REF)

    if [[ "$_CONFIG" == "compose" ]]; then
        sc_heading 2 "Installing curl..."
        $_ST_DNF_HOST install --installroot ${_MOUNT_REF:?} $_ST_DNF_OPTS_HOST curl
        $_ST_DNF_HOST clean all --installroot ${_MOUNT_REF:?} --noplugins

        sc_heading 2 "Disabling otel..."
        buildah config --env OTEL_ENABLED="off" $_CONTAINER_REF
    fi

    sc_heading 2 "Adding configuration..."
    buildah add --chown 1001:0 --chmod 440 $_CONTAINER_REF "$_NGINX_CONFIG" "${_VOLUME_DST_CONFIG}/serenditree.conf"

    sc_heading 2 "Adding application..."
    buildah add --chown 1001:0 $_CONTAINER_REF "${_VOLUME_SRC}/dist/browser" "${_ST_CONTAINER_ROOT}/html"

    sc_heading 2 "Configuring image..."
    buildah config \
        --volume ${_ST_CONTAINER_ROOT}/template- \
        --volume ${_ST_CONTAINER_ROOT}/cache- \
        --env DESCRIPTION="$_DESCRIPTION" \
        --env OTEL_SERVICE="$_SERVICE" \
        --label description="$_DESCRIPTION" \
        $_CONTAINER_REF

    buildah rm $_BUILD_CONTAINER_REF
    sc_image_config_commit "$_SERVICE" "$_IMAGE" "$_VERSION" "$_TAG" "$_ORDINAL" "$_CONTAINER_REF"
########################################################################################################################
# UP
########################################################################################################################
elif [[ " $* " =~ " up " ]] && [[ -z "$_ST_CONTEXT_CLUSTER" ]]; then
    sc_heading 1 "Starting ${_SERVICE}:${_TAG}"
    sc_container_rm $_CONTAINER

    podman run \
        --user 0:0 \
        --log-level $_ST_LOG_LEVEL \
        --pod $_ST_POD \
        --name $_CONTAINER \
        --label serenditree.io/service=${_SERVICE} \
        --volume ${_VOLUME_SRC}:${_VOLUME_DST}:Z \
        --health-cmd "curl localhost:8080" \
        --health-interval 3s \
        --health-retries 1 \
        --detach \
        serenditree/node-builder:latest \
        yarn run host
fi
