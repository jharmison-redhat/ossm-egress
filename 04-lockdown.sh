#!/bin/bash
cd "$(dirname "$(realpath "$0")")"
source common.sh

oc apply -f 04-lockdown.yml

sleep 1

update_deployments

check_connections
