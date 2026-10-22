#!/usr/bin/env bash
set -o errexit
set -o pipefail

# Emits the RHCOS openstack artifact that matches the local openshift-install.
openshift-install coreos print-stream-json |
    jq -c '.architectures.x86_64.artifacts.openstack as $stream | {
        release:             $stream.release,
        url:                 $stream.formats["qcow2.gz"].disk.location,
        sha256:              $stream.formats["qcow2.gz"].disk.sha256,
        uncompressed_sha256: $stream.formats["qcow2.gz"].disk["uncompressed-sha256"]
    }'
