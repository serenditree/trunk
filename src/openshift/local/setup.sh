#!/usr/bin/env bash
########################################################################################################################
# OPENSHIFT LOCAL
# Installs, upgrades, configures and resets CodeReady Containers (CRC).
########################################################################################################################

function sc_openshift_local_up() {
    crc start || {
        crc stop
        crc start
    }
}

function sc_openshift_local_down() {
    if crc status | grep -q Stopped; then
        echo "Nothing to shut down."
    else
        crc stop
    fi
}

# Extracts and/or copies the new or existing crc binary to ~/.local/bin.
function sc_openshift_local_prepare_setup() {
    echo "Copying archive..."
    cp -v ~/Downloads/crc-* ~/.local/bin
    echo "Removing old crc binary..."
    rm -vf crc
    echo "Extracting..."
    tar -xf crc*
    echo "Moving binary..."
    find . -type f -name crc -exec mv -v {} . \;
    if [[ -f crc ]]; then
        echo "Removing archive..."
        rm -vfr crc-*
    else
        echo "Could not find binary. Aborting..."
        exit 1
    fi
}

# Installs, upgrades or resets CodeReady Containers (CRC).
function sc_openshift_local_setup() {
    cd ~/.local/bin
    sc_openshift_local_prepare_setup

    echo "Starting setup..."
    crc setup

    echo "Removing old oc symlink..."
    rm -vf oc
    echo "Symlinking oc binary..."
    find ~/.crc -type f -name oc -exec ln -vs {} oc \;

    read -rp "Number of cpus to use [12]: " _cpus
    crc config set cpus ${_cpus:-12} >/dev/null
    crc config get cpus
    read -rp "MB of memory to use [51200]: " _memory
    crc config set memory ${_memory:-51200} >/dev/null
    crc config get memory
    read -rp "GB of disk-size to use [32]: " _disk_size
    crc config set disk-size ${_disk_size:-32} >/dev/null
    crc config get disk-size
    read -rp "Enable cluster-monitoring [true]: " _monitoring
    crc config set enable-cluster-monitoring ${_monitoring:-true} >/dev/null
    crc config get enable-cluster-monitoring
    read -rp "Set kubeadmin-password? [Y/n]: " _kubeadmin
    if [[ "${_kubeadmin}" != "n" ]]; then
        read -rp "kubeadmin-password [crc.testing]: " _kubeadmin
        crc config set kubeadmin-password ${_kubeadmin:-crc.testing} >/dev/null
        crc config get kubeadmin-password
    fi

    crc start || {
        crc stop
        crc start
    }
}

function sc_openshift_local_download() {
    local -r _download_url=https://cloud.redhat.com/openshift/install/crc/installer-provisioned
    echo "Download crc from ${_download_url} to ~/Downloads!"

    read -rp "Open download page now? [Y/n]: " _PROCEED
    if [[ "$_PROCEED" != "n" ]]; then
        echo "Opening download page..."
        xdg-open $_download_url
    fi
    unset _PROCEED

    read -rp "Download finished and ready to proceed? [Y/n]: " _PROCEED

    [[ "$_PROCEED" != "n" ]]
}

function sc_openshift_local() {
    if sc_openshift_local_download; then
        if [[ -z "${_ARG_UPGRADE}" ]]; then
            echo "Installing libvirt..."
            sudo dnf install -y libvirt
            echo "Enabling libvirtd..."
            sudo systemctl enable --now libvirtd
        fi
        if command -v crc; then
            echo "Checking cluster status..."
            if crc status | grep -iq running; then
                crc stop
            fi
            echo "Cluster stopped. Deleting old cluster..."
            crc delete
            read -rp "Do you want to cleanup? [y/N]: " _CLEANUP
            if [[ "${_CLEANUP:-y}" != "n" ]]; then
                crc cleanup
                echo "Removing cache..."
                rm -vfr ~/.crc/cache/*
            fi
        fi
        sc_openshift_local_setup
    fi
}
