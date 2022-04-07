#!/bin/bash
set -x
set -e

# shellcheck disable=SC1091
source ./providers/universal/images/default/packer.env
# shellcheck disable=SC1091
source ./providers/universal/images/ivy-kubernetes-1.21/packer.env

packer build ./providers/universal/packer/universal-qemu.pkr.hcl
