#!/bin/bash
# shellcheck disable=SC1091
source /opt/ivy/bash_functions.sh
OUT_FILE=$1

echo "PROVIDER_ID=$(get_provider_id)" > "${OUT_FILE}"
