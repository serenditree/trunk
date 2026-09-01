#!/bin/bash

function init_log() {
    echo "[$(date +%Y-%m-%dT%H:%M:%S,%3N)][INIT] $1"
}

if [[ -n "$S3_ACCESS_KEY" ]] && [[ -n "$S3_SECRET_KEY" ]]; then
    init_log "Adding s3 credentials..."
    echo "$S3_ACCESS_KEY" |
        ./bin/opensearch-keystore add --stdin --force s3.client.default.access_key &&
        init_log "Added access key."
    echo "$S3_SECRET_KEY" |
        ./bin/opensearch-keystore add --stdin --force s3.client.default.secret_key &&
        init_log "Added secret key."
else
  init_log "No s3 credentials available..."
fi
