#!/usr/bin/env bash

rm -rf "${ASSETS_DIR}"
mkdir -p "${ASSETS_DIR}"
pushd "${ASSETS_DIR}" >/dev/null

########################################################################################################################
# CONFIG
########################################################################################################################
cp -v "${CONFIG_TEMPLATE}" "${ASSETS_DIR}"

# Removes double quotes from keys and numeric values. Alphanumeric values get single quoted and empty lines removed.
echo "${CONTROL_PLANE}${COMPUTE}" |
    sed -E -e 's/"([^"]+)":/\1:/' -e 's/(replicas: )"([[:digit:]]+)"/\1\2/' -e '/^$/d' |
    tr '"' "'" >>install-config.yaml
# Adds the missing platform key. TODO add to terraform
if [[ "$COMPUTE_NODES_ENABLED" == "false" ]]; then
   echo "  platform: {}" >>install-config.yaml
fi

# Sets missing values define in terraform variables.
sed -Ei -e "s/CLUSTER_NAME/${CLUSTER_NAME}/" -e "s/BASE_DOMAIN/${BASE_DOMAIN}/" install-config.yaml

# Sets missing values defined in environment variables.
# https://console.redhat.com/openshift/install/pull-secret for full functionality.
if [[ -z "$_ST_TERRA_PULL_SECRET" ]]; then
    _ST_TERRA_PULL_SECRET='{"auths":{"fake":{"auth":"aWQ6cGFzcwo="}}}'
fi
echo "pullSecret: '${_ST_TERRA_PULL_SECRET}'" >>install-config.yaml
echo "sshKey: '${_ST_TERRA_SSH_KEY}'" >>install-config.yaml

# Config backup.
cp -v install-config.yaml install-config.bak.yaml
########################################################################################################################
# MANIFESTS
########################################################################################################################
openshift-install create manifests
if [[ "$COMPUTE_NODES_ENABLED" == "true" ]]; then
    # Avoids that application workloads run on control plane nodes.
    sed -Ei 's/(mastersSchedulable.*)true/\1false/' manifests/cluster-scheduler-02-config.yml
fi
########################################################################################################################
# IGNITION
########################################################################################################################
openshift-install create ignition-configs
exo storage mb "${EXOSCALE_SOS}" --zone "${EXOSCALE_ZONE}"
exo storage upload bootstrap.ign "${EXOSCALE_SOS}"
exo storage presign "${EXOSCALE_SOS}/bootstrap.ign" --expires 24h | tee bootstrap.src

echo -n "{\"ignition\":{\"config\":{\"replace\":{\"source\":\"$(cat bootstrap.src)\"}},\"version\":\"3.2.0\"}}" \
    >bootstrap.remote.ign

head ./*.ign

popd >/dev/null
