#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Ensure dependencies are present
if ! command -v git &> /dev/null || ! command -v docker &> /dev/null; then
    echo "[-] Dependencies unmet.  Please verify that the following are installed and in the PATH:  git, docker" >&2
    exit 1
fi

GITROOT="$(git rev-parse --show-toplevel)"
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
    declare -a CHMOD_COMMAND=('chmod')

    if [[ "$EUID" -ne 0 ]]; then
      CHMOD_COMMAND=('sudo' 'chmod')
    fi

    if [[ -e "${SYSTEM_BASE_FILES}/${BINARY}" ]]; then
      echo "${BINARY} has been downloaded already, if you want to download a new version"
      echo "delete the current one at ${SYSTEM_BASE_FILES}/${BINARY}"
      return 0
    fi

    echo "Downloading ${BINARY} using docker (you need to be able to run docker commands)"
    echo "${BINARY} will be at ${SYSTEM_BASE_FILES}/${BINARY}"
    case ${BINARY} in

      gostatsd)
        docker run --rm -v "${SYSTEM_BASE_FILES}":/output -e BINARY="${BINARY}" \
            --entrypoint /bin/ash "${DOCKER_IMAGE}" -c 'cp $(which ${BINARY}) /output'
        ;;

      bpftrace)
        docker run --rm -v "${SYSTEM_BASE_FILES}":/output -e BINARY="${BINARY}" \
            "${DOCKER_IMAGE}" /bin/bash -c "cp /usr/bin/bpftrace /output"
        ;;

      *)
        echo "${BINARY} is not supported"
        return 1
        ;;
    esac
    "${CHMOD_COMMAND[@]}" 0755 "${SYSTEM_BASE_FILES}/${BINARY}"
    echo "Deleting docker image since the same tag might be reused"
    docker rmi "${DOCKER_IMAGE}"
}

for binary in "${!BINARIES[@]}"; do
    echo "binary is ${binary} and docker image is ${BINARIES[$binary]}"
    download_if_not_present "${binary}" "${BINARIES[$binary]}"
done
