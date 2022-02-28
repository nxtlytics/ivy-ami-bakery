#!/bin/bash

# This script tries to detect ec2 ephemeral volumes
# and turn them all into a single RAIDed device
# mounted at /mnt

METADATA_URL_BASE="http://169.254.169.254/2012-01-12"
root_drive=$(df -h | grep -v 'grep' | awk 'NR==2{print $1}')

if [ "${root_drive}" == '/dev/xvda1' ]; then
  echo "Detected 'xvd' drive naming scheme (root: ${root_drive})"
  DRIVE_SCHEME='xvd'
else
  echo "Detected 'sd' drive naming scheme (root: ${root_drive})"
  DRIVE_SCHEME='sd'
fi

drives=''
ephemeral_count=0
declare -a ephemerals
mapfile -t ephemerals < <(grep 'ephemeral' <(curl --silent "${METADATA_URL_BASE}/meta-data/block-device-mapping/"))

for e in "${ephemerals[@]}"; do
  echo "Probing ${e} .."
  device_name="$(curl --silent "${METADATA_URL_BASE}/meta-data/block-device-mapping/${e}")"
  # might have to convert 'sdb' -> 'xvdb'
  # shellcheck disable=SC2001
  device_name="$(sed "s/sd/$DRIVE_SCHEME/" <<<"${device_name}")"
  device_path="/dev/${device_name}"
  if [ -b "${device_path}" ]; then
    echo "Detected ephemeral disk: ${device_path}"
    drives="${drives} ${device_path}"
    ephemeral_count=$((ephemeral_count + 1 ))
  else
    echo "Ephemeral disk ${e}, ${device_path} is not present. skipping"
  fi
done

if [ "${ephemeral_count}" -gt 0 ]; then
    partprobe
    udevadm control --stop-exec-queue
    # shellcheck disable=SC2086
    mdadm --create --force --run --verbose /dev/md0 --name=RAID --level=0 -c256 --raid-devices=${ephemeral_count} ${drives}
    udevadm control --start-exec-queue
    mkfs.ext4 -L RAID /dev/md0
    mount -t ext4 -o noatime LABEL=RAID /mnt
    echo "LABEL=RAID /mnt ext4 noatime 0 0" | tee -a /etc/fstab
else
    echo "No ephemeral disk detected."
fi
