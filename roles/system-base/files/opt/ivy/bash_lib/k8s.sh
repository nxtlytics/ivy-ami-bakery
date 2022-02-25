#!/bin/echo "This is a library, please source it from another script"

##
## k8s.sh
## Kubernetes-specific modules for Ivy
##
## Use this script by sourcing the parent `bash_functions.sh` script.
##


# Prevent direct sourcing of this module
if [[ -z "${IVY}" ]]; then
    echo "WARNING: Script '$(basename ${BASH_SOURCE})' was incorrectly sourced. Please do not source it directly."
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

  local CRT_SERIAL="$(date '+%s')"

  local CSR_OUT="$(mktemp -t csr_out.XXX)"

  local KEY_OUT="${CONFIG_PATH}/${CERT_NAME}.key"
  local CRT_OUT="${CONFIG_PATH}/${CERT_NAME}.crt"

  # make a csr
  if [[ "${USAGE}" = "server" ]]; then
    local CSR_CONFIG="$(mktemp -t csr_config.XXX)"
    cat <<EOT > ${CSR_CONFIG}
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
      -keyout ${KEY_OUT} \
      -config ${CSR_CONFIG} \
      -out ${CSR_OUT}

    local EXT="-extfile ${CSR_CONFIG}"
  else
    # create csr using inline subject
    openssl req \
      -new \
      -batch \
      -newkey rsa:2048 \
      -nodes \
      -sha256 \
      -keyout ${KEY_OUT} \
      -subj "/O=${GROUP_NAME}/CN=${USER_NAME}" \
      -out ${CSR_OUT}

    local EXT=""
  fi

  # issue it against the CA for 5 years validity
  openssl x509 \
    -req \
    -days 1825 \
    -sha256 \
    -CA ${CA_CRT} \
    -CAkey ${CA_KEY} \
    -set_serial ${CRT_SERIAL} \
    -extensions v3_req \
    ${EXT} \
    -in ${CSR_OUT} \
    -out ${CRT_OUT}

  rm -f $CSR_CONFIG $CSR_OUT
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

function check_systemctl_status() {
  local UNIT="${1}"
  local STATUS="${2:-running}"
  local SYSTEMCTL_OUTPUT VALID_STATUS
  SYSTEMCTL_OUTPUT="$(systemctl status "${UNIT}")"
  VALID_STATUS="Active: active (${STATUS})"
  if ! grep -q "${VALID_STATUS}" <<<"${SYSTEMCTL_OUTPUT}"; then
    echo "${UNIT} status is NOT: ${VALID_STATUS}"
    return 1
  fi
  echo "${SYSTEMCTL_OUTPUT}"
}

function k8s_controller_checks() {
  local EXPLAIN="${1:-yes}"
  local ASK="${2}"
  echo -e "\e[31m =============================================\e[0m"
  echo -e "\e[31m e2d status should be running without errors  \e[0m"
  echo -e "\e[31m =============================================\e[0m"
  check_systemctl_status 'e2d' 'running'

  e="e2d is a command-line tool for deploying and managing etcd clusters, both in the cloud or on
bare-metal. It also includes e2db, an ORM-like abstraction for working with etcd."
  explain "${EXPLAIN}" "${e}"
  ask_to_continue "${ASK}"

  echo -e "\e[31m ==========================\e[0m"
  echo -e "\e[31m Confirm you have 3 members\e[0m"
  echo -e "\e[31m ==========================\e[0m"
  /opt/ivy/etcdctl.sh -w table member list
  ask_to_continue "${ASK}"

  echo -e "\e[31m ================================== \e[0m"
  echo -e "\e[31m Confirm 3 etcd members are healthy \e[0m"
  echo -e "\e[31m ================================== \e[0m"
  /opt/ivy/etcdctl.sh -w table endpoint health
  ask_to_continue "${ASK}"

  echo -e "\e[31m ========================= \e[0m"
  echo -e "\e[31m Confirm there is 1 leader \e[0m"
  echo -e "\e[31m ========================= \e[0m"
  /opt/ivy/etcdctl.sh -w table endpoint status
  ask_to_continue "${ASK}"

  echo -e "\e[31m ========================= \e[0m"
  echo -e "\e[31m kube-apiserver is running \e[0m"
  echo -e "\e[31m ========================= \e[0m"
  check_systemctl_status 'kube-apiserver' 'running'
  ask_to_continue "${ASK}"

  echo -e "\e[31m ===================================== \e[0m"
  echo -e "\e[31m cloud-lifecycle-controller is running \e[0m"
  echo -e "\e[31m ===================================== \e[0m"
  check_systemctl_status 'cloud-lifecycle-controller' 'running'
  ask_to_continue "${ASK}"
}

function k8s_checks() {
  local EXPLAIN="${1:-yes}"
  local ASK="${2}"
  echo -e "\e[31m ============================================== \e[0m"
  echo -e "\e[31m Confirm controller/agent is recognized as such \e[0m"
  echo -e "\e[31m ============================================== \e[0m"
  kubectl --kubeconfig /etc/kubernetes/kubelet/kubeconfig.yaml get nodes
  ask_to_continue "${ASK}"

  echo -e "\e[31m ====================================== \e[0m"
  echo -e "\e[31m Confirm csr(s) are Issued and Approved \e[0m"
  echo -e "\e[31m ====================================== \e[0m"
  kubectl --kubeconfig /etc/kubernetes/kubelet/kubeconfig.yaml get csr
  ask_to_continue "${ASK}"

  echo -e "\e[31m ============================================ \e[0m"
  echo -e "\e[31m Confirm datadog-agent is configured properly \e[0m"
  echo -e "\e[31m ============================================ \e[0m"
  datadog-agent status
  ask_to_continue "${ASK}"

  echo -e "\e[31m ===================================================== \e[0m"
  echo -e "\e[31m Confirm aws-vpc-cni-hairpinning exited without errors \e[0m"
  echo -e "\e[31m ===================================================== \e[0m"
  check_systemctl_status 'aws-vpc-cni-hairpinning' 'exited'
  ask_to_continue "${ASK}"

  echo -e "\e[31m =============================================================== \e[0m"
  echo -e "\e[31m Confirm line: 'NXTLYTICS, hairpin all incoming' is listed below \e[0m"
  echo -e "\e[31m =============================================================== \e[0m"
  iptables -t mangle --numeric --list --verbose
  e="See https://en.wikipedia.org/wiki/Hairpinning
and https://github.com/aws/amazon-vpc-cni-k8s/blob/master/docs/cni-proposal.md#solution-components"
  explain "${EXPLAIN}" "${e}"
}
