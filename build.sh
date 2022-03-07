#!/bin/bash

set -eu -o pipefail
DEBUG=

bold=$(tput bold)
norm=$(tput sgr0)

function get_latest_ami() {
    local ami_name="$1"
    #local region="${2:-"us-west-2"}"
    ami_id=$(aws ec2 describe-images \
                 --owners "amazon" "self" \
                 --filters "Name=name,Values=${ami_name}" \
                 --query 'Images[*].[CreationDate, ImageId]' \
                 --output text | sort -r | sed '1!d' | awk '{print $2}')
    if [[ $? -ne 0 || -z ${ami_id} ]]; then
        echo -e "${bold}FAILURE:${norm} cannot find latest AMI for filter '${ami_name}'" >&2
        exit 1
    fi
    echo -n "${ami_id}"
}

function get_aws_accounts_for_org() {
    local profile="${1:-"orgs"}"
    local self_account_id account_ids
    self_account_id=$(aws sts get-caller-identity \
                          --query Account \
                          --output text)
    # shellcheck disable=SC2016
    local start_query='. as $arr | del($arr[] | select(contains("'
    local end_query='"))) | join(",")'
    account_ids=$(aws organizations list-accounts \
                      --query 'Accounts[*].Id' \
                      --output json \
                      --profile="${profile}" \
                      | jq -r \
                      "${start_query}${self_account_id}${end_query}")
    if [[ $? -ne 0 || -z ${account_ids} ]]; then
        echo -e "${bold}FAILURE:${norm} cannot find other accounts in awscli profile ${profile}, using own Account ID only: ${self_account_id} " >&2
        account_ids=${self_account_id}
    fi
    echo -n "${account_ids}"
}

function get_regions() {
  local regions="${1:-""}"
  local local_region
  local_region="$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/\(.*\)[a-z]/\1/')"
  if [[ -z ${regions:-""} ]] ; then
    regions="${local_region}"
  fi
  echo -n "${regions}"
}

function setup_env() {
    local provider=$1
    local image=$2
    local regions="${3:-""}"
    local multiaccountprofile=${4}
    local enableazurecompat="${5}"

    # Source the defaults
    # shellcheck disable=SC1090
    source ./providers/"${provider}"/images/default/packer.env

    # Allow override from defaults per provider/service pair
    if [[ -e ./providers/"${provider}"/images/"${image}"/packer.env ]]; then
        # shellcheck disable=SC1090
        source ./providers/"${provider}"/images/"${image}"/packer.env
    fi

    # Inherit from env file or default, not inlined below to prevent subshell from TRAP'ing exit code
    PACKER_SOURCE_IMAGE="$(get_latest_ami "${PACKER_SOURCE_IMAGE_NAME}")"
    PACKER_IMAGE_USERS="$(get_aws_accounts_for_org "${multiaccountprofile}")"
    PACKER_IMAGE_REGIONS="$(get_regions "${regions}")"
    export PACKER_SOURCE_IMAGE
    export PACKER_IMAGE_NAME="${image}"
    export PACKER_IMAGE_USERS
    export PACKER_IMAGE_REGIONS
    # Inherit from default packer config
    export PACKER_CONFIG_PATH=./providers/"${provider}"/packer/"${PACKER_CONFIG}"
    export PACKER_SSH_USERNAME
    export PACKER_VOLUME_SIZE
    export PACKER_IVY_TAG
    export PACKER_ENABLE_AZURE_COMPAT="${enableazurecompat}"

    # Show options for tracking purposes
    cat <<EOT
 ------------------------------------------------------
PACKER_IMAGE_NAME=${PACKER_IMAGE_NAME}
PACKER_IMAGE_USERS=${PACKER_IMAGE_USERS}
PACKER_IMAGE_REGIONS=${PACKER_IMAGE_REGIONS}
PACKER_SOURCE_IMAGE_NAME=${PACKER_SOURCE_IMAGE_NAME}
PACKER_SOURCE_IMAGE=${PACKER_SOURCE_IMAGE}
PACKER_CONFIG_PATH=${PACKER_CONFIG_PATH}
PACKER_IVY_TAG=${PACKER_IVY_TAG}
PACKER_ENABLE_AZURE_COMPAT=${PACKER_ENABLE_AZURE_COMPAT}
------------------------------------------------------
EOT

    # shellcheck disable=SC2236
    if [[ ! -n "${SUDO_USER:-''}" ]]; then
        echo "WARN: Sanitizing sudo environment variables"
        unset SUDO_USER SUDO_UID SUDO_COMMAND SUDO_GID
    fi
}

function get_packer_vars() {
    local vars="${1:-""}"
    declare -a VARIABLES_TO_PASS ARGUMENTS_TO_PASS
    mapfile -t VARIABLES_TO_PASS < <(tr ',' '\n' <<<"${vars}")
    if [[ "${#VARIABLES_TO_PASS[@]}" -gt '0' ]]; then
        for i in "${VARIABLES_TO_PASS[@]}"; do
            ARGUMENTS_TO_PASS+=("-var ${i}")
        done
    else
	    echo ""
	    return
    fi
    echo "${ARGUMENTS_TO_PASS[@]}"
}

function run_packer() {
    local ARGUMENTS="${1:-""}"
    declare -a PACKER_BINS
    echo "Downloading bpftrace"
    bash ./scripts/binaries/download_binaries.sh
    # This is needed when using RedHat based distros
    # More info at https://www.packer.io/intro/getting-started/install.html#troubleshooting
    mapfile -t PACKER_BINS < <(type -a packer | awk '{ print $3 }')
    echo "These are the packer bins available in your PATH: ${PACKER_BINS[*]}"
    for bin in "${PACKER_BINS[@]}"; do
      if ${bin} -h 2>&1 | grep 'build image' > /dev/null; then
        PACKER=${bin}
      fi
    done
    if [[ -z "${DEBUG}" ]]; then
        eval "${PACKER} build ${ARGUMENTS} ${DEBUG} ${PACKER_CONFIG_PATH}"
    else
        echo "Environment configuration ===================="
        env | grep -v -E '.*_PASS' | awk -F'=' '{st = index($0,"="); printf("\033[0;35m%-50s\033[0m= \"%s\"\n", $1, substr($0,st+1))}'
        echo "=============================================="
        eval "PACKER_LOG=1 ${PACKER} build ${ARGUMENTS} ${DEBUG} ${PACKER_CONFIG_PATH}"
    fi
}

function validate_provider() {
    local provider="${1}"
    if ! [[ -d ./providers/${provider} ]]; then
        echo -e "${bold}ERROR:${norm} no such provider '${provider}'."
        exit 1
    fi
}

function validate_image() {
    local provider="${1}"
    local image="${2}"
    if ! [[ -d ./providers/${provider}/images/${image} ]]; then
        echo -e "${bold}ERROR:${norm} no such image '${image}'."
        exit 1
    fi
}

function show_help() {
    cat <<EOT
Bake AMI from Ansible roles using Packer

 Usage: $(basename "${0}") -p PROVIDER -i IMAGE -r REGIONS -m MULTI-ACCOUNT_PROFILE [-v 'var1_name=value1,var2_name=value2'] [-d]

 Options:
   -v    variables and their values to pass to packer, key value pairs separated by commas
   -p    provider to use (amazon|google|nocloud|...)
   -r    regions to copy this image to (comma separated values)
   -m    awscli profile that can assume role to list all accounts in this org
   -i    image to provision
   -a    disable azure compatibility
   -d    enable debug mode
EOT
}

while getopts ":p:i:r:m:v:ad" opt; do
    case ${opt} in
        v)
            vars="${OPTARG}"
            ;;
        p)
            provider="${OPTARG}"
            ;;
        i)
            image="${OPTARG}"
            ;;
        r)
            regions="${OPTARG}"
            ;;
        m)
            multiaccountprofile="${OPTARG}"
            ;;
        a)
            enableazurecompat="false"
            ;;

        d)
            export DEBUG='--debug'
            ;;
        \?)
            echo -e "${bold}Invalid option:${norm} ${OPTARG}" 1>&2
            show_help
            exit 1
            ;;
        :)
            echo -e "${bold}Invalid option:${norm} ${OPTARG} requires an argument" 1>&2
            show_help
            exit 1
            ;;
    esac
done

shift $((OPTIND -1))

if [[ -z ${provider} ]] || [[ -z ${image} ]]; then
    echo -e "${bold}ERROR:${norm} Must specify provider and image"
    show_help
    exit 1
fi

# validate args
validate_provider "${provider}"
validate_image "${provider}" "${image}"

# do it nao
setup_env "${provider}" "${image}" "${regions:-""}" "${multiaccountprofile:-""}" "${enableazurecompat:-"true"}"
arguments=$(get_packer_vars "${vars:-""}")
run_packer "${arguments:-""}"
