#!/usr/bin/env bash

##
## azure.sh
## Azure-specific modules for Ivy
##
## Use this script by sourcing the parent `bash_functions.sh` script.
##


# Prevent direct sourcing of this module
if [[ ${#BASH_SOURCE[@]} -lt 2 ]]; then
  echo "WARNING: Script '$(basename "${BASH_SOURCE[0]}")' was incorrectly sourced. Please do not source it directly."
  return 255
fi

function az_login() {
  # infinite retry loop to log into azure using the system identity
  retry az login --identity
}

function get_availability_zone() {
  curl -H 'Metadata:true' --retry 3 --silent --fail --noproxy "*" \
    'http://169.254.169.254/metadata/instance/compute?api-version=2021-02-01' | jq -r '.zone'
}

function get_region() {
  curl -H 'Metadata:true' --retry 3 --silent --fail --noproxy "*" \
    'http://169.254.169.254/metadata/instance/compute?api-version=2021-02-01' | jq -r '.location'
}

function get_instance_id() {
  # returns instance uuid, not usually what you want
  curl -H 'Metadata:true' --retry 3 --silent --fail --noproxy "*" \
    'http://169.254.169.254/metadata/instance/compute?api-version=2021-02-01' | jq -r '.vmId'
}

function get_subscription_id() {
  curl -H 'Metadata:true' --retry 3 --silent --fail --noproxy "*" \
    'http://169.254.169.254/metadata/instance/compute?api-version=2021-02-01' | jq -r '.subscriptionId'
}

function get_instance_type() {
  curl -H 'Metadata:true' --retry 3 --silent --fail --noproxy "*" \
    'http://169.254.169.254/metadata/instance/compute?api-version=2021-02-01' | jq -r '.vmSize'
}

# In azure get_provider_id is basically aliased to get_resource_id. This gives
# us a common function call between aws and azure.
function get_provider_id() {
  echo "azure://$(get_resource_id)"
}

function get_name() {
  # returns computerName, in a vmss this is `${computerNamePrefix}_${index}`
  curl -H 'Metadata:true' --retry 3 --silent --fail --noproxy "*" \
    'http://169.254.169.254/metadata/instance/compute?api-version=2021-02-01' | jq -r '.name'
}

function get_resource_id() {
  # in a VMSS, this is the vmss id + index
  curl -H 'Metadata:true' --retry 3 --silent --fail --noproxy "*" \
    'http://169.254.169.254/metadata/instance/compute?api-version=2021-02-01' | jq -r '.resourceId'
}

function get_vmss_name() {
  curl -H 'Metadata:true' --retry 3 --silent --fail --noproxy "*" \
    'http://169.254.169.254/metadata/instance/compute?api-version=2021-02-01' | jq -r '.vmScaleSetName'
}

function get_vmss_index() {
  curl -H 'Metadata:true' --retry 3 --silent --fail --noproxy "*" \
    'http://169.254.169.254/metadata/instance/compute?api-version=2021-02-01' | jq -r '.resourceId | split("/")[-1]'
}

function get_resource_group() {
  curl -H 'Metadata:true' --retry 3 --silent --fail --noproxy "*" \
    'http://169.254.169.254/metadata/instance/compute?api-version=2021-02-01' | jq -r '.resourceGroupName'
}

function get_tags() {
  local SEPARATOR="${1:- }"
  local QUERY=".tags | split(\";\") | join(\"${SEPARATOR}\")"
  curl -H 'Metadata:true' --retry 3 --silent --fail --noproxy "*" \
    'http://169.254.169.254/metadata/instance/compute?api-version=2021-02-01' | jq -r "${QUERY}"
}

function get_tag_value() {
  local tag_key_to_query="${1}"
  local tag_key tag_value
  declare -a array_of_tags elements_in_tag
  declare -A tags
  mapfile -t array_of_tags < <(get_tags '\n')
  for tag in "${array_of_tags[@]}"; do
    tag_value="$(rev <<< "${tag}" | cut -d ':' -f 1 | rev)"
    mapfile -t elements_in_tag < <( tr ':' '\n' <<< "${tag}")
    if [ "${#elements_in_tag[@]}" -eq 2 ]; then
      tag_key=${elements_in_tag[0]}
    elif [ "${#elements_in_tag[@]}" -eq 3 ]; then
      tag_key="$(echo "${tag}" | cut -d ':' -f 1-2)"
    fi
    tags["${tag_key}"]=${tag_value}
  done
  echo "${tags["${tag_key_to_query}"]}"
}

function get_sysenv() {
  get_tag_value "$(get_ivy_tag):sysenv"
}

function get_service() {
  get_tag_value "$(get_ivy_tag):service"
}

function get_role() {
  get_tag_value "$(get_ivy_tag):role"
}

function get_group() {
  get_tag_value "$(get_ivy_tag):group"
}

function get_keyvault_key() {
  local KEY_URI=${1}
  retry az keyvault secret show --id "${KEY_URI}" --query 'value' -o tsv
}
