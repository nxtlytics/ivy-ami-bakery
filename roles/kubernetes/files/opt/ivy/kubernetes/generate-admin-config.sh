#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

CLUSTER_NAME="${1:-ivynetes}"
CERTIFICATE_AUTHORITY_LOCATION="${2:-/var/lib/kubernetes/ca.pem}"
EMBED_CERTS="${3:-true}"
API_SERVER_ENDPOINT="${4:-https://127.0.0.1:6443}"
ADMIN_CERTIFICATE_LOCATION="${5:-/var/lib/kubernetes/admin.pem}"
ADMIN_KEY_LOCATION="${6:-/var/lib/kubernetes/admin-key.pem}"

kubectl config set-cluster "${CLUSTER_NAME}" \
  --certificate-authority="${CERTIFICATE_AUTHORITY_LOCATION}" \
  --embed-certs="${EMBED_CERTS}" \
  --server="${API_SERVER_ENDPOINT}" \
  --kubeconfig=admin.kubeconfig

kubectl config set-credentials admin \
  --client-certificate="${ADMIN_CERTIFICATE_LOCATION}" \
  --client-key="${ADMIN_KEY_LOCATION}" \
  --embed-certs="${EMBED_CERTS}" \
  --kubeconfig=admin.kubeconfig

kubectl config set-context default \
  --cluster="${CLUSTER_NAME}" \
  --user=admin \
  --kubeconfig=admin.kubeconfig

kubectl config use-context default --kubeconfig=admin.kubeconfig
