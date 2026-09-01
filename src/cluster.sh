#!/usr/bin/env bash
########################################################################################################################
# CLUSTER FUNCTIONS
# Functions for the interaction with kubernetes clusters.
########################################################################################################################
# shellcheck disable=SC2155

# Deploys the latest versions of branch and leaf.
function sc_cluster_deploy() {
    local -r _args=$1
    local _apps
    sc_login argocd
    for _app in branch leaf; do
        if [[ "$_app" =~ $_args ]]; then
            if sc_prompt "Deploy ${_app}?"; then
                sc_heading 2 "Deployment of $_app started..."
                argocd app actions run --all --kind Deployment $_app restart
                _apps+=" $_app"
            fi
        fi
    done
    [[ -n "$_apps" ]] && argocd app wait $_apps --health
}

# Starts a Tekton PipelineRun
# $@: Pipelines to run. Empty means all pipelines.
function sc_cluster_tekton() {
    [[ -n "$_ARG_DEBUG" ]] && export _DEBUG=-debug
    [[ -z "$1" ]] && set -- "branch leaf"

    for _pipeline in $@; do
        export _PIPELINE=$_pipeline
        sc_heading 1 "$_PIPELINE"

        envsubst '$_PIPELINE $_DEBUG' <"${_ST_HOME_TRUNK}/rc/templates/pipeline-template.yml" |
            kubectl create --namespace tekton-pipelines -f - &&
            sleep 1s &&
            tkn pipeline logs --namespace tekton-pipelines --last --follow "$_PIPELINE"
    done
}

# Displays and returns status of control plane and worker nodes.
function sc_cluster_status() {
    if [[ -n "${_ST_CONTEXT_OPENSHIFT_LOCAL}${_ST_CONTEXT_KUBERNETES_LOCAL}" ]]; then
        local -r _request_timeout='--request-timeout=500ms'
    else
        local -r _request_timeout='--request-timeout=2s'
    fi

    echo -en "\nChecking control plane..."
    if kubectl --context $_ST_CONTEXT api-resources $_request_timeout 2>&1 | grep -qm1 'true'; then
        sc_heading 2 "up"

        echo -en "Checking nodes..."
        local -r _nodes=$(kubectl get node --no-headers | wc -l)
        local -r _ready=$(kubectl get node --no-headers | grep -c ' Ready ')
        if [[ -n "$_ARG_SETUP" ]] && [[ $_nodes -gt 0 ]]; then
            sc_heading 2 "up"
        elif [[ $_nodes -eq $_ready ]]; then
            sc_heading 2 "up"
            local -r _cluster_ready=0
        else
            echo "${_BOLD}warning:${_NORMAL} ${_ready}/${_nodes} nodes ready"
            local -r _cluster_ready=1
        fi
    else
        sc_heading 2 "down"
        local -r _cluster_ready=1
    fi

    return $_cluster_ready
}
export -f sc_cluster_status

# Retrieves current account balance.
function sc_cluster_balance() {
    local -r _host="https://api-${_ST_ZONE_COMPUTE_1}.exoscale.com"
    local -r _url="/v2/organization"
    local -r _method="GET"
    local -r _expiration="$(( $( date +%s ) + 600 ))"
    local -r _key="$(pass serenditree/iam/serenditree.access)"
    local -r _secret="$(pass serenditree/iam/serenditree.secret)"
    local -r _msg="$(echo -en "$_method $_url\n\n\n\n$_expiration")"
    local -r _signature=$(echo -n "$_msg" | openssl dgst -sha256 -hmac "$_secret" -binary | base64)
    local -r _auth_header="Authorization: EXO2-HMAC-SHA256 credential=$_key,expires=$_expiration,signature=$_signature"

    curl -s -X "$_method" -H "$_auth_header" "${_host}${_url}" | jq -r '"EUR \(.balance)"'
}

# Waits for all pods to become ready.
# $1: Timeout.
function sc_cluster_wait() {
    local -r _timeout="$1"
    kubectl wait --for condition=ready --all pod \
        --field-selector status.phase==Running \
        --all-namespaces \
        --timeout "$_timeout"

    sc_heading 2 "Running pods:"
    kubectl get pod --all-namespaces --output wide
}

# Restores databases.
function sc_cluster_restore() {
    # Get latest snapshot
    echo -n "Getting latest snapshot..."
    kubectl port-forward --namespace serenditree svc/root-seed 9200:9200 &>/dev/null &
    local -r _pid=$!
    sc_trap "kill ${_pid}" EXIT
    sleep 1s
    local -r _latest="$(
        curl -s 'http://localhost:9200/_snapshot/seed-backup/_all' |
            jq -r '.snapshots | reverse | .[0].snapshot'
    )"

    if [[ $_latest =~ ^seed-backup-[0-9]{12}$ ]]; then
        echo "$_latest"
        for _comp in user seed; do
            _latest_snapshot=$_latest envsubst '$_latest_snapshot' <"${_ST_HOME_TRUNK}/rc/jobs/restore-${_comp}.yml" |
                kubectl create --namespace serenditree --filename -
        done
        sleep .5s
        kubectl wait --for=condition=complete job \
            --namespace=serenditree \
            --selector="serenditree.io/job=restore" \
            --timeout=120s
    else
        echo "Error. Aborting..."
        exit 1
    fi
}

# Creates database backup jobs manually from cronjobs.
function sc_cluster_backup() {
    for _comp in user seed; do
        kubectl create job "root-${_comp}-backup-$(date +%Y%m%d%H%M)" \
            --from=cronjob/root-${_comp}-backup \
            --namespace serenditree
    done
    sleep .5s
    kubectl wait --for=condition=complete job \
        --namespace=serenditree \
        --selector="serenditree.io/job=backup" \
        --timeout=120s
}

# Prints cluster logs.
# $1: Service or "job[s]"
function sc_cluster_logs() {
    local -r _service=$1
    if [[ "$_service" =~ jobs? ]]; then
        kubectl get pod \
            --namespace serenditree \
            --output custom-columns="name:metadata.name" \
            --sort-by 'metadata.creationTimestamp' |
        grep -E 'backup|restore' |
        tail -n3 |
        xargs -I{} bash -c "echo -e '\n${_BOLD}{}${_NORMAL}\n' && kubectl logs {} --all-containers && echo"
    else
        kubectl logs --namespace serenditree --follow "svc/${_service}"
    fi
}

# Prints resource allocations.
function sc_cluster_resources() {
    local -r _csv=$1
    local -r _tmp=/tmp/serenditree-nodes
    sc_heading 1 "Cluster resource allocation"
    if [[ "$_csv" == "csv" ]]; then
        local _pipe="tee"
    else
        local _pipe="column -ts ';'"
    fi
    kubectl describe node >$_tmp
    cat \
        <(echo "NAMESPACE;NAME;CPU REQUESTS;CPU LIMITS;MEMORY REQUESTS;MEMORY LIMITS") \
        <(sed -n '/Non-terminated Pods/,/Allocated resources/p' $_tmp |
              sed '0,/--/{/--/d;}' |
              sed -E -e '/(Allocated|Non|Namespace)/d' \
                  -e 's/([0-9]+)(m|Mi)/\1/g' \
                  -e 's/([0-9]+)Gi/\1000/g' \
                  -e 's/\s([1-9])\s/ \1000 /g' \
                  -e 's/\([^)]+\)//g' \
                  -e 's/\s\w+$//' \
                  -e 's/\s+$//' \
                  -e 's/^\s+//' \
                  -e 's/--+.*/;;;;;/' \
                  -e 's/\s+/;/g') |
        $_pipe

    sc_heading 1 "Cluster resource allocation summary"
    cat \
        <(echo "RESOURCE;REQUESTS;PERCENT;LIMITS;PERCENT") \
        <(sed -n '/Allocated resources/,/Events:/p' $_tmp |
            sed -En '/(cpu|memory)/p' |
            sed -E  -e 's/[()]//g' -e 's/\s+$//' -e 's/^\s+//' -e 's/\s+/;/g' |
            awk 'NR % 2 == 1 {print} NR % 2 == 0 {print $0 "\n;;;;"}') |
        head -n -1 |
        $_pipe

    sc_heading 1 "Cluster cpu and memory"
    cat \
        <(echo "CPU;MEMORY;") \
        <(paste \
            <(sed -En 's/\s+cpu:\s+(\S+)/\1/p' $_tmp) \
            <(sed -En 's/\s+memory:\s+([0-9]+).*/\1/p' $_tmp | awk '{print $1 / 1000}') |
                sed -E  -e 's/\s+$//' -e 's/^\s+//' -e 's/\s+/;/g' |
                awk 'NR % 2 == 1 {print $0 "Mi;capacity"} NR % 2 == 0 {print $0 "Mi;allocatable\n;;"}') |
        head -n -1 |
        $_pipe
}

# Lists all v2 keys in the cluster's vault.
function sc_cluster_keys() {
    local -r _token=$(pass serenditree/vault | jq -r '.root_token')
    kubectl exec --namespace terra-vault vault-0 -- sh -c "
        export BAO_TOKEN=$_token
        list_keys() {
            bao kv list serenditree/\$1 2>/dev/null | tail -n+3 | while read -r _key; do
                if [[ \"\$_key\" =~ /$ ]]; then
                    list_keys \"\$1\$_key\"
                else
                    bao kv get serenditree/\$1\$_key && echo
                fi
            done
        }
        list_keys
    "
}

# Unseals the cluster's vault.
function sc_cluster_unseal() {
    echo "Unsealing vault..."
    local _unseal_key
    for _key in $(seq 0 2); do
        _unseal_key=$(pass serenditree/vault | jq -r ".unseal_keys_b64[${_key}]")
        kubectl exec --namespace terra-vault vault-0 -- bao operator unseal "$_unseal_key"
    done
}

# Prints certificate information.
function sc_cluster_certificate() {
    local -r _cert="lets-encrypt-${_ST_ISSUER}"

    if [[ -z "$_ARG_RESET" ]]; then
        sc_heading 1 "Orders and Challenges"
        kubectl get orders,challenges --namespace terra-gateway --output yaml
        sc_heading 1 "Certificate"
        kubectl get certificate "$_cert" --namespace terra-gateway --output yaml
        sc_heading 1 "Secret"
        kubectl get secrets "$_cert" --namespace terra-gateway --output yaml
        sc_heading 1 "Certificate info"
        kubectl get secrets "$_cert" --namespace terra-gateway --output json |
            jq -r '.data."tls.crt"' |
            base64 --decode |
            #sed -n '0,/--END/p' |
            openssl x509 -noout -text
    else
        kubectl delete order,challenges,certificate --namespace terra-gateway --all
    fi
}

# Deletes dispensable resources.
function sc_cluster_clean() {
    # Failed pods
    kubectl get pod \
        --all-namespaces \
        --field-selector="status.phase==Failed" \
        --output=custom-columns='namespace:metadata.namespace,name:metadata.name' \
        --no-headers |
        xargs --no-run-if-empty -n2 bash -c 'kubectl --namespace $0 delete pod $1'
    # Completed pods except the two most recent ones.
    kubectl get pod \
        --namespace serenditree \
        --field-selector='status.phase==Succeeded' \
        --sort-by '{.metadata.creationTimestamp}' \
        --output=custom-columns='name:.metadata.name' \
        --no-headers |
        head -n -2 |
        xargs --no-run-if-empty kubectl --namespace serenditree delete pod
    # Orphaned replica sets.
    kubectl get rs \
        --namespace serenditree \
        --output=jsonpath='{.items[?(@.spec.replicas==0)].metadata.name}' |
        xargs --no-run-if-empty kubectl --namespace serenditree delete rs
    if kubectl get ns tekton-pipelines &>/dev/null; then
        # Pipeline runs except the two most recent ones.
        tkn pipelinerun delete --keep 2 --namespace tekton-pipelines
    fi
}

# Inspects all or defined images of the OpenShift registry.
# $1: Optional list of image names.
function sc_cluster_registry() {
    local -r _images=$(sc_args_to_pattern "$*")

    oc get is --no-headers |
        grep -Ei "${_images}" |
        cut -d' ' -f1 |
        xargs -I{} bash -c "sc_heading 1 serenditree/{} &&
            skopeo inspect --tls-verify=false docker://${_ST_REGISTRY}/serenditree/{}"
}

# Proxy kubernetes services
function sc_cluster_proxy() {
    if [[ -z "$_ARG_DELETE" ]]; then
        nohup kubectl proxy &>/tmp/nohup-proxy.log &
        column -Lt <"${_ST_HOME_TRUNK}/rc/config/cluster-proxy"
    else
        pgrep -f 'kubectl proxy' | xargs kill
    fi
}

# Port-forwarding for management dashboards.
# $1: Pattern for service selection
function sc_cluster_expose() {
    local -r _pattern=$1
    local _used_ports

    _used_ports="$(netstat -4tlnp 2>&1 | sed -En 's/.*127.0.0.1:([0-9]+).*kubectl/\1/p' | xargs echo | tr ' ' '|')"
    [[ -n "$_used_ports" ]] || _used_ports='none'
    echo -e "kubectl listening on ports: $_used_ports\n" | tr '|' ' '

    local -r _logs=/tmp/nohup-expose.log
    { while IFS=";" read -r _name _namespace _svc _ports; do
        if [[ $_name =~ $_pattern ]]; then
            _svc="svc/${_svc}"
            if [[ -n "$_ARG_DELETE" ]]; then
                # Terminate port-forwarding
                netstat -4tlnp 2>&1 |
                    sed -En "s/.*127.0.0.1:${_ports%:*}.* ([0-9]+)\/kubectl/\1/p" |
                    xargs kill &>/dev/null && echo "${_name};${_BOLD}terminated${_NORMAL}"
            elif [[ ${_ports%:*} =~ $_used_ports ]]; then
                # Port-forwarding already started
                echo "${_name};http://localhost:${_ports%:*}"
            else
                # Start port-forwarding
                if kubectl get --namespace $_namespace $_svc &>/dev/null; then
                    echo "${_name};http://localhost:${_ports%:*}"
                    nohup kubectl port-forward $_svc $_ports --namespace $_namespace &>$_logs &
                    _used_ports+="${_ports%:*}"
                else
                    echo "${_name};${_BOLD}unavailable${_NORMAL}"
                fi
            fi
        fi
    done <"${_ST_HOME_TRUNK}/rc/config/cluster-expose"; } |
        column -ts';' |
        tr ' ' '.'
    echo -e "\nCheck logs in ${_logs}!"
}
export -f sc_cluster_expose

# Starts or stops all nodes of the cluster.
# $1: start or stop
function sc_cluster_toggle() {
    local -r _toggle=$1

    for _instance in $(exo compute instance list --zone "$_ST_ZONE_COMPUTE_1" --output-template '{{.ID}}'); do
        exo compute instance "$_toggle" "$_instance" --force --output-format json | jq
    done
}

# Starts all nodes of the cluster.
function sc_cluster_up() {
    sc_heading 2 "Starting nodes..."
    sc_cluster_toggle start

    sc_heading 2 "Waiting for pods to become ready..."
    sc_cluster_wait 10m

    local -r _scaler=terra-scale-exoscale-cluster-autoscaler
    if kubectl get deployment $_scaler --namespace kube-system &>/dev/null; then
        sc_prompt "Enable autoscaler?" && kubectl scale deployment $_scaler --replicas 1 --namespace kube-system
    fi
}

# Stops all nodes of the cluster.
function sc_cluster_down() {
    local -r _scaler=terra-scale-exoscale-cluster-autoscaler
    if kubectl get deployment $_scaler --namespace kube-system &>/dev/null; then
        sc_heading 2 "Disabling autoscaler..."
        kubectl scale deployment $_scaler --replicas 0 --namespace kube-system
    fi

    sc_heading 2 "Stopping nodes..."
    sc_cluster_toggle stop
}
