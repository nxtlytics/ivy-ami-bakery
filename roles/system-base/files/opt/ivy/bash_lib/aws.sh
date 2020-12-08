#!/bin/echo "This is a library, please source it from another script"

##
## aws.sh
## AWS-specific modules for Ivy
##
## Use this script by sourcing the parent `bash_functions.sh` script.
##


# Prevent direct sourcing of this module
if [[ -z "${IVY}" ]]; then
    echo "WARNING: Script '$(basename ${BASH_SOURCE})' was incorrectly sourced. Please do not source it directly."
    return 255
fi

function get_instance_id() {
    echo $(curl --retry 3 --silent --fail http://169.254.169.254/latest/meta-data/instance-id)
}

function get_availability_zone() {
    echo $(curl --retry 3 --silent --fail http://169.254.169.254/latest/meta-data/placement/availability-zone)
}

function get_region() {
    local availability_zone=$(get_availability_zone)
    echo ${availability_zone%?}
}

function get_environment() {
    local REGION=$(get_region)
    local INSTANCE_ID=$(get_instance_id)

    echo $(aws ec2 describe-instances --region ${REGION} \
                                      --instance-id ${INSTANCE_ID} \
                                      --query "Reservations[0].Instances[0].Tags[?Key==\`$(get_ivy_tag):sysenv\`].Value" \
                                      --output text)
}

function get_service() {
    local REGION=$(get_region)
    local INSTANCE_ID=$(get_instance_id)

    echo $(aws ec2 describe-instances --region ${REGION} \
                                      --instance-id ${INSTANCE_ID} \
                                      --query "Reservations[0].Instances[0].Tags[?Key==\`$(get_ivy_tag):service\`].Value" \
                                      --output text)
}

function get_role() {
    local REGION=$(get_region)
    local INSTANCE_ID=$(get_instance_id)

    echo $(aws ec2 describe-instances --region ${REGION} \
                                      --instance-id ${INSTANCE_ID} \
                                      --query "Reservations[0].Instances[0].Tags[?Key==\`$(get_ivy_tag):role\`].Value" \
                                      --output text)
}

function get_group() {
    local REGION=$(get_region)
    local INSTANCE_ID=$(get_instance_id)

    echo $(aws ec2 describe-instances --region ${REGION} \
                                      --instance-id ${INSTANCE_ID} \
                                      --query "Reservations[0].Instances[0].Tags[?Key==\`$(get_ivy_tag):group\`].Value" \
                                      --output text)
}

function get_tags() {
    local SEPARATOR="${1:- }"
    local REGION=$(get_region)
    local INSTANCE_ID=$(get_instance_id)
    echo $(aws ec2 describe-tags --region ${REGION} \
                                 --filters "Name=resource-id,Values=${INSTANCE_ID}" \
                                 --query 'Tags[*].[@.Key, @.Value]' \
                                 --output text | sed -e 's/\s\+/:/g' | tr '\n' "${SEPARATOR}")
}

function get_eni_id() {
    local ENI_ROLE=$1
    local SERVICE=$2

    local REGION=$(get_region)
    local ENV=$(get_environment)
    local TAG=$(get_ivy_tag)
    echo $(aws ec2 describe-network-interfaces --region ${REGION} \
           --filters Name=tag:"${TAG}:sysenv",Values="${ENV}" \
                     Name=tag:"${TAG}:role",Values="${ENI_ROLE}" \
                     Name=tag:"${TAG}:service",Values="${SERVICE}" \
           --query 'NetworkInterfaces[0].NetworkInterfaceId' \
           --output text)
}

function get_eni_ip() {
    local ENI_ID=$1

    local REGION=$(get_region)
    echo $(aws ec2 describe-network-interfaces --region ${REGION} \
           --network-interface-ids ${ENI_ID} \
           --query 'NetworkInterfaces[0].PrivateIpAddress' \
           --output text)
}

function get_eni_public_ip() {
    local ENI_ID=$1

    local REGION=$(get_region)
    echo $(aws ec2 describe-network-interfaces --region ${REGION} \
           --network-interface-ids ${ENI_ID} \
           --query 'NetworkInterfaces[0].Association.PublicIp' \
           --output text)
}

function get_eni_private_dns_name() {
    local ENI_ID=$1

    local REGION=$(get_region)
    echo $(aws ec2 describe-network-interfaces --region ${REGION} \
           --network-interface-ids ${ENI_ID} \
           --query 'NetworkInterfaces[0].PrivateDnsName' \
           --output text)
}

function get_eni_interface() {
    local ENI_ID="${1}"
    local REGION="$(get_region)"
    local ENI_FILE=$(mktemp -t -u "ENI.XXXX.json")
    echo "$(aws ec2 describe-network-interfaces --region ${REGION} --network-interface-ids ${ENI_ID} --query 'NetworkInterfaces[0]' --output json)" &> "${ENI_FILE}"
    local ENI_STATUS="$(jq -r '.Status' ${ENI_FILE})"
    if [[ "${ENI_STATUS}" != 'in-use' ]]; then
      return 1
    fi
    local MAC_ADDRESS="$(jq -r '.MacAddress' ${ENI_FILE})"
    rm -f "${ENI_FILE}"
    echo "$(ip -o link | awk '$2 != "lo:" {print $2, $(NF-2)}' | grep -m 1 "${MAC_ADDRESS}" | cut -d ':' -f1)"
}

function attach_eni() {
    local INSTANCE_ID=$1
    local ENI_ID=$2

    local OLD_INTERFACE=$(get_default_interface)
    local REGION=$(get_region)
    local ENI_IP=$(get_eni_ip ${ENI_ID})
    local status=$(aws ec2 describe-network-interfaces --region ${REGION} \
                   --network-interface-ids ${ENI_ID} \
                   --query 'NetworkInterfaces[0].Status' --output text)

    if [ "${status}" == "in-use" ]; then
      local attachment_id=$(aws ec2 describe-network-interfaces --region ${REGION} \
                           --network-interface-ids ${ENI_ID} \
                           --query 'NetworkInterfaces[0].Attachment.AttachmentId' --output text)
      aws ec2 detach-network-interface --region ${REGION} \
                                       --attachment-id ${attachment_id} --force
    fi

    until [ "${status}" == "available" ]; do
        status=$(aws ec2 describe-network-interfaces --region ${REGION} \
                 --network-interface-ids ${ENI_ID} \
                 --query 'NetworkInterfaces[0].Status' --output text) || sleep 1
        sleep 1
    done

    aws ec2 attach-network-interface --region ${REGION} \
                                     --instance-id ${INSTANCE_ID} \
                                     --network-interface-id ${ENI_ID} \
                                     --device-index 1

    until [ "${status}" == "in-use" ]; do
        status=$(aws ec2 describe-network-interfaces --region ${REGION} \
                 --network-interface-ids ${ENI_ID} \
                 --query 'NetworkInterfaces[0].Status' --output text) || sleep 1
        sleep 1
    done

    local NEW_INTERFACE=$(get_eni_interface ${ENI_ID})

    until /sbin/ip link show dev ${NEW_INTERFACE} &>/dev/null; do
        sleep 1
    done

    echo "Attachment: region=${REGION}, instance-id=${INSTANCE_ID}, eni=${ENI_ID}"

    until [ "$(</sys/class/net/${NEW_INTERFACE}/operstate)" == "up" ]; do
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
    local INSTANCE_ID=$1
    local VOLUME_ID=$2
    local DEVICE=$3

    local REGION=$(get_region)
    local vol_state=$(aws ec2 describe-volumes --region ${REGION} \
                        --volume-ids ${VOLUME_ID} \
                        --query 'Volumes[0].Attachments' --output text)
    local attached_instance_id=""

    if [ $? -ne 0 ]; then
        echo "ERROR: Volume ${VOLUME_ID} not found"
        return 1
    fi

    if [ -n "${vol_state}" ]; then
        # Volume is currently attached. Detach if necessary
        attached_instance_id=$(echo ${vol_state} | awk '{print $4}')
        local status=$(echo ${vol_state} | awk '{print $5}')
        if [ "${attached_instance_id}" == "${INSTANCE_ID}" ]; then
            echo "Volume ${VOLUME_ID} is already attached to ${INSTANCE_ID}"
            return 0
        fi
        # forcibly detach
        echo "Detaching ${VOLUME_ID}..."
        aws ec2 detach-volume --region ${REGION} --force --volume-id ${VOLUME_ID}
        if [ $? -ne 0 ]; then
            echo "ERROR: Detaching volume ${VOLUME_ID}."
            return 1
        fi
        until [ -z "${vol_state}" ]; do
            local vol_state=$(aws ec2 describe-volumes --region ${REGION} \
                                --volume-ids ${VOLUME_ID} \
                                --query 'Volumes[0].Attachments' --output text)
            echo "Waiting on detaching ${VOLUME_ID}..."
            sleep 1
        done
    fi

    # Attach
    echo "Attaching ${VOLUME_ID}..."
    aws ec2 attach-volume --region ${REGION} \
        --instance-id ${INSTANCE_ID} \
        --volume-id ${VOLUME_ID} \
        --device ${DEVICE}
    if [ $? -ne 0 ]; then
        echo "ERROR: Attaching volume ${VOLUME_ID}."
        return 1
    fi
    until [ "${attached_instance_id}" == "${INSTANCE_ID}" ]; do
        local vol_state=$(aws ec2 describe-volumes --region ${REGION} \
                            --volume-ids ${VOLUME_ID} \
                            --query 'Volumes[0].Attachments' --output text)
        local attached_instance_id=$(echo ${vol_state} | awk '{print $4}')
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
    local DEFAULT_INTERFACE=$(get_default_interface)
    local INTERNAL_IP=$(get_ip_from_interface ${DEFAULT_INTERFACE})

    local HOSTED_ZONE_ID=$1
    local RRSET_NAME=$2
    local IP=${3-$INTERNAL_IP} # Override IP address if specified

    local TXN_FILE=$(mktemp -t -u "r53-dns-transaction.XXXX.json")

    cat <<EOF > ${TXN_FILE}
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

    aws route53 change-resource-record-sets --hosted-zone-id ${HOSTED_ZONE_ID} --change-batch file://${TXN_FILE}
    rm -f ${TXN_FILE}
}
