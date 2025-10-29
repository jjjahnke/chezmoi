#!/bin/bash
#
# This script recursively lists all secret paths in a Vault KVv2 engine.
# It's a safe way to explore the structure of your secrets.
#
# USAGE:
# ./scripts/list-all-vault-secrets.sh [starting_path]
#
# EXAMPLE (to list everything in the 'secret' engine):
# ./scripts/list-all-vault-secrets.sh secret/
#

set -eufo pipefail

# This function is called recursively
list_secrets() {
    local path=$1
    # The '|| true' prevents the script from exiting if a path is empty
    local keys=$(vault kv list -format=json "$path" 2>/dev/null || true)

    # If there are no keys, stop recursing
    if [ -z "$keys" ] || [ "$keys" == "null" ]; then
        return
    fi

    # Use jq to reliably parse the JSON output
    echo "$keys" | jq -r '.[]' | while read -r key; do
        # If the key ends with a '/', it's a directory, so we go deeper
        if [[ "$key" == */ ]]; then
            list_secrets "${path}${key}"
        else
            # If it's a key, we print the full path to the secret
            echo "${path}${key}"
        fi
    done
}

# --- Script Start ---
START_PATH=${1:-secret/} # Default to 'secret/' if no argument is given

# Ensure the starting path ends with a slash for consistency
if [[ "$START_PATH" != */ ]]; then
    START_PATH="${START_PATH}/"
fi

echo "--- Recursively listing all secrets from '${START_PATH}' ---"
list_secrets "$START_PATH"
echo "--- End of list ---"
