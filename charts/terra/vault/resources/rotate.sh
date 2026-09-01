#!/usr/bin/env bash
set -o errexit

VAULT_HOST=${VAULT_HOST:-"http://vault.terra-vault.svc.cluster.local:8200"}
VAULT_TOKEN="Authorization: Bearer $(</var/run/secrets/vault/token)"
CONTENT_TYPE="Content-Type: application/json"
KEY_VALUE_PATH=${KEY_VALUE_PATH:-"serenditree/data/app/branch/jwk"}
KEY_BYTES=64

function validate_key() {
    local -r _key=$1
    if [[ $(base64 -d <<<"$_key" | wc -c) -ne $KEY_BYTES ]]; then
        echo "Invalid key: ${_key}. Aborting..."
        exit 1
    fi
}

for KEY_USE in signature encryption; do
    echo "Rotating ${KEY_USE} keys..."
    ACTIVE_PATH="${KEY_VALUE_PATH}/${KEY_USE}"
    RETIRING_PATH="${ACTIVE_PATH}/retiring"

    echo -n "Getting the active key data..."
    RETIRING_KEY_DATA=$(
        curl \
            -fs \
            -H "$VAULT_TOKEN" \
            "${VAULT_HOST}/v1/${ACTIVE_PATH}" |
                jq '.data.data'
    )
    validate_key "$(jq -r '.value' <<<"$RETIRING_KEY_DATA")" && echo "ok"

    echo "Retiring the active key..."
    curl \
        -fs \
        -X POST \
        -H "$VAULT_TOKEN" \
        -H "$CONTENT_TYPE" \
        -d "{\"data\": ${RETIRING_KEY_DATA}}" \
        "${VAULT_HOST}/v1/${RETIRING_PATH}" | jq

    echo -n "Getting a new active key..."
    ACTIVE_KEY=$(
        curl \
            -fs \
            -X POST \
            -H "$VAULT_TOKEN" \
            -H "$CONTENT_TYPE" \
            -d '{"format": "base64"}' \
            "${VAULT_HOST}/v1/sys/tools/random/all/${KEY_BYTES}" |
                jq -r '.data.random_bytes'
    )
    validate_key "$ACTIVE_KEY" && echo "ok"

    echo "Posting the new active key..."
    curl \
        -fs \
        -X POST \
        -H "$VAULT_TOKEN" \
        -H "$CONTENT_TYPE" \
        -d "{\"data\": {\"value\": \"${ACTIVE_KEY}\"}}" \
        "${VAULT_HOST}/v1/${ACTIVE_PATH}" | jq
done
