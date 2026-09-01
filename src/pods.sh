#!/usr/bin/env bash
########################################################################################################################
# POD
# Control of- and interaction with the local development pod.
########################################################################################################################

# Lists local pods with custom formatting.
# $1: Disables "down"-message if set.
# shellcheck disable=SC2120
function sc_pod_list() {
    if podman pod exists "$_ST_POD" || podman pod exists "pod_${_ST_POD}"; then
        local -r _columns="{{.Names}};{{.Image}};{{.Command}};{{.Ports}};{{.Status}}"
        cat \
            <(echo "$_columns" | tr -d '{}.' | tr '[:lower:]' '[:upper:]') \
            <(podman ps --filter label=serenditree.io/service --format "$_columns") | column -ts';'
    elif [[ -z "$1" ]]; then
        echo "down"
    fi
}

# Spins up all or defined containers/services inside the local pod by executing the "run" action of the corresponding
# plot. If the  local pod does not yet exist, it is created.
# $*: Optional list of services.
function sc_pod_up() {
    local -r _plots="$(sc_args_to_pattern "$*")"

    if ! podman pod exists $_ST_POD; then
        sc_heading 1 "Creating pod"

        if [[ -n "${_ARG_EXPOSE}${_ARG_INTEGRATION}" ]]; then
            local -r _expose="--publish 8085:5432 --publish 8086:9200 --publish 5601:5601 --publish 9092:9092"
            echo "Exposing ports..."
        fi

        podman pod create \
            --name $_ST_POD \
            --add-host root-user:127.0.0.1 \
            --add-host root-seed:127.0.0.1 \
            --add-host root-wind:127.0.0.1 \
            --add-host branch-poll:127.0.0.1 \
            --publish 8080-8084:8080-8084 $_expose
    fi

    sc_plots_do "${_plots}" up

    sc_heading 1 "Running"
    sc_pod_list
    sc_pod_up_watch
}

# Waits for readiness if --wait or --integration is set.
function sc_pod_up_watch() {
    if [[ -n "${_ARG_WAIT}${_ARG_INTEGRATION}" ]]; then
        sc_heading 1 "Waiting"
        tput civis
        trap "tput cnorm" EXIT
        until sc_pod_health; do :; done
        if [[ $? -ne 0 ]]; then
            # Cancel integration tests!
            sc_heading 2 "Error during startup!"
            exit 1
        fi
    fi
}

# Spins up a pod for integration testing.
# $1 Timestamp of the build to be tested.
# $2 The projects base-directory.
# $3 Flag that indicates if the pod should be shut down after each artifact.
# $4 Flag that indicates if the pod should be shut down after all artifacts were tested.
function sc_pod_integration_up() {
    local -r _build=/tmp/serenditree-build-${1//:/-}.log
    local -r _dir="$2"
    local _down_after_all=$3
    local _down_after_each=$4

    [[ "$_down_after_each" == "true" ]] &&
        [[ "$_down_after_all" == "false" ]] &&
        echo "[WARN] Invalid parameter combination..." &&
        _down_after_all=true

    if podman pod exists $_ST_POD; then
        echo "[INFO] Reusing existing pod..."
        local -r _pod_exists=true
    fi

    if [[ ! -f $_build ]]; then
        pushd "$_dir" &>/dev/null || exit 1
        if [[ "$_down_after_each" == "false" ]] && [[ "$_down_after_all" == "true" ]]; then
            echo "[INFO] Saving build order..."
            mapfile -t _reactor \
                < <(mvn validate | sed -rn -e '/Reactor Build Order/,/-{2,}/p' | sed -rn 's/.+ (\S+) +\[.+/\1/p')
        fi
        if [[ -n "${_reactor[*]}" ]]; then
            echo "[INFO] First: ${_reactor[0]}"
            echo "[INFO] Last : ${_reactor[-1]}"
            echo "${_reactor[-1]}" >$_build
        else
            touch $_build
        fi
        popd &>/dev/null || exit 1
        if [[ -z "$_pod_exists" ]]; then
            echo "[INFO] Starting pod..."
            sc_pod_up root-{user,seed,wind} branch
        fi
    fi
}

# Stops and removes a single container.
# $1: Name of the container to remove.
function sc_pod_down_sub() {
    local -r _container=$1
    local -r _start=$(date +'%s')

    echo "Shutting down ${_container}..."
    podman container exists "$_container" &&
        podman container stop --time "$_ST_POD_TIMEOUT" "$_container" >/dev/null
    podman container rm --force "$_container" >/dev/null &&
        echo "Shut down ${_container}...${_BOLD}ok${_NORMAL} ($(($(date +'%s') - _start))s)"
}
export -f sc_pod_down_sub

# Stops and removes all or defined containers/services.
# $*: Optional list of services.
function sc_pod_down() {
    local -r _containers=$(sc_args_to_pattern "$*")

    if podman pod exists $_ST_POD; then
        podman container ls --filter label=serenditree.io/service --all --format '{{.Names}}' |
            grep -E "${_containers}" |
            xargs -I{} -P0 bash -c 'sc_pod_down_sub {}'

        if [[ -z "$*" ]]; then
            echo -n "Removing pod..."
            podman pod rm --force $_ST_POD >/dev/null && echo "${_BOLD}done${_NORMAL}"
        fi
    else
        echo "Nothing to shut down."
    fi

    local -r _container=opensearch-dashboards
    if test -z "$*" && podman ps --filter label=serenditree.io/service=$_container | grep -q $_container; then
        echo -n "Stopping ${_container}..."
        podman container stop $_container >/dev/null && echo "${_BOLD}done${_NORMAL}"
    fi
}

# Shuts down the pod for integration testing after failure or each/all artifacts.
# $1 Timestamp of the build to be tested.
# $2 The projects base-directory and artifact id separated by '::'.
# $3 Flag that indicates if the pod should be shut down after each artifact.
# $4 Flag that indicates if the pod should be shut down after all artifacts were tested.
function sc_pod_integration_down() {
    local -r _build=/tmp/serenditree-build-${1//:/-}.log
    local -r _dir="${2%::*}"
    local -r _failsafe_dir="${_dir}/target/failsafe-reports"
    local -r _artifact="${2#*::}"
    local _down_after_all=$3
    local _down_after_each=$4

    [[ "$_down_after_each" == "true" ]] &&
        [[ "$_down_after_all" == "false" ]] &&
        _down_after_all=true

    # Shut down after each or all!
    if [[ -f $_build ]]; then
        local -r _last_artifact="$(cat $_build)"
    fi
    if [[ "$_down_after_each" == "true" ]] ||
        [[ "$_last_artifact" == "$_artifact" ]]; then
        if [[ "$_down_after_all" == "true" ]]; then
            echo "[INFO] Shutting pod down..."
            sc_pod_down ""
        fi
        rm -f $_build
    fi

    # Shut down if tests failed!
    # shellcheck disable=SC2038
    if [[ "$_down_after_all" == "true" ]] &&
        [[ -d "$_failsafe_dir" ]] &&
        ! find "$_failsafe_dir" -name '*.txt' \
            -exec sed -rn 's/.*Failures: ([0-9]+), Errors: ([0-9]+).*/\1\2/p' {} ';' |
        xargs -I{} test "{}" == "00"; then
        echo "[INFO] Shutting pod down..."
        sc_pod_down ""
        rm -f $_build
    fi
}

# Executes deployment scripts within all or defined Java containers/services.
# $*: Optional list of services.
function sc_pod_deploy() {
    podman pod exists $_ST_POD ||
        { echo "ERROR: Local pod does not exists. Did you mean sc cluster deploy...?" && exit 1; }
    sc_pod_up "$*"
}

# Prints and follows the logs of all or defined services.
# $*: Optional list of services.
function sc_pod_logs() {
    local -r _pods=$(sc_args_to_pattern "$*")

    # podman logs --names doesn't work with pods?
    local -r _id_to_name="$(podman ps --all --format '{{.ID}} {{.Names}} {{.Image}}' |
        grep serenditree |
        grep -E "$_pods" |
        sed -r "s/(.+) (.+) .*/^\1%${_BOLD}\2${_NORMAL}/" |
        xargs -I{} echo "-e s%{}%")"

    podman ps --all --format '{{.ID}} {{.Names}} {{.Image}}' |
        grep serenditree |
        grep -E "$_pods" |
        cut -d' ' -f1 |
        xargs podman logs --follow 2>&1 |
        sed -E ${_id_to_name//$'\n'/ }
}

# Runs health-checks on services.
# Return codes:
# 0: All containers are healthy
# 1: One or more containers are unhealthy
function sc_pod_health() {
    local _exit=0
    # quick (probably outdated health status depending on interval)
    if [[ ! "$_ARG_COMMAND" = "up" ]] && [[ -z "$_ARG_VERBOSE" ]]; then
        if [[ -n "${_ARG_WAIT}" ]]; then
            local -r _duration=$(date -d "@$(($(date +%s) - _ST_START))" "+%Mm %Ss")
            echo -e "Monitoring health... ${_duration}\n"
        fi

        podman ps --filter label=serenditree.io/service --format '{{.Names}} {{.Status}}' |
            sed -rn 's/^(\S+).*\((starting|unhealthy|healthy)\)$/\1 \2/p' |
            sort |
            column -t
    # latest (actively run health-checks)
    else
        local -r _tmp=/tmp/sc-containers
        podman ps --filter label=serenditree.io/service --format '{{.Names}}' >$_tmp
        local -r _count=$(wc -l $_tmp)
        # Pad with maximum length of a container name.
        local -r _format="\e[2K%-$(awk '{if (length > max) max=length} END {print max}' $_tmp)s  %s\n"

        local -r _tmp_unhealthy=/tmp/sc-containers-unhealthy
        podman ps --filter label=serenditree.io/service --format '{{.Names}}' |
            xargs -P0 -I{} bash -c "sc_pod_health_sub '$_format' '$_tmp_unhealthy' {}" | sort

        [[ -f $_tmp_unhealthy ]] &&
            rm $_tmp_unhealthy &&
            [[ -z "$_ARG_VERBOSE" ]] &&
            _exit=1 &&
            echo -en "\e[${_count% *}A"
    fi
    return $_exit
}
export -f sc_pod_health

# Runs an healthcheck for the given container.
# $1: Format string for printf.
# $2: Location for the temporary file that indicates an unhealthy container.
# $3: Name of the container to check.
function sc_pod_health_sub() {
    local -r _format=$1
    local -r _unhealthy=$2
    local -r _container=$3

    if podman healthcheck run "$_container" >/dev/null; then
        _status=healthy
    else
        _status=unhealthy
        touch "$_unhealthy"
    fi
    printf "$_format" "$_container" "$_status"
}
export -f sc_pod_health_sub

# Creates backups of local databases.
function sc_pod_data_backup() {
    if [[ -n "$_ARG_COMPOSE" ]]; then
        local -r _pod=pod_serenditree
        local -r _network="--network serenditree_default"
    else
        local -r _pod=serenditree
    fi

    # Backup root-user
    sc_heading 1 "Backing up root-user..."
    podman run --rm --name pgdumb --pod $_pod $_network --volume ${HOME}/Downloads/backup:/backup:Z \
        --env PGPASSWORD=root \
        --env PGUSER=postgres \
        --env PGDATABASE=serenditree \
        --env PGHOST=root-user \
        localhost/serenditree/root-user:latest \
        sh -c "pg_dump  \
                --data-only \
                --quote-all-identifiers \
                --no-password |
                gzip > /backup/user-backup.gz"

    # Backup root-seed
    sc_heading 1 "Backing up root-seed..."
    podman run --rm --name mongodump --pod $_pod $_network --volume ${HOME}/Downloads/backup:/backup:Z \
        localhost/serenditree/root-seed:latest \
        sh -c "mongodump mongodb://root-seed:27017 \
                 --username=root  \
                 --password=root \
                 --authenticationMechanism=SCRAM-SHA-256  \
                 --authenticationDatabase=admin  \
                 --db=serenditree \
                 --archive=/backup/seed-backup.gz \
                 --gzip"
}

# Restores local databases from local or remote data.
function sc_pod_data_restore() {
    if [[ -z "$_ARG_LOCAL" ]]; then
        sc_heading 1 "Downloading archives..."
        exo storage download --recursive --force sos://serenditree-backup ${HOME}/Downloads/backup
    fi
    if [[ -n "$_ARG_COMPOSE" ]]; then
        local -r _pod=pod_serenditree
        local -r _network="--network serenditree_default"
    else
        local -r _pod=serenditree
    fi

    # Restore root-user
    sc_heading 1 "Restoring root-user..."
    local _select
    for _table in User Poll PollOption FenceRecord FenceIdRecord; do
        _select+="echo 'SELECT COUNT(*) FROM \"${_table}\";' | tee /dev/stderr | psql &&
                  echo 'SELECT * FROM \"${_table}\" LIMIT 42;' | tee /dev/stderr | psql &&"
    done
    podman run --rm --name pgrestore --pod $_pod $_network --volume ${HOME}/Downloads/backup:/backup:Z \
        --env PGPASSWORD=root \
        --env PGUSER=postgres \
        --env PGDATABASE=serenditree \
        --env PGHOST=root-user \
        localhost/serenditree/root-user:latest \
        sh -c "gunzip < /backup/user-backup.gz | psql >/dev/null && ${_select% &&}"

    # Restore root-seed
    sc_heading 1 "Restoring root-seed..."
    podman run --rm --name mongorestore --pod $_pod $_network --volume ${HOME}/Downloads/backup:/backup:Z \
        localhost/serenditree/root-seed:latest \
        sh -c "mongorestore mongodb://root-seed:27017 \
                    --username root \
                    --password root \
                    --authenticationDatabase admin \
                    --nsInclude='serenditree.*' \
                    --archive=/backup/seed-backup.gz \
                    --gzip \
                    --preserveUUID \
                    --drop"
}
