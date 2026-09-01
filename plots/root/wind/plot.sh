#!/usr/bin/env bash
########################################################################################################################
# ROOT-WIND
########################################################################################################################
_SERVICE=root-wind
_ORDINAL=11

_IMAGE=serenditree/$_SERVICE
_VERSION=${_ST_STAGE//dev/latest}
_TAG=$_VERSION
_CONTAINER=$_SERVICE
_EXPOSE=9092/tcp

_KAFKA_PORT=${_EXPOSE%/*}
_KRAFT_PORT=9093
_KAFKA_TOPICS="seed-created seed-deleted user-deleted"

if [[ " $* " =~ " info " ]] || [[ -n "$_ARG_DRYRUN" ]]; then
    echo "${_ORDINAL} ${_SERVICE} ${_IMAGE} ${_TAG} $(realpath $0)"
fi
########################################################################################################################
# BUILD
########################################################################################################################
if [[ " $* " =~ " build " ]]; then
    sc_heading 1 "Building ${_IMAGE}:${_TAG}"
    [[ -n "$_ARG_DRYRUN" ]] && exit 0
    _DESCRIPTION="Local development image for root-wind."
    _CONTAINER_REF=$(buildah from serenditree/java-base)
    _MOUNT_REF=$(buildah mount $_CONTAINER_REF)

    _KAFKA_MIRROR=https://archive.apache.org/dist/kafka
    _KAFKA_PATH="$(
        curl -s "${_KAFKA_MIRROR}/${_ST_VERSION_KAFKA}/" |
            sed -En "s/.*>(kafka_.*${_ST_VERSION_KAFKA}.tgz)<.*/\1/p"
    )"
    _KAFKA_ARCHIVE="data/${_KAFKA_PATH%.*}.tar.gz"

    if [[ ! -f ${_KAFKA_ARCHIVE} ]]; then
        sc_heading 2 "Downloading to ${_KAFKA_ARCHIVE}..."
        mkdir -p ${_KAFKA_ARCHIVE%/*}
        curl "${_KAFKA_MIRROR}/${_ST_VERSION_KAFKA}/${_KAFKA_PATH}" --output ${_KAFKA_ARCHIVE}
    fi
    sc_heading 2 "Adding kafka and scripts..."
    buildah config --workingdir $_ST_CONTAINER_ROOT $_CONTAINER_REF
    buildah add --chown 1000:0 $_CONTAINER_REF ${_KAFKA_ARCHIVE}
    buildah add --chown 1000:0 $_CONTAINER_REF src/

    sc_heading 2 "Configuring image..."
    buildah config \
        --env DESCRIPTION="$_DESCRIPTION" \
        --env KAFKA_PATH="${_KAFKA_PATH%.*}" \
        --env KAFKA_VERSION="$_ST_VERSION_KAFKA" \
        --env KAFKA_PORT="$_KAFKA_PORT" \
        --env KRAFT_PORT="$_KRAFT_PORT" \
        --env KAFKA_TOPICS="$_KAFKA_TOPICS" \
        --label description="$_DESCRIPTION" \
        --port "$_EXPOSE" \
        --cmd "bash wrapper.sh" \
        $_CONTAINER_REF

    sc_image_config_commit "$_SERVICE" "$_IMAGE" "$_VERSION" "$_TAG" "$_ORDINAL" "$_CONTAINER_REF"
########################################################################################################################
# UP
########################################################################################################################
elif [[ " $* " =~ " up " ]] && [[ -z "$_ST_CONTEXT_CLUSTER" ]]; then
    sc_heading 1 "Starting ${_SERVICE}:${_TAG}"
    sc_container_rm $_CONTAINER

    podman run \
        --log-level $_ST_LOG_LEVEL \
        --pod $_ST_POD \
        --name $_CONTAINER \
        --env KAFKA_TOPICS="$_KAFKA_TOPICS" \
        --health-cmd "bash health.sh" \
        --health-interval 3s \
        --health-retries 1 \
        --detach \
        ${_IMAGE}:${_TAG}
fi
