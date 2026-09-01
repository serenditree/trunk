#!/usr/bin/env bash
########################################################################################################################
# CONFIG
# Global settings and definitions.
########################################################################################################################
# UTILITY
########################################################################################################################
if [[ -z "$_ST_CONTEXT_TKN" ]]; then
    _NORMAL=$(tput sgr0 2>/dev/null)
    _BOLD=$(tput bold 2>/dev/null)
    export _NORMAL _BOLD
fi
########################################################################################################################
# STAGE/ISSUER
########################################################################################################################
if [[ -n "$_ARG_TEST" ]]; then
    _ST_STAGE="test"
    _ST_ISSUER="staging"
elif [[ -n "$_ARG_PROD" ]]; then
    _ST_STAGE="prod"
    _ST_ISSUER="prod"
else
    _ST_STAGE="dev"
    _ST_ISSUER="staging"
fi
if [[ -n "$_ARG_XISSUER" ]]; then
    if [[ "$_ST_ISSUER" == "staging" ]]; then
        _ST_ISSUER="prod"
    else
        _ST_ISSUER="staging"
    fi
fi
export _ST_STAGE _ST_ISSUER
########################################################################################################################
# PROJECT
#######################################################################################################################
if [[ -z "$_ST_CONTEXT_TKN" ]]; then
    _ST_HOME=$(realpath $0 | sed 's/\/trunk.*//')
    export _ST_HOME
    export _ST_HOME_TRUNK=${_ST_HOME}/trunk
    export _ST_HOME_BRANCH=${_ST_HOME}/branch
    export _ST_HOME_LEAF=${_ST_HOME}/leaf
else
    export _ST_HOME_TRUNK=${_ST_HOME}/sc
    export _ST_HOME_BRANCH=${_ST_HOME}/src
    export _ST_HOME_LEAF=${_ST_HOME}/src
fi
export _ST_BIN=${_ST_BIN:-${HOME}/.local/bin}
########################################################################################################################
# CONFIG
########################################################################################################################
export _ST_ACCOUNT=${_ST_ACCOUNT:-serenditree}
export _ST_DOMAIN=${_ST_DOMAIN:-serenditree.io}
export _ST_GIT=${_ST_GIT:-git@github.com:serenditree/trunk.git}
export _ST_GIT_SSH=${_ST_GIT_SSH:-${HOME}/.ssh/trunk@serenditree.io}
export _ST_LOG_LEVEL=${_ST_LOG_LEVEL:-info}
export _ST_POD=${_ST_POD:-serenditree}
export _ST_POD_TIMEOUT=${_ST_POD_TIMEOUT:-20}
export _ST_SCALE=$_ARG_SCALE
export _ST_GATEWAY=$_ARG_GATEWAY
export _ST_ZONE_COMPUTE_1=${_ST_ZONE_COMPUTE_1:-at-vie-2}
export _ST_ZONE_STORAGE_1=${_ST_ZONE_STORAGE_1:-at-vie-1}
export _ST_ZONE_STORAGE_2=${_ST_ZONE_STORAGE_2:-hr-zag-1}

export EXOSCALE_ACCOUNT=$_ST_ACCOUNT
########################################################################################################################
# NOTIFICATIONS
########################################################################################################################
if [[ -n "$_ARG_NOTIFY" ]]; then
    _ST_NOTIFY="$(compgen -c | grep -E '^notify-send$')"
    _ST_NOTIFY_SOUND="$(compgen -c | grep -E '^canberra-gtk-play$')"
else
    _ST_NOTIFY=
    _ST_NOTIFY_SOUND=
fi
export _ST_NOTIFY _ST_NOTIFY_SOUND
########################################################################################################################
# VERSIONS
########################################################################################################################

if [[ -f /etc/fedora-release ]] && [[ -z "$_ST_CONTEXT_TKN" ]]; then
    _ST_VERSION_FEDORA=$(cut -d' ' -f3 /etc/fedora-release)
    export _ST_VERSION_FEDORA
fi
export _ST_VERSION_ANGULAR=22
export _ST_VERSION_BUILDAH=v1.43.2
export _ST_VERSION_GO=1.27
export _ST_VERSION_JAVA=25
export _ST_VERSION_K6=2.2.0
export _ST_VERSION_KAFKA=4.3.1
export _ST_VERSION_KUBERNETES=1.37.0
export _ST_VERSION_NODE=24.x
export _ST_VERSION_NGINX=release-1.31.5
export _ST_VERSION_NGINX_OTEL=v0.1.2
export _ST_VERSION_OPENSEARCH=3
export _ST_VERSION_POSTGRESQL=18
export _ST_VERSION_TILESERVER=5.6.0

#export _ST_VERSION_FIXED_HELM=cert-manager # chart[|chart]
########################################################################################################################
# BUILD
########################################################################################################################
export _ST_CONTAINER_ROOT=/serenditree

export _ST_JAVA_JRE_HOME=/usr/lib/jvm/jre-${_ST_VERSION_JAVA}-openjdk
export _ST_JAVA_JDK_HOME=/usr/lib/jvm/java-${_ST_VERSION_JAVA}-openjdk
export _ST_JAVA_PACKAGE=java-${_ST_VERSION_JAVA}-openjdk-headless
export _ST_JAVA_PACKAGE_DEVEL=java-${_ST_VERSION_JAVA}-openjdk-devel
export _ST_JAVA_BUILD=${_ST_JAVA_BUILD:-jvm} # jvm|native
export _ST_MAVEN_PACKAGE=maven-openjdk${_ST_VERSION_JAVA}

_ST_DNF_OPTS="--assumeyes --noplugins --nodocs --setopt install_weak_deps=0"
_ST_DNF_OPTS_HOST="--use-host-config --setopt *.countme=false "
_ST_DNF_OPTS_HOST+="--releasever $_ST_VERSION_FEDORA $_ST_DNF_OPTS"
_ST_DNF_HOST="env HOME=${_ST_HOME_TRUNK}/rc/config/rpm dnf"
export _ST_DNF_OPTS _ST_DNF_OPTS_HOST _ST_DNF_HOST
########################################################################################################################
# BASE IMAGES
########################################################################################################################
export _ST_FROM_ROOT_SEED=docker.io/opensearchproject/opensearch:${_ST_VERSION_OPENSEARCH}
export _ST_FROM_ROOT_SEED_DASH=docker.io/opensearchproject/opensearch-dashboards:${_ST_VERSION_OPENSEARCH}
export _ST_FROM_ROOT_USER=docker.io/postgres:${_ST_VERSION_POSTGRESQL}
export _ST_FROM_ROOT_WIND_DASH=docker.io/obsidiandynamics/kafdrop:latest
export _ST_FROM_SOIL_BUILDAH=quay.io/buildah/stable:${_ST_VERSION_BUILDAH}
export _ST_FROM_SOIL_TEST=docker.io/grafana/k6:${_ST_VERSION_K6}
export _ST_FROM_SOIL_TEST_BUILDER=docker.io/library/golang:${_ST_VERSION_GO}
#export _ST_FROM_SOIL_NATIVE=quay.io/quarkus/ubi9-quarkus-micro-image:2.0
#export _ST_FROM_SOIL_NATIVE_BUILDER=quay.io/quarkus/ubi9-quarkus-mandrel-builder-image:jdk-${_ST_VERSION_JAVA}
########################################################################################################################
# CONTEXT
########################################################################################################################
_kubernetes="serenditree-kubernetes"
_kubernetes_local="serenditree-kubernetes-local"
_openshift="serenditree-openshift"
_openshift_local="serenditree-openshift-local"

# shellcheck disable=SC2155,SC2011
if [[ -z "$_ST_CONTEXT_TKN" ]]; then
    export MINIKUBE_IN_STYLE=false

    if [[ -n "$_ARG_KUBERNETES" ]]; then
        if [[ -n "$_ARG_LOCAL" ]]; then
            export _ST_CONTEXT=$_kubernetes_local
        else
            export _ST_CONTEXT=$_kubernetes
        fi
    elif [[ -n "$_ARG_OPENSHIFT" ]]; then
        if [[ -n "$_ARG_LOCAL" ]]; then
            export _ST_CONTEXT=$_openshift_local
        else
            export _ST_CONTEXT=$_openshift
        fi
    else
        _ST_CONTEXT=$(kubectl config current-context)
        export _ST_CONTEXT
    fi
fi

export _ST_CONTEXTS=("$_kubernetes" "$_kubernetes_local" "$_openshift" "$_openshift_local")
export _ST_CONTEXTS_NOOP="noop/serenditree"
export _ST_REGISTRY=quay.io
if [[ "$_ST_CONTEXT" == "$_kubernetes" ]]; then
    export _ST_CONTEXT_IS_KUBERNETES=on
    export _ST_CONTEXT_IS_REMOTE=on
    export _ST_CONTEXT_KUBERNETES=$_kubernetes
elif [[ "$_ST_CONTEXT" == "$_kubernetes_local" ]]; then
    export _ST_CONTEXT_IS_KUBERNETES=on
    export _ST_CONTEXT_IS_LOCAL=on
    export _ST_CONTEXT_KUBERNETES_LOCAL=$_kubernetes_local
elif [[ "$_ST_CONTEXT" == "$_openshift" ]]; then
    export _ST_CONTEXT_IS_OPENSHIFT=on
    export _ST_CONTEXT_IS_REMOTE=on
    export _ST_CONTEXT_OPENSHIFT=$_openshift
    export _ST_REGISTRY=default-route-openshift-image-registry.apps.serenditree...
elif [[ "$_ST_CONTEXT" == "$_openshift_local" ]]; then
    export _ST_CONTEXT_IS_OPENSHIFT=on
    export _ST_CONTEXT_IS_LOCAL=on
    export _ST_CONTEXT_OPENSHIFT_LOCAL=$_openshift_local
    export _ST_REGISTRY=default-route-openshift-image-registry.apps-crc.testing
else
    [[ -z "${_ST_ARGBASH}${_ST_CONTEXT_TKN}" ]] &&
        ! [[ $_ARG_COMMAND =~ [1-4]|ctx|context ]] &&
        echo -e "${_BOLD}Warning:${_NORMAL} Serenditree context is not set\n" >&2
    export _ST_CONTEXT=
fi
if [[ -n "$_ST_CONTEXT_IS_KUBERNETES" ]]; then
    export _ST_CONTEXT_HOME="${_ST_HOME_TRUNK}/src/kubernetes"
else
    export _ST_CONTEXT_HOME="${_ST_HOME_TRUNK}/src/openshift"
fi
export _ST_CONTEXT_PLAN="${_ST_CONTEXT_HOME}/serenditree.tfplan"
########################################################################################################################
# COMPOSE
########################################################################################################################
if [[ -z "$_ST_CONTEXT_TKN" ]] &&
    podman pod exists "pod_${_ST_POD}" &&
    [[ $_ARG_COMMAND =~ ^(down|logs|log)$ ]]
then
    export _ARG_COMPOSE=on
fi
