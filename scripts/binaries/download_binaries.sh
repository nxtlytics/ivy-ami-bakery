#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Ensure dependencies are present
if [[ ! -x $(command -v git) || ! -x $(command -v docker) ]]; then
    echo "[-] Dependencies unmet.  Please verify that the following are installed and in the PATH:  git, docker" >&2
    exit 1
fi

GITROOT=$(git rev-parse --show-toplevel)
SYSTEM_BASE_FILES="${GITROOT}/roles/system-base/files/usr/local/bin"
declare -A BINARIES

# see https://github.com/iovisor/bpftrace/blob/master/INSTALL.md#copying-bpftrace-binary-from-docker
BINARIES=(
    ['gostatsd']='atlassianlabs/gostatsd:28.3.0'
    ['bpftrace']='quay.io/iovisor/bpftrace:master-vanilla_llvm_clang_glibc2.23'
)

mkdir -p "${SYSTEM_BASE_FILES}"

function download_if_not_present() {
    local BINARY="${1}"
    local DOCKER_IMAGE="${2}"
    if [[ -e "${SYSTEM_BASE_FILES}/${BINARY}" ]]; then
      echo "${BINARY} has been downloaded already, if you want to download a new version"
      echo "delete the current one at ${SYSTEM_BASE_FILES}/${BINARY}"
      exit 0
    fi

    echo "Downloading ${BINARY} using docker (you need to be able to run docker commands)"
    echo "${BINARY} will be at ${SYSTEM_BASE_FILES}/${BINARY}"
    docker run --rm -v ${SYSTEM_BASE_FILES}:/output "${DOCKER_IMAGE}" /bin/bash -c "cp /usr/bin/bpftrace /output"
    chmod 0755 "${SYSTEM_BASE_FILES}/${BINARY}"
    echo "Deleting docker image since the same tag might be reused"
    docker rmi "${DOCKER_IMAGE}"
}

for binary in "${!BINARIES[@]}"; do
    echo "binary is ${binary} and docker image is ${BINARIES[$binary]}"
    download_if_not_present "${binary}" "${BINARIES[$binary]}"
done
