#!/usr/bin/env bash
########################################################################################################################
# Vault init
########################################################################################################################
_NAMESPACE="terra-vault"
_POD="vault-0"

echo "Waiting for vault..."
until kubectl exec --namespace $_NAMESPACE $_POD -- bao version &>/dev/null; do sleep 2s; done

function sc_vault_init() {
    echo "Initializing vault..."
    kubectl exec --namespace $_NAMESPACE $_POD -- bao operator init \
        -key-shares=5 \
        -key-threshold=3 \
        -format=json |
        pass insert --force --multiline serenditree/vault >/dev/null
}
sc_vault_init

echo "Setting root-token..."
_ROOT_TOKEN="$(pass serenditree/vault | jq -r '.root_token')"

function sc_vault_unseal() {
    echo "Unsealing vault..."
    local _unseal_key
    for _key in $(seq 0 2); do
        _unseal_key=$(pass serenditree/vault | jq -r ".unseal_keys_b64[${_key}]")
        kubectl exec --namespace $_NAMESPACE $_POD -- bao operator unseal "$_unseal_key"
    done
}
sc_vault_unseal

function sc_vault_kv_v2() {
    echo "Enabling kv-v2..."
    kubectl exec --namespace $_NAMESPACE $_POD -- sh -c "
    BAO_TOKEN=$_ROOT_TOKEN bao secrets enable -path=serenditree kv-v2
    "
}
sc_vault_kv_v2
########################################################################################################################
# Creating policies
########################################################################################################################
function sc_vault_policy_internal() {
   echo "Creating policy for key rotation..."
   kubectl exec --namespace $_NAMESPACE $_POD -- sh -c "
cat <<EOF | BAO_TOKEN=$_ROOT_TOKEN bao policy write serenditree-internal -
path \"serenditree/data/*\" {
 capabilities = [\"read\", \"create\", \"update\"]
}
path \"serenditree/metadata/*\" {
 capabilities = [\"read\"]
}
path \"sys/tools/random/*\" {
 capabilities = [\"update\"]
}
EOF
"
}
sc_vault_policy_internal

function sc_vault_policy_external() {
   echo "Creating policy for external-secrets operator..."
   kubectl exec --namespace $_NAMESPACE $_POD -- sh -c "
cat <<EOF | BAO_TOKEN=$_ROOT_TOKEN bao policy write serenditree-external -
path \"serenditree/data/*\" {
 capabilities = [\"read\"]
}
path \"serenditree/metadata/*\" {
 capabilities = [\"read\"]
}
EOF
"
}
sc_vault_policy_external

function sc_vault_policy_token() {
    local -r _policy=$1
    echo "Creating token for the policy serenditree-${_policy}..."
    local -r _policy_token="$(
        kubectl exec --namespace $_NAMESPACE $_POD -- sh -c "
            BAO_TOKEN=$_ROOT_TOKEN bao token create -policy=serenditree-${_policy} -format=json
            " |
            jq -r '.auth.client_token'
    )"
    kubectl create secret generic "vault-${_policy}" \
        --from-literal=token="$_policy_token" \
        --namespace $_NAMESPACE
}
sc_vault_policy_token internal
sc_vault_policy_token external
########################################################################################################################
# Putting secrets
########################################################################################################################
function sc_vault_put() {
    local -r _cmd="\nBAO_TOKEN=$_ROOT_TOKEN bao kv put 'serenditree"
    local -r _out=">/dev/null && echo PUT serenditree/X"
    local _cmds=
    local _path=

    for _folder in app cicd o11y oidc iam; do
        echo "Preparing vault-secrets for ${_folder}..." >&2
        while read -r _item; do
            if [[ "$_folder" == "oidc" ]]; then
                _country="${_item%.*}"
                if [[ "${_item#*.}" == "id" ]]; then
                    _path="${_folder}/${_country}/country"
                    _cmds+="${_cmd}/${_path}' value='${_country}' ${_out//X/$_path}"
                fi
                _path="${_folder}/${_country}/${_item#*.}"
                _cmds+="${_cmd}/${_path}' value='$(pass "serenditree/oidc/${_country}.${_item#*.}")' ${_out//X/$_path}"
            else
                _path="${_folder}/${_item//./\/}"
                _cmds+="${_cmd}/${_path}' value='$(pass "serenditree/${_folder}/${_item}")' ${_out//X/$_path}"
            fi
        done < <(pass "serenditree/${_folder}" | sed -En 's/.* ([a-zA-Z.]+)/\1/p')
    done
    kubectl exec --namespace $_NAMESPACE $_POD -- sh -c "$(echo -e "$_cmds")"
}
sc_vault_put

