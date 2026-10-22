#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

: "${EXOSCALE_ZONE:?}" "${TEMPLATE_NAME:?}" "${TEMPLATE_DISK_SIZE:?}" "${MANAGE_TEMPLATE:?}" "${RELEASE:?}"
: "${IMAGE_URL:?}" "${IMAGE_SHA256:?}" "${DISK_SHA256:?}" "${WORK_DIR:?}" "${ID_FILE:?}"
: "${EXOSCALE_API_KEY:?}" "${EXOSCALE_API_SECRET:?}"

_BUCKET="${TEMPLATE_BUCKET:-${TEMPLATE_NAME}}"
_OBJECT="${TEMPLATE_NAME}.qcow2"
_ARCHIVE="${WORK_DIR}/${TEMPLATE_NAME}.qcow2.gz"
_DISK="${WORK_DIR}/${_OBJECT}"
_STAMP="${_DISK}.stamp"
_PLATFORM_ID="exoscale"

mkdir -p "$WORK_DIR"

function template_id() {
    exo compute instance-template show \
        --zone "$EXOSCALE_ZONE" \
        --visibility private \
        --output-format json \
        "$TEMPLATE_NAME" 2>/dev/null | jq -er '.id'
}
########################################################################################################################
# Short circuit
########################################################################################################################
if _ID="$(template_id)"; then
    echo "Template ${TEMPLATE_NAME} already registered in ${EXOSCALE_ZONE} (${_ID})."
    echo -n "$_ID" >"$ID_FILE"
    exit 0
fi

if [[ "$MANAGE_TEMPLATE" != "true" ]]; then
    echo "Template ${TEMPLATE_NAME} not found in ${EXOSCALE_ZONE} and manage_template is false."
    exit 1
fi

echo "Registering RHCOS ${RELEASE} as ${TEMPLATE_NAME} in ${EXOSCALE_ZONE}."
########################################################################################################################
# Platform
########################################################################################################################
# https://gist.github.com/pierre-emmanuelJ/c546777ce5e9e70ecf2ac951e5628e7d
function patch_platform_id() {
    local _dev _entries _entry _patched=()

    _dev="$(guestfish --ro -a "$_DISK" run : findfs-label boot)"
    _entries="${WORK_DIR}/loader-entries"

    rm -rf "$_entries"
    mkdir -p "$_entries"

    guestfish --ro -a "$_DISK" -m "$_dev" glob copy-out '/loader/entries/*.conf' "$_entries"

    compgen -G "${_entries}/*.conf" >/dev/null || {
        echo "No boot loader entries in the image. Cannot set ignition.platform.id" >&2
        exit 1
    }

    for _entry in "$_entries"/*.conf; do
        sed -i -E "s/ignition\.platform\.id=[^[:space:]]+/ignition.platform.id=${_PLATFORM_ID}/" "$_entry"

        grep -q "ignition\.platform\.id=${_PLATFORM_ID}" "$_entry" || {
            echo "No ignition.platform.id on the kernel command line of ${_entry##*/}" >&2
            exit 1
        }
        _patched+=("${_entry##*/}")
    done

    guestfish --rw -a "$_DISK" -m "$_dev" copy-in "$_entries"/*.conf /loader/entries

    echo "Set ignition.platform.id=${_PLATFORM_ID} in ${_patched[*]}"
    rm -rf "$_entries"
}
########################################################################################################################
# Download
########################################################################################################################
if [[ ! -f "$_DISK" || "$(cat "$_STAMP" 2>/dev/null)" != "$DISK_SHA256" ]]; then
    rm -f "$_STAMP"

    if [[ ! -f "$_ARCHIVE" ]] || ! echo "${IMAGE_SHA256}  ${_ARCHIVE}" | sha256sum --check --status; then
        echo "Downloading ${IMAGE_URL}"
        curl -fL --retry 3 --retry-delay 5 -o "$_ARCHIVE" "$IMAGE_URL"
        echo "${IMAGE_SHA256}  ${_ARCHIVE}" | sha256sum --check
    fi
    echo "Decompressing ${_ARCHIVE}"
    gzip -dc "$_ARCHIVE" >"$_DISK"
    echo "${DISK_SHA256}  ${_DISK}" | sha256sum --check

    patch_platform_id
    echo -n "$DISK_SHA256" >"$_STAMP"
fi
########################################################################################################################
# Prepare
########################################################################################################################
qemu-img resize "$_DISK" "${TEMPLATE_DISK_SIZE}G"
qemu-img info "$_DISK"

_MD5="$(md5sum "$_DISK" | cut -d' ' -f1)"
echo "MD5: ${_MD5}"
########################################################################################################################
# Stage
########################################################################################################################
exo storage mb --zone "$EXOSCALE_ZONE" "sos://${_BUCKET}" 2>/dev/null || true
exo storage upload --acl public-read "$_DISK" "sos://${_BUCKET}/${_OBJECT}"

_URL="https://sos-${EXOSCALE_ZONE}.exo.io/${_BUCKET}/${_OBJECT}"
########################################################################################################################
# Register
########################################################################################################################
exo compute instance-template register \
    --zone "$EXOSCALE_ZONE" \
    --username core \
    --disable-password \
    --boot-mode uefi \
    --version "$RELEASE" \
    --build "$(date +%Y%m%d-%H%M%S)" \
    --description "Red Hat CoreOS ${RELEASE}" \
    --maintainer "openshift-tofu" \
    "$TEMPLATE_NAME" \
    "$_URL" \
    "$_MD5"

_ID="$(template_id)" || {
    echo "Template ${TEMPLATE_NAME} was registered but cannot be looked up." >&2
    exit 1
}
echo -n "$_ID" >"$ID_FILE"
echo "Registered ${TEMPLATE_NAME} (${_ID})."
########################################################################################################################
# Cleanup
########################################################################################################################
rm -f "$_ARCHIVE" "$_DISK" "$_STAMP"
echo "Staging bucket sos://${_BUCKET} left in place. destroy.sh removes it."
