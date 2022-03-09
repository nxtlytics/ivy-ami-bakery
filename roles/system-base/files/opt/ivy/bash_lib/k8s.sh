#!/usr/bin/env bash

##
## k8s.sh
## Kubernetes-specific modules for Ivy
##
## Use this script by sourcing the parent `bash_functions.sh` script.
##


# Prevent direct sourcing of this module
if [[ ${#BASH_SOURCE[@]} -lt 2 ]]; then
  echo "WARNING: Script '$(basename "${BASH_SOURCE[0]}")' was incorrectly sourced. Please do not source it directly."
  return 255
fi

function generate_pki() {
  # Issue a TLS certificate against a local CA
  # Use:
  # generate_pki "/etc/kubernetes" "pki/apiserver" "kubernetes" "thunder:$(get_availability_zone)" "server" "pki/ca.crt" "pki/ca.key" "${APISERVER_SANS}" "${APISERVER_IPS}"
  # or
  # generate_pki "/etc/kubernetes" "pki/aws-iam-authenticator" "aws-iam-authenticator-$(get_availability_zone)" "system:masters" "client" "pki/ca.crt" "pki/ca.key"
  local CONFIG_PATH="${1}"; shift
  local CERT_NAME="${1}"; shift
  local USER_NAME="${1}"; shift
  local GROUP_NAME="${1}"; shift
  local USAGE="${1}"; shift
  local CA_CRT="${CONFIG_PATH}/${1}"; shift
  local CA_KEY="${CONFIG_PATH}/${1}"; shift
  local DNS_SANS="${1}"; shift
  local IP_SANS="${1}"; shift

  local CRT_SERIAL CSR_OUT CSR_CONFIG EXT
  CRT_SERIAL="$(date '+%s')"
  CSR_OUT="$(mktemp -t csr_out.XXX)"


  local KEY_OUT="${CONFIG_PATH}/${CERT_NAME}.key"
  local CRT_OUT="${CONFIG_PATH}/${CERT_NAME}.crt"

  # make a csr
  if [[ "${USAGE}" = "server" ]]; then
    CSR_CONFIG="$(mktemp -t csr_config.XXX)"
    cat <<EOT > "${CSR_CONFIG}"
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
default_bits = 2048
prompt = no

[req_distinguished_name]
organizationName = ${GROUP_NAME}
commonName = ${USER_NAME}

[v3_req]
basicConstraints=CA:FALSE
keyUsage=keyEncipherment,dataEncipherment,digitalSignature
extendedKeyUsage=clientAuth,serverAuth
subjectAltName = @alt_names

[alt_names]
$(
  LINE=1
  IFS=$'\n'
  for dns_name in ${DNS_SANS}; do
    echo "DNS.${LINE} = ${dns_name}"
    LINE=$((LINE + 1))
  done
)
$(
  LINE=1
  IFS=$'\n'
  for ip_addr in ${IP_SANS}; do
    echo "IP.${LINE} = ${ip_addr}"
    LINE=$((LINE + 1))
  done
)
EOT
    # create csr using config file
    openssl req \
      -new \
      -batch \
      -newkey rsa:2048 \
      -nodes \
      -sha256 \
      -keyout "${KEY_OUT}" \
      -config "${CSR_CONFIG}" \
      -out "${CSR_OUT}"

    EXT="-extfile ${CSR_CONFIG}"
  else
    # create csr using inline subject
    openssl req \
      -new \
      -batch \
      -newkey rsa:2048 \
      -nodes \
      -sha256 \
      -keyout "${KEY_OUT}" \
      -subj "/O=${GROUP_NAME}/CN=${USER_NAME}" \
      -out "${CSR_OUT}"
  fi

  # issue it against the CA for 5 years validity
  # shellcheck disable=SC2086
  openssl x509 \
    -req \
    -days 1825 \
    -sha256 \
    -CA "${CA_CRT}" \
    -CAkey "${CA_KEY}" \
    -set_serial "${CRT_SERIAL}" \
    -extensions v3_req \
    ${EXT} \
    -in "${CSR_OUT}" \
    -out "${CRT_OUT}"

  rm -f "${CSR_CONFIG}" "${CSR_OUT}"
}

function generate_component_kubeconfig() {
  # Generate a kubeconfig file
  # Use:
  # generate_component_kubeconfig /etc/kubernetes aws-iam-authenticator/kubeconfig.yaml pki/aws-iam-authenticator.crt pki/aws-iam-authenticator.key ${ENDPOINT_NAME} "aws-iam-authenticator-$(get_availability_zone)"
  local CONFIG_PATH="${1}"; shift
  local FILENAME="${1}"; shift
  local CERT_PATH="${1}"; shift
  local CERT_KEY_PATH="${1}"; shift
  local ENDPOINT="${1}"; shift
  local USER_NAME="${1}"; shift

  cat <<EOT > "${CONFIG_PATH}/${FILENAME}"
kind: Config
preferences: {}
apiVersion: v1
clusters:
- cluster:
    server: https://${ENDPOINT}:443
    certificate-authority: ${CONFIG_PATH}/pki/ca.crt
  name: default
contexts:
- context:
    cluster: default
    user: ${USER_NAME}
  name: default
current-context: default
users:
- name: ${USER_NAME}
  user:
    client-certificate: ${CONFIG_PATH}/${CERT_PATH}
    client-key: ${CONFIG_PATH}/${CERT_KEY_PATH}
EOT
}

function get_k8s_node_name() {
  local INSTANCE_ID NODE_LABEL JSON_PATH
  INSTANCE_ID="$(get_instance_id)"
  JSON_PATH='{.items[0].metadata.name}'
  NODE_LABEL="node.kubernetes.io/instance-id=${INSTANCE_ID}"
  kubectl get nodes \
    --kubeconfig /etc/kubernetes/kubelet/kubeconfig.yaml \
    -l "${NODE_LABEL}" -o jsonpath="${JSON_PATH}" 2>/dev/null
}

function get_k8s_node_status() {
  local INSTANCE_ID NODE_LABEL
  INSTANCE_ID="$(get_instance_id)"
  NODE_LABEL="node.kubernetes.io/instance-id=${INSTANCE_ID}"
  kubectl get nodes \
    --kubeconfig /etc/kubernetes/kubelet/kubeconfig.yaml \
    -l "${NODE_LABEL}" | grep -v NAME | awk '{ print $2 }'
}

function check_dd_features() {
  local FEATURES_AS_STRING="${1}"
  declare -a FEATURES
  # TODO: Make these toggleable
  FEATURES=(
    'feature_apm_enabled: true'
    'feature_logs_enabled: true'
    'feature_networks_enabled: true'
  )
  for feature in "${FEATURES[@]}"; do
    if ! grep -q "${feature}" <<<"${FEATURES_AS_STRING}"; then
      warn "feature is not configured properly, should be ${feature}"
      return 1
    fi
  done
}

function k8s_controller_checks() {
  local EXPLAIN="${1:-yes}"
  local ASK="${2}"
  local e endpoint health errors leader
  declare -a ETCD_MEMBERS ETCD_LEADERS

  echo -e "\e[31m =============================================\e[0m"
  echo -e "\e[31m e2d status should be running without errors  \e[0m"
  echo -e "\e[31m =============================================\e[0m"
  check_systemctl_status 'e2d'

  e="e2d is a command-line tool for deploying and managing etcd clusters, both in the cloud or on
bare-metal. It also includes e2db, an ORM-like abstraction for working with etcd."
  explain "${EXPLAIN}" "${e}"
  ask_to_continue "${ASK}"

  echo -e "\e[31m ==========================\e[0m"
  echo -e "\e[31m Confirm you have 3 members\e[0m"
  echo -e "\e[31m ==========================\e[0m"
  #/opt/ivy/etcdctl.sh -w table member list
  ETCD_MEMBERS=()
  mapfile -t ETCD_MEMBERS < <(/opt/ivy/etcdctl.sh member list)
  if [[ ${#ETCD_MEMBERS[@]} -ne 3 ]]; then
    warn "You only have ${#ETCD_MEMBERS[@]} etcd members but you should have 3"
    return 1
  fi
  ask_to_continue "${ASK}"

  echo -e "\e[31m ================================== \e[0m"
  echo -e "\e[31m Confirm 3 etcd members are healthy \e[0m"
  echo -e "\e[31m ================================== \e[0m"
  #/opt/ivy/etcdctl.sh -w table endpoint health
  while IFS= read -r line; do
    health="$(cut -d '|' -f3 <(echo "${line}")|xargs)"
    if [[ "${health}" != 'true' ]]; then
      endpoint="$(cut -d '|' -f2 <(echo "${line}")|xargs)"
      errors="$(cut -d '|' -f5 <(echo "${line}"))"
      warn "endpoint ${endpoint} is not healthy and has errors: ${errors}"
      return 1
    fi
  done < <(grep 'https' <(/opt/ivy/etcdctl.sh -w table endpoint health))
  ask_to_continue "${ASK}"

  echo -e "\e[31m ========================= \e[0m"
  echo -e "\e[31m Confirm there is 1 leader \e[0m"
  echo -e "\e[31m ========================= \e[0m"
  #/opt/ivy/etcdctl.sh -w table endpoint status
  ETCD_LEADERS=()
  while IFS= read -r line; do
    leader="$(cut -d ',' -f5 <(echo "${line}")|xargs)"
    if [[ "${leader}" == 'true' ]]; then
      endpoint="$(cut -d ',' -f1 <(echo "${line}"))"
      ETCD_LEADERS+=("${endpoint}")
    fi
  done < <(/opt/ivy/etcdctl.sh endpoint status)
  if [[ ${#ETCD_LEADERS[@]} -ne 1 ]]; then
    warn "You have ${#ETCD_LEADERS[@]} leader(s) but you should only have 1"
    return 1
  fi
  ask_to_continue "${ASK}"

  echo -e "\e[31m ================================= \e[0m"
  echo -e "\e[31m Confirm kube-apiserver is running \e[0m"
  echo -e "\e[31m ================================= \e[0m"
  check_systemctl_status 'kube-apiserver'
  ask_to_continue "${ASK}"

  echo -e "\e[31m ================================= \e[0m"
  echo -e "\e[31m Confirm kube-scheduler is running \e[0m"
  echo -e "\e[31m ================================= \e[0m"
  check_systemctl_status 'kube-scheduler'
  ask_to_continue "${ASK}"

  echo -e "\e[31m ========================================== \e[0m"
  echo -e "\e[31m Confirm kube-controller-manager is running \e[0m"
  echo -e "\e[31m ========================================== \e[0m"
  check_systemctl_status 'kube-controller-manager'
  ask_to_continue "${ASK}"

  echo -e "\e[31m ============================================= \e[0m"
  echo -e "\e[31m Confirm cloud-lifecycle-controller is running \e[0m"
  echo -e "\e[31m ============================================= \e[0m"
  check_systemctl_status 'cloud-lifecycle-controller'
  ask_to_continue "${ASK}"
}

function k8s_checks() {
  local EXPLAIN="${1:-yes}"
  local ASK="${2}"
  local NODE_NAME NODE_STATUS DD_STATUS DD_FEATURES DD_FAILED_CHECKS
  echo -e "\e[31m ================================= \e[0m"
  echo -e "\e[31m Confirm controller/agent is Ready \e[0m"
  echo -e "\e[31m ================================= \e[0m"
  if NODE_NAME="$(get_k8s_node_name)"; then
    echo -e "\e[31m Instance ID $(get_instance_id) is k8s node ${NODE_NAME} \e[0m"
  else
    warn "Instance ID $(get_instance_id) is not part of k8s cluster"
    return 1
  fi
  NODE_STATUS="$(get_k8s_node_status)"
  if [[ "${NODE_STATUS}" != 'Ready' ]]; then
    warn "k8s node ${NODE_NAME} is NOT ready"
    return 1
  fi

  echo -e "\e[31m ============================================ \e[0m"
  echo -e "\e[31m Confirm datadog-agent is configured properly \e[0m"
  echo -e "\e[31m ============================================ \e[0m"
  check_systemctl_status 'datadog-agent'
  if ! timeout 2 datadog-agent status &> /dev/null; then
    warn "datadog-agent has not finished gathering info for the first time"
    return 1
  fi
  if ! grep -q 'Agent health: PASS' <(datadog-agent health); then
    warn 'datadog-agent is NOT healthy'
    return 1
  fi
  DD_STATUS="$(datadog-agent status)"
  DD_FEATURES="$(grep 'feature_' <<<"${DD_STATUS}")"
  check_dd_features "${DD_FEATURES}"
  DD_FAILED_CHECKS="$(grep -A2 'Failed checks' <<<"${DD_STATUS}")"
  if ! grep -q 'no checks' <<<"${DD_FAILED_CHECKS}"; then
    warn 'There are datadog checks that failed'
    return 1
  fi
  ask_to_continue "${ASK}"

  if grep -q 'aws' /etc/cni/net.d/*; then
    echo -e "\e[31m ===================================================== \e[0m"
    echo -e "\e[31m Confirm aws-vpc-cni-hairpinning exited without errors \e[0m"
    echo -e "\e[31m ===================================================== \e[0m"
    check_systemctl_status 'aws-vpc-cni-hairpinning'
    ask_to_continue "${ASK}"

    echo -e "\e[31m =============================================================== \e[0m"
    echo -e "\e[31m Confirm line: 'NXTLYTICS, hairpin all incoming' is listed below \e[0m"
    echo -e "\e[31m =============================================================== \e[0m"
    grep -q 'NXTLYTICS, hairpin all incoming' <(iptables -t mangle --numeric --list --verbose)
    e="See https://en.wikipedia.org/wiki/Hairpinning
and https://github.com/aws/amazon-vpc-cni-k8s/blob/master/docs/cni-proposal.md#solution-components"
    explain "${EXPLAIN}" "${e}"
  fi
}
