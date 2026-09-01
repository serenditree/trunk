#!/usr/bin/env bash
########################################################################################################################
# ROOT-MAP
########################################################################################################################
_SERVICE=root-map
_ORDINAL=10

_IMAGE=serenditree/root-map
_VERSION=${_ST_STAGE//dev/latest}
_TAG=$_VERSION
_CONTAINER=$_SERVICE
_VOLUME_SRC="$(dirname "$(realpath $0)")/data/tiles"
_VOLUME_DST=${_ST_CONTAINER_ROOT}/data
_EXPOSE=8081/tcp
_EXPOSE_LOCAL=8084/tcp

_TILESERVER_VERSION="$_ST_VERSION_TILESERVER"
_TILESERVER_PORT="${_EXPOSE%/*}"
_STYLES_VERSION=v1.9
_FONTS_VERSION=v2.0
_BASE_URL=https://github.com/openmaptiles
_STYLES_URL=${_BASE_URL}/positron-gl-style/releases/download/${_STYLES_VERSION}/${_STYLES_VERSION}.zip
_FONTS_URL=${_BASE_URL}/fonts/releases/download/${_FONTS_VERSION}/${_FONTS_VERSION}.zip

if [[ " $* " =~ " info " ]] || [[ -n "$_ARG_DRYRUN" ]]; then
    echo "${_ORDINAL} ${_SERVICE} ${_IMAGE} ${_TAG} $(realpath $0)"
fi
########################################################################################################################
# BUILD
########################################################################################################################
if [[ " $* " =~ " build " ]]; then
    sc_heading 1 "Building ${_IMAGE}:${_TAG}"
    [[ -n "$_ARG_DRYRUN" ]] && exit 0
    _DESCRIPTION="Production image for root-map."
    _CONTAINER_REF=$(buildah from serenditree/node-base)
    _MOUNT_REF=$(buildah mount $_CONTAINER_REF)

    _SERVER_DIR="./data/server-${_TILESERVER_VERSION}"
    if [[ ! -d $_SERVER_DIR  ]]; then
        mkdir -pv ${_SERVER_DIR}/styles/positron ${_SERVER_DIR}/fonts ${_SERVER_DIR}/data
        pushd $_SERVER_DIR >/dev/null || exit 1
        sc_heading 2 "Downloading styles ${_STYLES_VERSION}..."
        curl -L $_STYLES_URL -o styles/positron/${_STYLES_VERSION}.zip
        unzip -q styles/positron/${_STYLES_VERSION}.zip -d styles/positron && rm styles/positron/${_STYLES_VERSION}.zip
        sc_heading 2 "Downloading fonts ${_FONTS_VERSION}..."
        curl -L $_FONTS_URL -o fonts/${_FONTS_VERSION}.zip
        unzip -q fonts/${_FONTS_VERSION}.zip -d fonts && rm fonts/${_FONTS_VERSION}.zip

        sc_heading 2 "Installing tileserver ${_TILESERVER_VERSION}..."
        yarn add tileserver-gl-light@${_TILESERVER_VERSION}
        ln -s ./node_modules/.bin/tileserver-gl tileserver-gl
        popd >/dev/null || exit 1
    else
        sc_heading 2 "Using existing data..."
    fi

    sc_heading 2 "Adding script..."
    buildah add --chown 1001:0 $_CONTAINER_REF ./src
    sc_heading 2 "Adding server..."
    buildah add --chown 1001:0 $_CONTAINER_REF $_SERVER_DIR

    buildah run $_CONTAINER_REF -- chown -R 1001:0 $_ST_CONTAINER_ROOT
    buildah run $_CONTAINER_REF -- chmod -R g=u $_ST_CONTAINER_ROOT

    sc_heading 2 "Configuring image..."
    buildah config \
        --env DESCRIPTION="$_DESCRIPTION" \
        --env TILESERVER_VERSION="$_TILESERVER_VERSION" \
        --env TILESERVER_PORT="$_TILESERVER_PORT" \
        --label description="$_DESCRIPTION" \
        --volume "$_VOLUME_DST" \
        --port "$_EXPOSE" \
        --port "$_EXPOSE_LOCAL" \
        --user 1001:0 \
        --cmd "bash wrapper.sh" \
        $_CONTAINER_REF

    rm -rf ${_MOUNT_REF:?}/var/cache/*
    sc_image_config_commit "$_SERVICE" "$_IMAGE" "$_VERSION" "$_TAG" "$_ORDINAL" "$_CONTAINER_REF"
########################################################################################################################
# UP
########################################################################################################################
elif [[ " $* " =~ " up " ]] && [[ -z "$_ST_CONTEXT_CLUSTER" ]]; then
    sc_heading 1 "Starting ${_SERVICE}:${_TAG}"
    sc_container_rm $_CONTAINER

    if [[ ! -f ${_VOLUME_SRC}/osm.mbtiles ]]; then
        echo "Database osm.mbtiles does not exist. Aborting..."
        exit 1
    fi

    podman run \
        --log-level $_ST_LOG_LEVEL \
        --pod $_ST_POD \
        --name $_CONTAINER \
        --env TILESERVER_PORT=${_EXPOSE_LOCAL%/*} \
        --volume ${_VOLUME_SRC}:${_VOLUME_DST}:Z \
        --health-cmd "curl --silent localhost:${_EXPOSE_LOCAL%/*}/index.json" \
        --health-interval 3s \
        --health-retries 1 \
        --detach \
        ${_IMAGE}:${_TAG}
fi
