#!/usr/bin/env bash
# Enable bash's unofficial strict mode
GITROOT=$(git rev-parse --show-toplevel)
# shellcheck disable=SC1090,SC1091
. "${GITROOT}"/scripts/lib/strict-mode
# shellcheck disable=SC1090,SC1091
. "${GITROOT}"/scripts/lib/utils
strictMode

THIS_SCRIPT=$(basename "${0}")
PADDING=$(printf %-${#THIS_SCRIPT}s " ")

function usage () {
  echo "Usage:"
  echo "${THIS_SCRIPT} -r, --region-name <AWS region name. Examples: us-east-1, us-west-2. REQUIRED>"
  echo "${PADDING} -f, --first <Use this flag to pick the first Auto Scaling Group>"
  echo
  echo "Copy an AMI to another AWS region"
  exit 1
}

# Ensure dependencies are present
if ! command -v aws &> /dev/null || ! command -v git &> /dev/null || ! command -v jq &> /dev/null || ! command -v yq &> /dev/null; then
  msg_fatal "[-] Dependencies unmet. Please verify that the following are installed and in the PATH: aws, git, jq, yq. Check README for requirements"
fi

while [[ $# -gt 0 ]]; do
  case "${1}" in
    -r|--region-name)
      REGION_NAME="${2}"
      shift # past argument
      shift # past value
      ;;
    -*)
      echo "Unknown option ${1}"
      usage
      ;;
  esac
done

if [[ -z ${REGION_NAME:-""} ]] ; then
  usage
fi

# Create temp directory
TMP_DIR="$(create_temp_dir "${THIS_SCRIPT}")"
function cleanup() {
  echo "Deleting ${TMP_DIR}"
  rm -rf "${TMP_DIR}"
}
# Make sure cleanup runs even if this script fails
trap cleanup EXIT


#ASG_FILE="$(select_asg "${STACK_NAME}" "${TMP_DIR}" "${FIRST}")"

#get_user_data "${ASG_FILE}" "${TMP_DIR}"

AMI="$(select_ami "${TMP_DIR}")"

AMI_NAME="$(cut -d ',' -f1 <<<"${AMI}")"
AMI_ID="$(cut -d ',' -f2 <<<"${AMI}")"
# The command below does NOT respect environment variables:
# - AWS_REGION
# - AWS_DEFAULT_REGION
# We expect to run this script from ami bakery instance
CURRENT_REGION="$(aws configure get region)"

msg_info "Selected AMI_NAME is ${AMI_NAME} and its ID is ${AMI_ID}"
msg_info "Current region is ${CURRENT_REGION}"

aws --region "${REGION_NAME}" ec2 copy-image --name "${AMI_NAME}" \
  --source-image-id "${AMI_ID}" --source-region "${CURRENT_REGION}" --dry-run
