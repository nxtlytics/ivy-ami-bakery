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
    echo "Deletes resources created by setup.sh in this same directory"
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


echo "Deleting resources in profile ${CHILD_ACCOUNT_PROFILE}"

echo "Detaching policy ${CHILD_ACCOUNT_POLICY} from role ${CHILD_ACCOUNT_ROLE}"
aws iam detach-role-policy \
  --role-name "${CHILD_ACCOUNT_ROLE}" \
  --policy-arn "arn:${AWS_IDENTITY_PARTITION}:iam::${CHILD_ACCOUNT_ID}:policy/${CHILD_ACCOUNT_POLICY}" \
  --profile "${CHILD_ACCOUNT_PROFILE}"

echo "Deleting policy ${CHILD_ACCOUNT_POLICY}"
aws iam delete-policy \
  --policy-arn "arn:${AWS_IDENTITY_PARTITION}:iam::${CHILD_ACCOUNT_ID}:policy/${CHILD_ACCOUNT_POLICY}" \
  --profile "${CHILD_ACCOUNT_PROFILE}"

echo "Looking up for all instances with instance profile ${CHILD_ACCOUNT_ROLE}"
if aws ec2 describe-iam-instance-profile-associations --profile "${CHILD_ACCOUNT_PROFILE}" --output text | grep -q "${CHILD_ACCOUNT_ROLE}"; then
  declare -a ASSOCIATED_ROLES
  mapfile -t ASSOCIATED_ROLES < <(aws ec2 describe-iam-instance-profile-associations --query 'IamInstanceProfileAssociations[*].{AssociationId: AssociationId, Arn: IamInstanceProfile.Arn}' --profile "${CHILD_ACCOUNT_PROFILE}" --output text | grep "${CHILD_ACCOUNT_ROLE}" | awk '{ print $2 }')

  echo "Removing instance profile ${CHILD_ACCOUNT_PROFILE} from ${ASSOCIATED_ROLES[*]}"
  for ASSOCIATION in "${ASSOCIATED_ROLES[@]}"; do
    aws ec2 disassociate-iam-instance-profile \
      --association-id "${ASSOCIATION}" \
      --profile "${CHILD_ACCOUNT_PROFILE}"
  done
fi

echo "Removing role ${CHILD_ACCOUNT_ROLE} from instance profile ${CHILD_ACCOUNT_ROLE}"
aws iam remove-role-from-instance-profile \
  --role-name "${CHILD_ACCOUNT_ROLE}" \
  --instance-profile-name "${CHILD_ACCOUNT_ROLE}" \
  --profile "${CHILD_ACCOUNT_PROFILE}"

echo "Deleting role ${CHILD_ACCOUNT_ROLE}"
aws iam delete-role \
  --role-name "${CHILD_ACCOUNT_ROLE}" \
  --profile "${CHILD_ACCOUNT_PROFILE}"

echo "Deleting instance profile ${CHILD_ACCOUNT_ROLE}"
aws iam delete-instance-profile \
  --instance-profile-name "${CHILD_ACCOUNT_ROLE}" \
  --profile "${CHILD_ACCOUNT_PROFILE}"

echo "Deleting resources in profile ${PARENT_ACCOUNT_PROFILE}"

echo "Detaching policy AWSOrganizationsReadOnlyAccess from role ${PARENT_ACCOUNT_ROLE}"
aws iam detach-role-policy \
  --role-name "${PARENT_ACCOUNT_ROLE}" \
  --policy-arn 'arn:aws:iam::aws:policy/AWSOrganizationsReadOnlyAccess' \
  --profile "${PARENT_ACCOUNT_PROFILE}"

echo "Deleting role ${PARENT_ACCOUNT_ROLE} in profile ${PARENT_ACCOUNT_PROFILE}"
aws iam delete-role \
  --role-name "${PARENT_ACCOUNT_ROLE}" \
  --profile "${PARENT_ACCOUNT_PROFILE}"
