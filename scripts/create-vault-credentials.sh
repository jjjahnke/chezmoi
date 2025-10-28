#!/bin/bash
#
# This script generates the ~/.vault-credentials file required for chezmoi to
# authenticate with HashiCorp Vault via the AppRole method.
#
# It should be run once on a new machine during the bootstrapping process.
# It relies on the VAULT_ADDR and VAULT_TOKEN environment variables being set.
#
# USAGE:
#   VAULT_ADDR="<your-vault-addr>" VAULT_TOKEN="<your-vault-token>" ./scripts/create-vault-credentials.sh
#

set -e

# --- Configuration ---
# IMPORTANT: If your AppRole is not named 'dotfiles-approle', change this value.
APPROLE_NAME="chezmoi-vm"
CRED_FILE="$HOME/.vault-credentials"

# --- Environment Variable Validation ---
if [ -z "$VAULT_ADDR" ] || [ -z "$VAULT_TOKEN" ]; then
    echo "Error: VAULT_ADDR and VAULT_TOKEN must be set as environment variables." >&2
    echo "Usage: VAULT_ADDR=\"...\" VAULT_TOKEN=\"...\" $(basename "$0")" >&2
    exit 1
fi

echo "--> Using Vault server at $VAULT_ADDR..."
echo "--> Fetching RoleID for AppRole '$APPROLE_NAME'..."

# --- Fetch RoleID ---
ROLE_ID=$(vault read -format=json "auth/approle/role/$APPROLE_NAME/role-id" | jq -r .data.role_id)

if [ -z "$ROLE_ID" ] || [ "$ROLE_ID" == "null" ]; then
  echo "Error: Could not fetch the RoleID." >&2
  echo "Please check that your VAULT_ADDR is correct, your token is valid, and the AppRole name '$APPROLE_NAME' exists." >&2
  exit 1
fi

echo "--> RoleID fetched successfully."
echo "--> Generating a new SecretID..."

# --- Generate SecretID ---
SECRET_ID=$(vault write -f -format=json "auth/approle/role/$APPROLE_NAME/secret-id" | jq -r .data.secret_id)

if [ -z "$SECRET_ID" ] || [ "$SECRET_ID" == "null" ]; then
  echo "Error: Could not generate a new SecretID." >&2
  echo "Please check that your token has the correct permissions." >&2
  exit 1
fi

echo "--> SecretID generated successfully."
echo "--> Creating credentials file at $CRED_FILE..."

# --- Create Credentials File ---
cat > "$CRED_FILE" <<EOF
# This file contains the AppRole credentials for Vault authentication.
# It is sourced by ~/.zprofile to enable automatic login.
export ROLE_ID="$ROLE_ID"
export SECRET_ID="$SECRET_ID"
EOF

# --- Set Secure Permissions ---
chmod 600 "$CRED_FILE"

echo "✅ Successfully created and secured $CRED_FILE."
echo "You can now open a new terminal tab to automatically log in to Vault."
