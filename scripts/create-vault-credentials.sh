#!/bin/bash
#
# This script generates a new RoleID and SecretID for the chezmoi AppRole
# and saves them to ~/.vault-credentials for automatic login.
#
# It requires a token with privileges to read the AppRole configuration.
# A temporary root token is the easiest way to run this.
#

set -eufo pipefail

# --- Environment Validation ---
if [ -z "${VAULT_ADDR:-}" ] || [ -z "${VAULT_TOKEN:-}" ]; then
    echo "Error: VAULT_ADDR and VAULT_TOKEN environment variables must be set."
    exit 1
fi

ROLE_NAME="chezmoi-vm"
CREDS_FILE="$HOME/.vault-credentials"

echo "Fetching RoleID for '${ROLE_NAME}'..."
ROLE_ID=$(vault read -format=json auth/approle/role/${ROLE_NAME}/role-id | jq -r .data.role_id)

if [ -z "$ROLE_ID" ] || [ "$ROLE_ID" == "null" ]; then
    echo "Error: Could not fetch RoleID. Does the '${ROLE_NAME}' role exist?"
    echo "You may need to run 'scripts/setup-vault-approle.sh' first."
    exit 1
fi

echo "Generating a new SecretID..."
SECRET_ID=$(vault write -f -format=json auth/approle/role/${ROLE_NAME}/secret-id | jq -r .data.secret_id)

if [ -z "$SECRET_ID" ] || [ "$SECRET_ID" == "null" ]; then
    echo "Error: Could not generate SecretID."
    exit 1
fi

echo "Writing new credentials to ${CREDS_FILE}..."
cat > "${CREDS_FILE}" <<EOF
# This file contains the AppRole credentials for Vault authentication.
# It is sourced by ~/.zprofile to enable automatic login.
export ROLE_ID="${ROLE_ID}"
export SECRET_ID="${SECRET_ID}"
EOF

echo "Successfully created new credentials in ${CREDS_FILE}"
echo "Please open a new terminal session to use them."