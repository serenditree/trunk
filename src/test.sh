#!/usr/bin/env bash
########################################################################################################################
# TEST
# Prepares and runs tests.
########################################################################################################################

# Generates tests from OpenAPI-specs.
function sc_test_generate_openapi() {
    local -r _volume_src=${_ST_HOME_TRUNK}/charts/terra/testing/generated
    local -r _volume_target=/k6-test

    for _api in user:8081 seed:8082 poll:8083; do
        print_log "Generating tests for ${_api}..."
        _service="${_api%:*}"
        _port="${_api#*:}"
        _dir="${_volume_src}/${_service}"
        rm -rf "$_dir"
        mkdir -p "$_dir"

        podman run \
            --rm \
            --network host \
            --volume "${_dir}:${_volume_target}:Z" \
            docker.io/openapitools/openapi-generator-cli generate \
                --input-spec http://localhost:${_port}/api/v1/${_service}/openapi?format=json \
                --generator-name k6 \
                --output "${_volume_target}"
    done
}

# Generates test from HAR-files.
# $1: HAR-file location.
function sc_test_generate_har() {
    local -r _har="$1"
    local -r _volume_src="${_har}"
    local -r _volume_target=/converter/"${_har##*/}"
    local -r _js="${_ST_HOME_TRUNK}/charts/terra/testing/generated/har-$(date +%Y%m%d-%H%M%S).js"
    echo -n "Generating tests from ${_har}..."
    podman run \
        --rm \
        --volume "${_volume_src}:${_volume_target}:Z" \
        docker.io/grafana/har-to-k6:latest -- \
        "${_har##*/}" > "$_js" &&
        echo -e "\033[3D: $_js"
}

# Runs test locally.
function sc_test_run_local() {
    local _env=" BRANCH_USER=localhost:8081 BRANCH_SEED=localhost:8082 BRANCH_POLL=localhost:8083"
    _env+=" ROOT_MAP=localhost:8084"
    [[ -z "$_ARG_DELETE" ]] && _env+=" K6_NO_TEARDOWN=true"
    [[ -n "$_ARG_VERBOSE" ]] && _env+=" K6_SUMMARY_MODE=full"
    _env=${_env// / --env }

    if k6 &>/dev/null; then
        k6 run $_env "${_ST_HOME_TRUNK}/charts/terra/testing/resources/main.js"
    else
        podman run \
            --rm \
            --network host \
            --volume "${_ST_HOME_TRUNK}/charts/terra/testing/resources/:/home/k6/:Z" \
            localhost/serenditree/testing:latest \
            -- \
            run --quiet $_env main.js
    fi
}

# Runs test using k6-operator.
function sc_test_run_cluster() {
    local -r _namespace=terra-testing
    if [[ -z "$_ARG_DELETE" ]]; then
        sc_heading 1 "Testing"
        kubectl create \
            --filename "${_ST_HOME_TRUNK}/rc/jobs/test-serenditree.yml" \
            --namespace $_namespace

        echo "Waiting for logs..."
        until [[ $(kubectl get pod \
            --no-headers \
            --namespace $_namespace \
            --selector runner=true \
            --field-selector status.phase==Running 2>/dev/null |
            wc -l) -eq 2 ]]
        do
            sleep 1s
        done
        until kubectl logs \
            --namespace $_namespace \
            --selector runner=true \
            --prefix \
            --follow 2>/dev/null
        do
            sleep 1s
        done

        sc_heading 1 "Results"
        kubectl logs --namespace $_namespace --selector runner=true --prefix --tail 200
    else
        echo "Cleaning up test-run..."
        kubectl delete job --all --namespace $_namespace
    fi
}

function sc_test() {
    local -r _command="$1"
    local -r _har="$2"

    case "$_command" in
    openapi|api)
        sc_test_generate_openapi
        ;;
    har)
        sc_test_generate_har "$_har"
        ;;
    *)
        sc_test_run_local
        ;;
    esac
}
