#!/usr/bin/env bash
set -e

##
## Cassandra Backup script
## This script can be used to set up a backup volume or run as a cron to backup cassandra
##
##

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

SCRIPTNAME="$(basename $0)"
PIDFILE="/var/run/${SCRIPTNAME}"

# lock the script
exec 200>${PIDFILE}
flock -n 200 || exit 1
PROCESSID=$$
echo ${PROCESSID} 1>&200

# Add path here because crond doesn't source amazon's environment
export PATH="$PATH:/opt/aws/bin/"
source /opt/ivy/bash_functions.sh

DATA_DEVICE='/dev/sdf'

# Cassandra snapshot name
SNAP_NAME="${SNAP_NAME:-cassandra-backup}"

TIMESTAMP=$(date +%Y%M%d-%H%m)
MY_INSTANCE_ID=$(get_instance_id)
MY_REGION=$(get_region)
MY_ROLE=$(aws ec2 describe-instances --region ${MY_REGION} --instance-ids ${MY_INSTANCE_ID} --query "Reservations[0].Instances[0].Tags[?Key==\`$(get_ivy_tag):role\`].{Value:Value}" --output text)
MY_SERVICE=$(aws ec2 describe-instances --region ${MY_REGION} --instance-ids ${MY_INSTANCE_ID} --query "Reservations[0].Instances[0].Tags[?Key==\`$(get_ivy_tag):service\`].{Value:Value}" --output text)

function show_help() {
    echo "${SCRIPTNAME} : run cassandra backups"
    echo "${SCRIPTNAME} cron                    - run the backup and snapshot of the local cassandra database"
    echo "${SCRIPTNAME} backup --name my-backup - run the backup and snapshot of the local cassandra database with a different name"
}

function clearsnapshot() {
  nodetool clearsnapshot -t ${SNAP_NAME}
}

function run_backup() {
    echo "[+] Running backup cron job at $(date)"
    set -x

    # remove old snapshots on exit
    trap clearsnapshot EXIT

    # make the snapshot
    nodetool snapshot -t ${SNAP_NAME}

    # find my ebs volume ID
    EBS_DATA_VOLUME_ID=$(aws ec2 describe-instances --region ${MY_REGION} --instance-ids $(get_instance_id) --query "Reservations[0].Instances[0].BlockDeviceMappings[?DeviceName==\`${DATA_DEVICE}\`].{id:Ebs.VolumeId}" --output text)
    if [ -z "${EBS_DATA_VOLUME_ID}" ]; then
        echo "ERROR: Unable to get cassandra data volume ID."
        exit 1
    fi

    # flush disk buffers
    sync

    # Snapshot the volume
    SNAPSHOT_ID=$(aws ec2 create-snapshot --region ${MY_REGION} --volume-id ${EBS_DATA_VOLUME_ID} --description "${TIMESTAMP} ${MY_ROLE} Backup - Snapshot Name: ${SNAP_NAME}" --output text --query "{ID:SnapshotId,STATE:State,VOLUME:VolumeId}" | awk '{print $1}')
    sleep 5

    # Tag it!
    aws ec2 create-tags --region ${MY_REGION} --resources ${SNAPSHOT_ID} --tags Key=Name,Value=${MY_ROLE} Key=$(get_ivy_tag):role,Value=${MY_ROLE} Key=$(get_ivy_tag):sysenv,Value=$(get_sysenv) Key=$(get_ivy_tag):service,Value=${MY_SERVICE}

    # Delete old snapshots
    CUTOFF_DAY=$(date -d 'now - 7 days' -u +"%Y-%m-%dT00:00:00.000Z")
    IFS=$'\n' && for snapshot in $(aws ec2 describe-snapshots                                                                                           \
        --region ${MY_REGION}                                                                                                                           \
        --filters Name=tag:"$(get_ivy_tag):sysenv",Values=$(get_sysenv) Name=tag:"$(get_ivy_tag):service",Values=${MY_SERVICE} Name=tag:"$(get_ivy_tag):role",Values=${MY_ROLE}   \
        --query 'Snapshots[*].[SnapshotId,StartTime]'                                                                                                   \
        --output text); do
            snapshot_id=$(echo $snapshot | awk '{print $1}')
            start_time=$(echo $snapshot | awk '{print $2}')
            if [[ "${start_time}" < "${CUTOFF_DAY}" ]]; then
                aws ec2 delete-snapshot --region ${MY_REGION} --snapshot-id ${snapshot_id}
            fi
    done

    set +x
    echo "[+] Finished running backup cron job at $(date)"
}

case "${1}" in
    cron)
        run_backup
        exit 0
        ;;
    backup)
        case "${2}" in
            --name)
                if [[ -n "${3}" ]]; then
                    SNAP_NAME="${3}"
                    run_backup
                    exit 0
                else
                    show_help
                    exit 1
                fi
                ;;
            *)
                show_help
                exit 1
                ;;
        esac
        ;;
    *)
        show_help
        exit 1
        ;;
esac
