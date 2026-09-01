#!/usr/bin/env bash
########################################################################################################################
# CONTEXT
# Define and use serenditree contexts.
########################################################################################################################

# Returns the kubernetes cluster domain.
function sc_context_cluster_domain() {
    if kubectl version &>/dev/null; then
        kubectl get cm coredns \
            --namespace kube-system \
            --output=jsonpath="{.data.Corefile}" |
            sed -rn 's/.*kubernetes ([^ ]+) .*/\1/p'
    else
        echo "unavailable"
    fi
}
export -f sc_context_cluster_domain

# Initializes or resets available contexts.
function sc_context_init_generic() {
    local -r _from=$1
    local -r _to=$2
    kubectl config get-contexts "$_to" &>/dev/null && kubectl config delete-context "$_to"
    kubectl config rename-context "$_from" "$_to"
    kubectl config set-context "$_to"
    kubectl config set-context --current --namespace=serenditree
}
export -f sc_context_init_generic

# Sets the context for the remote kubernetes cluster.
# $1: Location of the kubeconfig file to merge.
# $2: Fetch before merge if set to "--fetch".
function sc_context_init_kube() {
    local -r _kubeconfig="$1"
    if [[ "$2" == "--fetch" ]]; then
        echo "Fetching kubeconfig..."
        local -r _ttl="$((60 * 60 * 24 * 90))"
        local -r _group="system:masters"
        until exo compute sks kubeconfig serenditree kubeadmin/serenditree \
            --ttl $_ttl \
            --group $_group  \
            --group "$_ST_ACCOUNT"  \
            --zone "$_ST_ZONE_COMPUTE_1" >"$_kubeconfig"
        do
            sleep 1s
        done
    fi
    echo "Creating backup of ${KUBECONFIG}..."
    cp -v "$KUBECONFIG" "${KUBECONFIG}.$(date +%Y%m%d-%H%M%S).bak"
    local -r _context_serenditree="$(sed -En 's/.*current-context: (.*)/\1/p' "$_kubeconfig")"
    sed -i '/current-context/d' "$KUBECONFIG"
    echo "Merging contexts..."
    KUBECONFIG="${KUBECONFIG}:${_kubeconfig}" kubectl config view --flatten >"${KUBECONFIG}.merged"
    mv "${KUBECONFIG}.merged" "${KUBECONFIG}"
    chmod 600 "$KUBECONFIG"
    kubectl config use-context "$_context_serenditree"
    sc_context_init_generic "$_context_serenditree" "$_ST_CONTEXT_KUBERNETES"
}
export -f sc_context_init_kube

# Adds noop cluster and user.
function sc_context_init_noop() {
    local -r _tmp_key=/tmp/key.pem
    local -r _tmp_cert=/tmp/cert.pem

    openssl req -x509 -newkey rsa:2048 -days 365 -noenc -config "${_ST_HOME_TRUNK}/rc/config/openssl.cnf" \
        -keyout $_tmp_key \
        -out $_tmp_cert &>/dev/null

    kubectl config set-cluster "$_ST_CONTEXTS_NOOP" \
        --server https://localhost \
        --embed-certs \
        --certificate-authority $_tmp_cert
    kubectl config set-credentials "$_ST_CONTEXTS_NOOP" \
        --embed-certs \
        --client-key $_tmp_key \
        --client-certificate $_tmp_cert
}

# Cleans context from orphaned serenditree contexts.
function sc_context_clean() {
    if kubectl config get-contexts "$_ST_CONTEXT" &>/dev/null; then
        local -r _cluster=$(kubectl config get-contexts "$_ST_CONTEXT" --no-headers |
            tr -d '*' | awk '{print $2}')
        local -r _user=$(kubectl config get-contexts "$_ST_CONTEXT" --no-headers |
            tr -d '*' | awk '{print $3}')
        kubectl config delete-context "$_ST_CONTEXT"
        [[ "$_cluster" != "$_ST_CONTEXTS_NOOP" ]] && kubectl config delete-cluster "$_cluster"
        [[ "$_user" != "$_ST_CONTEXTS_NOOP" ]] && kubectl config delete-user "$_user"
    fi
}
export -f sc_context_clean

# Initializes available contexts.
function sc_context_init() {
    if ! kubectl config view | grep -q "name: $_ST_CONTEXTS_NOOP"; then
        sc_context_init_noop
    fi
    for _context in "${_ST_CONTEXTS[@]}"; do
        if ! kubectl config get-contexts $_context &>/dev/null; then
            kubectl config set-context $_context \
                --cluster "$_ST_CONTEXTS_NOOP" \
                --user "$_ST_CONTEXTS_NOOP" \
                --namespace serenditree
        fi
    done

    if [[ -n "$_ARG_SETUP" ]]; then
        if [[ -n "$_ST_CONTEXT_KUBERNETES" ]]; then
            sc_context_init_kube /tmp/serenditree-kubeconfig --fetch
        elif [[ -n "$_ST_CONTEXT_KUBERNETES_LOCAL" ]]; then
            sc_context_init_generic minikube "$_ST_CONTEXT_KUBERNETES_LOCAL"
        elif [[ -n "$_ST_CONTEXT_OPENSHIFT_LOCAL" ]]; then
            oc login -u kubeadmin -p crc.testing https://api.crc.testing:6443
            sc_context_init_generic default/api-crc-testing:6443/kubeadmin "$_ST_CONTEXT_OPENSHIFT_LOCAL"
        fi
    fi
}
export -f sc_context_init

# Selects a context.
# $1: Pattern or index for context selection
function sc_context_use() {
    if [[ $1 =~ [[:digit:]] ]]; then
        local -r _pattern=serenditree
        local -r _index=$1
    else
        local -r _pattern=$1
        local -r _index=1
    fi
    kubectl config get-contexts --no-headers |
        grep -E "$_pattern" |
        sed -En -e 's/[* ]+(\S+).*/\1/' -e "${_index}p" |
        xargs -I{} bash -c "[[ \"$(kubectl config current-context)\" != \"{}\" ]] && kubectl config use-context {}"
}
export -f sc_context_use

# Shows and/or sets the cluster context.
# $1: Optional ID of the context to set.
function sc_context() {
    if [[ -n "${_ARG_INIT}" ]]; then
        sc_context_init
    fi
    # Set context!
    if [[ -n "$1" ]]; then
        sc_context_use "$1"
    elif [[ $_ST_CONTEXT =~ ^serenditree ]]; then
        sc_context_use "[[:space:]]${_ST_CONTEXT}[[:space:]]"
    fi
    # Show contexts!
    kubectl config get-contexts --no-headers |
        grep -E "serenditree" |
        sed -E 's/([* ]+\S+).*/\1/' |
        nl -w1 -s' '

    local _ready=1
    [[ -n "$_ST_CONTEXT" ]] && sc_cluster_status && _ready=0

    return $_ready
}
export -f sc_context
