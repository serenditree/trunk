#!/usr/bin/env bash
########################################################################################################################
# COMPOSE
# Routines for podman compose.
########################################################################################################################
# shellcheck disable=SC2068,SC2155
_SC_COMPOSE="--file ${_ST_HOME_TRUNK}/rc/compose/compose.yml --project-name serenditree"

function sc_compose() {
    if [[ "$1" == "up" ]]; then
        shift
        sc_compose_up $@
    else
        podman compose $_SC_COMPOSE $@
    fi
}

function sc_compose_up() {
    export NPROC=$(ulimit -u)
    export NOFILE=$(ulimit -n)

    sc_heading 1 "Starting"
    local -r _podman_args=$(${_ST_HOME_TRUNK}/plots/branch/src/secrets.sh podman)
    podman compose $_SC_COMPOSE --podman-run-args "$_podman_args" \
        up --detach $@

    sc_heading 1 "Running"
    sc_pod_list
    sc_pod_up_watch
}

function sc_compose_down() {
    podman compose $_SC_COMPOSE \
        down --timeout $_ST_POD_TIMEOUT $@
}
