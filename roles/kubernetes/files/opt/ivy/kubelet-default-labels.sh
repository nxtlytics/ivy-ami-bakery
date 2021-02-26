#!/bin/bash

source /opt/ivy/bash_functions.sh
set -e
set -o pipefail

if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
  cat <<EOT
Usage: $(basename $0) PATH

Write DEFAULT_NODE_LABELS to a file as specified by PATH in the format like:
  DEFAULT_NODE_LABELS='beta.kubernetes.io/instance-type=m4.xlarge,ivy/service=eks-agents'

The output file is sourced as an EnvironmentFile by the kubelet systemd unit

EOT
  exit 0
fi

OUT_FILE=$1

# Generate the node labels for the kubelet
NODE_LABELS=()

# Add the instance type labels
# beta.kubernetes.io/instance-type=t3.xlarge
# node.kubernetes.io/instance-type=t3.xlarge
instance_type_labels=( "beta.kubernetes.io/instance-type" "node.kubernetes.io/instance-type" )
for label in "${instance_type_labels[@]}"; do
  NODE_LABELS+=("${label}=$(get_instance_type)")
done

# Add the zone (availability zone) labels
# failure-domain.beta.kubernetes.io/zone=us-west-2c
# topology.kubernetes.io/zone=us-west-2c
az_labels=( "failure-domain.beta.kubernetes.io/zone" "topology.kubernetes.io/zone")
for label in "${az_labels[@]}"; do
  NODE_LABELS+=("${label}=$(get_availability_zone)")
done

# Add the region labels
# failure-domain.beta.kubernetes.io/region=us-west-2
# topology.kubernetes.io/region=us-west-2
region_labels=( "failure-domain.beta.kubernetes.io/region" "topology.kubernetes.io/region")
for label in "${region_labels[@]}"; do
  NODE_LABELS+=("${label}=$(get_region)")
done

# Add instance ID
NODE_LABELS+=("node.kubernetes.io/instance-id=$(get_instance_id)")

# Add all Ivy tags as labels to the node
ivy_tags=$(get_tags | tr " " "\n" | grep "$(get_ivy_tag)" | awk '{ split($0, tagspec, ":"); print tagspec[1] "/" tagspec[2] "=" tagspec[3];}')
for ivy_tag in ${ivy_tags}; do
  NODE_LABELS+=("${ivy_tag}")
done

# Write out our node labels to a file
NODE_LABEL_STR=$(IFS=,; echo "${NODE_LABELS[*]}")
cat <<EOT > ${OUT_FILE}
# Default node labels added by /opt/ivy/kubelet-default-labels.sh
DEFAULT_NODE_LABELS='${NODE_LABEL_STR}'
EOT