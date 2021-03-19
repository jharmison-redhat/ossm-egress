#!/bin/bash
cd "$(dirname "$(realpath "$0")")"
source common.sh

oc project bookinfo-prod
sed 's/subdomain/bookinfo-prod/' 02-bookinfo.yml | oc apply -f -
finish_deployments

oc project bookinfo
sed 's/subdomain/bookinfo/' 02-bookinfo.yml | oc apply -f -
finish_deployments

check_connections
