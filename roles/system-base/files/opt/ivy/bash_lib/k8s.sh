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


