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
  echo "${PADDING} -p, --prefix <AMI name prefix. REQUIRED>"
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
    -p|--prefix)
      PREFIX="${2}"
      shift # past argument
      shift # past value
      ;;
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

if [[ -z ${REGION_NAME:-""} ]] || [[ -z ${PREFIX:-""} ]]; then
  usage
fi

AMI="$(select_ami "${PREFIX}")"

AMI_NAME="$(cut -d ',' -f1 <<<"${AMI}")"
AMI_ID="$(cut -d ',' -f2 <<<"${AMI}")"
# The command below does NOT respect environment variables:
# - AWS_REGION
# - AWS_DEFAULT_REGION
# We expect to run this script from ami bakery instance
CURRENT_REGION="$(aws configure get region)"

msg_info "Selected AMI_NAME is ${AMI_NAME} and its ID is ${AMI_ID}"
msg_info "Current region is ${CURRENT_REGION}"

NEW_IMAGE_ID="$(aws --region "${REGION_NAME}" ec2 copy-image --name "${AMI_NAME}" \
                  --source-image-id "${AMI_ID}" --source-region "${CURRENT_REGION}" \
                  --query 'ImageId' --output text)"

msg_info "AMI_NAME ${AMI_NAME} in region ${REGION_NAME} has ID ${NEW_IMAGE_ID}"

declare -a ACCOUNT_IDS=()
while IFS= read -r a; do
  ACCOUNT_IDS+=("${a}")
done < <(get_aws_accounts_for_org "orgs")

msg_info "These are the AWS Account IDs that will have access to ${NEW_IMAGE_ID}:"
msg_info "${ACCOUNT_IDS[*]+"${ACCOUNT_IDS[*]}"}"

msg_info "Waiting until ${NEW_IMAGE_ID} is ready"

aws --region "${REGION_NAME}" ec2 wait image-available --image-ids "${NEW_IMAGE_ID}"

aws --region "${REGION_NAME}" ec2 modify-image-attribute --image-id "${NEW_IMAGE_ID}" \
  --attribute 'launchPermission' --operation-type 'add' \
  --user-ids "${ACCOUNT_IDS[@]+"${ACCOUNT_IDS[@]}"}"

msg_info "I'm done!"
