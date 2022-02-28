#!/bin/bash

# read common kubernetes pki options
# shellcheck disable=SC1091
source /etc/sysconfig/kube-pki
# read e2d pki options
# shellcheck disable=SC1091
source /etc/sysconfig/e2d

# export these options for etcdctl to use
export ETCDCTL_CACERT=${ETCD_CA}
export ETCDCTL_CERT=${E2D_SERVER_CERT}
export ETCDCTL_KEY=${E2D_SERVER_KEY}

# retrieve a list of members and export them
ETCDCTL_ENDPOINTS=$(/usr/bin/etcdctl member list -w json | jq -r '.members | map(.clientURLs[0]) | join(",")')
export ETCDCTL_ENDPOINTS

# run the command
/usr/bin/etcdctl "$@"
