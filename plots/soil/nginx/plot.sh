#!/usr/bin/env bash
########################################################################################################################
# NGINX
########################################################################################################################
# shellcheck disable=SC2086
_SERVICE=soil-nginx
_ORDINAL=5

_IMAGE=serenditree/nginx
_VERSION=${_ST_STAGE//dev/latest}
_TAG=$_VERSION
_VOLUME_DST_CONFIG=${_ST_CONTAINER_ROOT}/template
_VOLUME_DST_CACHE=${_ST_CONTAINER_ROOT}/cache
_EXPOSE=8080/tcp

if [[ " $* " =~ " info " ]] || [[ -n "$_ARG_DRYRUN" ]]; then
    echo "${_ORDINAL} ${_SERVICE} ${_IMAGE} ${_TAG} $(realpath $0)"
fi
########################################################################################################################
# BUILD
########################################################################################################################
if [[ " $* " =~ " build " ]]; then
    sc_heading 1 "Building ${_IMAGE}:${_TAG}"
    #-------------------------------------------------------------------------------------------------------------------
    # STEP BUILDER
    #-------------------------------------------------------------------------------------------------------------------
    _BUILD_CONTAINER_REF=$(buildah from scratch)
    _BUILD_MOUNT_REF=$(buildah mount $_BUILD_CONTAINER_REF)

    sc_heading 2 "Installing build-dependencies..."
    $_ST_DNF_HOST install --installroot ${_BUILD_MOUNT_REF:?} $_ST_DNF_OPTS_HOST \
        c-ares-devel cmake gcc-c++ git openssl-devel openssl-devel-engine pcre2-devel zlib-ng-compat-devel

    sc_heading 2 "Building and installing nginx with modules..."
    buildah config \
        --env NGINX_ROOT="$_ST_CONTAINER_ROOT" \
        --env NGINX_VERSION="$_ST_VERSION_NGINX" \
        --env NGINX_OTEL_VERSION="$_ST_VERSION_NGINX_OTEL" \
        $_BUILD_CONTAINER_REF

    buildah add $_BUILD_CONTAINER_REF ./src/make.sh /
    buildah run $_BUILD_CONTAINER_REF -- /make.sh
    #-------------------------------------------------------------------------------------------------------------------
    # STEP PACKAGE
    #-------------------------------------------------------------------------------------------------------------------
    _CONTAINER_REF=$(buildah from scratch)
    _MOUNT_REF=$(buildah mount $_CONTAINER_REF)

    sc_heading 2 "Installing envsubst..."
    $_ST_DNF_HOST install --installroot ${_MOUNT_REF:?} $_ST_DNF_OPTS_HOST gettext-envsubst tee
    $_ST_DNF_HOST clean all --installroot ${_MOUNT_REF:?} --noplugins

    sc_heading 2 "Adding build artifacts..."
    buildah config --workingdir $_ST_CONTAINER_ROOT $_CONTAINER_REF
    buildah add --chown 1001:0 $_CONTAINER_REF ${_BUILD_MOUNT_REF:?}${_ST_CONTAINER_ROOT}
    buildah add --chown 1001:0 $_CONTAINER_REF ${_BUILD_MOUNT_REF:?}/usr/lib64/libcares.so\* \
                                               ${_BUILD_MOUNT_REF:?}/usr/lib64/libcrypt.so\* \
                                               ${_BUILD_MOUNT_REF:?}/usr/lib64/libcrypto.so\* \
                                               ${_BUILD_MOUNT_REF:?}/usr/lib64/libpcre\* \
                                               ${_BUILD_MOUNT_REF:?}/usr/lib64/libssl.so\* \
                                               ${_BUILD_MOUNT_REF:?}/usr/lib64/libstdc++.so\* \
                                               ${_BUILD_MOUNT_REF:?}/usr/lib64/libz.so\* \
                                               /usr/lib64/
    sc_heading 2 "Adding configuration and run-script..."
    buildah add --chown 1001:0 --chmod 440 $_CONTAINER_REF ./rc/serenditree.conf ${_VOLUME_DST_CONFIG}/
    buildah add --chown 1001:0 --chmod 550 $_CONTAINER_REF ./src/run.sh

    sc_heading 2 "Configuring linked libraries..."
    buildah run --user 0:0 $_CONTAINER_REF -- ldconfig -v

    sc_heading 2 "Configuring image..."
    buildah config \
        --env DESCRIPTION="NGINX with otel module" \
        --env SERENDITREE_ROOT="${_ST_CONTAINER_ROOT}" \
        --env SERENDITREE_CONTENT="${_ST_CONTAINER_ROOT}/html" \
        --env SERENDITREE_CONFIG="${_ST_CONTAINER_ROOT}/conf/nginx.conf" \
        --env SERENDITREE_CONFIG_TEMPLATE="${_VOLUME_DST_CONFIG}/serenditree.conf" \
        --env SERENDITREE_BIN="${_ST_CONTAINER_ROOT}/sbin/nginx" \
        --env OTEL_ENABLED="on" \
        --env OTEL_HOST="localhost" \
        --env OTEL_PORT="4317" \
        --env OTEL_SERVICE="serenditree" \
        --env OTEL_SPAN="serve" \
        --env NGINX_VERSION="${_ST_VERSION_NGINX#*-}" \
        --env NGINX_OTEL_VERSION="${_ST_VERSION_NGINX_OTEL#v}" \
        --volume "$_VOLUME_DST_CONFIG" \
        --volume "$_VOLUME_DST_CACHE" \
        --port "$_EXPOSE" \
        --stop-signal "SIGQUIT" \
        --user 1001:0 \
        --cmd "./run.sh" \
        $_CONTAINER_REF

    buildah umount $_BUILD_CONTAINER_REF
    buildah rm $_BUILD_CONTAINER_REF
    sc_image_config_commit "$_SERVICE" "$_IMAGE" "$_VERSION" "$_TAG" "$_ORDINAL" "$_CONTAINER_REF" "on"
fi
