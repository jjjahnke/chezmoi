#!/bin/bash
#
# This script automates the process of updating the encrypted 'vault_token'
# in the vault_vars.yml file using command-line arguments.
#
# WARNING: Passing secrets as command-line arguments can be insecure.
# They may be visible in your shell history and the system's process list.
#
# USAGE:
# ./scripts/update-ansible-vault-token.sh "your_ansible_vault_password" "s.YourNewRootToken"
#

set -eufo pipefail

VAULT_VARS_FILE="vault_vars.yml"
TEMP_PASS_FILE=$(mktemp)

# Ensure the temp file is cleaned up on exit
trap 'rm -f "$TEMP_PASS_FILE"' EXIT

# --- Argument Validation ---
if [ "$#" -ne 2 ]; then
    echo "Error: Invalid number of arguments."
    echo "Usage: $0 \"<ansible_vault_password>\" \"<new_hashicorp_root_token>\""
    exit 1
fi

ANSIBLE_VAULT_PASS=$1
NEW_ROOT_TOKEN=$2

echo "$ANSIBLE_VAULT_PASS" > "$TEMP_PASS_FILE"

# --- Encryption and Replacement ---

echo "Generating new encrypted vault_token..."

# Generate the new encrypted block. The output includes the variable name.
NEW_ENCRYPTED_BLOCK=$(ansible-vault encrypt_string --vault-password-file "$TEMP_PASS_FILE" "$NEW_ROOT_TOKEN" --name vault_token)

if [ $? -ne 0 ]; then
    echo "Error: ansible-vault command failed. Is ansible installed?"
    exit 1
fi

echo "Updating ${VAULT_VARS_FILE}..."

# Export the new block so Perl can access it safely
export NEW_ENCRYPTED_BLOCK

# Use Perl to replace the multi-line vault_token block.
# This matches 'vault_token:', the rest of that line, and all subsequent lines that start with whitespace.
perl -i -0777 -pe 's/^vault_token:.*?(\n(?=\S)|\Z)/$ENV{NEW_ENCRYPTED_BLOCK}\n/ms' "$VAULT_VARS_FILE"

# Remove the backup file created by sed
rm -f "${VAULT_VARS_FILE}.bak"

echo "Successfully updated the vault_token in ${VAULT_VARS_FILE}."
