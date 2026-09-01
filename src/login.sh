#!/usr/bin/env bash
########################################################################################################################
# LOGIN
# Authenticates and checks authentication.
########################################################################################################################

# Checks registry authentication using podman.
# $1: Registry to check (for example quay.io)
function sc_logged_in() {
    podman login --get-login $1 >/dev/null 2>&1
}
export -f sc_logged_in

# Authenticate at the given service.
# $1: Service that needs authentication.
function sc_login() {
    case $1 in
    redhat)
        local -r _registry=registry.redhat.io
        local -r _credentials=$(pass serenditree/ext/redhat.io)
        { sc_logged_in $_registry && echo 'Already logged in.'; } || podman login \
            -u "${_credentials%%:*}" \
            -p "${_credentials#*:}" \
            "$_registry"
        ;;
    quay)
        local -r _registry=quay.io
        local -r _credentials=$(pass serenditree/ext/quay.io)
        echo "Containers..."
        { sc_logged_in $_registry && echo 'Already logged in.'; } || podman login \
            -u "${_credentials%%:*}" \
            -p "${_credentials#*:}" \
            "$_registry"
        echo "Charts..."
        helm registry login \
            -u "${_credentials%%:*}" \
            -p "${_credentials#*:}" \
            "$_registry"
        ;;
    ghcr*)
        _GHCR_PKG_READ="$(pass serenditree/ext/ghcr.io)"
        helm registry login ghcr.io \
            --username "${_GHCR_PKG_READ%:*}" \
            --password "${_GHCR_PKG_READ#*:}"
        ;;
    argo*)
        local -r _argocd_password="$(pass serenditree/cicd/terraArgocd.password)"
        sc_cluster_expose argocd
        sleep 1s
        argocd login localhost:9098 --insecure --username admin --password "$_argocd_password"
        ;;
    openshift)
        echo "Requesting token..."
        xdg-open "$_ST_CLUSTER_OAUTH" >/dev/null 2>&1
        read -rp "Token: " _token
        echo "Logging in to openshift online..."
        [[ -n "$_token" ]] && oc login --token="$_token" "$_ST_CLUSTER"
        sc_login quay
        ;;
    openshift/local)
        echo "Logging in to crc..."
        if [[ -n "$_ST_CONTEXT_TKN" ]]; then
            local -r _credentials="${_ST_OPENSHIFT_USERNAME}:${_ST_OPENSHIFT_PASSWORD}"
        else
            local -r _credentials="kubeadmin:crc.testing"
        fi
        oc login \
            -u "${_credentials%%:*}" \
            -p "${_credentials#*:}" \
            https://api.crc.testing:6443
        oc registry login
        ;;
    esac
}
export -f sc_login

# Opens a psql console
# $1: connection string
function sc_login_psql() {
    podman run \
        --rm \
        --tty \
        --interactive \
        --network host \
        "$_ST_FROM_ROOT_USER" \
        psql "$1"
}

# Opens a database interface
# $1: local or cluster context
# $2: database
function sc_login_db() {
    local -r _ctx=$1
    local -r _db=$2

    case $_db in
    user)
        if [[ "$_ctx" == "cluster" ]]; then
            kubectl --namespace serenditree port-forward svc/root-user 5432:5432 &
            local -r _pid=$!
            if [[ -z "$_ARG_EXPOSE" ]]; then
                local -r _username=$(pass serenditree/app/rootUser.db.user)
                local -r _password=$(pass serenditree/app/rootUser.db.password)
                sc_login_psql "postgresql://${_username}:${_password}@localhost:5432/serenditree"
                kill $_pid
            fi
        else
            sc_login_psql "postgresql://user:user@localhost:8085/serenditree"
        fi
        ;;
    seed)
        if [[ "$_ctx" == "cluster" ]]; then
            kubectl --namespace serenditree port-forward svc/root-seed 9200:9200 &>/dev/null &
            local -r _container=opensearch-dashboards
            if podman container exists $_container; then
                podman container start $_container
            else
                podman run \
                    --detach \
                    --name $_container \
                    --network host \
                    --label serenditree.io/service=$_container \
                    --volume ${_container}:/usr/share/opensearch-dashboards/data \
                    --env OPENSEARCH_HOSTS=http://localhost:9200 \
                    --env DISABLE_SECURITY_DASHBOARDS_PLUGIN=true \
                    docker.io/opensearchproject/${_container}:3
            fi
            echo "http://localhost:5601/app/dev_tools#/console"
        fi
        ;;
    esac
}
