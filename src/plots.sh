#!/usr/bin/env bash
########################################################################################################################
# PLOT
# Finding, selecting and executing plots. A plot is a folder containing a file named 'plot.sh'.
########################################################################################################################

# Finds plots and prints their definitions/information.
# $1: Pattern for plot filtering.
function sc_plots() {
    local -r _pattern=$1
    # shellcheck disable=SC2044
    { for _plot in $(find . -type d -path '*/\.*' -prune -o -name 'plot.sh' -print); do
        pushd ${_plot%/*} >/dev/null || exit 1
        bash ./plot.sh info
        popd >/dev/null || exit 1
    done; } | grep -E "$_pattern" | sort -n -k1 | sed -En "/\s${_ARG_RESUME:-.*}\s/,\$p"
}

# Prints or opens available plots.
# $1: Pattern for plot filtering.
function sc_plots_inspect() {
    local -r _pattern=$1
    if [[ -n "$_ARG_OPEN" ]]; then
        sc_plots $_pattern |
            sed -En 's/.* (\/.*\.sh).*/\1/p' |
            uniq |
            xargs -I{} bash -c "echo 'Opening {}...' && idea {} >/dev/null"
    else
        cat <(echo 'ORDINAL SERVICE IMAGE TAG PATH') <(sc_plots $_pattern) | column -ts' '
    fi
}

# Executes the given action for the given plot.
# $1: Path (location) of the plot.
# $*: Arguments containing action and modifiers.
function sc_plot_do() {
    local _plot=$1
    shift

    pushd ${_plot%/*} >/dev/null || exit 1
    _plot=${_plot##*/}
    _plot=${_plot//:/ }
    if [[ " $* " =~ " build " ]] && [[ -z "$_ST_CONTEXT_TKN" ]]; then
        buildah unshare bash $_plot "$*" || exit 1
    else
        bash $_plot "$*" || exit 1
    fi
    popd >/dev/null || exit 1
}

# Finds plots and executes defined actions.
# $1: Pattern for plot filtering.
# $*: Arguments containing action and modifiers.
function sc_plots_do() {
    local -r _pattern=$1
    shift
    for _plot in $(sc_plots $_pattern | cut -d' ' -f5); do
        sc_plot_do $_plot "$*"
    done
}

# Prepares the insertion/deletion of a plot by adjusting ordinals.
# $1: Position of the plot (ordinal).
# $2: Increment/decrement.
function sc_plots_insert() {
    local -r _from=$1
    local -r _increment=$2
    local _current
    local _offset
    while read -r _plot; do
        _current=$(sed -En 's/^_ORDINAL=([0-9]+).*/\1/p' "$_plot")
        _offset=
        if [[ -z "$_current" ]]; then
            _current=$(sed -En 's/^_ORDINAL=.*_OFFSET \+ ([0-9]+).*/\1/p' "$_plot")
            _offset=true
        fi
        if [[ -n "$_current" ]] && [[ $_current -ge $_from ]]; then
            local _new=$(( _current + _increment ))
            printf "Setting ordinal %d to %d (offset %s) in %s...\n" "$_current" "$_new" ${_offset:-false} "$_plot"
            if [[ -z "$_ARG_DRYRUN" ]]; then
                if [[ -z "$_offset" ]]; then
                    sed -Ei "s/^_ORDINAL=${_current}.*/_ORDINAL=${_new}/" "$_plot"
                else
                    sed -Ei "s/^(_ORDINAL=.*_OFFSET \+ )${_current}(.*)/\1${_new}\2/" "$_plot"
                fi
            fi
        fi
    done <<< "$(find . -type d -path '*/\.*' -prune -o -name 'plot*sh' -print)"
}

# Prepares a plot template.
# $1: Position of the plot (ordinal).
# $2: Name of the plot.
# $3: Path for the plot.
function sc_plots_template() {
    local -r _ordinal="$1"
    local -r _name="$2"
    local -r _path="$3"
    local -r _plot="${_path}/plot.sh"
    local _pipe="highlight -S shellscript -O xterm256 -s rdark"

    echo -e "\nCreating plot '${_name}' with ordinal '${_ordinal}' at '${_plot}'..."
    if [[ -z "$_ARG_DRYRUN" ]]; then
        _pipe="tee ${_plot}"
        mkdir -p "$_path"
    fi
    export _HEADER_SUBST=${_name^^}
    export _NAME_SUBST=$_name
    export _ORDINAL_SUBST=$_ordinal
    envsubst '$_HEADER_SUBST $_NAME_SUBST $_ORDINAL_SUBST' <"${_ST_HOME_TRUNK}/rc/templates/plot-template.sh" | $_pipe
}
