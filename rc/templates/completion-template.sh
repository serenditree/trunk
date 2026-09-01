#!/usr/bin/env bash
########################################################################################################################
# BASH COMPLETION
# Bash completion script template for the serenditree command-line interface (sc).
########################################################################################################################
# shellcheck disable=SC2207

function _sc_completion() {
    local -r _current="${COMP_WORDS[COMP_CWORD]}"
    local -r _previous="${COMP_WORDS[COMP_CWORD - 1]}"
    local -r _local="${_LOCAL}"
    local -r _cluster="${_CLUSTER}"
    local -r _services="${_SERVICES}"
    local -r _charts="${_CHARTS}"

    # Options are not yet context aware.
    case "$_current" in
    --*)
        local -r _long="${_LONG}"
        ;;
    -)
        local -r _short="${_SHORT}"
        ;;
    esac

    case "$_previous" in
    cluster)
        COMPREPLY=($(compgen -W "$_cluster $_long $_short" -- "$_current"))
        ;;
    compose)
        COMPREPLY=($(compgen -W "up down $_long $_short" -- "$_current"))
        ;;
    database | db)
        COMPREPLY=($(compgen -W "user seed trace" -- "$_current"))
        ;;
    helm)
        COMPREPLY=($(compgen -W "charts push pull template" -- "$_current"))
        ;;
    template)
        COMPREPLY=($(compgen -W "$_charts" -- "$_current"))
        ;;
    registry)
        COMPREPLY=($(compgen -W "info scan age" -- "$_current"))
        ;;
    tekton|branch|leaf)
        COMPREPLY=($(compgen -W "branch leaf" -- "$_current"))
        ;;
    --scale)
        COMPREPLY=($(compgen -W "karpenter karpenter-only autoscaler" -- "$_current"))
        ;;
    *)
        if [[ "$_previous" == "sc" ]]; then
            COMPREPLY=($(compgen -W "$_local cluster help $_long $_short" -- "$_current"))
        elif [[ ${#COMP_WORDS[@]} -gt 2 ]]; then
            COMPREPLY=($(compgen -W "$_services $_long $_short" -- "$_current"))
        fi
        ;;
    esac
}

complete -F _sc_completion sc
