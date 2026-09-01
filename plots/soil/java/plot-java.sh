#!/usr/bin/env bash
########################################################################################################################
# JAVA
########################################################################################################################
_FLAVOR=$1
_OFFSET=$2
_SERVICE=soil-java-${_FLAVOR}
_ORDINAL=$((_OFFSET + 1))

_IMAGE=serenditree/java-${_FLAVOR}
_VERSION=${_ST_STAGE//dev/latest}
_TAG=$_VERSION
[[ "$_ST_JAVA_BUILD" == "native" ]] && _TAG+=-native
_VOLUME_DST_MVN=${_ST_CONTAINER_ROOT}/.m2

if [[ " $* " =~ " info " ]] || [[ -n "$_ARG_DRYRUN" ]]; then
    echo "${_ORDINAL} ${_SERVICE} ${_IMAGE} ${_TAG} $(realpath $0):${_FLAVOR}:${_OFFSET}"
fi
########################################################################################################################
# BUILD
########################################################################################################################
if [[ " $* " =~ " build " ]]; then
    sc_heading 1 "Building java-${_FLAVOR}:${_TAG}"
    [[ -n "$_ARG_DRYRUN" ]] && exit 0
    #-------------------------------------------------------------------------------------------------------------------
    # BUILD BASE
    #-------------------------------------------------------------------------------------------------------------------
    if [[ "$_FLAVOR" == "base" ]]; then
        _DESCRIPTION="Java runtime (${_ST_JAVA_PACKAGE}) including curl."
        _CONTAINER_REF=$(buildah from scratch)
        _MOUNT_REF=$(buildah mount $_CONTAINER_REF)

        $_ST_DNF_HOST install --installroot ${_MOUNT_REF:?} $_ST_DNF_OPTS_HOST $_ST_JAVA_PACKAGE curl ca-certificates
        $_ST_DNF_HOST clean all --installroot ${_MOUNT_REF:?} --noplugins

        buildah add $_CONTAINER_REF ./src/run.sh ${_ST_CONTAINER_ROOT}/run.sh

        buildah run $_CONTAINER_REF -- chown -R 1000:0 $_ST_CONTAINER_ROOT
        buildah run $_CONTAINER_REF -- chmod u+x ${_ST_CONTAINER_ROOT}/run.sh
        buildah run $_CONTAINER_REF -- chmod -R g=u $_ST_CONTAINER_ROOT

        buildah config \
            --env SERENDITREE_LOG_LEVEL=INFO \
            --env DESCRIPTION="$_DESCRIPTION" \
            --env JAVA_VERSION="$_ST_VERSION_JAVA" \
            --env JAVA_HOME="$_ST_JAVA_JRE_HOME" \
            --env JAVA_PACKAGE="$_ST_JAVA_PACKAGE" \
            --env LANG="en_US.UTF-8" \
            --env LANGUAGE="en_US:en" \
            --label description="$_DESCRIPTION" \
            --workingdir $_ST_CONTAINER_ROOT \
            $_CONTAINER_REF
    #-------------------------------------------------------------------------------------------------------------------
    # BUILD BUILDER
    #-------------------------------------------------------------------------------------------------------------------
    elif [[ "$_ST_JAVA_BUILD" == "native" ]] && [[ "$_FLAVOR" == "builder" ]]; then
        _DESCRIPTION="GraalVM development kit (${_ST_JAVA_PACKAGE}) including curl."
        _CONTAINER_REF=$(buildah from --pull $_ST_FROM_SOIL_NATIVE_BUILDER)
        _MOUNT_REF=$(buildah mount $_CONTAINER_REF)

        buildah add --chown 1000:0 $_CONTAINER_REF ./src $_ST_CONTAINER_ROOT

        buildah config \
            --env DESCRIPTION="$_DESCRIPTION" \
            --env M2_HOME="${_VOLUME_DST_MVN}" \
            --env MAVEN_OPTS="-Dmaven.repo.local=${_VOLUME_DST_MVN}/repository" \
            --label description="$_DESCRIPTION" \
            --entrypoint='' \
            --workingdir=$_ST_CONTAINER_ROOT \
            $_CONTAINER_REF
    else
        _DESCRIPTION="Java development kit (${_ST_JAVA_PACKAGE}) including curl."
        _CONTAINER_REF=$(buildah from serenditree/java-base)
        _MOUNT_REF=$(buildah mount $_CONTAINER_REF)

        $_ST_DNF_HOST install --installroot ${_MOUNT_REF:?} $_ST_DNF_OPTS_HOST $_ST_JAVA_PACKAGE_DEVEL maven
        $_ST_DNF_HOST clean all --installroot ${_MOUNT_REF:?} --noplugins

        buildah config \
            --env SERENDITREE_LOG_LEVEL=DEBUG \
            --env DESCRIPTION="$_DESCRIPTION" \
            --env JAVA_HOME=$_ST_JAVA_JDK_HOME \
            --env M2_HOME="${_VOLUME_DST_MVN}" \
            --env MAVEN_OPTS="-Dmaven.repo.local=${_VOLUME_DST_MVN}/repository" \
            --label description="$_DESCRIPTION" \
            $_CONTAINER_REF

        buildah run $_CONTAINER_REF -- mkdir src
        buildah add --chown 1000:0 $_CONTAINER_REF ./src
    fi

    sc_image_commit "$_IMAGE" "$_TAG" "$_CONTAINER_REF" "on"
fi
