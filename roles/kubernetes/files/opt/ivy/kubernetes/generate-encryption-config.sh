#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)
ENCRYPTION_LOCATION="${1:-encryption-config.yaml}"

cat > "${ENCRYPTION_LOCATION}" <<EOF
kind: EncryptionConfig
apiVersion: v1
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENCRYPTION_KEY}
      - identity: {}
EOF
