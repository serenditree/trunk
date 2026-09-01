#!/usr/bin/env bash
########################################################################################################################
# TERRA
# Cloud infrastructure setup.
########################################################################################################################
# Runs infra commands with all variables set.
# $*: Command to run.
function sc_terra_run() {
    TF_VAR_api_key="$(pass serenditree/iam/serenditree.access)"
    TF_VAR_api_secret="$(pass serenditree/iam/serenditree.secret)"
    TF_VAR_oidc_parameters="$(sc_terra_oidc)"
    export TF_VAR_api_key TF_VAR_api_secret TF_VAR_oidc_parameters

    if [[ -z "$AWS_ACCESS_KEY_ID" ]]; then
        AWS_ACCESS_KEY_ID="$(pass serenditree/iam/serenditree.access)"
        AWS_SECRET_ACCESS_KEY="$(pass serenditree/iam/serenditree.secret)"
        export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
    fi

    tofu -chdir="$_ST_CONTEXT_HOME" $* \
        -var=kubernetes_version="${_ST_VERSION_KUBERNETES}" \
        -var=wait="${_ARG_WAIT:-false}" \
        -var=context="${_ST_CONTEXT}" \
        -var=auto_scaler="${_ST_SCALE}" \
        -var=gateway="${_ST_GATEWAY}" \
        -var=stage="${_ST_STAGE}" \
        -var=host="${_ST_DOMAIN}" \
        -var=issuer="${_ST_ISSUER}" \
        -var=email="$(pass serenditree/app/terraCerts.email)" \
        -var=zone_compute_1="${_ST_ZONE_COMPUTE_1}" \
        -var=zone_storage_1="${_ST_ZONE_STORAGE_1}" \
        -var=zone_storage_2="${_ST_ZONE_STORAGE_2}" \
        -var=charts="${_ST_HOME_TRUNK}/charts"
}

# Turns OIDC key-value pairs in pass-_folders (standard unix password manager) into JSON objects.
function sc_terra_oidc() {
    local _index=0

    _json="{"
    while read -r _item; do
        _country="${_item%.*}"
        _json+="\"branch.parameters.oidc[${_index}]\": \"${_country}\", "
        ((_index++))
    done < <(pass "serenditree/oidc" | sed -En 's/.* ([a-zA-Z]+)\..*/\1/p' | sort -u)
    _json="${_json%,*}}"
    echo "$_json" | jq -c
}

# Renders ArgoCD applications using values from the IaC plan (OpenTofu).
function sc_terra_render() {
    sc_heading 1 "Rendering apps"
    tofu -chdir="$_ST_CONTEXT_HOME" show -json "$_ST_CONTEXT_PLAN" |
        jq ".resource_changes[] | select(.type == \"helm_release\" and .name == \"serenditree\") | \
            .change.after.set[] | \"--set=\(.name)=\(.value)\"" |
        xargs helm template "${_ST_HOME_TRUNK}/charts/tree" |
        sed -E 's/sync-wave: "([-0-9]+)"/sync-wave: \1/' |
        yq eval-all '[.] | sort_by(.metadata.annotations."serenditree.io/wave") | .[] | splitDoc' |
        sed -E 's/sync-wave: ([-0-9]+)/sync-wave: "\1"/' |
        yq
}

# Syncs versions.tf with versions from a lockfile.
function sc_terra_versions() {
    local -r _versions_tf=$(find "${_ST_CONTEXT_HOME}" -name versions.tf)
    sed -En \
        -e 's/provider "registry.terraform.io\/(.+)".*/\1/p' \
        -e 's/.*version.*=.*"(.+)".*/\1/p' \
        "${_ST_CONTEXT_HOME}/.terraform.lock.hcl" |
        xargs -n2 echo |
        while read -r _version; do
            echo "Setting ${_version// / to }..."
            _version=${_version//\//\\\/}
            sed -Ei "/${_version% *}/,/version/s/(.*>= )[[:digit:/]+(.*)/\1${_version#* }\2/" $_versions_tf
        done
}
########################################################################################################################
# Up
########################################################################################################################
# Checks and sets preconditions.
function sc_terra_up_preconditions() {
    echo -n "Checking kubernetes version ${_ST_VERSION_KUBERNETES}..."
    if exo compute sks versions --output-format text | grep -Eq "^${_ST_VERSION_KUBERNETES}$"; then
        sc_heading 2 "ok"
    else
        sc_heading 2 "error"
        exit 1
    fi

    echo -n "Checking default zone ${_ST_ZONE_COMPUTE_1}..."
    local -r _default_zone="$(exo config get --output-template '{{ .DefaultZone }}')"
    if [[ "$_default_zone"  == "$_ST_ZONE_COMPUTE_1" ]]; then
        sc_heading 2 "ok"
    else
        sc_heading 2 "error"
        exit 1
    fi

    local -r _state_bucket=serenditree-state
    export AWS_PROFILE=serenditree
    export AWS_REGION=$_ST_ZONE_STORAGE_1
    export AWS_ENDPOINT_URL="https://sos-${AWS_REGION}.exo.io"
    echo -n "Checking if bucket ${_state_bucket} exists..."
    if aws s3 ls ${_state_bucket} &>/dev/null; then
        sc_heading 2 "ok"
    else
        aws s3 mb s3://${_state_bucket}
    fi

    echo -n "Rotating keys..."
    sc_rotate_keys >/dev/null
    sc_heading 2 "ok"
}

# Initializes OpenTofu.
# If '--init' is given, previous initialization-artifacts are removed.
function sc_terra_up_init() {
    sc_heading 1 "Initializing"
    sc_terra_up_preconditions
    if [[ -n "$_ARG_INIT" ]]; then
        rm -rf "${_ST_CONTEXT_HOME}/"{terraform*,.terraform,modules/bootstrap/assets}
    fi
    tofu -chdir="$_ST_CONTEXT_HOME" init \
        -var=zone_storage_1="${_ST_ZONE_STORAGE_1}" \
        -upgrade=true
}

# Checks if wait-jobs are activated and returns a refresh strategy.
function sc_terra_up_wait_refresh() {
    local -r _wait="$(
        kubectl get application serenditree \
            --namespace terra-argocd \
            --output jsonpath='{.spec.source.helm.parameters[?(@.name=="global.wait")].value}'
    )"
    if [[ "$_wait" == "true" ]]; then
        echo "Unknown"
    else
        echo "(Unknown|Missing)"
    fi
}

# Wait for apps to become healthy.
function sc_terra_up_wait() {
    tput civis
    trap "tput cnorm; tput cud1" EXIT

    local -r _refresh="$(sc_terra_up_wait_refresh)"
    local -r _tmp=/tmp/serenditree-setup
    rm -f $_tmp

    local _iteration=0
    local _total=1
    local _healthy=-1
    local _state=
    local _refresh_done=0
    local _reset_done=0

    until [[ $_healthy -eq $_total ]]; do
        (( ++_iteration ))
        sc_cluster_expose argocd &>>$_tmp

        _state="$(argocd app list 2>>$_tmp)"
        if grep -Eq "\s+(Unknown|Missing|OutOfSync|Synced)\s+" <<<"$_state"; then
            _total=$(( $(wc -l <<<"$_state") - 1 ))
            _healthy=$(grep -Ec "\s+Synced\s+Healthy\s+" <<<"$_state")

            echo -en "\e[0J${_state}\nHealthy: ${_healthy}/${_total} Iteration: ${_iteration}"

            # Refresh apps with status as defined in $_refresh
            if [[ $_refresh_done -lt 10 ]] || [[ $(( _iteration - _refresh_done )) -gt 10 ]]; then
                local _refresh_echo=
                while read -r _app; do
                    [[ -z "$_refresh_echo" ]] &&
                        echo -n " Refreshing app(s)" &&
                        _refresh_echo="done"
                    argocd app get --hard-refresh "$_app" &>> $_tmp &&
                        argocd app sync --replace --async "$_app" &>> $_tmp &&
                        _refresh_done=$_iteration
                done < <(sed -En "s/^(\S+).* $_refresh .*/\1/p" <<<"$_state")
            fi

            # Wait and clear state
            [[ $_healthy -ne $_total ]] &&
                sleep 5s &&
                echo -en "\r\e[$(( _total + 1 ))A"
        else
            sleep 2s
        fi
    done
    echo " Done"
}

# Provisions infrastructure, configures context, bootstraps Serenditree and hands-over control to ArgoCD.
function sc_terra_up() {
    AWS_ACCESS_KEY_ID="$(pass serenditree/iam/serenditree.access)"
    AWS_SECRET_ACCESS_KEY="$(pass serenditree/iam/serenditree.secret)"
    export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY

    if [[ -z "$_ARG_RESUME" ]]; then
        sc_terra_up_init
        if [[ -n "${_ARG_SETUP}" ]]; then
            sc_heading 1 "Planing infrastructure"
            sc_terra_run plan -out "$_ST_CONTEXT_PLAN"
        fi
    fi

    if [[ -n "$_ARG_DRYRUN" ]]; then
        sc_terra_render
    elif [[ -n "${_ARG_SETUP}" ]]; then
        sc_heading 1 "Applying plan"
        tofu -chdir="$_ST_CONTEXT_HOME" apply "$_ST_CONTEXT_PLAN"
        sc_heading 1 "Setting up context"
        sc_context_clean
        sc_context_init_kube "${_ST_CONTEXT_HOME}/kubeconfig"
        sc_heading 1 "Waiting for Serenditree to become ready"
        sc_terra_up_wait
        if [[ -n "${_ARG_RESTORE}" ]]; then
            sc_heading 1 "Restoring databases from backup"
            sc_cluster_restore
        fi
    fi
}
########################################################################################################################
# Down
########################################################################################################################
# Deletes scaler resources.
function sc_terra_down_scaler() {
    echo "Deleting scaler resources..."
    _ARG_DELETE="" sc_login argocd
    argocd app set terra-argocd/serenditree --parameter terraScale.enabled=false
    argocd app sync terra-argocd/serenditree
    argocd app wait terra-argocd/serenditree --sync

    until ! argocd app get terra-argocd/terra-scale &>/dev/null; do
        sleep 2
        _ARG_DELETE="" sc_login argocd
    done
}

# Deletes all block-storage volumes that were attached to cluster pods.
function sc_terra_down_volumes() {
    echo "Deleting volumes..."
    xargs -I{} -P0 -r bash -c \
        'echo "Deleting {}..." && exo compute block-storage delete --force --quiet {} && echo "Deleted {}"' \
        </tmp/serenditree-pv
}

# Removes all resources that were create during setup.
function sc_terra_down() {
    AWS_ACCESS_KEY_ID="$(pass serenditree/iam/serenditree.access)"
    AWS_SECRET_ACCESS_KEY="$(pass serenditree/iam/serenditree.secret)"
    export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY

    echo "Saving persistent volumes..."
    kubectl get pv --output=custom-columns='name:.metadata.name' --no-headers | tee /tmp/serenditree-pv

    sc_prompt "Remove helm releases from terraform state?" &&
        tofu -chdir="$_ST_CONTEXT_HOME" show -json serenditree.tfplan |
            jq -r ".configuration.root_module.resources[] | select(.type == \"helm_release\") | .address" |
            xargs tofu -chdir="$_ST_CONTEXT_HOME" state rm -var=zone_storage_1="${_ST_ZONE_STORAGE_1}"

    [[ -n "$_ST_SCALE" ]] &&
        kubectl get applications.argoproj.io --namespace terra-argocd terra-scale &>/dev/null &&
        sc_prompt "Delete scaler resources?" &&
        sc_terra_down_scaler

    if sc_prompt "Destroy terraform resources?"; then
        for _cmd in "destroy -compact-warnings -target=module.serenditree_gateway" "destroy"; do
            sc_terra_run $_cmd -auto-approve
        done
    fi

    sc_prompt "Delete volumes?" &&
        sc_terra_down_volumes
}
