#!/bin/bash
#
# This script adds a read capability for a given path to a Vault policy.
# It requires administrative privileges (a token that can write policies).
#
# USAGE:
# ./scripts/add-vault-policy-path.sh <policy_name> <vault_secret_path>
#
# EXAMPLE:
# ./scripts/add-vault-policy-path.sh chezmoi-readonly secret/data/personal/docker
#

set -eufo pipefail

# --- Input Validation ---
if [ "$#" -ne 2 ]; then
    echo "Error: Invalid number of arguments."
    echo "Usage: $0 <policy_name> <vault_secret_path>"
    exit 1
fi

POLICY_NAME=$1
VAULT_PATH=$2

# --- Environment Validation ---
if [ -z "${VAULT_ADDR:-}" ]; then
    echo "Error: The VAULT_ADDR environment variable is not set."
    exit 1
fi

if [ -z "${VAULT_TOKEN:-}" ]; then
    echo "Error: The VAULT_TOKEN environment variable is not set."
    echo "This script requires a token with privileges to write policies."
    exit 1
fi

# --- Logic ---
echo "Reading existing policy '${POLICY_NAME}'..."
EXISTING_POLICY=$(vault policy read "${POLICY_NAME}")

if [ $? -ne 0 ]; then
    echo "Error: Could not read policy '${POLICY_NAME}'. Does it exist?"
    exit 1
fi

# Check if the path already exists in the policy to avoid duplicates
if echo "$EXISTING_POLICY" | grep -q "path \"${VAULT_PATH}\"" ; then
    echo "Path \"${VAULT_PATH}\" already exists in policy '${POLICY_NAME}'. No changes needed."
    exit 0
fi

echo "Adding read capability for path \"${VAULT_PATH}\" to policy '${POLICY_NAME}'..."

# Construct the new policy rule
NEW_RULE=$(cat <<EOF

# Grant read access for ${VAULT_PATH}
path "${VAULT_PATH}" {
  capabilities = ["read"]
}
EOF
)

# Append the new rule and write the policy back to Vault using the robust syntax
{ echo "$EXISTING_POLICY"; echo "$NEW_RULE"; } | vault policy write "${POLICY_NAME}" -

if [ $? -eq 0 ]; then
    echo "Successfully updated policy '${POLICY_NAME}'."
else
    echo "Error: Failed to write updated policy '${POLICY_NAME}' to Vault."
    exit 1
fi
