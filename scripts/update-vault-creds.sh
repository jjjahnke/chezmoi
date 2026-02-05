#!/bin/bash
set -e

# This script is for the ADMIN to run when Vault credentials need rotation.
# It does three things:
# 1. Accepts the new Root Token.
# 2. Generates new AppRole credentials (RoleID/SecretID) and saves them locally.
# 3. Adds the local credentials file to chezmoi for distribution.

CHEZMOI_DIR=$(chezmoi source-path)
CREDS_FILE="$HOME/.vault-credentials"
ROLE_NAME="chezmoi-vm"
VAULT_VARS_FILE="vault_vars.yml"

echo "--- Vault Credential Updater ---"
echo "You are about to update the Vault credentials for the entire fleet."

# 1. Get the Root Token
if [ -z "$VAULT_TOKEN" ]; then
    read -s -p "Enter the NEW Vault Root Token (hvs...): " NEW_TOKEN
    echo ""
    if [ -z "$NEW_TOKEN" ]; then
        echo "Error: Token cannot be empty."
        exit 1
    fi
    export VAULT_TOKEN="$NEW_TOKEN"
else
    echo "Using VAULT_TOKEN from environment."
fi

# 2. Verify Token & Connection
echo "Verifying connection to Vault..."
# Get VAULT_ADDR from config if not set
if [ -z "$VAULT_ADDR" ]; then
    VAULT_ADDR_LINE=$(grep 'vault_addr' "$CHEZMOI_DIR/.chezmoidata.toml")
    export VAULT_ADDR=$(echo "$VAULT_ADDR_LINE" | sed -n 's/.*vault_addr *= *"\([^"]*\)".*/\1/p')
fi
echo "Target: $VAULT_ADDR"

if ! vault token lookup >/dev/null 2>&1; then
    echo "Error: Invalid Token or Vault unreachable."
    exit 1
fi
echo "Connection verified."

# 3. Generate New Credentials
echo "Generating new AppRole credentials..."
ROLE_ID=$(vault read -format=json auth/approle/role/${ROLE_NAME}/role-id | jq -r .data.role_id)
SECRET_ID=$(vault write -f -format=json auth/approle/role/${ROLE_NAME}/secret-id | jq -r .data.secret_id)

echo "Writing to $CREDS_FILE..."
cat > "$CREDS_FILE" <<EOF
# This file contains the AppRole credentials for Vault authentication.
# It is sourced by ~/.zprofile to enable automatic login.
export ROLE_ID="${ROLE_ID}"
export SECRET_ID="${SECRET_ID}"
EOF

# 4. Add to Chezmoi
echo "Adding to chezmoi..."
# Ensure it's not ignored (we might need to force it or remove from gitignore first)
# For now, we just add it.
chezmoi add "$CREDS_FILE"

echo "---------------------------------------------------"
echo "Success! New credentials are in $CREDS_FILE and added to chezmoi."
echo "Please commit and push your changes:"
echo "  chezmoi cd"
echo "  git commit -m 'chore: rotate vault credentials'"
echo "  git push"
echo "---------------------------------------------------"
