#!/bin/bash
#
# This script performs a Vault AppRole login to get a temporary session token.
# It sources credentials from your existing chezmoi and .vault-credentials files.
#
# USAGE:
# You must SOURCE this script for it to set the environment variables in your
# current shell session.
#
#   source scripts/login-vault.sh
#
# After sourcing, you can run vault commands directly, e.g., `vault status`.

# --- Get VAULT_ADDR from chezmoi config ---
CHEZMOI_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." &> /dev/null && pwd )"
VAULT_ADDR_LINE=$(grep 'vault_addr' "${CHEZMOI_DIR}/.chezmoidata.toml")
if [ -z "$VAULT_ADDR_LINE" ]; then
    echo "Error: Could not find 'vault_addr' in .chezmoidata.toml"
    return 1
fi
export VAULT_ADDR=$(echo "$VAULT_ADDR_LINE" | sed -n 's/.*vault_addr *= *"\([^"]*\)".*/\1/p')

# --- Get AppRole credentials ---
VAULT_CREDS_FILE="$HOME/.vault-credentials"
if [ ! -f "$VAULT_CREDS_FILE" ]; then
    echo "Error: Credential file not found at ${VAULT_CREDS_FILE}"
    return 1
fi
# Source the file to get ROLE_ID and SECRET_ID into the script's environment
source "$VAULT_CREDS_FILE"

if [ -z "${ROLE_ID:-}" ] || [ -z "${SECRET_ID:-}" ]; then
    echo "Error: ROLE_ID or SECRET_ID not found in ${VAULT_CREDS_FILE}"
    return 1
fi

# --- Perform AppRole Login ---
echo "Attempting Vault AppRole login for VAULT_ADDR: ${VAULT_ADDR}..."

# The login response is a JSON object. We need to capture it.
# We hide stderr temporarily in case of old token warnings.
login_response=$(vault write -format=json auth/approle/login role_id="${ROLE_ID}" secret_id="${SECRET_ID}" 2>/dev/null)

if [ $? -ne 0 ]; then
    echo "Error: Vault AppRole login failed. Please check your credentials and Vault server status."
    return 1
fi

# --- Export the Token ---
# Use jq to safely parse the token from the JSON response
export VAULT_TOKEN=$(echo "$login_response" | jq -r .auth.client_token)

if [ -z "$VAULT_TOKEN" ] || [ "$VAULT_TOKEN" == "null" ]; then
    echo "Error: Could not extract client token from Vault's response."
    echo "You may need to install 'jq'. On macOS: brew install jq"
    return 1
fi

echo "Vault login successful!"
echo "A temporary VAULT_TOKEN has been exported to your shell session."
echo "You can now use the 'vault' CLI."
