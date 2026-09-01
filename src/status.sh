#!/usr/bin/env bash
########################################################################################################################
# STATUS
# Inspects the host system for problems and prints information about active contexts, containers, available plots,...
########################################################################################################################

# Checks required applications.
function sc_status_required_applications() {
    echo -n "Required applications..."
    local -r _required="$(tr '\n' '|' <"${_ST_HOME_TRUNK}/rc/config/required-apps")"
    local -r _missing=$(
        cat <(compgen -c | grep -E "^(${_required%|})$") <(echo -e "${_required//|/\\n}") |
            sort |
            uniq -u
    )
    if [[ -n "$_missing" ]]; then
        echo "${_BOLD}warning:${_NORMAL} $_missing not found" | xargs
    else
        echo "${_BOLD}ok${_NORMAL}"
    fi
}

# Checks required files and folders.
function sc_status_required_files() {
    echo -n "Required files..."
    if [[ -f "$_ST_GIT_SSH" ]]; then
        echo "${_BOLD}ok${_NORMAL}"
    else
        echo "${_BOLD}warning:${_NORMAL} ssh private key for argocd github access does not exits."
    fi
    echo -n "Required folders..."
    if [[ -d ~/.m2/repository ]]; then
        echo "${_BOLD}ok${_NORMAL}"
    else
        echo "${_BOLD}warning:${_NORMAL} local maven repository at ~/.m2/repository does not exits."
    fi
}

# Checks if the repository for custom node versions exists.
function sc_status_build_node() {
    echo -n "Checking nodejs repository..."
    local -r _node_repo=/etc/yum.repos.d/nodesource-nodejs.repo
    if [[ -f $_node_repo ]]; then
        echo "${_BOLD}ok${_NORMAL}"
    else
        echo " nodejs repository does not exists."
        sc_trap "sudo rm -f ${_node_repo//nodejs/*}" EXIT
        sc_prompt "Temporarily install custom nodjs repository" &&
            curl -fsSL "https://rpm.nodesource.com/setup_${_ST_VERSION_NODE}" |
            sudo bash -
    fi
}

# Checks operating system.
function sc_status_os() {
    echo -n "Required distribution..."
    if [[ -e /etc/fedora-release ]]; then
        echo "${_BOLD}ok${_NORMAL}"
    else
        echo "${_BOLD}error:${_NORMAL} image building only tested on fedora"
    fi
    echo -n "Checking uid..."
    if [[ $(id -u) -eq 1000 ]]; then
        echo "${_BOLD}ok${_NORMAL}"
    else
        echo "${_BOLD}warning:${_NORMAL} your uid ($(id -u), not 1000) might lead to troubles."
    fi
    echo -n "Checking nofiles..."
    if [[ $(ulimit -n) -ge 65535 ]]; then
        echo "${_BOLD}ok${_NORMAL}"
    else
        echo "${_BOLD}warning:${_NORMAL} nofiles ($(ulimit -n)) is lower than 65535."
    fi
}

# Prints registry authentications.
function sc_status_registries() {
    if [[ -n "$REGISTRY_AUTH_FILE" ]]; then
        local -r _auth_json=$REGISTRY_AUTH_FILE
    else
        local -r _auth_json=${XDG_RUNTIME_DIR}/containers/auth.json
        echo "${_BOLD}Warning:${_NORMAL} Using default auth.json (${_auth_json})"
    fi
    if [[ -e $_auth_json ]]; then
        local -r _registries="$(jq -r ".auths | keys[]" $_auth_json)"
    fi
    echo "${_registries:-none}"
}

# Prints global environment variables based on context.
function sc_status_env() {
    env | grep '^_ST_' | sed -E -e 's/=/#/' -e 's/\s+/ /g' | sort | column -ts'#' | cut -c 1-200
}

# Prints cli and java config.
function sc_status_config() {
    sc_heading 1 "Environment"
    sc_status_env

    for _branch in seed user poll; do
        sc_heading 1 "Branch-${_branch^}"
        # shellcheck disable=SC2038,SC2016
        find "${_ST_HOME_BRANCH}/leaves" \
            -regextype posix-extended -regex ".*/leaf-${_branch}/src/.*/application.yml" |
            xargs yq eval-all '. as $item ireduce ({}; . * $item) | ... comments=""'
    done
}

# Prints cluster status information.
function sc_status_cluster() {
    sc_heading 1 "Context"
    sc_context && local -r _ready=on
    [[ -n "$_ST_CONTEXT" ]] && echo &&
        { kubectl version 2>/dev/null | sed -E -e '/Kustomize/d' -e 's/v([0-9])/\1/' &&
        echo "Defined Version: ${_ST_VERSION_KUBERNETES}" &&
        echo "Available Versions: $(exo compute sks versions --output-format text | xargs)" &&
        echo "Cluster Domain: $(sc_context_cluster_domain)"; } | column -ts':' &&

    sc_heading 1 "Balance"
    sc_cluster_balance

    if [[ -n "$_ready" ]];then
        sc_heading 1 "Pods"
        kubectl get pods --all-namespaces --output wide --no-headers | grep -Ev "Running|Completed" || echo "No issues"
        sc_heading 1 Apps
        echo -n "ArgoCD login..."
        if argocd version --request-timeout 1s &>/dev/null || sc_login argocd >/dev/null; then
            sc_heading 2 "ok"
            argocd app list | sed '1d' | grep -v Healthy || echo "No issues"
        else
            sc_heading 2 "error"
        fi
    fi

    sc_heading 1 "Storage"
    local _head=7
    [[ -n "$_ARG_VERBOSE" ]] && _head=9999
    exo storage ls --use-account serenditree | sort -k6 | column -t && echo
    exo storage ls --use-account serenditree --versions sos://serenditree-backup-user/ |
        head -n $_head |
        column -t &&
        echo
    exo storage ls --use-account serenditree --versions sos://serenditree-backup-seed/ |
        grep 'index.latest' |
        head -n $_head |
        column -t

    if [[ -n "${_ST_CONTEXT_KUBERNETES_LOCAL}${_ST_CONTEXT_OPENSHIFT_LOCAL}" ]]; then
        sc_heading 1 "Local"
        if [[ -n "${_ST_CONTEXT_KUBERNETES_LOCAL}" ]]; then
            minikube config view
        elif [[ -n "${_ST_CONTEXT_OPENSHIFT_LOCAL}" ]]; then
            crc config view
        fi
    fi
}

# Prints an overview of the development environment.
function sc_status() {
    sc_heading 1 "Environment"
    sc_status_env
    sc_heading 1 "System"
    sc_status_os
    sc_status_required_applications
    sc_status_required_files

    sc_heading 1 "Authentications"
    sc_status_registries

    sc_heading 1 "Pod"
    sc_pod_list

    if [[ -n "$_ARG_ALL" ]]; then
        sc_status_cluster
    fi
}
