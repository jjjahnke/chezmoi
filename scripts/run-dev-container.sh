#!/bin/bash
#
# run-dev-container.sh: Securely fetches a Vault token and starts the dev container.
#

set -euo pipefail

# --- Default Values ---
CONTAINER_NAME="dev-container-$(openssl rand -hex 3)"
IMAGE_NAME="jahnke/dev-env:latest"

# --- Help/Usage Function ---
usage() {
  cat <<EOF
Usage: $(basename "$0") --name <container-name> --image <image-name>

Starts the development container, securely injecting a Vault token.

OPTIONS:
  --name <name>    Required. The name for the new container.
  --image <image>  Required. The Docker image to run.
  -h, --help       Show this help message.

PREREQUISITES:
  - The 'vault' CLI must be installed and authenticated on the machine running this script.
  - A Vault AppRole named 'dev-role' must be configured for generating tokens.
EOF
  exit 1
}

# --- Argument Parsing ---
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --name)
      CONTAINER_NAME="$2"
      shift; shift
      ;;
    --image)
      IMAGE_NAME="$2"
      shift; shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown option: $1"
      usage
      ;;
  esac
done

# --- Prerequisite Check ---
if ! command -v vault &>/dev/null; then
  echo "Error: 'vault' CLI is not installed or not in your PATH." >&2
  exit 1
fi

# --- Main Logic ---
echo "--> Fetching temporary Vault token..."

# IMPORTANT: This assumes you have a Vault AppRole configured for this purpose.
# Adjust the role name and authentication method as needed for your setup.
VAULT_TOKEN=$(vault write -field=token auth/approle/role/dev-role/secret-id)

if [[ -z "$VAULT_TOKEN" ]]; then
  echo "Error: Failed to fetch a Vault token. Please check your Vault authentication." >&2
  exit 1
fi

echo "--> Starting container '$CONTAINER_NAME' from image '$IMAGE_NAME'..."

# Run the container, securely passing the token as an environment variable.
# The container will be removed automatically on exit (--rm).
docker run -it --rm \
  --name "$CONTAINER_NAME" \
  --env VAULT_TOKEN="$VAULT_TOKEN" \
  "$IMAGE_NAME"

echo "--> Container '$CONTAINER_NAME' has exited."
