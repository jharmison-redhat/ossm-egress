#!/bin/bash
cd "$(dirname "$(realpath "$0")")"
source common.sh

wait_on 5 600 "CRC to finish rebooting" 'crc status | grep "^OpenShift" | grep -qF Running'
