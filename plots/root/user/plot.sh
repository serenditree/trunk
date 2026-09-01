#!/usr/bin/env bash
########################################################################################################################
# ROOT-USER
########################################################################################################################
_SERVICE=root-user
_ORDINAL=8

_IMAGE=serenditree/root-user
_VERSION=${_ST_STAGE//dev/latest}
_TAG=$_VERSION
_CONTAINER=$_SERVICE
_VOLUME_SRC=root-user
_VOLUME_DST=/var/lib/postgresql
_EXPOSE=5432/tcp

if [[ " $* " =~ " info " ]] || [[ -n "$_ARG_DRYRUN" ]]; then
    echo "${_ORDINAL} ${_SERVICE} ${_IMAGE} ${_TAG} $(realpath $0)"
fi
########################################################################################################################
# BUILD
########################################################################################################################
if [[ " $* " =~ " build " ]]; then
    sc_heading 1 "Building ${_IMAGE}:${_TAG}"
    [[ -n "$_ARG_DRYRUN" ]] && exit 0
    _CONTAINER_REF=$(buildah from --pull $_ST_FROM_ROOT_USER)

    buildah add --chown 1001:0 $_CONTAINER_REF ./rc/0.0.1-init.sql /docker-entrypoint-initdb.d/
    # Removes preconfigured entrypoint-volumes to avoid anonymous local volumes.
    buildah config \
        --volume $_VOLUME_DST \
        --port $_EXPOSE \
        $_CONTAINER_REF

    # sc_env_rm $_CONTAINER_REF
    sc_label_rm $_ST_FROM_ROOT_USER $_CONTAINER_REF
    sc_image_config_commit "$_SERVICE" "$_IMAGE" "$_VERSION" "$_TAG" "$_ORDINAL" "$_CONTAINER_REF"
########################################################################################################################
# UP
########################################################################################################################
elif [[ " $* " =~ " up " ]] && [[ -z "$_ST_CONTEXT_CLUSTER" ]]; then
    sc_heading 1 "Starting ${_SERVICE}:${_TAG}"
    sc_container_rm $_CONTAINER

    # shellcheck disable=SC2046
    podman run \
        --log-level $_ST_LOG_LEVEL \
        --pod $_ST_POD \
        --name $_CONTAINER \
        --env POSTGRES_PASSWORD=root \
        $([[ -z "$_ARG_INTEGRATION" ]] && echo --volume ${_VOLUME_SRC}:${_VOLUME_DST}) \
        --health-interval 3s \
        --health-retries 1 \
        --health-cmd 'pg_isready -U user -d serenditree -h 127.0.0.1 -p 5432' \
        --detach \
        ${_IMAGE}:${_TAG}
fi
