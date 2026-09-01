#!/usr/bin/env bash
########################################################################################################################
# SERENDITREE COMMANDLINE INTERFACE
########################################################################################################################
# shellcheck disable=SC2154
_ST_HELP_DETAIL="'sc <command> --help' for details about a certain command!"
_ST_HELP="Please type 'sc <help>' for a list of commands or $_ST_HELP_DETAIL"
# m4_ignore(
_ST_ARGBASH=true
echo -n "Building Serenditree CLI..."
argbash cli-template.sh --output cli.sh
sed -Ei \
    -e 's/"\$0"/" sc" \&\& echo/' \
    -e 's/\(no-\)//g' \
    -e 's/, --no-[^:]+//g' \
    -e 's/\\t%s\\n([^:]+): /\\t%-20s%s\\n\1:" "/g' \
    -e 's/ \(off by default\)//g' \
    -e 's/FATAL //g' \
    -e "s/, but got only [^.]+./.\n\n$_ST_HELP/" \
    -e 's/(.*)"You have passed.*/\1"ERROR: Unknown option: $2"/' \
    cli.sh
echo "Done"
#)
# ARG_POSITIONAL_SINGLE([command], [Command to execute. Please type sc <help> for a list of commands!], [])
# ARG_OPTIONAL_BOOLEAN([all], [a], [All...])
# ARG_OPTIONAL_BOOLEAN([compose], [c], [Run or build for podman compose.])
# ARG_OPTIONAL_BOOLEAN([delete], [], [Deletion flag.])
# ARG_OPTIONAL_BOOLEAN([dryrun], [d], [Activates dryrun mode.])
# ARG_OPTIONAL_BOOLEAN([expose], [E], [Exposes database ports on local pods.])
# ARG_OPTIONAL_BOOLEAN([help], [h], [Command help. Please type sc <help> for a list of commands!])
# ARG_OPTIONAL_BOOLEAN([init], [], [Initialization flag.])
# ARG_OPTIONAL_BOOLEAN([insert], [], [Inserts a new plot.])
# ARG_OPTIONAL_BOOLEAN([integration], [], [Run for integration testing.])
# ARG_OPTIONAL_BOOLEAN([kubernetes], [k], [Use vanilla kubernetes.])
# ARG_OPTIONAL_BOOLEAN([local], [l], [Target local cluster.])
# ARG_OPTIONAL_BOOLEAN([notify], [n], [Enable desktop notifications.])
# ARG_OPTIONAL_BOOLEAN([open], [], [Open plots.])
# ARG_OPTIONAL_BOOLEAN([openshift], [o], [Use openshift.])
# ARG_OPTIONAL_BOOLEAN([prod], [P], [Sets the target stage to prod. (default is dev)])
# ARG_OPTIONAL_BOOLEAN([reset], [], [Reset flag.])
# ARG_OPTIONAL_BOOLEAN([restore], [], [Restore flag.])
# ARG_OPTIONAL_BOOLEAN([setup], [], [Setup flag.])
# ARG_OPTIONAL_BOOLEAN([test], [T], [Sets the target stage to test. (default is dev)])
# ARG_OPTIONAL_BOOLEAN([upgrade], [], [Upgrade flag.])
# ARG_OPTIONAL_BOOLEAN([wait], [w], [Wait for completion.])
# ARG_OPTIONAL_BOOLEAN([debug], [D], [Debug flag.])
# ARG_OPTIONAL_INCREMENTAL([verbose], [v], [Verbose flag.])
# ARG_OPTIONAL_INCREMENTAL([yes], [y], [Assumes yes on prompts.])
# ARG_OPTIONAL_BOOLEAN([xissuer], [x], [Set cert-issuer to prod when stage is not prod and vice versa.])
# ARG_OPTIONAL_SINGLE([scale], [s], [Auto-scaling implementation.], [karpenter])
# ARG_OPTIONAL_SINGLE([gateway], [g], [Gateway implementation.], [traefik])
# ARG_OPTIONAL_SINGLE([resume], [], [Resume plots from the given plot.])
# ARG_LEFTOVERS([Other arguments passed to command.])
# ARG_DEFAULTS_POS()
# ARG_RESTRICT_VALUES([no-any-options])
# ARG_POSITIONAL_DOUBLEDASH()
# ARGBASH_SET_INDENT([    ])
# ARGBASH_GO
# [
pushd "$(dirname "$(realpath $0)")" &>/dev/null || exit 1
########################################################################################################################
# ARGUMENTS
########################################################################################################################
export _ARG_COMMAND=$_arg_command
export _ARG_SUB_COMMAND=${_arg_leftovers[0]}
# shellcheck disable=SC2206
export _ARG_LEFTOVERS=(${_arg_leftovers[*]})

export _ARG_PROD=${_arg_prod/off/}
export _ARG_TEST=${_arg_test/off/}

export _ARG_ALL=${_arg_all/off/}
export _ARG_DRYRUN=${_arg_dryrun/off/}
export _ARG_DEBUG=${_arg_debug/off/}
export _ARG_VERBOSE=${_arg_verbose/0/}
export _ARG_YES=${_arg_yes/0/}
export _ARG_NOTIFY=${_arg_notify/off/}

export _ARG_COMPOSE=${_arg_compose/off/}
export _ARG_KUBERNETES=${_arg_kubernetes/off/}
export _ARG_LOCAL=${_arg_local/off/}
export _ARG_OPENSHIFT=${_arg_openshift/off/}

export _ARG_DELETE=${_arg_delete/off/}
export _ARG_INIT=${_arg_init/off/}
export _ARG_RESET=${_arg_reset/off/}
export _ARG_RESTORE=${_arg_restore/off/}
export _ARG_RESUME=$_arg_resume
export _ARG_SCALE=$_arg_scale
export _ARG_GATEWAY=$_arg_gateway
export _ARG_SETUP=${_arg_setup/off/}
export _ARG_UPGRADE=${_arg_upgrade/off/}

export _ARG_EXPOSE=${_arg_expose/off/}
export _ARG_INSERT=${_arg_insert/off/}
export _ARG_OPEN=${_arg_open/off/}

_ARG_WAIT=${_arg_wait/off/}
_ARG_WAIT=${_ARG_WAIT/on/true}
export _ARG_WAIT

export _ARG_XISSUER=${_arg_xissuer//off/}
export _ARG_INTEGRATION=${_arg_integration/off/}

export _ARG_HELP=${_arg_help/off/}
########################################################################################################################
# SHELL OPTIONS
########################################################################################################################
[[ -n "${_ST_DEBUG}${_ARG_DEBUG}" ]] && set -o xtrace
[[ -n "${_ST_CONTEXT_TKN}" ]] && set -o errexit
########################################################################################################################
# IMPORT
########################################################################################################################
source ./src/env.sh

source ./src/cluster.sh
source ./src/compose.sh
source ./src/container.sh
source ./src/context.sh
source ./src/git.sh
source ./src/helm.sh
source ./src/login.sh
source ./src/plots.sh
source ./src/pods.sh
source ./src/status.sh
source ./src/update.sh
source ./src/utils.sh
source ./src/terra.sh
source ./src/test.sh
########################################################################################################################
# HELP
########################################################################################################################
function sc_help() {
    sc_heading 2 "Serenditree CLI"
    print_help

    local _options
    printf '\n\t%s\n' "${_BOLD}Local commands:${_NORMAL}"
    _options='[--expose] [--wait] [--compose] [--integration]'
    printf '\t%-20s%s\n' "up [svc]:" "Starts a local development stack or a single container. $_options"
    _options='[--compose] [--integration]'
    printf '\t%-20s%s\n\n' "down [svc]:" "Stops local stack or single containers. $_options"

    printf '\t%-20s%s\n' "build [svc]:" "Builds all or individual images."
    printf '\t%-20s%s\n' "backup:" "Backup local databases."
    printf '\t%-20s%s\n' "charts:" "Prints charts information."
    printf '\t%-20s%s\n' "completion:" "Adds bash-completion script to /etc/bash_completion.d/. [--all]"
    printf '\t%-20s%s\n' "compose [--] <cmd>:" "Run podman compose commands."
    printf '\t%-20s%s\n' "config:" "Prints cli and java config."
    printf '\t%-20s%s\n' "context [id]:" "Switch or display contexts."
    printf '\t%-20s%s\n' "database <db>:" "Open local database console. {user|seed}"
    printf '\t%-20s%s\n' "deploy [svc]:" "Deploys all or individual services to the local stack."
    printf '\t%-20s%s\n' "env:" "Prints global environment variables based on context."
    printf '\t%-20s%s\n' "expose:" "Port-forward operation-services. [--reset|--delete]"
    printf '\t%-20s%s\n' "git [--] <cmd>:" "Execute arbitrary git commands."
    printf '\t%-20s%s\n' "helm <cmd> [chart]:" "Push commons, update dependencies or render charts."
    printf '\t%-20s%s\n' "health:" "Runs health-checks on services. [--wait|--verbose]"
    printf '\t%-20s%s\n' "loc:" "Prints lines of code."
    printf '\t%-20s%s\n' "login <reg>:" "Login to configured registries."
    printf '\t%-20s%s\n' "logs|log [svc]:" "Prints logs of all or individual services on the local pod."
    printf '\t%-20s%s\n' "plots:" "Prints or inserts/deletes plots. [--open] [--insert|--delete]"
    printf '\t%-20s%s\n' "proxy:" "Proxy kubernetes services."
    printf '\t%-20s%s\n' "ps:" "Lists locally running serenditree containers."
    printf '\t%-20s%s\n' "push [svc]:" "Push all or individual images."
    printf '\t%-20s%s\n' "registry:" "Inspect images in remote registries. [--verbose]"
    printf '\t%-20s%s\n' "release:" "Updates the parent git repository and pushes new commits."
    printf '\t%-20s%s\n' "restore:" "Restores local databases from remote data."
    printf '\t%-20s%s\n' "rotate:" "Rotates JWK material locally."
    printf '\t%-20s%s\n' "status:" "Prints status information and checks prerequisites."
    printf '\t%-20s%s\n' "terra <cmd>:" "Run infra commands with all variables set."
    printf '\t%-20s%s\n' "test:" "Prepares and runs tests. [--delete][--verbose]"
    printf '\t%-20s%s\n' "update [comp]:" "Update components."

    printf '\n\t%s\n' "${_BOLD}Cluster commands:${_NORMAL}"
    printf '\t%-20s%s\n' "up:" "Cluster start/setup. [--init] [--setup] [--wait] [--scale]"
    printf '\t%-20s%s\n\n' "down:" "Cluster stop/deletion. [--reset|--delete] [--yes]"

    printf '\t%-20s%s\n' "backup:" "Setup backup cronjobs or run backups from cronjobs. [--setup]"
    printf '\t%-20s%s\n' "certificate:" "Prints certificate information."
    printf '\t%-20s%s\n' "clean:" "Deletes dispensable resources."
    printf '\t%-20s%s\n' "database <db>:" "Open database console. {user|seed}"
    printf '\t%-20s%s\n' "deploy:" "Deploys new images."
    printf '\t%-20s%s\n' "expose:" "Port-forward operation-services. [--reset|--delete]"
    printf '\t%-20s%s\n' "keys:" "List all keys in the cluster's vault."
    printf '\t%-20s%s\n' "login:" "Login to OpenShift and its internal registry."
    printf '\t%-20s%s\n' "logs <svc>:" "Prints logs of the given pod(s)."
    printf '\t%-20s%s\n' "proxy:" "Proxy kubernetes services."
    printf '\t%-20s%s\n' "registry [img]:" "Inspects the OpenShift image registry."
    printf '\t%-20s%s\n' "resources [csv]:" "Prints resource allocations. Optionally in CSV."
    printf '\t%-20s%s\n' "restore:" "Restore databases."
    printf '\t%-20s%s\n' "status:" "Prints cluster status information."
    printf '\t%-20s%s\n' "tekton [svc]:" "Triggers tekton runs for all or individual services."
    printf '\t%-20s%s\n' "test:" "Run tests using k6-operator. [--delete]"
    printf '\t%-20s%s\n' "unseal:" "Unseal the cluster's vault"

    echo -e "\nPlease type $_ST_HELP_DETAIL"
}
########################################################################################################################
# MAIN
########################################################################################################################
case ${_ARG_COMMAND} in
########################################################################################################################
# LOCAL
########################################################################################################################
up)
    if [[ -n "$_ARG_HELP" ]]; then
        sc_heading 2 "sc up [svc] [--expose] [--wait] [--compose] [--integration]"
        echo "Starts a local development stack or a single container."
    elif [[ -n "$_ARG_INTEGRATION" ]]; then
        sc_pod_integration_up ${_ARG_LEFTOVERS[*]}
    elif [[ -n "$_ARG_COMPOSE" ]]; then
        time sc_compose_up ${_ARG_LEFTOVERS[*]}
    else
        time sc_pod_up ${_ARG_LEFTOVERS[*]}
    fi
    ;;
down)
    if [[ -n "$_ARG_HELP" ]]; then
        sc_heading 2 "sc down [svc] [--compose] [--integration]"
        echo "Stops local stack or single containers."
    elif [[ -n "$_ARG_INTEGRATION" ]]; then
        sc_pod_integration_down ${_ARG_LEFTOVERS[*]}
    elif [[ -n "$_ARG_COMPOSE" ]]; then
        time sc_compose_down ${_ARG_LEFTOVERS[*]}
    else
        time sc_pod_down ${_ARG_LEFTOVERS[*]}
    fi
    ;;
build)
    if [[ -n "$_ARG_HELP" ]]; then
        sc_heading 2 "sc build [svc]"
        echo "Builds all or individual images."
    else
        time sc_build ${_ARG_LEFTOVERS[*]}
    fi
    ;;
backup)
    if [[ -n "$_ARG_HELP" ]]; then
        sc_heading 2 "sc backup"
        echo "Backup local databases to ~/Downloads/backup. [--compose]"
    else
        sc_pod_data_backup
    fi
    ;;
charts)
    if [[ -n "$_ARG_HELP" ]]; then
        sc_heading 2 "sc charts"
        echo "Prints charts information. [--verbose]"
    else
        sc_helm charts
    fi
    ;;
completion)
    if [[ -n "$_ARG_HELP" ]]; then
        sc_heading 2 "sc completion"
        echo "Adds bash-completion script to /etc/bash_completion.d/. [--all]"
    else
        sc_completion
    fi
    ;;
compose)
    if [[ -n "$_ARG_HELP" ]]; then
        sc_heading 2 "sc compose [--] <cmd>"
        echo "Run podman compose commands."
    else
        sc_compose ${_ARG_LEFTOVERS[*]}
    fi
    ;;
context)
    if [[ -n "$_ARG_HELP" ]]; then
        sc_heading 2 "sc context [id]"
        echo "Switch or display contexts. [--init]"
    else
        sc_context ${_ARG_LEFTOVERS[*]}
    fi
    ;;
config)
    if [[ -n "$_ARG_HELP" ]]; then
        sc_heading 2 "sc config"
        echo "Prints cli and java config."
    else
        sc_status_config
    fi
    ;;
database)
    if [[ -n "$_ARG_HELP" ]]; then
        sc_heading 2 "sc database <db>"
        echo "Open local database console. {user|seed}"
    else
        sc_login_db local ${_ARG_SUB_COMMAND}
    fi
    ;;
deploy)
    if [[ -n "$_ARG_HELP" ]]; then
        sc_heading 2 "sc deploy [svc]"
        echo "Deploys all or individual services to the local stack."
    else
        time sc_pod_deploy ${_ARG_LEFTOVERS[*]}
    fi
    ;;
env)
    if [[ -n "$_ARG_HELP" ]]; then
        sc_heading 2 "sc env"
        echo "Prints global environment variables based on context."
    else
        sc_status_env
    fi
    ;;
expose)
    if [[ -n "$_ARG_HELP" ]]; then
        sc_heading 2 "sc expose"
        echo "Port-forward operation-services. [--reset|--delete]"
    else
        if [[ -n "$_ARG_RESET" ]]; then
            _ARG_DELETE=on sc_cluster_expose "$(sc_args_to_pattern ${_ARG_LEFTOVERS[*]})"
            unset _ARG_DELETE
        fi
        sc_cluster_expose "$(sc_args_to_pattern ${_ARG_LEFTOVERS[*]})"
    fi
    ;;
git)
    if [[ -n "$_ARG_HELP" ]]; then
        sc_heading 2 "sc git [--] <cmd>"
        echo "Execute arbitrary git commands across this repo and its submodules."
    elif [[ "${_ARG_SUB_COMMAND}" == "backup" ]]; then
        sc_git push local --all
    else
        sc_git ${_ARG_LEFTOVERS[*]}
    fi
    ;;
helm)
    if [[ -n "$_ARG_HELP" ]]; then
        sc_heading 2 "sc helm {charts|push|pull|setup|template} [chart]"
        echo "Push commons, update dependencies or render charts."
        printf '\n\t%-20s%s\n' "charts" "Print chart information. [--verbose]"
        printf '\t%-20s%s\n' "pull" "Pull chart dependencies. [--init]"
        printf '\t%-20s%s\n' "push" "Package and push commons and CRDs."
        printf '\t%-20s%s\n' "setup" "Add configured helm repos."
        printf '\t%-20s%s\n' "template" "Render templates locally. [--verbose]"
    else
        sc_helm ${_ARG_SUB_COMMAND}
    fi
    ;;
health)
    if [[ -n "$_ARG_HELP" ]]; then
        sc_heading 2 "sc health"
        echo "Runs health-checks on services. [--wait] [--verbose]"
    elif [[ -n "$_ARG_WAIT" ]]; then
        _ST_START="$(date +%s)"
        export _ST_START
        watch -tn1 sc_pod_health
    else
        sc_pod_health
    fi
    ;;
loc)
    if [[ -n "$_ARG_HELP" ]]; then
        sc_heading 2 "sc loc"
        echo "Prints lines of code."
    else
        tokei -e .idea,.iml,.git,e2e,node_modules,target,lucene,javadoc,docs,dist -s files $_ST_HOME |
            sed -e '/-/d' -e 's/^ //' -e 's/=/-/g'
    fi
    ;;
login)
    if [[ -n "$_ARG_HELP" ]]; then
        sc_heading 2 "sc login <reg>"
        echo "Login to configured registries: redhat, quay, openshift, openshift/local"
    else
        sc_login "${_ARG_SUB_COMMAND}"
    fi
    ;;
logs | log)
    if [[ -n "$_ARG_HELP" ]]; then
        sc_heading 2 "sc logs|log [svc]"
        echo "Prints logs of all or individual services on the local pod."
    else
        sc_pod_logs ${_ARG_LEFTOVERS[*]} || echo "Did you mean 'sc cluster logs'?"
    fi
    ;;
plots)
    if [[ -n "$_ARG_HELP" ]]; then
        sc_heading 2 "sc plots [ordinal [name path]]"
        echo "Prints or inserts/deletes plots. [--all] [--open] [--insert|--delete]"
        echo "Path needs to be absolute."
    elif [[ -n "$_ARG_INSERT" ]]; then
        sc_plots_insert "${_ARG_SUB_COMMAND}" "1" | sort -nk3
        sc_plots_template ${_ARG_LEFTOVERS[*]}
    elif [[ -n "$_ARG_DELETE" ]]; then
        sc_plots_insert "${_ARG_SUB_COMMAND}" "-1" | sort -nk3
    else
        sc_plots_inspect "$(sc_args_to_pattern ${_ARG_LEFTOVERS[*]})"
    fi
    ;;
proxy)
    if [[ -n "$_ARG_HELP" ]]; then
        sc_heading 2 "sc proxy"
        echo "Proxy kubernetes services. [--delete]"
    else
        sc_cluster_proxy
    fi
    ;;
ps)
    if [[ -n "$_ARG_HELP" ]]; then
        sc_heading 2 "sc ps"
        echo "Lists locally running serenditree containers."
    else
        sc_pod_list silent
    fi
    ;;
push)
    if [[ -n "$_ARG_HELP" ]]; then
        sc_heading 2 "sc push [svc]"
        echo "Push all or individual images. [--dryrun]"
    else
        time sc_push_plots "$(sc_args_to_pattern ${_ARG_LEFTOVERS[*]})"
    fi
    ;;
registry)
    if [[ -n "$_ARG_HELP" ]]; then
        sc_heading 2 "sc registry {info|scan|age} [comp]"
        echo "Retrieves information from the registry."
    else
        export _ARG_LEFTOVERS=(${_ARG_LEFTOVERS[*]:1})
        case ${_ARG_SUB_COMMAND} in
            info)
                time sc_registry_inspect "$(sc_args_to_pattern ${_ARG_LEFTOVERS[*]})"
                ;;
            scan)
                time sc_registry_scan "$(sc_args_to_pattern ${_ARG_LEFTOVERS[*]})"
                ;;
            age)
                time sc_registry_age
                ;;
        esac
    fi
    ;;
release)
    if [[ -n "$_ARG_HELP" ]]; then
        sc_heading 2 "sc release"
        echo "Updates the parent git repository and pushes new commits."
    else
        sc_git_release
    fi
    ;;
restore)
    if [[ -n "$_ARG_HELP" ]]; then
        sc_heading 2 "sc restore"
        echo "Restores local databases from remote (or local) data. [--local] [--compose]"
    else
        sc_pod_data_restore
    fi
    ;;
rotate)
    if [[ -n "$_ARG_HELP" ]]; then
        sc_heading 2 "sc rotate"
        echo "Rotates JWK material locally."
    else
        sc_rotate_keys
    fi
    ;;
secrets)
    if [[ -n "$_ARG_HELP" ]]; then
        sc_heading 2 "sc secrets"
        echo "Manages vault secrets."
    else
        sc_terra_vault
    fi
    ;;
status)
    if [[ -n "$_ARG_HELP" ]]; then
        sc_heading 2 "sc status"
        echo "Prints status information and checks prerequisites. [--all]"
    else
        sc_status
    fi
    ;;
terra)
    if [[ -n "$_ARG_HELP" ]]; then
        sc_heading 2 "sc terra <cmd>"
        echo "Run infra (OpenTofu) commands with all variables set."
    else
        sc_terra_run ${_ARG_LEFTOVERS[*]}
    fi
    ;;
test)
    if [[ -n "$_ARG_HELP" ]]; then
        sc_heading 2 "sc test [openapi|har <file>]"
        echo "Prepares and runs tests. [--delete] [--verbose]"
        printf '\n\t%-20s%s\n' "(none)" "Run tests locally against localhost."
        printf '\t%-20s%s\n' "openapi|api" "Generate tests from OpenAPI specs."
        printf '\t%-20s%s\n' "har <file>" "Generate tests from a HAR-file."
    else
        sc_test ${_ARG_LEFTOVERS[*]}
    fi
    ;;
update)
    if [[ -n "$_ARG_HELP" ]]; then
        sc_heading 2 "sc update [comp] [--yes] [--yes] [--all]"
        echo "Update components. Without specification, all components are updated or checked for latest versions."
        printf '\n\t%-20s%s\n' "helm" "Update chart versions."
        printf '\n\t%-20s%s' "{image* | img}" "Update base images or check for upgrades."
        printf '\n\t%-20s%s\n' "kustomize" "Update additional kustomize deployments."
        printf '\n\t%-20s%s\n' "crd*" "Updates custom resource definitions."
        printf '\n\t%-20s%s' "kubernetes" "Update Kubernetes."
        printf '\n\t%-20s%s' "{kafka}" "Update Kafka."
        printf '\n\t%-20s%s\n' "{maven | mvn | java}" "Update maven dependencies."
        printf '\n\t%-20s%s' "tile*" "Update Tileserver."
        printf '\n\t%-20s%s\n' "yarn" "Update node modules."
        printf '\n\t%-20s%s\n' "tools" "Update tools."
    else
        sc_update
    fi
    ;;
[1-4])
    sc_context $_ARG_COMMAND
    ;;
########################################################################################################################
# CLUSTER
########################################################################################################################
cluster)
    if [[ -z "${_ST_CONTEXT}" ]]; then
        tput cuu1
        sc_heading 2 "Aborting..." >&2
        exit 1
    fi
    export _ST_CONTEXT_CLUSTER=on
    # shift leftovers array
    # shellcheck disable=SC2206
    export _ARG_LEFTOVERS=(${_ARG_LEFTOVERS[*]:1})
    case ${_ARG_SUB_COMMAND} in
    up)
        if [[ -n "$_ARG_HELP" ]]; then
            _help_message="sc cluster up"
            _help_message+="[--init|--setup|--upgrade]"
            sc_heading 2 "$_help_message"
            echo "Start or install the cluster of the current context."
            printf '\n\t%-20s%s\n' "--init" "Initialize OpenTofu and create assets for openshift-install."
            printf '\n\t%-20s%s\n' "--setup" "Setup the cluster of the current context."
            printf '\n\t%-20s%s\n' "--upgrade" "Upgrade the cluster of the current context."
        else
            if [[ -n "${_ARG_SETUP}${_ARG_INIT}" ]]; then
                time sc_terra_up
            else
                time sc_cluster_up
            fi
        fi
        ;;
    down)
        if [[ -n "$_ARG_HELP" ]]; then
            _help_message="sc cluster down"
            _help_message+="[--reset|--delete]"
            sc_heading 2 "$_help_message"
            echo "Stop, delete or reset the cluster of the current context. "
            printf '\t%-20s%s\n' "--reset" "Reset the cluster of the current context."
            printf '\t%-20s%s\n' "--delete" "Delete the cluster of the current context."
         else
            if [[ -n "$_ARG_DELETE" ]]; then
                sc_prompt "Delete cluster?" && time sc_terra_down
            else
                sc_prompt "Stop worker nodes?" && time sc_cluster_down
            fi
        fi
        ;;
    clean)
        if [[ -n "$_ARG_HELP" ]]; then
            sc_heading 2 "sc cluster clean"
            echo "Deletes dispensable resources (failed pods, orphaned replica sets, old pipeline runs)."
        else
            time sc_cluster_clean
        fi
        ;;
    database)
        if [[ -n "$_ARG_HELP" ]]; then
            sc_heading 2 "sc cluster database <db>"
            echo "Open database console. {user|seed} [--expose]"
        else
            sc_login_db cluster ${_ARG_LEFTOVERS[*]}
        fi
        ;;
    deploy)
        if [[ -n "$_ARG_HELP" ]]; then
            sc_heading 2 "sc cluster deploy [svc]"
            echo "Deploys new images. {branch|leaf}"
        else
            sc_cluster_deploy "$(sc_args_to_pattern ${_ARG_LEFTOVERS[*]})"
        fi
        ;;
    expose)
        if [[ -n "$_ARG_HELP" ]]; then
            sc_heading 2 "sc cluster expose"
            echo "Port-forward operation-services. [--reset|--delete]"
        else
            if [[ -n "$_ARG_RESET" ]]; then
                _ARG_DELETE=on sc_cluster_expose "$(sc_args_to_pattern ${_ARG_LEFTOVERS[*]})"
                unset _ARG_DELETE
            fi
            sc_cluster_expose "$(sc_args_to_pattern ${_ARG_LEFTOVERS[*]})"
        fi
        ;;
    key*)
        if [[ -n "$_ARG_HELP" ]]; then
            sc_heading 2 "sc cluster keys"
            echo "List all keys in the cluster's vault."
        else
            sc_cluster_keys
        fi
        ;;
    login)
        if [[ -n "$_ARG_HELP" ]]; then
            sc_heading 2 "sc cluster login"
            echo "Login to OpenShift and its internal registry."
        elif [[ -n "$_ST_CONTEXT_OPENSHIFT" ]]; then
            sc_login openshift
        else
            sc_login openshift/local
        fi
        ;;
    logs | log)
        if [[ -n "$_ARG_HELP" ]]; then
            sc_heading 2 "sc cluster logs|log <svc>"
            echo "Prints logs of the given pod(s). {jobs} shows recent backup/restore job logs."
        else
            sc_cluster_logs ${_ARG_LEFTOVERS[*]}
        fi
        ;;
    proxy)
        if [[ -n "$_ARG_HELP" ]]; then
            sc_heading 2 "sc cluster proxy"
            echo "Proxy kubernetes services. [--delete]"
        else
            sc_cluster_proxy
        fi
        ;;
    registry)
        if [[ -n "$_ARG_HELP" ]]; then
            sc_heading 2 "sc cluster registry [img]"
            echo "Inspects the OpenShift image registry."
        else
            time sc_cluster_registry ${_ARG_LEFTOVERS[*]}
        fi
        ;;
    resources)
        if [[ -n "$_ARG_HELP" ]]; then
            sc_heading 2 "sc cluster resources [csv]"
            echo "Prints resource allocations. Optionally in CSV."
        else
            time sc_cluster_resources ${_ARG_LEFTOVERS[*]}
        fi
        ;;
    restore)
        if [[ -n "$_ARG_HELP" ]]; then
            sc_heading 2 "sc cluster restore"
            echo "Restore databases from the latest snapshot."
        else
            time sc_cluster_restore
        fi
        ;;
    status)
        if [[ -n "$_ARG_HELP" ]]; then
            sc_heading 2 "sc cluster status"
            echo "Prints cluster status information."
        else
            sc_status_cluster
        fi
        ;;
    backup)
        if [[ -n "$_ARG_HELP" ]]; then
            sc_heading 2 "sc cluster backup"
            echo "Creates database backup jobs manually from cronjobs."
        else
            time sc_cluster_backup
        fi
        ;;
    certificate)
        if [[ -n "$_ARG_HELP" ]]; then
            sc_heading 2 "sc cluster certificate"
            echo "Prints certificate information. [--reset]"
        else
            time sc_cluster_certificate
        fi
        ;;
    tekton)
        if [[ -n "$_ARG_HELP" ]]; then
            sc_heading 2 "sc cluster tekton [svc]"
            echo "Triggers tekton runs for all or individual services. [--debug]"
        else
            time sc_cluster_tekton "${_ARG_LEFTOVERS[*]}"
        fi
        ;;
    test)
        if [[ -n "$_ARG_HELP" ]]; then
            sc_heading 2 "sc cluster test"
            echo "Run tests using k6-operator. [--delete]"
        else
            sc_test_run_cluster
        fi
        ;;
    unseal)
        if [[ -n "$_ARG_HELP" ]]; then
            sc_heading 2 "sc cluster unseal"
            echo "Unseal the cluster's vault."
        else
            sc_cluster_unseal
        fi
        ;;
    *)
        sc_heading 2 "Unknown cluster command: ${_ARG_SUB_COMMAND}"
        print_help
        ;;
    esac
    ;;
help)
    sc_help
    ;;
*)
    if [[ -z "$_ST_ARGBASH" ]]; then
        sc_heading 2 "Unknown command: ${_ARG_COMMAND}"
        print_help
    fi
    ;;
esac
# ]
