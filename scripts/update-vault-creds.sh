#!/bin/bash
set -e

# This script is for the ADMIN to run when Vault credentials need rotation.
# It does three things:
# 1. Accepts the new Root Token.
# 2. Generates new AppRole credentials (RoleID/SecretID) and saves them locally.
# 3. Adds the local credentials file to chezmoi for distribution.
# 4. Updates vault_vars.yml for future Ansible provisioning.

CHEZMOI_DIR=$(chezmoi source-path)
CREDS_FILE="$HOME/.vault-credentials"
ROLE_NAME="chezmoi-vm"
VAULT_VARS_FILE="vault_vars.yml"

echo "--- Vault Credential Updater ---"
echo "You are about to update the Vault credentials for the entire fleet."

# 1. Get the Root Token
if [ -f "temp_token.txt" ]; then
    echo "Reading token from temp_token.txt..."
    NEW_TOKEN=$(cat temp_token.txt)
    export VAULT_TOKEN="$NEW_TOKEN"
elif [ -z "${VAULT_TOKEN:-}" ]; then
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
if [ -z "${VAULT_ADDR:-}" ]; then
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
chezmoi add "$CREDS_FILE"

# 5. Update vault_vars.yml
echo "Updating vault_vars.yml with the new root token..."
if [ -f ".vault_pass" ]; then
    # Encrypt the token and replace in vault_vars.yml
    NEW_ENCRYPTED_BLOCK=$(ansible-vault encrypt_string --vault-password-file .vault_pass "$VAULT_TOKEN" --name vault_token)
    
    # Export for perl
    export NEW_ENCRYPTED_BLOCK
    perl -i -0777 -pe 's/^vault_token:.*?(\n(?=\S)|\Z)/$ENV{NEW_ENCRYPTED_BLOCK}\n/ms' "$VAULT_VARS_FILE"
    echo "vault_vars.yml updated and encrypted."
else
    echo "Warning: .vault_pass not found. Skipping vault_vars.yml update."
fi

echo "---------------------------------------------------"
echo "Success! New credentials are in $CREDS_FILE and added to chezmoi."
echo "Ansible vault_vars.yml has also been updated."
echo "Please commit and push your changes:"
echo "  chezmoi cd"
echo "  git commit -m 'chore: rotate vault credentials and update bootstrap token'"
echo "  git push"
echo "---------------------------------------------------"