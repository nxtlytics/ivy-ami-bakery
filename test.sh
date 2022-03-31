#!/bin/bash
set -x
set -e

source ./providers/universal/images/default/packer.env
source ./providers/universal/images/ivy-kubernetes-1.21/packer.env

./bin/packer build ./providers/universal/packer/universal-qemu.pkr.hcl