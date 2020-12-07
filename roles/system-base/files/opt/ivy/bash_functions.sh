#!/bin/echo "This is a library, please source it from another script"

##
## bash_functions.sh
## Common functions for scripts used across the entire Ivy stack
##
## Source this script where necessary with `source /opt/ivy/bash_functions.sh`
##


# Prevent modules from being sourced directly
IVY="yes"

function get_ivy_tag() {
    # Allow override of Ivy tag for custom build customers

    local TAG_FILE=/opt/ivy/tag

    if [[ -f ${TAG_FILE} ]]; then
        cat ${TAG_FILE}
    else
        echo -n "ivy"
    fi
}

function get_cloud() {
    # Discover the current cloud platform. Very rudimentary, could fail eventually, but since 'compute' is
    # Google's trademark word for their service, it's not likely that AWS suddenly has this value.

    if [[ -f /var/lib/cloud_provider ]]; then
        cat /var/lib/cloud_provider
        return
    fi

    local META_TEST=$(curl --retry 3 --silent --fail http://169.254.169.254/)
    if echo "${META_TEST}" | grep "computeMetadata" 2>&1 > /dev/null; then
        echo "google"
        echo "google" > /var/lib/cloud_provider
    else
        echo "aws"
        echo "aws" > /var/lib/cloud_provider
    fi
}

function get_default_interface() {
    echo $(ip route | sed -n 's/default via .* dev \(.\S*.\) .*$/\1/p')
}

function get_ip_from_interface() {
    local INTERFACE=$1

    echo $(ip -4 addr show dev ${INTERFACE} primary | grep inet | awk '{split($2,a,"/"); print a[1]}')
}

function set_hostname() {
    local HOST=$1

    local ENV=$(get_environment)
    local HOST_FULL="${HOST}.node.${ENV}.$(get_ivy_tag)"

    hostnamectl set-hostname ${HOST}

    DEFAULT_INTERFACE=$(get_default_interface)
    BIND_IP=$(get_ip_from_interface ${DEFAULT_INTERFACE})

    HOST_LINE="${BIND_IP} ${HOST_FULL} ${HOST}"
    if grep -q "${BIND_IP}" /etc/hosts; then
        sed -i "/${BIND_IP}/c\\${HOST_LINE}" /etc/hosts
    else
        echo "${HOST_LINE}" >> /etc/hosts
    fi

    # Restart rsyslog & datadog since hostname changed
    systemctl restart rsyslog
    systemctl restart datadog-agent
}

function get_ram_mb_by_percent() {
    local PERCENT=$1

    MB=$(grep MemTotal /proc/meminfo | awk "{printf(\"%.0f\", \$2 / 1024 * ${PERCENT})}")

    echo ${MB}
}

function get_ram_mb_by_percent_for_java() {
    local PERCENT=$1

    MB=$(get_ram_mb_by_percent ${PERCENT})

    if [ ${MB} -gt 31744 ]; then
        echo "31744"
    else
        echo ${MB}
    fi
}

function set_datadog_key() {
    local DD_API_KEY="${1}"
    local DD_CONFIG_FILE="${2:-/etc/datadog-agent/datadog.yaml}"
    sed -i "s/ivy-use-set-datadog-key/${DD_API_KEY}/g" "${DD_CONFIG_FILE}"
}

function set_newrelic_infra_key() {
    local NRIA_LICENSE_KEY="${1}"
    local NRIA_LICENSE_FILE="${2:-/etc/newrelic-infra.yml}"
    echo "license_key: ${NRIA_LICENSE_KEY}" > "${NRIA_LICENSE_FILE}"
}

function set_prompt_color() {
    local COLOR=$1
    echo -n "${COLOR}" > /etc/sysconfig/console/color
}

case "$(get_cloud)" in
    aws)
        source $(dirname ${BASH_SOURCE})/bash_lib/aws.sh
        ;;
    *)
        echo 'ERROR: Unknown cloud provider, unable to proceed!'
        ;;
esac
