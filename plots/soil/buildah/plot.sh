#!/usr/bin/env bash
########################################################################################################################
# BUILDAH
########################################################################################################################
_SERVICE=soil-buildah
_ORDINAL=7

_IMAGE=serenditree/buildah
_VERSION=${_ST_STAGE//dev/latest}
_TAG=$_VERSION

if [[ " $* " =~ " info " ]] || [[ -n "$_ARG_DRYRUN" ]]; then
    echo "${_ORDINAL} ${_SERVICE} ${_IMAGE} ${_TAG} $(realpath $0)"
fi
########################################################################################################################
# BUILD
########################################################################################################################
if [[ " $* " =~ " build " ]]; then
    sc_heading 1 "Building buildah:${_TAG}"
    [[ -n "$_ARG_DRYRUN" ]] && exit 0
    _DESCRIPTION="Buildah image including findutils and jq."
    _CONTAINER_REF=$(buildah from --pull quay.io/buildah/stable:latest)

    buildah run $_CONTAINER_REF -- dnf install findutils jq $_ST_DNF_OPTS

    sc_image_upgrade dnf $_CONTAINER_REF

    buildah config --env DESCRIPTION="$_DESCRIPTION" $_CONTAINER_REF
    buildah config --label description="$_DESCRIPTION" $_CONTAINER_REF

    sc_image_commit "$_IMAGE" "$_TAG" "$_CONTAINER_REF"
fi
