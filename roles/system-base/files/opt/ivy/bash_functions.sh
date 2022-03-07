#!/usr/bin/env bash

##
## bash_functions.sh
## Common functions for scripts used across the entire Ivy stack
##
## Source this script where necessary with `source /opt/ivy/bash_functions.sh`
##


# Prevent modules from being sourced directly
# shellcheck disable=SC2034
IVY="yes"

function get_ivy_tag() {
  # Allow override of Ivy tag for custom build customers

  local TAG_FILE='/opt/ivy/tag'

  if [[ -f "${TAG_FILE}" ]]; then
    cat "${TAG_FILE}"
  else
    echo -n 'ivy'
  fi
}

function set_ivy_tag() {
  local TAG="${1}"
  local TAG_FILE='/opt/ivy/tag'
  echo "${TAG}" > "${TAG_FILE}"
}

function get_cloud() {
  # Discover the current cloud platform. Very rudimentary, could fail eventually, but since 'compute' is
  # Google's trademark word for their service, it's not likely that AWS suddenly has this value.
  local CLOUD_PROVIDER_FILE='/var/lib/cloud_provider'
  local BASE_URL='http://169.254.169.254'
  declare -a CURL_OPTS
  CURL_OPTS=('--retry' '3' '--silent' '--fail')

  if [[ -f "${CLOUD_PROVIDER_FILE}" ]]; then
    cat "${CLOUD_PROVIDER_FILE}"
    return
  fi

  if curl "${CURL_OPTS[@]}" "${BASE_URL}/" | grep -q 'computeMetadata'; then
    echo -n "google" | tee "${CLOUD_PROVIDER_FILE}"
  elif curl -H 'Metadata:true' "${CURL_OPTS[@]}" "${BASE_URL}/metadata/instance/compute?api-version=2019-06-01" || false; then
    echo -n "azure" | tee "${CLOUD_PROVIDER_FILE}"
  else
    echo -n "aws" | tee "${CLOUD_PROVIDER_FILE}"
  fi
}

function get_default_interface() {
  ip route | sed -n 's/default via .* dev \(.\S*.\) .*$/\1/p'
}

function get_ip_from_interface() {
  local INTERFACE="${1}"

  ip -4 addr show dev "${INTERFACE}" primary | grep inet | awk '{split($2,a,"/"); print a[1]}'
}

function set_hostname() {
  local HOST="${1}"
  local SYSENV DEFAULT_INTERFACE BIND_IP HOST_LINE HOST_FULL

  SYSENV="$(get_sysenv)"
  HOST_FULL="${HOST}.node.${SYSENV}.$(get_ivy_tag)"

  hostnamectl set-hostname "${HOST}"

  DEFAULT_INTERFACE=$(get_default_interface)
  BIND_IP="$(get_ip_from_interface "${DEFAULT_INTERFACE}")"

  HOST_LINE="${BIND_IP} ${HOST_FULL} ${HOST}"
  if grep -q "${BIND_IP}" /etc/hosts; then
      sed -i "/${BIND_IP}/c\\${HOST_LINE}" /etc/hosts
  else
      echo "${HOST_LINE}" >> /etc/hosts
  fi

  # Restart rsyslog since hostname changed
  systemctl restart rsyslog
}

function get_ram_mb_by_percent() {
  local PERCENT="${1}"

  MB="$(grep MemTotal /proc/meminfo | awk "{printf(\"%.0f\", \$2 / 1024 * ${PERCENT})}")"

  echo "${MB}"
}

function get_capped_ram_mb_by_percent() {
  local PERCENT="${1}"
  local LIMIT="${2:-31744}"

  MB="$(get_ram_mb_by_percent "${PERCENT}")"

  if [ "${MB}" -gt "${LIMIT}" ]; then
      echo "${LIMIT}"
  else
      echo "${MB}"
  fi
}

function set_datadog_key() {
  local DD_API_KEY="${1}"
  local DD_CONFIG_FILE="${2:-/etc/datadog-agent/datadog.yaml}"
  cat <<EOF > "${DD_CONFIG_FILE}"
api_key: ${DD_API_KEY}
bind_host: 0.0.0.0
EOF
}

function enable_datadog_cloud_security() {
  local SYSTEM_PROBE_CONFIG_FILE="/etc/datadog-agent/system-probe.yaml"
  local SECURITY_AGENT_CONFIG_FILE="/etc/datadog-agent/security-agent.yaml"
  if [[ ! -e "${SYSTEM_PROBE_CONFIG_FILE}" ]]; then
    install -o dd-agent -g dd-agent \
        "${SYSTEM_PROBE_CONFIG_FILE}.example" "${SYSTEM_PROBE_CONFIG_FILE}"
  fi
  install -o dd-agent -g dd-agent \
      "${SECURITY_AGENT_CONFIG_FILE}.example" "${SECURITY_AGENT_CONFIG_FILE}"
  yq e -i '.runtime_security_config.enabled = true' "${SYSTEM_PROBE_CONFIG_FILE}"
  yq e -i '.runtime_security_config.enabled = true' "${SECURITY_AGENT_CONFIG_FILE}"
  yq e -i '.compliance_config.enabled = true' "${SECURITY_AGENT_CONFIG_FILE}"
}

function enable_datadog_network_monitoring() {
  local SYSTEM_PROBE_CONFIG_FILE="/etc/datadog-agent/system-probe.yaml"
  if [[ ! -e "${SYSTEM_PROBE_CONFIG_FILE}" ]]; then
    install -o dd-agent -g dd-agent \
        "${SYSTEM_PROBE_CONFIG_FILE}.example" "${SYSTEM_PROBE_CONFIG_FILE}"
  fi
  yq e -i '.network_config.enabled = true' "${SYSTEM_PROBE_CONFIG_FILE}"
}

function set_newrelic_infra_key() {
  local NRIA_LICENSE_KEY="${1}"
  local NRIA_LICENSE_FILE="${2:-/etc/newrelic-infra.yml}"
  echo "license_key: ${NRIA_LICENSE_KEY}" > "${NRIA_LICENSE_FILE}"
}

# Note: the function below requires get_tags function which
#       is only present in bash_lib/<cloud>.sh
function set_newrelic_statsd() {
  local NR_API_KEY="${1}"
  local NR_ACCOUNT_ID="${2}"
  local NR_EU_REGION="${3:-false}"
  local NR_STATSD_CFG="${4:-/etc/newrelic-infra/nri-statsd.toml}"
  local NR_INSIGHTS_DOMAIN='newrelic.com'
  local NR_METRICS_DOMAIN='newrelic.com'
  local HOSTNAME_VALUE
  HOSTNAME_VALUE="$(hostname -f)"

  if [ "${NR_EU_REGION}" == 'true' ]; then
    NR_INSIGHTS_DOMAIN='eu01.nr-data.net'
    NR_METRICS_DOMAIN="eu.${NR_METRICS_DOMAIN}"
  fi

  cat <<EOF > "${NR_STATSD_CFG}"
hostname = "${HOSTNAME_VALUE}"
default-tags = "hostname:${HOSTNAME_VALUE} $(get_tags)"
percent-threshold = [90, 95, 99]
backends='newrelic'
[newrelic]
flush-type = "metrics"
transport = "default"
address = "https://insights-collector.${NR_INSIGHTS_DOMAIN}/v1/accounts/${NR_ACCOUNT_ID}/events"
address-metrics = "https://metric-api.${NR_METRICS_DOMAIN}/metric/v1"
api-key = "${NR_API_KEY}"
EOF
}

function set_prompt_color() {
  local COLOR=$1
  echo -n "${COLOR}" > /etc/sysconfig/console/color
}

function setup_docker_storage() {
  # Setup storage for docker images
  # Use: setup_docker_storage "/dev/xvdb"
  local DEVICE="${1}"
  local MOUNT_PATH='/mnt/docker'

  systemctl stop docker
  sleep 2

  mkfs.xfs "${DEVICE}"
  mkdir -p "${MOUNT_PATH}"
  mount "${DEVICE}" "${MOUNT_PATH}"

  rm -rf /var/lib/docker
  ln -s "${MOUNT_PATH}" /var/lib/docker

  # TODO: can probably remove this once it's baked into the AMI(?)
  echo 'DOCKER_STORAGE_OPTIONS="--storage-driver overlay2"' > /etc/sysconfig/docker-storage

  local FSTAB="${DEVICE} ${MOUNT_PATH} xfs defaults 0 0"
  # shellcheck disable=SC2016
  sed -i '/${DEVICE}/d' /etc/fstab
  echo "${FSTAB}" >> /etc/fstab

  systemctl enable --now docker
}

function update_env() {
  # Update a line in a dotenv file
  # Use: update_env /etc/sysconfig/aws-iam-authenticator "AWS_AUTH_KUBECONFIG" /etc/kubernetes/aws-iam-authenticator/kubeconfig.yaml
  local FILE="${1}"
  local KEY="${2}"
  local VALUE="${3}"

  # search for value
  if grep -q -E "^${KEY}[[:space:]]*=" "${FILE}"; then
    # if exists, sed it
    sed -i -e "s#^${KEY}[[:space:]]*=.*#${KEY}=${VALUE}#" "${FILE}"
  else
    # if not, just cat it to the end of the file
    echo "${KEY}=${VALUE}" >> "${FILE}"
  fi
}

function ask_to_continue(){
  local ASK="${1:-yes}"
  if [[ "${ASK}" == 'yes' ]]; then
    echo -e "\e[31m press [enter] to continue \e[0m"
    read -r -p ""
  fi
}

function explain(){
  local EXPLAIN="${1:-yes}"
  local MESSAGE="${2}"
  if [[ "${EXPLAIN}" == 'yes' ]]; then
    echo -e "\e[36m ${MESSAGE} \e[0m"
  fi
}


function warn() {
  local MESSAGE=${1}
  echo "[WARN] ${MESSAGE}" >&2
}

function retry() {
  until "${@}"; do
    warn "Waiting for '${*}' to succeed, sleeping 5 seconds"
    sleep 5
  done
}

case "$(get_cloud)" in
  aws)
    # shellcheck disable=SC1091
    source "$(dirname "${BASH_SOURCE[0]}")"/bash_lib/aws.sh
    ;;
  azure)
    # shellcheck disable=SC1091
    source "$(dirname "${BASH_SOURCE[0]}")"/bash_lib/azure.sh
    ;;
  *)
    echo 'ERROR: Unknown cloud provider, unable to proceed!'
    ;;
esac

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")"/bash_lib/k8s.sh
