#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

THIS_SCRIPT=$(basename "${0}")
PADDING=$(printf %-${#THIS_SCRIPT}s " ")

usage () {
    echo "Usage:"
    echo "${THIS_SCRIPT} -p <REQUIRED: Parent account profile name> -o <Optional: Name for the Read only role in the master account>"
    echo "${PADDING} -c <REQUIRED: Child account profile name> -a <Optional: Name for the AMI builder role in the child account>"
    echo
    echo "Sets up a trust between AWS parent and child accounts"
    echo "that allows the child read-only to the parent organization"
    exit 1
}

# Ensure dependencies are present
if ! command -v aws &> /dev/null || ! command -v envsubst &> /dev/null || ! command -v jq &> /dev/null; then
    echo "[-] Dependencies unmet.  Please verify that the following are installed and in the PATH:  aws, envsubst, jq" >&2
    exit 1
fi

while getopts ":a:c:o:p:" opt; do
  case ${opt} in
    a)
      CHILD_ACCOUNT_ROLE=${OPTARG} ;;
    c)
      CHILD_ACCOUNT_PROFILE=${OPTARG} ;;
    o)
      PARENT_ACCOUNT_ROLE=${OPTARG} ;;
    p)
      PARENT_ACCOUNT_PROFILE=${OPTARG} ;;
    \?)
      usage ;;
    :)
      usage ;;
  esac
done

if [[ -z ${CHILD_ACCOUNT_PROFILE:-""} || -z ${PARENT_ACCOUNT_PROFILE:-""} ]] ; then
  usage
fi

if [[ -z ${PARENT_ACCOUNT_ROLE:-""} ]] ; then
  PARENT_ACCOUNT_ROLE='ORGSReadOnlyTrust'
  echo "Setting PARENT_ACCOUNT_ROLE to default value: ${PARENT_ACCOUNT_ROLE}"
fi

if [[ -z ${CHILD_ACCOUNT_ROLE:-""} ]] ; then
  CHILD_ACCOUNT_ROLE='AMIBuilder'
  echo "Setting CHILD_ACCOUNT_ROLE to default value: ${CHILD_ACCOUNT_ROLE}"
fi

CHILD_ACCOUNT_POLICY="${CHILD_ACCOUNT_ROLE}-AccessToParentRole"

function get_account_arn() {
  local PROFILE="${1}"
  aws --profile="${PROFILE}" sts get-caller-identity --query Arn --output text
}

function get_accountid_from_arn() {
  local ARN="${1}"
  echo "${ARN}" | cut -d ':' -f5
}

function get_identity_partition_from_arn() {
  local ARN="${1}"
  echo "${ARN}" | cut -d ':' -f2
}

SLEEP_TIME="10s"
PARENT_ARN="$(get_account_arn "${PARENT_ACCOUNT_PROFILE}")"
# We can only set trusts between accounts in the same identity partition
AWS_IDENTITY_PARTITION="$(get_identity_partition_from_arn "${PARENT_ARN}")"
PARENT_ACCOUNT_ID="$(get_accountid_from_arn "${PARENT_ARN}")"
CHILD_ACCOUNT_ID="$(get_accountid_from_arn "$(get_account_arn "${CHILD_ACCOUNT_PROFILE}")")"
export AWS_IDENTITY_PARTITION
export PARENT_ACCOUNT_ID
export CHILD_ACCOUNT_ID
export PARENT_ACCOUNT_ROLE
export CHILD_ACCOUNT_ROLE


echo "Creating role ${CHILD_ACCOUNT_ROLE} in profile ${CHILD_ACCOUNT_PROFILE} that allows ec2 service to assume it, if the role does not exist"

if ! aws iam get-role --role-name "${CHILD_ACCOUNT_ROLE}" --profile "${CHILD_ACCOUNT_PROFILE}" &> /dev/null; then
  aws iam create-role \
    --role-name "${CHILD_ACCOUNT_ROLE}" \
    --assume-role-policy-document file://./dev_ec2_trust_policy.json \
    --profile "${CHILD_ACCOUNT_PROFILE}"
fi

echo "Sleeping for ${SLEEP_TIME} before creating role in profile ${PARENT_ACCOUNT_PROFILE} to avoid error:"
echo "Invalid principal in policy: \"AWS\":\"arn:${AWS_IDENTITY_PARTITION}:iam::${CHILD_ACCOUNT_ID}:role/${CHILD_ACCOUNT_ROLE}\""
sleep "${SLEEP_TIME}"

echo "Creating role ${PARENT_ACCOUNT_ROLE} in profile ${PARENT_ACCOUNT_PROFILE} that allows arn:${AWS_IDENTITY_PARTITION}:iam::${CHILD_ACCOUNT_ID}:role/${CHILD_ACCOUNT_ROLE} to assume it, if not exists"

if ! aws iam get-role --role-name "${PARENT_ACCOUNT_ROLE}" --profile "${PARENT_ACCOUNT_PROFILE}" &> /dev/null; then
  aws iam create-role \
    --role-name "${PARENT_ACCOUNT_ROLE}" \
    --assume-role-policy-document "$(envsubst < ./prod_trust_policy.json.tpl | jq -c)" \
    --profile "${PARENT_ACCOUNT_PROFILE}"
fi

echo "Attaching aws' managed policy: AWSOrganizationsReadOnlyAccess to role arn:${AWS_IDENTITY_PARTITION}:iam::${PARENT_ACCOUNT_ID}:role/${PARENT_ACCOUNT_ROLE} in profile ${PARENT_ACCOUNT_PROFILE}"
aws iam attach-role-policy \
  --role-name "${PARENT_ACCOUNT_ROLE}" \
  --policy-arn "arn:${AWS_IDENTITY_PARTITION}:iam::aws:policy/AWSOrganizationsReadOnlyAccess" \
  --profile "${PARENT_ACCOUNT_PROFILE}"

echo "Creating policy ${CHILD_ACCOUNT_POLICY} in profile ${CHILD_ACCOUNT_PROFILE} that allows assuming role arn:${AWS_IDENTITY_PARTITION}:iam::${PARENT_ACCOUNT_ID}:role/${PARENT_ACCOUNT_ROLE}"
aws iam create-policy \
  --policy-name "${CHILD_ACCOUNT_POLICY}" \
  --description 'Allow assuming parent account role' \
  --policy-document "$(envsubst < ./dev_assume_role_prod.json.tpl | jq -c)" \
  --profile "${CHILD_ACCOUNT_PROFILE}"

echo "Attaching policy ${CHILD_ACCOUNT_POLICY} to role ${CHILD_ACCOUNT_ROLE} in profile ${CHILD_ACCOUNT_PROFILE}"
aws iam attach-role-policy \
  --role-name "${CHILD_ACCOUNT_ROLE}" \
  --policy-arn "arn:${AWS_IDENTITY_PARTITION}:iam::${CHILD_ACCOUNT_ID}:policy/${CHILD_ACCOUNT_POLICY}" \
  --profile "${CHILD_ACCOUNT_PROFILE}"

echo "Creating instance profile ${CHILD_ACCOUNT_ROLE} in profile ${CHILD_ACCOUNT_PROFILE}, if not exists"

if ! aws iam get-instance-profile --instance-profile-name "${CHILD_ACCOUNT_ROLE}" --profile "${CHILD_ACCOUNT_PROFILE}" &> /dev/null; then
  aws iam create-instance-profile \
    --instance-profile-name "${CHILD_ACCOUNT_ROLE}" \
    --profile "${CHILD_ACCOUNT_PROFILE}"
fi

echo "Attaching role ${CHILD_ACCOUNT_ROLE} to instance profile ${CHILD_ACCOUNT_ROLE} in profile ${CHILD_ACCOUNT_PROFILE}"
aws iam add-role-to-instance-profile \
  --role-name "${CHILD_ACCOUNT_ROLE}" \
  --instance-profile-name "${CHILD_ACCOUNT_ROLE}" \
  --profile "${CHILD_ACCOUNT_PROFILE}"
