#!/bin/bash
cd "$(dirname "$(realpath "$0")")"
source common.sh

oc apply -f 01-control-plane.yml

wait_on 5 600 "control plane initialization" 'oc get smcp -n istio-system | grep -qF ComponentsReady'
