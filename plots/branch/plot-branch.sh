#!/usr/bin/env bash
########################################################################################################################
# BRANCH
########################################################################################################################
_BRANCH=$1
_ROOT=$2
_OFFSET=$3
_SERVICE=branch-${_BRANCH}
_ORDINAL=$((_OFFSET + 12))

_IMAGE=serenditree/branch-${_BRANCH}
_VERSION=${_ST_STAGE//dev/latest}
_TAG=$_VERSION
_CONTAINER=$_SERVICE
_VOLUME_SRC_MVN=${HOME}/.m2
_VOLUME_DST_MVN=${_ST_CONTAINER_ROOT}/.m2
_VOLUME_SRC_SRC=${_ST_HOME_BRANCH}
_VOLUME_DST_SRC=${_ST_CONTAINER_ROOT}/src
_EXPOSE=8080/tcp

if [[ -n "$_ST_CONTEXT_TKN" ]]; then
    _QUALIFIED="${_ST_REGISTRY}/"
    _VOLUME_SRC_MVN=$_ST_MVN
fi

if [[ " $* " =~ " info " ]] || [[ -n "$_ARG_DRYRUN" ]]; then
    echo "${_ORDINAL} ${_SERVICE} ${_IMAGE} ${_TAG} $(realpath $0):${_BRANCH}:${_ROOT}:${_OFFSET}"
fi
########################################################################################################################
# BUILD native
########################################################################################################################
if [[ "$_ST_JAVA_BUILD" == "native" ]] && [[ " $* " =~ " build " ]]; then
    sc_heading 1 "Building ${_IMAGE}:${_TAG}"

    _DESCRIPTION="Production image for branch-${_BRANCH}."
    _BUILDAH_ARGS="--ulimit nofile=10240 "
    _BUILDAH_ARGS+="--volume ${_VOLUME_SRC_MVN}:${_VOLUME_DST_MVN}:rw,z "
    #-------------------------------------------------------------------------------------------------------------------
    # STEP BUILDER
    #-------------------------------------------------------------------------------------------------------------------
    _BUILD_CONTAINER_REF=$(buildah from --pull $_BUILDAH_ARGS $_ST_FROM_SOIL_NATIVE_BUILDER)
    _BUILD_MOUNT_REF=$(buildah mount $_BUILD_CONTAINER_REF)

    buildah copy --chown quarkus:quarkus $_BUILD_CONTAINER_REF $_VOLUME_SRC_SRC $_VOLUME_DST_SRC

    buildah config --workingdir $_VOLUME_DST_SRC $_BUILD_CONTAINER_REF
    buildah config --user quarkus $_BUILD_CONTAINER_REF
    buildah config --env M2_HOME="${_VOLUME_DST_MVN}" \
        --env MAVEN_OPTS="-Dmaven.repo.local=${_VOLUME_DST_MVN}/repository" \
        $_BUILD_CONTAINER_REF

    buildah run $_BUILD_CONTAINER_REF -- ./mvnw clean package \
        --also-make \
        --projects leaves/leaf-${_BRANCH} \
        --activate-profiles native
    #-------------------------------------------------------------------------------------------------------------------
    # STEP PACKAGE
    #-------------------------------------------------------------------------------------------------------------------
    _CONTAINER_REF=$(buildah from --pull $_BUILDAH_ARGS $_ST_FROM_SOIL_NATIVE)

    buildah add $_CONTAINER_REF \
        ${_BUILD_MOUNT_REF:?}/serenditree/src/leaves/leaf-${_BRANCH}/target/*-runner \
        ${_ST_CONTAINER_ROOT}/run

    buildah run $_CONTAINER_REF chmod 775 ${_ST_CONTAINER_ROOT} ${_ST_CONTAINER_ROOT}/run
    buildah run $_CONTAINER_REF chown -R 1001 ${_ST_CONTAINER_ROOT}
    buildah run $_CONTAINER_REF chmod -R "g+rwX" ${_ST_CONTAINER_ROOT}
    buildah run $_CONTAINER_REF chown -R 1001:0 ${_ST_CONTAINER_ROOT}

    buildah config --workingdir ${_ST_CONTAINER_ROOT} $_CONTAINER_REF
    buildah config --port 8080 $_CONTAINER_REF
    buildah config --user 1001 $_CONTAINER_REF
    buildah config --cmd './run' $_CONTAINER_REF

    buildah umount $_BUILD_CONTAINER_REF
    buildah rm $_BUILD_CONTAINER_REF

    sc_label_rm $_ST_FROM_SOIL_NATIVE $_CONTAINER_REF
    sc_image_config_commit "$_SERVICE" "$_IMAGE" "$_VERSION" "$_TAG" "$_ORDINAL" "$_CONTAINER_REF"
########################################################################################################################
# BUILD jvm
########################################################################################################################
elif [[ " $* " =~ " build " ]]; then
    sc_heading 1 "Building ${_IMAGE}:${_TAG}"
    [[ -n "$_ARG_DRYRUN" ]] && exit 0
    _DESCRIPTION="Production image for branch-${_BRANCH}."
    _BUILDAH_ARGS="--ulimit nofile=10240 "
    _BUILDAH_ARGS+="--volume ${_VOLUME_SRC_MVN}:${_VOLUME_DST_MVN}:rw,z "
    #-------------------------------------------------------------------------------------------------------------------
    # STEP BUILDER
    #-------------------------------------------------------------------------------------------------------------------
    _BUILD_CONTAINER_REF=$(buildah from $_BUILDAH_ARGS ${_QUALIFIED}serenditree/java-builder)
    _BUILD_MOUNT_REF=$(buildah mount $_BUILD_CONTAINER_REF)

    buildah config \
        --env SERENDITREE_BRANCH=$_BRANCH\
        --workingdir $_VOLUME_DST_SRC \
        $_BUILD_CONTAINER_REF

    sc_heading 2 "Adding source from ${_VOLUME_SRC_SRC} and building project..."
    buildah add $_BUILD_CONTAINER_REF $_VOLUME_SRC_SRC
    buildah run $_BUILD_CONTAINER_REF -- mvn clean install --also-make --projects leaves/leaf-${_BRANCH}
    if [[ -n "$_ST_CONTEXT_TKN" ]]; then
        buildah run $_BUILD_CONTAINER_REF -- chmod -R g=u $_VOLUME_DST_MVN
    fi
    #-------------------------------------------------------------------------------------------------------------------
    # STEP PACKAGE
    #-------------------------------------------------------------------------------------------------------------------
    _CONTAINER_REF=$(buildah from $_BUILDAH_ARGS ${_QUALIFIED}serenditree/java-base)

    sc_heading 2 "Adding artifacts to production image..."
    buildah add --chown 1001:0 $_CONTAINER_REF \
        ${_BUILD_MOUNT_REF:?}/serenditree/src/leaves/leaf-${_BRANCH}/target/serenditree/lib/ \
        ${_ST_CONTAINER_ROOT}/lib/
    buildah add --chown 1001:0 $_CONTAINER_REF \
        ${_BUILD_MOUNT_REF:?}/serenditree/src/leaves/leaf-${_BRANCH}/target/serenditree/*.jar \
        ${_ST_CONTAINER_ROOT}/
    buildah add --chown 1001:0 $_CONTAINER_REF \
        ${_BUILD_MOUNT_REF:?}/serenditree/src/leaves/leaf-${_BRANCH}/target/serenditree/app/ \
        ${_ST_CONTAINER_ROOT}/app/
    buildah add --chown 1001:0 $_CONTAINER_REF \
        ${_BUILD_MOUNT_REF:?}/serenditree/src/leaves/leaf-${_BRANCH}/target/serenditree/quarkus/ \
        ${_ST_CONTAINER_ROOT}/quarkus/

    buildah config \
        --env SERENDITREE_BRANCH="$_BRANCH" \
        --env DESCRIPTION="$_DESCRIPTION" \
        --env JDK_JAVA_OPTIONS="-XshowSettings:vm" \
        --label description="$_DESCRIPTION" \
        --port "$_EXPOSE" \
        --user 1001:0 \
        --cmd "bash run.sh" \
        $_CONTAINER_REF

    buildah umount $_BUILD_CONTAINER_REF
    buildah rm $_BUILD_CONTAINER_REF

    sc_image_config_commit "$_SERVICE" "$_IMAGE" "$_VERSION" "$_TAG" "$_ORDINAL" "$_CONTAINER_REF"
########################################################################################################################
# UP
########################################################################################################################
elif [[ " $* " =~ " up " ]] && [[ -z "$_ST_CONTEXT_CLUSTER" ]]; then
    sc_heading 1 "Starting ${_SERVICE}:${_TAG}"
    sc_container_rm $_CONTAINER
    _EXPOSE="$((${_EXPOSE%/*} + _OFFSET + 1))"

    if [[ "$_ST_JAVA_BUILD" == "native" ]]; then
        # Volume for agent-tracing
        _BRANCH_CONFIG="${HOME}/Downloads/Serenditree/Native/${_SERVICE}"
        rm -rf "$_BRANCH_CONFIG"
        mkdir -p "$_BRANCH_CONFIG"
        _BRANCH_CONFIG="--volume ${_BRANCH_CONFIG}:${_ST_CONTAINER_ROOT}/native:Z"
        _TAG+=-native
    fi

    cat <(./src/secrets.sh) <(echo "$_BRANCH_CONFIG serenditree/java-builder:$_TAG bash wrapper.sh") | xargs \
        podman run \
        --user 0:0 \
        --log-level $_ST_LOG_LEVEL \
        --pod $_ST_POD \
        --name $_CONTAINER \
        --label serenditree.io/service=${_SERVICE} \
        --env-file ./plot.env \
        --env SERENDITREE_ENDPOINT_POLL=branch-poll:8083/api/v1 \
        --env SERENDITREE_BRANCH="$_BRANCH" \
        --env SERENDITREE_SERVICE="$_SERVICE" \
        --env SERENDITREE_VERSION="$_VERSION" \
        --env SERENDITREE_ORDINAL="$_ORDINAL" \
        --env SERENDITREE_STAGE="$_ST_STAGE" \
        --env SERENDITREE_BUILD="$_ST_JAVA_BUILD" \
        --env QUARKUS_HTTP_PORT="$_EXPOSE" \
        --volume ${_VOLUME_SRC_MVN}:${_VOLUME_DST_MVN}:Z \
        --health-cmd "bash health.sh" \
        --health-interval 3s \
        --health-retries 1 \
        --detach

    echo "Adding source from ${_VOLUME_SRC_SRC}..."
    podman cp ${_VOLUME_SRC_SRC}/. ${_CONTAINER}:${_VOLUME_DST_SRC}
    echo "Starting build..."
    podman exec ${_CONTAINER} touch ${_VOLUME_DST_SRC}/release
fi
