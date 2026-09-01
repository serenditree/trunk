#!/usr/bin/env bash
########################################################################################################################
# ROOT-SEED
########################################################################################################################
_SERVICE=root-seed
_ORDINAL=9

_IMAGE=serenditree/root-seed
_VERSION=${_ST_STAGE//dev/latest}
_TAG=$_VERSION
_CONTAINER=$_SERVICE
_VOLUME_SRC=root-seed
_VOLUME_DST=/usr/share/opensearch/data
_EXPOSE=9200/tcp

if [[ " $* " =~ " info " ]] || [[ -n "$_ARG_DRYRUN" ]]; then
    echo "${_ORDINAL} ${_SERVICE} ${_IMAGE} ${_TAG} $(realpath $0)"
fi
########################################################################################################################
# BUILD
########################################################################################################################
if [[ " $* " =~ " build " ]]; then
    sc_heading 1 "Building ${_IMAGE}:${_TAG}"
    [[ -n "$_ARG_DRYRUN" ]] && exit 0
    _CONTAINER_REF=$(buildah from --pull $_ST_FROM_ROOT_SEED)

    buildah run $_CONTAINER_REF -- /usr/share/opensearch/bin/opensearch-plugin install --batch repository-s3

    buildah config \
        --volume $_VOLUME_DST \
        --port $_EXPOSE \
        $_CONTAINER_REF

    # sc_env_rm $_CONTAINER_REF
    sc_label_rm $_ST_FROM_ROOT_SEED $_CONTAINER_REF
    sc_image_config_commit "$_SERVICE" "$_IMAGE" "$_VERSION" "$_TAG" "$_ORDINAL" "$_CONTAINER_REF"
########################################################################################################################
# UP
########################################################################################################################
elif [[ " $* " =~ " up " ]] && [[ -z "$_ST_CONTEXT_CLUSTER" ]]; then
    sc_heading 1 "Starting ${_SERVICE}:${_TAG}"
    sc_container_rm ${_CONTAINER}

    # shellcheck disable=SC2046
    podman run \
        --log-level $_ST_LOG_LEVEL \
        --pod $_ST_POD \
        --name ${_CONTAINER} \
        --env-file ./plot.env \
        --env "S3_ACCESS_KEY=$(pass serenditree/iam/backup-seed.access)" \
        --env "S3_SECRET_KEY=$(pass serenditree/iam/backup-seed.secret)" \
        --env "s3.client.default.endpoint=https://sos-${_ST_ZONE_STORAGE_1}.exo.io" \
        --env "s3.client.default.region=${_ST_ZONE_STORAGE_1}" \
        --volume ./rc/init.sh:/docker-entrypoint-initdb.d/init.sh:Z \
        $([[ -z "$_ARG_INTEGRATION" ]] && echo --volume ${_VOLUME_SRC}:${_VOLUME_DST}:Z) \
        --health-cmd "curl http://localhost:9200/_cluster/health?wait_for_status=yellow&timeout=1s" \
        --health-interval 3s \
        --health-retries 1 \
        --ulimit nproc=$(ulimit -u) \
        --ulimit nofile=$(ulimit -n) \
        --ulimit memlock=-1 \
        --detach \
        ${_IMAGE}:${_TAG}

    sc_container_rm ${_CONTAINER}-dash
    podman run \
        --log-level $_ST_LOG_LEVEL \
        --pod $_ST_POD \
        --name ${_CONTAINER}-dash \
        --env-file ./plot.env \
        --label serenditree.io/service=dashboards \
        --health-cmd "curl http://localhost:5601/api/status" \
        --health-interval 3s \
        --health-retries 1 \
        --detach \
        "$_ST_FROM_ROOT_SEED_DASH"
fi
