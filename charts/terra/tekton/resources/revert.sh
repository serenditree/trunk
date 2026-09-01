#!/usr/bin/env bash
QUAY_ENDPOINT="https://quay.io/api/v1/repository/serenditree"
QUAY_REPO="$(params.app)"
QUAY_TAG="$(params.tag)"

RESTORE_MANIFEST=$(
    curl -sX GET \
      -H "Authorization: Bearer $QUAY_TOKEN" \
      -H "Accept: application/json" \
      "${QUAY_ENDPOINT}/${QUAY_REPO}/tag/?specificTag=${QUAY_TAG}" |
      jq '.tags.[1].manifest_digest'
)

HTTP_STATUS=$(
    curl -sX POST \
      -H "Authorization: Bearer $QUAY_TOKEN" \
      -H "Content-Type: application/json" \
      -d "{\"manifest_digest\": ${RESTORE_MANIFEST}}" \
      -w "%{http_code}" \
      -o /dev/null \
      "${QUAY_ENDPOINT}/${QUAY_REPO}/tag/${QUAY_TAG}/restore"
)

if [[ $HTTP_STATUS -ge 200 ]] && [[ $HTTP_STATUS -lt 300 ]]; then
    echo "Restored previous revision."
else
    echo "Could not restore previous revision: ${HTTP_STATUS}."
    exit 1
fi
