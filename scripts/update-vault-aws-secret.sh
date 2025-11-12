#!/bin/bash
#
# This script updates a secret in HashiCorp Vault by adding a new key-value
# pair without overwriting existing data.
#
# It fetches the existing secret, extracts its keys, and then writes the
# entire secret back with the new key-value pair appended.

# --- Pre-flight Check ---
if [ -z "${VAULT_ADDR:-}" ] || [ -z "${VAULT_TOKEN:-}" ]; then
  echo "Error: VAULT_ADDR and VAULT_TOKEN environment variables must be set."
  exit 1
fi

# -----------------------------------------------------------------------------
# PLEASE REPLACE THIS PLACEHOLDER VALUE
# -----------------------------------------------------------------------------
AWS_ACCOUNT_ID="AWS_ACCOUNT_ID"           # Your 12-digit AWS Account ID
# -----------------------------------------------------------------------------

set -e

SECRET_PATH="secret/personal/aws/default"

echo "--> Fetching existing secret from Vault..."

# 1. Use the local vault CLI to fetch the secret
EXISTING_SECRET_JSON=$(vault kv get -format=json "$SECRET_PATH")

# 2. Extract the existing keys using jq
ACCESS_KEY_ID=$(echo "$EXISTING_SECRET_JSON" | jq -r .data.data.AccessKeyID)
SECRET_ACCESS_KEY=$(echo "$EXISTING_SECRET_JSON" | jq -r .data.data.SecretAccessKey)

# 3. Check that the keys were retrieved successfully
if [ -z "$ACCESS_KEY_ID" ] || [ "$ACCESS_KEY_ID" == "null" ] || [ -z "$SECRET_ACCESS_KEY" ] || [ "$SECRET_ACCESS_KEY" == "null" ]; then
  echo "Error: Could not retrieve existing AccessKeyID or SecretAccessKey from Vault."
  echo "Please check the secret path and try again."
  exit 1
fi

echo "--> Existing keys found. Writing secret back with new AccountID..."

# 4. Use the local vault CLI to write back the old keys along with the new AccountID.
vault kv put "$SECRET_PATH" \
  AccessKeyID="$ACCESS_KEY_ID" \
  SecretAccessKey="$SECRET_ACCESS_KEY" \
  AccountID="$AWS_ACCOUNT_ID"

echo "✅ Successfully updated the secret at '$SECRET_PATH'."
