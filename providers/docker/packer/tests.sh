#!/usr/bin/env bash
set -xeuo pipefail
IFS=$'\n\t'

DATADOG_VERSION='7.33.1'

if ! grep -q  "${DATADOG_VERSION}" <(yum versionlock list); then
  echo "Datadog is NOT locked to version ${DATADOG_VERSION}"
  exit 1
fi

if ! grep -q "${DATADOG_VERSION}" <(datadog-agent version); then
  echo "Installed datadog is NOT version ${DATADOG_VERSION}"
  exit 1
fi
