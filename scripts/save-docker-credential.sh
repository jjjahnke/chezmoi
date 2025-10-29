#!/bin/bash
#
# This script securely prompts for Docker credentials, generates the required
# base64 auth token, and saves it to Vault.
# It requires the VAULT_ADDR and VAULT_TOKEN environment variables to be set.
#

set -eufo pipefail

# 1. Check for VAULT_ADDR and VAULT_TOKEN
if [ -z "${VAULT_ADDR:-}" ] || [ -z "${VAULT_TOKEN:-}" ]; then
    echo "Error: VAULT_ADDR and VAULT_TOKEN environment variables must be set."
    exit 1
fi

# 2. Prompt for credentials
echo -n "Enter your Docker Username: "
read DOCKER_USERNAME

if [ -z "$DOCKER_USERNAME" ]; then
    echo "Error: Username cannot be empty."
    exit 1
fi

echo -n "Enter your Docker Password or Personal Access Token: "
read -s DOCKER_SECRET
echo

if [ -z "$DOCKER_SECRET" ]; then
    echo "Error: No secret was provided. Aborting."
    exit 1
fi

# 3. Generate the base64 auth token
AUTH_TOKEN=$(echo -n "${DOCKER_USERNAME}:${DOCKER_SECRET}" | base64)

# 4. Define the Vault path
VAULT_PATH="secret/personal/docker"

# 5. Write the secret to Vault
echo "Saving credential to Vault at path: ${VAULT_PATH}"
vault kv put "${VAULT_PATH}" auth="${AUTH_TOKEN}"

echo "Successfully saved the Docker auth token to Vault."

