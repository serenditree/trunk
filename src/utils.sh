########################################################################################################################
# UTILS
# Collection of utility functions.
########################################################################################################################
# shellcheck disable=SC2155

# Prints the given message prominently to stdout.
# $1: Heading ID.
# $2: "n" or heading.
# $*: Heading.
function sc_heading() {
    local -r _heading_id=$1
    shift
    [[ "$1" == "n" ]] && shift && echo

    echo -n "${_BOLD}"
    [[ $_heading_id -eq 1 ]] && [[ -z "$_ST_CONTEXT_TKN" ]] && printf "%*s\n" $(tput cols) | tr " " "-"
    echo "$*"
    [[ $_heading_id -eq 1 ]] && [[ -z "$_ST_CONTEXT_TKN" ]] && printf "%*s\n" $(tput cols) | tr " " "-"
    echo -n "${_NORMAL}"
}
export -f sc_heading

# Sends desktop notifications.
# $1: Notification to send.
function sc_notify() {
    [[ -n "$_ST_NOTIFY" ]] && notify-send \
        --app-name serenditree-cli \
        --expire-time=3 \
        --urgency=normal \
        --transient \
        --icon=utilities-terminal \
        "Serenditree CLI: $_ARG_COMMAND $_ARG_SUB_COMMAND" \
        "$1"
    [[ -n "$_ST_NOTIFY_SOUND" ]] && canberra-gtk-play \
        --id="complete" \
        --loop=1 \
        --display=:0.0 \
        --volume=-15
}
export -f sc_notify

# Grep pattern which selects everything if no additional terms (plots,...) are supplied.
# $*: Optional list of terms that will be compiled into an OR-pattern.
function sc_args_to_pattern() {
    local -r _args="$*"
    echo "st-all-or|${_args// /|}"
}
export -f sc_args_to_pattern

# Prompts the user before running a function. The prompt will be "$1 [y/N]: ".
# $1: Prompt message.
function sc_prompt() {
    if [[ -z "$_ARG_YES" ]]; then
        read -rp "${_BOLD}$1 [y/N]:${_NORMAL} " _proceed
    else
        _proceed=y
        echo "${_BOLD}$1 [y/N]:${_NORMAL} ${_proceed}"
    fi

    local _exit=1
    if [[ "$_proceed" == "y" ]]; then
        _exit=0
    fi
    unset _proceed

    return $_exit
}
export -f sc_prompt

# Adds a trap.
# $1: New trap to add.
# $2: Signals
# shellcheck disable=SC2064,SC2086
function sc_trap() {
    local -r _new_trap="${1}; echo done"
    local -r _signals="$2"
    local -r _trap=$(trap -p $_signals | sed -E -e "s/^[^']+'(.+)'[^']+/\1/" -e "s/['\]{3}//g")
    if [[ -n "$_trap" ]]; then
        trap "${_trap%;*}; ${_new_trap}" $_signals
    else
        trap "echo -n Cleaning up...; ${_new_trap}" $_signals
    fi
}

# Adds bash-completion script to /etc/bash_completion.d/.
function sc_completion() {
    if [[ -n "$_ARG_ALL" ]]; then
        for _app in oc crc; do
            sc_heading 1 $_app
            command -v $_app && $_app completion bash | sudo tee "/etc/bash_completion.d/${_app}"
        done
    fi

    sc_heading 1 sc
    local -r _cli="${_ST_HOME_TRUNK}/cli.sh"
    local -r _cmd_pattern='s/[[:space:]]+([^[:space:]|]+).*:[[:space:]]+[^[:space:]]+.*/\1/p'

    export _LOCAL=$(
        $_cli help |
            sed -n '/Local commands/,/Cluster commands/p' |
            sed -En "$_cmd_pattern" |
            sort -u |
            xargs
    )
    export _CLUSTER=$(
        $_cli help |
            sed '0,/Cluster commands/d' |
            sed -En "$_cmd_pattern" |
            sort -u |
            xargs
    )
    export _LONG="$($_cli help | sed -En 's/.*(--\w+).*/\1/p' | sort -u | xargs)"
    export _SHORT="$($_cli help | sed -En 's/.*\s(-\w).*/\1/p' | sort -u | xargs)"
    export _SERVICES="$(
        sc_plots |
        cut -d' ' -f2 |
        sed -E 's/soil-(\S+)/\0\n\1/' |
        tr -d '*' |
        sort |
        xargs
    )"
    export _CHARTS="$(sc_helm_charts | awk '{print $1}' | sort | xargs)"

    envsubst '$_LOCAL $_CLUSTER $_LONG $_SHORT $_SERVICES $_CHARTS' <"${_ST_HOME_TRUNK}/rc/templates/completion-template.sh" |
        sudo tee /etc/bash_completion.d/sc
}
export -f sc_completion

# Rotates JWK material locally.
function sc_rotate_keys() {
    local -r _path=serenditree/app/branch.jwk
    for _key in signature signature.retiring encryption encryption.retiring; do
        openssl rand -base64 64 |
            tr -d "\n" |
            pass insert --force --multiline ${_path}.${_key} >/dev/null

        pass ${_path}.${_key} && echo
    done

    pass git push 2>&1
}
