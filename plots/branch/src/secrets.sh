#!/usr/bin/env bash
########################################################################################################################
# BRANCH SECRETS
# Retrieves secrets for injection during command execution.
########################################################################################################################
_ENV=
_PASS_OIDC="${PASSWORD_STORE_DIR:-$HOME/.password-store}/serenditree/oidc"
find "$_PASS_OIDC" -name '*.gpg' -printf '%P\n' | sed 's/\.gpg$//' | while read -r _ITEM; do
    _COUNTRY="${_ITEM%.*}"
    _COUNTRY="${_COUNTRY^^}"
    if [[ "${_ITEM#*.}" == "id" ]]; then
        _ENV="QUARKUS_OIDC_${_COUNTRY}_CLIENT_ID"
    elif [[ "${_ITEM#*.}" == "secret" ]]; then
        _ENV="QUARKUS_OIDC_${_COUNTRY}_CREDENTIALS_SECRET"
    else
        echo -n "--env QUARKUS_OIDC_${_COUNTRY}_APPLICATION_TYPE=web-app "
        _ENV="QUARKUS_OIDC_${_COUNTRY}_AUTH_SERVER_URL"
    fi
    echo -n "--env ${_ENV}=$(pass serenditree/oidc/${_ITEM}) "
done
