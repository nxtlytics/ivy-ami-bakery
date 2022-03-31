#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

THIS_SCRIPT=$(basename "${0}")
PADDING=$(printf %-${#THIS_SCRIPT}s " ")
DEBUG=

bold=$(tput bold)
norm=$(tput sgr0)

function get_latest_ami() {
  local ami_name="${1}"
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
  local provider="${1}"
  local image="${2}"
  local regions="${3:-""}"
  local multiaccountprofile="${4}"
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
  if [[ "${provider}" == 'docker' ]]; then
    PACKER_SOURCE_IMAGE="${PACKER_SOURCE_IMAGE_NAME}"
  else
    PACKER_SOURCE_IMAGE="$(get_latest_ami "${PACKER_SOURCE_IMAGE_NAME}")"
  fi
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
  declare -a vars ARGUMENTS_TO_PASS
  vars=("${@}")
  ARGUMENTS_TO_PASS=()
  if [[ "${#vars[@]}" -gt '0' ]]; then
    for i in "${vars[@]}"; do
      ARGUMENTS_TO_PASS+=("-var")
      ARGUMENTS_TO_PASS+=("${i}")
    done
  fi
  return_non_empty_array "${ARGUMENTS_TO_PASS[@]+"${ARGUMENTS_TO_PASS[@]}"}"
}

function run_packer() {
  declare -a ARGUMENTS
  ARGUMENTS=("${@}")
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
    ${PACKER} build ${ARGUMENTS[@]+"${ARGUMENTS[@]}"} ${DEBUG:+"${DEBUG}"} "${PACKER_CONFIG_PATH}"
  else
    echo "Environment configuration ===================="
    env | grep -v -E '.*_PASS' | awk -F'=' '{st = index($0,"="); printf("\033[0;35m%-50s\033[0m= \"%s\"\n", $1, substr($0,st+1))}'
    echo "=============================================="
    PACKER_LOG=1 ${PACKER} build ${ARGUMENTS[@]+"${ARGUMENTS[@]}"} ${DEBUG:+"${DEBUG}"} "${PACKER_CONFIG_PATH}"
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

function join_by {
  local IFS="${1}"
  shift
  echo "${*}"
}

function return_non_empty_array() {
  declare -a INPUT
  INPUT=("${@}")
  if [[ ${#INPUT[@]} -ne 0 ]]; then
    printf "%s\n" "${INPUT[@]}"
  fi
}

function show_help() {
  cat <<EOT
Bake AMI from Ansible roles using Packer

 Usage: ${THIS_SCRIPT} -p PROVIDER
        ${PADDING} -i IMAGE
        ${PADDING} -r REGION [-r OTHER_REGION]
        ${PADDING} -m MULTI-ACCOUNT_PROFILE
        ${PADDING} -v 'var1_name=value1' [-v 'var2_name=value2']
        ${PADDING} -d
        ${PADDING} --disable-azure-compatibility

 Options:
   --disable-azure-compatibility  disable azure compatibility
   -d,--debug                     enable debug mode
   -i,--image                     image to provision
   -m,--multiaccountprofile       awscli profile that can assume role to list all accounts in this org
   -p,--provider                  provider to use (amazon|google|nocloud|...)
   -r,--region                    regions to copy this image to (can be used multiple times)
   -v,--packer-var                variables and their values to pass to packer, key value pairs (can be used multiple times)
EOT
  exit 1
}

declare -a regions packer_vars packer_args
regions=()
packer_vars=()
packer_args=()
while [[ $# -gt 0 ]]; do
  case "${1}" in
    --disable-azure-compatibility)
      enableazurecompat='false'
      shift # past argument
      ;;
    -d|--debug)
      export DEBUG='--debug'
      shift # past argument
      ;;
    -i|--image)
      image="${2}"
      shift # past argument
      shift # past value
      ;;
    -m|--multiaccountprofile)
      multiaccountprofile="${2}"
      shift # past argument
      shift # past value
      ;;
    -p|--provider)
      provider="${2}"
      shift # past argument
      shift # past value
      ;;
    -r|--region)
      regions+=("${2}")
      shift # past argument
      shift # past value
      ;;
    -v|--packer-var)
      packer_vars+=("${2}")
      shift # past argument
      shift # past value
      ;;
    -*)
      echo "Unknown option ${1}"
      show_help
      ;;
  esac
done

if [[ -z ${provider} ]] || [[ -z ${image} ]]; then
  echo -e "${bold}ERROR:${norm} Must specify provider and image"
  show_help
fi

# validate args
validate_provider "${provider}"
validate_image "${provider}" "${image}"

# See this https://stackoverflow.com/questions/7577052/bash-empty-array-expansion-with-set-u
# for an explanation of `"${regions[@]+"${regions[@]}"}"`

# do it nao
setup_env "${provider}" "${image}" "$(join_by ',' "${regions[@]+"${regions[@]}"}")" "${multiaccountprofile:-""}" "${enableazurecompat:-"true"}"
while IFS= read -r i; do
  packer_args+=("${i}")
done < <(get_packer_vars "${packer_vars[@]+"${packer_vars[@]}"}")
run_packer "${packer_args[@]+"${packer_args[@]}"}"
