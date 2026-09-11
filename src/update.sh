#!/usr/bin/env bash
########################################################################################################################
# UPDATE
# Global update tasks.
########################################################################################################################
# shellcheck disable=SC2155

# Echos current/latest versions.
# $1: Current version.
# $2: Latest version.
function sc_update_echo {
    local -r _current=$1
    local -r _latest=$2

    [[ "$_current" != "$_latest" ]] && echo -n "$_BOLD"
    echo -e "current: ${_current}\nlatest: ${_latest}${_NORMAL}" | column -t
}

# Updates versions defined in env.sh
# $1: Name of the component to update.
# $2: Current version.
# $3: Latest version.
function sc_update_env() {
    local -r _component=$1
    local -r _current=$2
    local -r _latest=$3

    if [[ -n "$_ARG_YES" ]]; then
        sed -Ei \
           "s/(export _ST_VERSION_$(tr '\-[:lower:]' '_[:upper:]' <<<"$_component")=)(\w*)[0-9.-]+/\1${_latest}/" \
           "${_ST_HOME_TRUNK}/src/env.sh" &&
           echo "Updated ${_component} to version ${_latest}"
        if [[ $_ARG_YES -gt 1 ]]; then
           echo -e "\nPushing updates..."
           git -C "$_ST_HOME_TRUNK" commit -m "$_component $_latest;" src/env.sh
           git -C "$_ST_HOME_TRUNK" push
        fi
    else
       sc_update_echo "$_current" "$_latest"
    fi
}

# Checks helm dependency updates.
# $1 Log file to store versions.
function sc_update_helm_check() {
    local -r _log="$1"
    local -A _url2repo
    while IFS=";" read -r _repo _url; do
        _url2repo["$_url"]="$_repo"
    done <"${_ST_HOME_TRUNK}/rc/config/helm-setup"
    local -A _checked

    rm -f "$_log"
    while IFS=" " read -r _chart _repo_url _version; do
        local _repo_url="${_repo_url#*:}"
        _repo_url="${_repo_url%/}"
        local _repo_id=""
        local _repo_type=""

        if [[ -n "${_url2repo[${_repo_url}]}" ]]; then
            _repo_id="${_url2repo[${_repo_url}]}/${_chart#*:}"
            _repo_type="helm"
        elif [[ "${_repo_url%%:*}" == "oci" ]]; then
            _repo_id="${_repo_url#*//}/${_chart#*:}"
            _repo_type="oci"
        fi

        if [[ -n "$_repo_id" ]]; then
            local _repo_key="$(base64 <<<"$_repo_id")"
            if [[ -z "${_checked[${_repo_key}]}" ]]; then
                # Get latest version
                if [[ $_repo_type == "helm" ]]; then
                    local _latest="$(helm search repo "$_repo_id" --output json | jq -r '.[0] | .version')"
                else
                    local _latest="$(
                        skopeo list-tags "docker://${_repo_id}" |
                            jq -r '.Tags[]' |
                            sort -rV |
                            grep -Eiv 'rc|alpha|beta|latest' |
                            head -n1
                    )"
                fi
                # Output
                [[ "${_version#*:}" != "${_latest}" ]] && echo -n "$_BOLD"
                echo -e "\nartifact: ${_repo_id}\npath: ${_chart%%:*}\nversion: ${_version#*:}\nlatest: ${_latest}" |
                    column -Lt |
                    tee -a "$_log"
                echo -n "$_NORMAL"
                unset _repo_id
                _checked["${_repo_key}"]="true"
            fi
        else
            echo -e "\nRepo for ${_BOLD}${_chart#*:}${_NORMAL} (${_chart#*trunk/charts/}) not configured!" >&2
        fi
    done < <(
        find "${_ST_HOME_TRUNK}/charts" -type d -name soil -prune -o -name Chart.yaml -exec bash \
            -c 'sed -En "s%[- ]+(name|repository|version): (.*)%$1:\2%p" $1' _ {} \; | # Prepends path to each match
            tr -d ' ' |
            xargs -n3
    )
}

# Applies helm dependency updates.
# $1 Log file with stored versions.
function sc_update_helm_apply() {
    local -r _log="$1"
    sc_heading 1 "Updating helm dependencies"
    sed -E "/${_ST_VERSION_FIXED_HELM:-st-none}/,/latest/d" "$_log" |
        grep -E '^(path|version|latest)' |
        awk '{print $2}' |
        xargs -n3 bash -c 'sed -i "s/$1/$2/" $0'
    git diff |
        grep -EB 3 "^\+\W+version: [0-9.v]+" |
        sed -E -e '/name: commons/,/version/d' -e '/repository/d' -e 's/^(\W+|.*:)//' |
        xargs -n3 |
        column -t

    sc_helm_pull
    sc_helm_push

    if [[ $_ARG_YES -gt 1 ]]; then
        sc_heading 1 "Pushing updates"
        git -C "$_ST_HOME_TRUNK" commit -am 'Dependencies update;'
        git -C "$_ST_HOME_TRUNK" push
    fi
    [[ -n "$_ST_VERSION_FIXED_HELM" ]] &&
        echo -e "\n${_BOLD}Warning:${_NORMAL} Skipped ${_ST_VERSION_FIXED_HELM};" | sed -E -e 's/\|/, /g' -e 's/\\//g'
}

# Checks helm dependency updates or applies them.
function sc_update_helm() {
    local -r _log=/tmp/sc-update-helm.log
    if [[ -z "$_ARG_YES" ]]; then
        helm repo update
        sc_update_helm_check "$_log"
    elif [[ -f "$_log" ]]; then
        sc_update_helm_apply "$_log"
    else
        echo -e "File $_log does not exits.\nPlease run 'sc update helm' first!"
        exit 1
    fi
}

# Updates custom resource definitions that are not managed by argocd apps and applied before bootstrapping starts.
function sc_update_crds() {
    local -r _pre_bootstrap="${_ST_HOME_TRUNK}/src/kubernetes/src/pre-bootstrap.sh"
    local _latest
    while read -r _repo _current; do
        _repo="${_repo%/*}"
        _latest="$(curl -s "https://api.github.com/repos/${_repo}/releases/latest" | jq -r '.tag_name')"

        if [[ -z "$_ARG_YES" ]]; then
            sc_heading 2 "$_repo"
            sc_update_echo "$_current" "$_latest"
        else
            echo "Updating ${_repo} to ${_latest}."
            sed -Ei "s%(.*${_repo}.*)${_current}(.*)%\1${_latest}\2%" "$_pre_bootstrap"
        fi
    done < <(sed -En \
        's%.*/.*/(([^/]+/){2})releases/download/([^/]+)/.*%\1 \3%p' \
        "$_pre_bootstrap"
    )
}

# Kubernetes update.
function sc_update_kubernetes() {
    local -r _latest="$(exo compute sks versions --output-format text | sort -V | tail -n1)"
    sc_update_env "Kubernetes" "$_ST_VERSION_KUBERNETES" "$_latest"
}

# Checks versions of kustomize deployments.
function sc_update_kustomize() {
    # Inline kustomization in Application resources
    while read -r _repo _current; do
        [[ -z "$_ARG_YES" ]] && sc_heading 2 "$_repo"
        local _latest=$(
            curl --silent "https://api.github.com/repos/${_repo//*.com\//}/releases/latest" | jq -r '.tag_name'
        )
        if [[ -z "$_ARG_YES" ]]; then
            sc_update_echo "$_current" "$_latest"
        else
            echo "Updating ${_repo} to ${_latest}."
            sed -Ei "s/(.*targetRevision: )${_current}/\1${_latest}/" "${_ST_HOME_TRUNK}/charts/tree/values.yaml"
        fi
    done < <(sed -En 's/.*(repoUrl|targetRevision): (.*)/\2/p' "${_ST_HOME_TRUNK}/charts/tree/values.yaml" | xargs -n 2)

    # Kustomization.yaml
    local -A _checked
    while read -r _kustomization; do
        _checked=()
        while read -r _repo _current; do
            if [[ -z "${_checked[$_repo]}" ]]; then
                _checked[$_repo]=true
                sc_heading 2 "https://github.com/$_repo"
                local _latest=$(curl -s "https://api.github.com/repos/${_repo}/releases/latest" | jq -r '.tag_name')
                if [[ -z "$_ARG_YES" ]]; then
                    sc_update_echo "$_current" "$_latest"
                else
                    echo "Updating ${_repo} to ${_latest}."
                    sed -Ei "s/(.*)${_current}(.*)/\1${_latest}\2/" "$_kustomization"
                fi
            fi
        done < <(sed -En "s%.*https://github.com/(.*)/releases/download/([^/]+)/.*%\1 \2%p" "$_kustomization")
    done < <(find "$_ST_HOME_TRUNK" -name 'kustomization.y*' -exec realpath {} \;)

    # Push
    if [[ $_ARG_YES -gt 1 ]]; then
        git -C "$_ST_HOME_TRUNK" commit -am 'Dependencies update;'
        git -C "$_ST_HOME_TRUNK" push
    fi
}

# Tileserver update.
function sc_update_tileserver() {
    local -r _latest=$(yarn info tileserver-gl-light --json | jq -r '.data.version')
    sc_update_env "Tileserver" "$_ST_VERSION_TILESERVER" "$_latest"

    if [[ -n "$_ARG_YES" ]] && [[ "$_ST_VERSION_TILESERVER" != "$_latest" ]]; then
        export _ST_VERSION_TILESERVER="$_latest"
        sc_build root-map
    fi
}

# Checks or updates Kafka to the latest supported version.
function sc_update_kafka() {
    local -r _chart="${_ST_HOME_TRUNK}/charts/terra/streams/Chart.yaml"
    local -r _kafka_yml="${_ST_HOME_TRUNK}/charts/root/wind/templates/kafka.yml"
    local -r _strimzi_repo="https://raw.githubusercontent.com/strimzi/strimzi-kafka-operator"

    local -r _strimzi_version="$(yq '.dependencies[] | select(.name == "strimzi-kafka-operator") | .version' "$_chart")"
    local -r _kafka_versions="${_strimzi_repo}/${_strimzi_version}/kafka-versions.yaml"

    local -r _supported="$(
        curl --silent "$_kafka_versions" |
        yq '.[] | select(.supported == true) | .version' |
        sort -V
    )"
    local -r _latest="$(tail -n1 <<<"$_supported")"
    local -r _current="$_ST_VERSION_KAFKA"

    if [[ -n "$_ARG_YES" ]]; then
        sed -i "s/version: ${_current}/version: ${_latest}/" "$_kafka_yml" &&
            sc_update_env Kafka "$_current" "$_latest"
    else
        {
            echo -e "strimzi: ${_strimzi_version}\nsupported: $(xargs <<<"$_supported" | tr ' ' '/')"
            [[ "$_current" != "$_latest" ]] && echo -n "$_BOLD"
            echo -e "current: ${_current}\nlatest: ${_latest}${_NORMAL}"
        } | column -t
    fi
}

# Updates nginx.
function sc_update_nginx() {
   for REPO in nginx/nginx:$_ST_VERSION_NGINX nginx/nginx-otel:$_ST_VERSION_NGINX_OTEL; do
       local _current="${REPO#*:}"
       local _repo="${REPO%:*}"
       local _latest=$(curl --silent "https://api.github.com/repos/${_repo}/releases/latest" | jq -r '.tag_name')

       sc_update_env "${_repo#*/}" "$_current" "$_latest"
   done
}

# Updates base images or checks for upgrades.
# $1: Pattern for image selection.
function sc_update_image() {
    env | grep "_ST_FROM_" | grep -v ":latest" | sort | cut -d'=' -f2 | while read -r _image; do
        sc_heading 2 "$_image"
        # get current
        local _component=
        local _current=
        local _v=
        case $_image in
            *opensearch*)
                _current=$(skopeo inspect containers-storage:$_image |
                    jq -r '.Labels."org.label-schema.version"')
                ;;
            *postgres*)
                _current=$(skopeo inspect containers-storage:$_image |
                    sed -En 's/.*PG_VERSION=([0-9.]+\.[0-9.]+).*/\1/p')
                ;;
            *golang*)
                _current=$(skopeo inspect containers-storage:$_image |
                    sed -En 's/.*GOLANG_VERSION=([0-9.]+).*/\1/p')
                ;;
            *buildah*)
                _component=buildah
                _current=${_image##*:}
                _v=v
                ;;
            *k6*)
                _component=k6
                _current=${_image##*:}
                ;;
        esac
        # get latest
        local _latest=$(
            skopeo list-tags docker://${_image%:*} |
                jq -r '.Tags[]' |
                grep -E "^${_v}[[:digit:]]+\.[[:digit:]]+\.?[[:digit:]]*$" |
                sort -Vr |
                head -n1
        )
        # output
        sc_update_echo "$_current" "$_latest"
        # update
        if [[ -n "$_ARG_YES" ]] && [[ "$_current" != "$_latest" ]]; then
            if [[ -n "$_component" ]]; then
                podman pull ${_image%:*}:$_latest &&
                    podman rmi ${_image%:*}:$_current
                sc_update_env "$_component" "$_current" "$_latest"
            else
                podman pull $_image
            fi
        fi
    done
}

# Updates maven dependencies or checks for updates.
function sc_update_maven() {
    pushd "$_ST_HOME_BRANCH" &>/dev/null || exit 1
    if [[ -n "$_ARG_YES" ]]; then
        echo "Updating dependencies..."
        mvn validate -Pupdate
        if [[ -n "$(git status --porcelain)" ]]; then
            mvn clean install --activate-profiles integration
        fi
    else
        if [[ -n "$_ARG_VERBOSE" ]]; then
            echo "Listing dependencies..."
            mvn dependency:list |
                sed -En 's/\[INFO\]\s{4}(\S+)\s.*/\1/p' |
                sort -u && echo
        fi
        echo "Searching dependency updates..."
        [[ -n "$_ARG_ALL" ]] && local -r _override='-Dversions.maven.plugin.rules='
        mvn validate -Pversion $_override |
            sed -rn '/\[INFO\] The following version/,/\[INFO\] +$/p' |
            sed -r -e 's/\[INFO\] +//' -e 's/.*available version.*/Latest:/' -e 's/.*are available.*/Updates:/' |
            head -n-1
    fi
    popd &>/dev/null || exit 1
}

# Updates node modules and syncs package.json with yarn.lock.
function sc_update_yarn() {
    pushd "$_ST_HOME_LEAF" &>/dev/null || exit 1
    yarn install
    if [[ -n "$_ARG_YES" ]]; then
        yarn upgrade-interactive --caret
        ./dev/yarn.py
    else
        yarn outdated
    fi
    popd &>/dev/null || exit 1
}

# Uploads tiles.
# $1: mbtiles file.
function sc_upload_tiles() {
    local -r _tiles="$1"
    local -r _bucket=serenditree-data

    export AWS_PROFILE=serenditree
    export AWS_REGION=$_ST_ZONE_STORAGE_1
    export AWS_ENDPOINT_URL="https://sos-${AWS_REGION}.exo.io"

    if ! aws s3api head-bucket --bucket $_bucket &>/dev/null; then
        aws s3 mb s3://$_bucket

        aws s3api put-bucket-acl \
          --bucket $_bucket \
          --acl private
    fi

    aws s3 cp "$_tiles" "s3://${_bucket}/${_tiles##*/}" --acl bucket-owner-read
}

# Updates tiles.
function sc_update_tiles() {
    local -r _tiles_urls=/tmp/mbtiles
    local -r _tiles_dir=./mbtiles
    local -r _tiles_dir_repo="${_ST_HOME_TRUNK}/plots/root/map/data/tiles"
    local -r _tiles=osm.mbtiles

    if [[ ! -f $_tiles_urls ]]; then
        local _dl="https://data.maptiler.com/my-extracts/?dataset=osm&division=europe"
        _dl="$(echo $_dl/{austria,germany,switzerland})"

        echo "The file $_tiles_urls containing the URLs to download does not exist. Aborting..."
        echo -e "\nDownload at:\n$(tr ' ' '\n' <<<"$_dl")\n\nStore at:\n$_tiles_urls"
        exit 1
    fi

    sc_heading 2 "Installing build-dependencies..."
    sudo dnf install -y gcc-c++ libsq3-devel zlib-devel

    sc_heading 2 "Cloning tippecanoe..."
    pushd /tmp || exit 1
    rm -rf tippecanoe
    git clone https://github.com/mapbox/tippecanoe.git

    sc_heading 2 "Building tippecanoe..."
    pushd tippecanoe || exit 1
    make -j

    sc_heading 2 "Downloading tiles..."
    mkdir $_tiles_dir
    while read -r _mbtiles_url; do
        wget -c -P $_tiles_dir "$_mbtiles_url"
    done <$_tiles_urls

    sc_heading 2 "Joining tiles..."
    ./tile-join -f -pk -pg -o "${_tiles_dir}/${_tiles}" ${_tiles_dir}/*

    mkdir -pv "$_tiles_dir_repo"
    mv -fv "${_tiles_dir}/${_tiles}" "$_tiles_dir_repo"

    sc_heading 2 "Uploading tiles..."
    sc_upload_tiles "${_tiles_dir_repo}/${_tiles}"
}

# Subroutine for sc_update_tools.
function sc_update_tools_sub() {
    local _latest=$1
    local _current=$2
    local _exit=1

    sc_update_echo "$_current" "$_latest"

    if [[ "$_latest" != "$_current" ]]; then
        [[ -z "${_ARG_YES}" ]] && read -rp "update? [y/N]: " _PROCEED
        if [[ -n "${_ARG_YES}" ]] || [[ "$_PROCEED" == "y" ]]; then
            _exit=0
        fi
    fi

    return $_exit
}

# Installs/updates tools that are unavailable in package managers.
function sc_update_tools() {
    local _current
    local _latest

    # argocd
    if [[ $* =~ (argocd|^$) ]]; then
        sc_heading 2 argocd
        _current="$(command -v argocd >/dev/null && argocd version --client -o json | jq -r '.client.Version')"
        _latest=$(curl -s https://api.github.com/repos/argoproj/argo-cd/releases/latest | jq -r '.tag_name')
        if sc_update_tools_sub "$_latest" "${_current%+*}"; then
            curl -L  "https://github.com/argoproj/argo-cd/releases/download/${_latest}/argocd-linux-amd64" \
            -o "$_ST_BIN/argocd"
            chmod +x "$_ST_BIN/argocd"
            argocd completion bash | sudo tee /etc/bash_completion.d/argocd >/dev/null
        fi
    fi

    # exo
    if [[ $* =~ (exo( |$)|^$) ]]; then
        sc_heading 2 exo
        _current="v$(command -v exo >/dev/null && exo version | cut -d' ' -f2)"
        _latest=$(curl -s https://api.github.com/repos/exoscale/cli/releases/latest | jq -r '.tag_name')
        if sc_update_tools_sub "$_latest" "$_current"; then
            local _tar=exoscale-cli_${_latest#v}_linux_amd64.tar.gz
            curl -L "https://github.com/exoscale/cli/releases/download/${_latest}/${_tar}" -o "/tmp/${_tar}"
            tar -xzf "/tmp/${_tar}" -C "$_ST_BIN" exo
            exo completion bash | sudo tee /etc/bash_completion.d/exo &>/dev/null
        fi
    fi

    # ocp
    if [[ $* =~ (ocp|^$) ]]; then
        sc_heading 2 ocp
        local _mirror="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable"
        _current="$(command -v oc >/dev/null && oc version 2>/dev/null | head -n1 | cut -d' ' -f3)"
        _latest=$(curl -s "${_mirror}/release.txt" |sed -En 's/^Name:\s+//p')
        if sc_update_tools_sub "$_latest" "$_current"; then
            for _client in client:oc install:openshift-install; do
                local _tar=openshift-${_client%:*}-linux.tar.gz
                curl -L "${_mirror}/${_tar}" -o "/tmp/${_tar}"
                tar -xzf "/tmp/${_tar}" -C "$_ST_BIN" ${_client#*:}
            done
            oc completion bash | sudo tee /etc/bash_completion.d/oc >/dev/null
        fi
    fi

    # tekton
    if [[ $* =~ (tekton|^$) ]]; then
        sc_heading 2 tekton
        _current="v$(command -v tkn >/dev/null && tkn version --component client | head -n1 | cut -d' ' -f3)"
        _latest=$(curl -s https://api.github.com/repos/tektoncd/cli/releases/latest | jq -r '.name')
        if sc_update_tools_sub "$_latest" "$_current"; then
            local _tar=tkn_${_latest#v}_Linux_x86_64.tar.gz
            curl -L "https://github.com/tektoncd/cli/releases/download/${_latest}/${_tar}" -o "/tmp/${_tar}"
            tar -xzf "/tmp/${_tar}" -C "$_ST_BIN" tkn
        fi
    fi
}

function sc_update() {
    case ${_ARG_SUB_COMMAND} in
    helm)
        sc_update_helm
        ;;
    crd*)
        sc_update_crds
        ;;
    kubernetes)
        sc_update_kubernetes
        ;;
    kustomize)
        sc_update_kustomize
        ;;
    tileserver)
        sc_update_tileserver
        ;;
    kafka)
        sc_update_kafka
        ;;
    nginx)
        sc_update_nginx
        ;;
    img)
        sc_update_image "$(sc_args_to_pattern "${_ARG_LEFTOVERS[*]:1}")"
        ;;
    mvn)
        sc_update_maven
        ;;
    yarn)
        sc_update_yarn
        ;;
    tiles)
        sc_update_tiles
        ;;
    tools)
        sc_update_tools "${_ARG_LEFTOVERS[*]:1}"
        ;;
    "")
        sc_heading 1 helm
        sc_update_helm
        sc_heading 1 crds
        sc_update_crds
        sc_heading 1 kubernetes
        sc_update_kubernetes
        sc_heading 1 kustomize
        sc_update_kustomize
        sc_heading 1 tileserver
        sc_update_tileserver
        sc_heading 1 kafka
        sc_update_kafka
        sc_heading 1 nginx
        sc_update_nginx
        sc_heading 1 images
        sc_update_image
        sc_heading 1 maven
        sc_update_maven
        sc_heading 1 yarn
        sc_update_yarn
        if [[ -n "$_ARG_ALL" ]]; then
            sc_heading 1 tiles
            sc_update_tiles
            sc_heading 1 tools
            sc_update_tools
        fi
        ;;
    *)
        echo "Unknown component '${_ARG_SUB_COMMAND}'. Enter sc update --help for available components!"
        ;;
    esac
}

