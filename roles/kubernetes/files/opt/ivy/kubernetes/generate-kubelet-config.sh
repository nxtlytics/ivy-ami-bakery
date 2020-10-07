#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Note: It may be a better idea to create 1 key and certificate for all kubelets

CLUSTER_NAME="${1:-ivynetes}"
CERTIFICATE_AUTHORITY_LOCATION="${2:-/var/lib/kubernetes/ca.pem}"
EMBED_CERTS="${3:-true}"
API_SERVER_ENDPOINT="${4}" # Load balancer endpoint
KUBELET_CERTIFICATE_LOCATION="${5:-/var/lib/kubernetes/kubelet.pem}"
KUBELET_KEY_LOCATION="${6:-/var/lib/kubernetes/kubelet-key.pem}"
KUBELET_ID="${7:-kubelet}"

kubectl config set-cluster "${CLUSTER_NAME}" \
  --certificate-authority="${CERTIFICATE_AUTHORITY_LOCATION}" \
  --embed-certs="${EMBED_CERTS}" \
  --server="${API_SERVER_ENDPOINT}" \
  --kubeconfig=kubelet.kubeconfig

kubectl config set-credentials "system:node:${KUBELET_ID}" \
  --client-certificate="${KUBELET_CERTIFICATE_LOCATION}" \
  --client-key="${KUBELET_KEY_LOCATION}" \
  --embed-certs="${EMBED_CERTS}" \
  --kubeconfig=kubelet.kubeconfig

kubectl config set-context default \
  --cluster="${CLUSTER_NAME}" \
  --user="system:node:${KUBELET_ID}" \
  --kubeconfig=kubelet.kubeconfig

kubectl config use-context default --kubeconfig=kubelet.kubeconfig
