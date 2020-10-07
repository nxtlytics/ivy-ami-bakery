#!/usr/bin/env bash
if ! [ -r "/etc/etcd/etcdctl.env" ]; then
	echo "Unable to read the etcdctl environment file '/etc/etcd/etcdctl.env'. The file must exist, and this wrapper must be run as root."
	exit 1
fi
. "/etc/etcd/etcdctl.env"
"/opt/bin/etcdctl" "$@"
