#!/usr/bin/env bash

##
## aws.sh
## AWS-specific modules for Ivy
##
## Use this script by sourcing the parent `bash_functions.sh` script.
##


# Prevent direct sourcing of this module
if [[ ${#BASH_SOURCE[@]} -lt 2 ]]; then
  echo "WARNING: Script '$(basename "${BASH_SOURCE[0]}")' was incorrectly sourced. Please do not source it directly."
  return 255
fi

function get_mdsv2() {
  # Got from https://github.com/aws-quickstart/quickstart-hashicorp-vault/blob/master/scripts/functions.sh#L34-L37
  local PARAMETER="${1}"
  local TOKEN
  TOKEN="$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 300" 2>/dev/null)"
  curl --retry 3 --silent --fail -H "X-aws-ec2-metadata-token: ${TOKEN}" \
    "http://169.254.169.254/latest/meta-data/${PARAMETER}" 2>/dev/null
}

function get_instance_id() {
  curl --retry 3 --silent --fail \
    'http://169.254.169.254/latest/meta-data/instance-id'
}

function get_instance_type() {
  curl --retry 3 --silent --fail \
    'http://169.254.169.254/latest/meta-data/instance-type'
}

function get_provider_id() {
  echo "aws:///$(get_availability_zone)/$(get_instance_id)"
}

function get_availability_zone() {
  curl --retry 3 --silent --fail \
    http://169.254.169.254/latest/meta-data/placement/availability-zone
}

function get_region() {
  local availability_zone
  availability_zone=$(get_availability_zone)
  echo "${availability_zone%?}"
}

function get_sysenv() {
  aws ec2 describe-instances --region "$(get_region)" \
                             --instance-id "$(get_instance_id)" \
                             --query "Reservations[0].Instances[0].Tags[?Key==\`$(get_ivy_tag):sysenv\`].Value" \
                             --output text
}

function get_service() {
  aws ec2 describe-instances --region "$(get_region)" \
                             --instance-id "$(get_instance_id)" \
                             --query "Reservations[0].Instances[0].Tags[?Key==\`$(get_ivy_tag):service\`].Value" \
                             --output text
}

function get_role() {
  aws ec2 describe-instances --region "$(get_region)" \
                             --instance-id "$(get_instance_id)" \
                             --query "Reservations[0].Instances[0].Tags[?Key==\`$(get_ivy_tag):role\`].Value" \
                             --output text
}

function get_group() {
  aws ec2 describe-instances --region "$(get_region)" \
                             --instance-id "$(get_instance_id)" \
                             --query "Reservations[0].Instances[0].Tags[?Key==\`$(get_ivy_tag):group\`].Value" \
                             --output text
}

function get_tags() {
  local SEPARATOR="${1:- }"
  aws ec2 describe-tags --region "$(get_region)" \
                        --filters "Name=resource-id,Values=$(get_instance_id)" \
                        --query 'Tags[*].[@.Key, @.Value]' \
                        --output json | jq -r '.[] | join(":")' | tr '\n' "${SEPARATOR}"
}

function get_eni_id() {
  local ENI_ROLE="${1}"
  local SERVICE="${2}"
  local TAG
  TAG=$(get_ivy_tag)
  aws ec2 describe-network-interfaces --region "$(get_region)" \
                                      --filters "Name=tag:${TAG}:sysenv,Values=$(get_sysenv)" \
                                                "Name=tag:${TAG}:role,Values=${ENI_ROLE}" \
                                                "Name=tag:${TAG}:service,Values=${SERVICE}" \
                                      --query 'NetworkInterfaces[0].NetworkInterfaceId' \
                                      --output text
}

function get_eni_ip() {
  local ENI_ID="${1}"
  aws ec2 describe-network-interfaces --region "$(get_region)" \
                                      --network-interface-ids "${ENI_ID}" \
                                      --query 'NetworkInterfaces[0].PrivateIpAddress' \
                                      --output text
}

function get_eni_public_ip() {
  local ENI_ID="${1}"
  aws ec2 describe-network-interfaces --region "$(get_region)" \
                                      --network-interface-ids "${ENI_ID}" \
                                      --query 'NetworkInterfaces[0].Association.PublicIp' \
                                      --output text
}

function get_eni_private_dns_name() {
  local ENI_ID="${1}"
  aws ec2 describe-network-interfaces --region "$(get_region)" \
                                      --network-interface-ids "${ENI_ID}" \
                                      --query 'NetworkInterfaces[0].PrivateDnsName' \
                                      --output text
}

function get_eni_interface() {
    local ENI_ID="${1}"
    local ENI_FILE ENI_STATUS MAC_ADDRESS
    ENI_FILE="$(mktemp -t -u 'ENI.XXXX.json')"
    aws ec2 describe-network-interfaces --region "$(get_region)" \
                                        --network-interface-ids "${ENI_ID}" \
                                        --query 'NetworkInterfaces[0]' \
                                        --output json &> "${ENI_FILE}"
    ENI_STATUS="$(jq -r '.Status' "${ENI_FILE}")"
    if [[ "${ENI_STATUS}" != 'in-use' ]]; then
      rm -f "${ENI_FILE}"
      return 1
    fi
    MAC_ADDRESS="$(jq -r '.MacAddress' "${ENI_FILE}")"
    rm -f "${ENI_FILE}"
    ip -o link | awk '$2 != "lo:" {print $2, $(NF-2)}' | grep -m 1 "${MAC_ADDRESS}" | cut -d ':' -f1
}

function attach_eni() {
  local INSTANCE_ID="${1}"
  local ENI_ID="${2}"
  local OLD_INTERFACE REGION status attachment_id NEW_INTERFACE

  OLD_INTERFACE=$(get_default_interface)
  REGION=$(get_region)
  status=$(aws ec2 describe-network-interfaces --region "${REGION}" \
                 --network-interface-ids "${ENI_ID}" \
                 --query 'NetworkInterfaces[0].Status' --output text)

  if [ "${status}" == "in-use" ]; then
    attachment_id=$(aws ec2 describe-network-interfaces --region "${REGION}" \
                         --network-interface-ids "${ENI_ID}" \
                         --query 'NetworkInterfaces[0].Attachment.AttachmentId' \
                         --output text)
    aws ec2 detach-network-interface --region "${REGION}" \
                                     --attachment-id "${attachment_id}" \
                                     --force
  fi

  until [ "${status}" == "available" ]; do
      status=$(aws ec2 describe-network-interfaces --region "${REGION}" \
               --network-interface-ids "${ENI_ID}" \
               --query 'NetworkInterfaces[0].Status' \
               --output text) || sleep 1
      sleep 1
  done

  aws ec2 attach-network-interface --region "${REGION}" \
                                   --instance-id "${INSTANCE_ID}" \
                                   --network-interface-id "${ENI_ID}" \
                                   --device-index 1

  until [ "${status}" == "in-use" ]; do
      status=$(aws ec2 describe-network-interfaces --region "${REGION}" \
               --network-interface-ids "${ENI_ID}" \
               --query 'NetworkInterfaces[0].Status' \
               --output text) || sleep 1
      sleep 1
  done

  NEW_INTERFACE=$(get_eni_interface "${ENI_ID}")

  until /sbin/ip link show dev "${NEW_INTERFACE}" &>/dev/null; do
      sleep 1
  done

  echo "Attachment: region=${REGION}, instance-id=${INSTANCE_ID}, eni=${ENI_ID}"

  until [ "$(</sys/class/net/"${NEW_INTERFACE}"/operstate)" == "up" ]; do
      sleep 1
  done

  sed -i -e 's/ONBOOT=yes/ONBOOT=no/' "/etc/sysconfig/network-scripts/ifcfg-${OLD_INTERFACE}"
  sed -i -e 's/BOOTPROTO=dhcp/BOOTPROTO=none/' "/etc/sysconfig/network-scripts/ifcfg-${OLD_INTERFACE}"
  ifdown "${OLD_INTERFACE}"
  sed -e "s/${OLD_INTERFACE}/${NEW_INTERFACE}/g" "/etc/sysconfig/network-scripts/route-${OLD_INTERFACE}" >> "/etc/sysconfig/network-scripts/route-${NEW_INTERFACE}"
  echo > "/etc/sysconfig/network-scripts/route-${OLD_INTERFACE}"
  service network restart
}

function attach_ebs() {
  # Forcibly attaches a volume to an instance
  local INSTANCE_ID="${1}"
  local VOLUME_ID="${2}"
  local DEVICE="${3}"
  local REGION vol_state attached_instance_id status

  REGION=$(get_region)
  attached_instance_id=""
  if ! vol_state=$(aws ec2 describe-volumes --region "${REGION}" \
                --volume-ids "${VOLUME_ID}" \
                --query 'Volumes[0].Attachments' \
                --output text)
  then
    echo "ERROR: Volume ${VOLUME_ID} not found"
    return 1
  fi

  if [ -n "${vol_state}" ]; then
    # Volume is currently attached. Detach if necessary
    attached_instance_id="$(awk '{print $4}' <<<"${vol_state}")"
    if [ "${attached_instance_id}" == "${INSTANCE_ID}" ]; then
      echo "Volume ${VOLUME_ID} is already attached to ${INSTANCE_ID}"
      return 0
    fi
    # forcibly detach
    echo "Detaching ${VOLUME_ID}..."
    if ! aws ec2 detach-volume --region "${REGION}" \
        --force \
        --volume-id "${VOLUME_ID}"
    then
      echo "ERROR: Detaching volume ${VOLUME_ID}."
      return 1
    fi
    until [ -z "${vol_state}" ]; do
      vol_state=$(aws ec2 describe-volumes --region "${REGION}" \
                          --volume-ids "${VOLUME_ID}" \
                          --query 'Volumes[0].Attachments' \
                          --output text)
      echo "Waiting on detaching ${VOLUME_ID}..."
      sleep 1
    done
  fi

  # Attach
  echo "Attaching ${VOLUME_ID}..."
  if ! aws ec2 attach-volume --region "${REGION}" \
      --instance-id "${INSTANCE_ID}" \
      --volume-id "${VOLUME_ID}" \
      --device "${DEVICE}"
  then
    echo "ERROR: Attaching volume ${VOLUME_ID}."
    return 1
  fi
  until [ "${attached_instance_id}" == "${INSTANCE_ID}" ]; do
    vol_state=$(aws ec2 describe-volumes --region "${REGION}" \
                        --volume-ids "${VOLUME_ID}" \
                        --query 'Volumes[0].Attachments' --output text)
    attached_instance_id=$(awk '{print $4}' <<<"${vol_state}")
    echo "Waiting on attaching ${VOLUME_ID}..."
    sleep 1
  done
  until [ -b "${DEVICE}" ]; do
    echo "Waiting for Linux to recognize ${DEVICE}..."
    sleep 1
  done
  echo "Volume ${VOLUME_ID} attached to ${INSTANCE_ID} at ${DEVICE}."
  return 0
}

function update_route53() {
  local DEFAULT_INTERFACE INTERNAL_IP TXN_FILE
  DEFAULT_INTERFACE=$(get_default_interface)
  INTERNAL_IP=$(get_ip_from_interface "${DEFAULT_INTERFACE}")

  local HOSTED_ZONE_ID="${1}"
  local RRSET_NAME="${2}"
  local IP="${3-$INTERNAL_IP}" # Override IP address if specified

  TXN_FILE=$(mktemp -t -u "r53-dns-transaction.XXXX.json")

  cat <<EOF > "${TXN_FILE}"
{
  "Comment": "Update ${RRSET_NAME}",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${RRSET_NAME}.",
        "Type": "A",
        "TTL": 60,
        "ResourceRecords": [
          {
            "Value": "${IP}"
          }
        ]
      }
    }
  ]
}
EOF

  aws route53 change-resource-record-sets --hosted-zone-id "${HOSTED_ZONE_ID}" --change-batch file://"${TXN_FILE}"
  rm -f "${TXN_FILE}"
}

function get_ssm_param() {
  local PARAMETER_NAME="${1}"
  local REGION="${3:-$(get_region)}"
  aws ssm get-parameter --region "${REGION}" \
                        --name "${PARAMETER_NAME}" \
                        --with-decryption \
                        --output text \
                        --query 'Parameter.Value'
}

function get_secret() {
  local SECRET_ID="${1}"
  local REGION="${2:-$(get_region)}"
  local VALUE
  VALUE=$(aws secretsmanager --region "${REGION}" get-secret-value --secret-id "${SECRET_ID}" | jq --raw-output .SecretString)
  echo "${VALUE}"
}
