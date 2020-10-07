#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

CLUSTER_NAME="${1:-ivynetes}"
CERTIFICATE_AUTHORITY_LOCATION="${2:-/var/lib/kubernetes/ca.pem}"
EMBED_CERTS="${3:-true}"
API_SERVER_ENDPOINT="${4}" # Load balancer endpoint
KUBE_PROXY_CERTIFICATE_LOCATION="${5:-/var/lib/kubernetes/kube-proxy.pem}"
KUBE_PROXY_KEY_LOCATION="${6:-/var/lib/kubernetes/kube-proxy-key.pem}"

kubectl config set-cluster "${CLUSTER_NAME}" \
  --certificate-authority="${CERTIFICATE_AUTHORITY_LOCATION}" \
  --embed-certs="${EMBED_CERTS}" \
  --server="${API_SERVER_ENDPOINT}" \
  --kubeconfig=kube-proxy.kubeconfig

kubectl config set-credentials system:kube-proxy \
  --client-certificate="${KUBE_PROXY_CERTIFICATE_LOCATION}" \
  --client-key="${KUBE_PROXY_KEY_LOCATION}" \
  --embed-certs="${EMBED_CERTS}" \
  --kubeconfig=kube-proxy.kubeconfig

kubectl config set-context default \
  --cluster="${CLUSTER_NAME}" \
  --user=system:kube-proxy \
  --kubeconfig=kube-proxy.kubeconfig

kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig
