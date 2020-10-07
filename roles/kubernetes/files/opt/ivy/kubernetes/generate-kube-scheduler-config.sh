#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

CLUSTER_NAME="${1:-ivynetes}"
CERTIFICATE_AUTHORITY_LOCATION="${2:-/var/lib/kubernetes/ca.pem}"
EMBED_CERTS="${3:-true}"
API_SERVER_ENDPOINT="${4:-https://127.0.0.1:6443}"
KUBE_SCHEDULER_CERTIFICATE_LOCATION="${5:-/var/lib/kubernetes/kube-scheduler.pem}"
KUBE_SCHEDULER_KEY_LOCATION="${6:-/var/lib/kubernetes/kube-scheduler-key.pem}"

kubectl config set-cluster "${CLUSTER_NAME}" \
  --certificate-authority="${CERTIFICATE_AUTHORITY_LOCATION}" \
  --embed-certs="${EMBED_CERTS}" \
  --server="${API_SERVER_ENDPOINT}" \
  --kubeconfig=kube-scheduler.kubeconfig

kubectl config set-credentials system:kube-scheduler \
  --client-certificate="${KUBE_SCHEDULER_CERTIFICATE_LOCATION}" \
  --client-key="${KUBE_SCHEDULER_KEY_LOCATION}" \
  --embed-certs="${EMBED_CERTS}" \
  --kubeconfig=kube-scheduler.kubeconfig

kubectl config set-context default \
  --cluster="${CLUSTER_NAME}" \
  --user=system:kube-scheduler \
  --kubeconfig=kube-scheduler.kubeconfig

kubectl config use-context default --kubeconfig=kube-scheduler.kubeconfig
