#!/bin/bash
#
# This script updates a secret in HashiCorp Vault (running in Kubernetes)
# by adding a new key-value pair without overwriting existing data.
#
# It fetches the existing secret, extracts its keys, and then writes the
# entire secret back with the new key-value pair appended.

# --- Pre-flight Check ---
if [ -z "$VAULT_TOKEN" ]; then
  echo "Error: The VAULT_TOKEN environment variable is not set."
  echo "Please export your Vault token before running this script."
  exit 1
fi

# -----------------------------------------------------------------------------
# PLEASE REPLACE THESE THREE PLACEHOLDER VALUES
# -----------------------------------------------------------------------------
VAULT_POD_NAME="vault-0"                  # The name of your Vault pod in Kubernetes
VAULT_NAMESPACE="vault"                   # The namespace where your Vault pod is running
AWS_ACCOUNT_ID="AWS_ACCOUNT_ID"           # Your 12-digit AWS Account ID
# -----------------------------------------------------------------------------

set -e

SECRET_PATH="secret/personal/aws/default"

echo "--> Fetching existing secret from Vault pod '$VAULT_POD_NAME'..."

# 1. Use kubectl to execute 'vault kv get' inside the pod and fetch the secret
#    We pass the local VAULT_TOKEN to authenticate as the user.
EXISTING_SECRET_JSON=$(kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD_NAME" -- env VAULT_TOKEN="$VAULT_TOKEN" vault kv get -format=json "$SECRET_PATH")

# 2. Extract the existing keys using jq
ACCESS_KEY_ID=$(echo "$EXISTING_SECRET_JSON" | jq -r .data.data.AccessKeyID)
SECRET_ACCESS_KEY=$(echo "$EXISTING_SECRET_JSON" | jq -r .data.data.SecretAccessKey)

# 3. Check that the keys were retrieved successfully
if [ -z "$ACCESS_KEY_ID" ] || [ "$ACCESS_KEY_ID" == "null" ] || [ -z "$SECRET_ACCESS_KEY" ] || [ "$SECRET_ACCESS_KEY" == "null" ]; then
  echo "Error: Could not retrieve existing AccessKeyID or SecretAccessKey from Vault."
  echo "Please check the secret path, pod name, and namespace and try again."
  exit 1
fi

echo "--> Existing keys found. Writing secret back with new AccountID..."

# 4. Use kubectl to execute 'vault kv put' inside the pod, writing back the old
#    keys along with the new AccountID.
kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD_NAME" -- \
  env VAULT_TOKEN="$VAULT_TOKEN" \
  vault kv put "$SECRET_PATH" \
  AccessKeyID="$ACCESS_KEY_ID" \
  SecretAccessKey="$SECRET_ACCESS_KEY" \
  AccountID="$AWS_ACCOUNT_ID"

echo "✅ Successfully updated the secret at '$SECRET_PATH'."
