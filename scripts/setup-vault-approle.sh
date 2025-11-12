#!/bin/bash
#
# This script sets up the necessary Vault AppRole and policy for chezmoi.
# It should be run once with a root or admin token after setting up a new
# Vault server.
#

set -eufo pipefail

# --- Environment Validation ---
if [ -z "${VAULT_ADDR:-}" ] || [ -z "${VAULT_TOKEN:-}" ]; then
    echo "Error: VAULT_ADDR and VAULT_TOKEN environment variables must be set."
    echo "Please run this with a root or admin token."
    exit 1
fi

# --- AppRole Enablement ---
# Enable the AppRole auth method if it's not already enabled.
if ! vault auth list | grep -q "approle/"; then
    echo "Enabling AppRole auth method..."
    vault auth enable approle
else
    echo "AppRole auth method is already enabled."
fi

# --- AppRole Creation ---
ROLE_NAME="chezmoi-vm"
POLICY_NAME="chezmoi-readonly"
echo "Creating AppRole role '${ROLE_NAME}' and attaching policy '${POLICY_NAME}'..."
# This command assumes that the '${POLICY_NAME}' policy has already been created
# by the repopulate_vault.sh script.
vault write auth/approle/role/"${ROLE_NAME}" \
    token_policies="${POLICY_NAME}" \
    token_ttl=1h \
    token_max_ttl=4h

# --- AppRole for Dev Containers ---
DEV_ROLE_NAME="dev-role"
echo "Creating AppRole role '${DEV_ROLE_NAME}' for dev containers..."
vault write auth/approle/role/"${DEV_ROLE_NAME}" \
    token_policies="${POLICY_NAME}" \
    token_ttl=1h \
    token_max_ttl=4h

echo "--- Vault AppRole setup complete ---"
