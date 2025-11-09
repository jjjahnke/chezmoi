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

# --- Policy Definition ---
POLICY_NAME="chezmoi-readonly"
echo "Writing '${POLICY_NAME}' policy..."
# This policy is sourced from the repopulate_vault.sh.tmpl script.
# It grants read-only access to all secrets managed by chezmoi.
vault policy write "${POLICY_NAME}" - <<EOF
# Allow reading all secrets required by chezmoi templates.
path "secret/data/personal/aws/default" { capabilities = ["read"] }
path "secret/data/personal/aws/rg" { capabilities = ["read"] }
path "secret/data/personal/aws/to" { capabilities = ["read"] }
path "secret/data/kube/personal/gpu-server" { capabilities = ["read"] }
path "secret/data/personal/api-keys" { capabilities = ["read"] }
path "secret/data/dev/api-keys" { capabilities = ["read"] }
path "secret/data/work/identity" { capabilities = ["read"] }
path "secret/data/personal/identity" { capabilities = ["read"] }
path "secret/data/dev/identity" { capabilities = ["read"] }
path "secret/data/personal/docker" { capabilities = ["read"] }
path "secret/data/kube/my-new-cluster" { capabilities = ["read"] }
path "secret/data/dev/myapplication" { capabilities = ["read"] }
path "secret/data/prod/postgres" { capabilities = ["read"] }
EOF

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
echo "Creating AppRole role '${ROLE_NAME}'..."
vault write auth/approle/role/"${ROLE_NAME}" \
    token_policies="${POLICY_NAME}" \
    token_ttl=1h \
    token_max_ttl=4h

echo "--- Vault AppRole setup complete ---"
