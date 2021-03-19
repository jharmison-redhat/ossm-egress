#!/bin/bash
cd "$(dirname "$(realpath "$0")")"

pip install --user --upgrade crc-manager

max_cpus=$(nproc --all)
max_ram=$(( $(grep MemTotal /proc/meminfo | sed 's/[^0-9]//g') / 1024 / 1024 * 3 / 4 ))

read -p "Enter the number of vCPUs for CRC (default: $max_cpus): " CRC_CPUS
read -p "Enter the amount of RAM in GiB for CRC (default: $max_ram): " CRC_MEMORY

if [ ! -r $HOME/.crc/pull-secret.json ]; then
    mkdir -p $HOME/.crc
    while [ -z "$CRC_PULL_SECRET" ]; do
        read -sp "Enter your pull secret, retrieved from https://cloud.redhat.com/openshift/create/local : " CRC_PULL_SECRET
    done
    echo "$CRC_PULL_SECRET" > $HOME/.crc/pull-secret.json
    unset CRC_PULL_SECRET
fi

export CRC_CPUS=${CRC_CPUS:-$max_cpus}
export CRC_MEMORY=$(( ${CRC_MEMORY:-$max_ram} * 1024 ))

./crc-up

source common.sh

oc whoami

oc apply -f 00-setup.yml

wait_on 5 30 "project creation" oc project bookinfo

wait_on 5 300 "operator installation" 'oc get pod -n openshift-operators -l name=istio-operator | grep -qF "1/1"'
