#!/bin/echo "This is a library, please source it from another script"

##
## azure.sh
## Azure-specific modules for Ivy
##
## Use this script by sourcing the parent `bash_functions.sh` script.
##


# Prevent direct sourcing of this module
if [[ -z "${IVY}" ]]; then
    echo "WARNING: Script '$(basename ${BASH_SOURCE})' was incorrectly sourced. Please do not source it directly."
    return 255
fi

function get_availability_zone() {
    echo $(curl -H 'Metadata:true' --retry 3 --silent --fail 'http://169.254.169.254/metadata/instance/compute?api-version=2019-06-01' | jq -r '.zone')
}

function get_region() {
    echo $(curl -H 'Metadata:true' --retry 3 --silent --fail 'http://169.254.169.254/metadata/instance/compute?api-version=2019-06-01' | jq -r '.location')
}

function get_instance_id() {
    echo $(curl -H 'Metadata:true' --retry 3 --silent --fail 'http://169.254.169.254/metadata/instance/compute?api-version=2019-06-01' | jq -r '.vmId')
}

function get_tags() {
    local SEPARATOR="${1:- }"
    echo $(curl -H 'Metadata:true' --retry 3 --silent --fail 'http://169.254.169.254/metadata/instance/compute?api-version=2019-06-01' | jq -r '.tags' | tr ';' "${SEPARATOR}")
}

function get_tag_value() {
    local tag_key_to_query="${1}"
    local tags_as_string=$(curl -H 'Metadata:true' --retry 3 --silent --fail 'http://169.254.169.254/metadata/instance/compute?api-version=2019-06-01' | jq -r '.tags')
    declare -a array_of_tags
    local IFS=';'; read -r -a array_of_tags <<< "${tags_as_string}"
    declare -A tags
    declare -a elements_in_tag
    for tag in "${array_of_tags[@]}"; do
        local tag_value=$(echo ${tag} | rev | cut -d ':' -f 1 | rev)
        IFS=':' read -r -a elements_in_tag <<< "${tag}"
        if [ "${#elements_in_tag[@]}" -eq 2 ]; then
          local tag_key=${elements_in_tag[0]}
        elif [ "${#elements_in_tag[@]}" -eq 3 ]; then
          local tag_key=$(echo ${tag} | cut -d ':' -f 1-2)
        fi
        tags["${tag_key}"]=${tag_value}
    done
    echo "${tags["${tag_key_to_query}"]}"
}

function get_environment() {
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
