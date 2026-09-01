#!/usr/bin/env bash
########################################################################################################################
# NODE
########################################################################################################################
_FLAVOR=$1
_OFFSET=$2
_SERVICE=soil-node-${_FLAVOR}
_ORDINAL=$((_OFFSET + 3))

_IMAGE=serenditree/node-${_FLAVOR}
_VERSION=${_ST_STAGE//dev/latest}
_TAG=$_VERSION
_VOLUME_DST=${_ST_CONTAINER_ROOT}/src

if [[ " $* " =~ " info " ]] || [[ -n "$_ARG_DRYRUN" ]]; then
    echo "${_ORDINAL} ${_SERVICE} ${_IMAGE} ${_TAG} $(realpath $0):${_FLAVOR}:${_OFFSET}"
fi
########################################################################################################################
# BUILD
########################################################################################################################
if [[ " $* " =~ " build " ]]; then
    sc_heading 1 "Building ${_IMAGE}:${_TAG}"
    [[ -n "$_ARG_DRYRUN" ]] && exit 0

    if [[ "$_FLAVOR" == "base" ]]; then
        _DESCRIPTION="Node base image including curl."
        _CONTAINER_REF=$(buildah from scratch)
        _MOUNT_REF=$(buildah mount $_CONTAINER_REF)

        $_ST_DNF_HOST install --installroot ${_MOUNT_REF:?} $_ST_DNF_OPTS_HOST nodejs curl ca-certificates
        $_ST_DNF_HOST clean all --installroot ${_MOUNT_REF:?} --noplugins

        buildah run $_CONTAINER_REF -- mkdir -pv $_ST_CONTAINER_ROOT

        buildah config \
            --env SERENDITREE_LOG_LEVEL=INFO \
            --env DESCRIPTION="$_DESCRIPTION" \
            --env LANG="en_US.UTF-8" \
            --env LANGUAGE="en_US:en" \
            --env NODE_VERSION="$_ST_VERSION_NODE" \
            --label description="$_DESCRIPTION" \
            --workingdir "$_ST_CONTAINER_ROOT" \
            $_CONTAINER_REF
    elif [[ "$_FLAVOR" == "builder" ]]; then
        _DESCRIPTION="Node builder image including curl."
        _CONTAINER_REF=$(buildah from serenditree/node-base)
        _MOUNT_REF=$(buildah mount $_CONTAINER_REF)

        $_ST_DNF_HOST install --installroot ${_MOUNT_REF:?} $_ST_DNF_OPTS_HOST yarnpkg
        $_ST_DNF_HOST clean all --installroot ${_MOUNT_REF:?} --noplugins

        buildah run $_CONTAINER_REF -- yarn global add @angular/cli@${_ST_VERSION_ANGULAR} sass-migrator
        buildah run $_CONTAINER_REF -- mkdir -pv "$_VOLUME_DST"

        buildah config \
            --env SERENDITREE_LOG_LEVEL=DEBUG \
            --env DESCRIPTION="$_DESCRIPTION" \
            --env YARN_CACHE="$(buildah run $_CONTAINER_REF yarn cache dir)" \
            --label description="$_DESCRIPTION" \
            --workingdir "$_VOLUME_DST" \
            --volume "$_VOLUME_DST" \
            $_CONTAINER_REF
    fi

    sc_image_commit "$_IMAGE" "$_TAG" "$_CONTAINER_REF" "on"
fi
