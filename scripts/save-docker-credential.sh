#!/bin/bash
#
# This script securely prompts for a Docker password/token and saves it to Vault.
# It requires the VAULT_ADDR and VAULT_TOKEN environment variables to be set.
#

set -eufo pipefail

# 1. Check for VAULT_ADDR
if [ -z "${VAULT_ADDR:-}" ]; then
    echo "Error: The VAULT_ADDR environment variable is not set."
    echo "Please set it to your Vault server's address."
    echo "Example: export VAULT_ADDR=\"http://192.168.150.210:30200\""
    exit 1
fi

# 2. Check for VAULT_TOKEN
if [ -z "${VAULT_TOKEN:-}" ]; then
    echo "Error: The VAULT_TOKEN environment variable is not set."
    echo "Please set it to your Vault token before running this script."
    echo "Example: export VAULT_TOKEN=\"s.YourRootToken\""
    exit 1
fi

# 3. Securely prompt for the password
echo -n "Please enter your Docker Password or Personal Access Token: "
read -s DOCKER_SECRET
echo

if [ -z "$DOCKER_SECRET" ]; then
    echo "Error: No secret was provided. Aborting."
    exit 1
fi

# 4. Define the Vault path
# This path should match the one used in the chezmoi script.
VAULT_PATH="secret/personal/docker"

# 5. Write the secret to Vault
echo "Saving credential to Vault at path: ${VAULT_PATH}"
vault kv put "${VAULT_PATH}" password="${DOCKER_SECRET}"

echo "Successfully saved the Docker credential to Vault."

