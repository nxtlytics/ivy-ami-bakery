#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Ensure dependencies are present
if [[ ! -x $(which docker) ]]; then
    echo "[-] Dependencies unmet.  Please verify that the following are installed and in the PATH:  docker" >&2
    exit 1
fi

if [[ -e /root/gostatsd ]]; then
  echo "gostatsd has been downloaded already, if you want to download a new version"
  echo "delete the current one at /root/gostatsd"
  /root/gostatsd --version
  exit 0
fi

echo "Changing directory to /root/"
cd /root/
echo "Downloading gostatsd using docker (you need to be able to run docker commands)"
docker run --rm -v $(pwd):/output atlassianlabs/gostatsd:28.3.0 /bin/bash -c "cp /bin/gostatsd /output"
chmod 0755 gostatsd
echo "Downloading gostatsd"
./gostatsd --version
echo "Returning to previous directory"
cd -
