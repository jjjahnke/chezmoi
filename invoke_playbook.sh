#!/bin/bash

set -e

# Check if at least one IP address is provided
if [ "$#" -eq 0 ]; then
  echo "Usage: $0 <ip_address1> [ip_address2]..."
  exit 1
fi

# Build the inventory string from all arguments.
INVENTORY=""
for ip in "$@"; do
  INVENTORY="$INVENTORY$ip,"
done

# --- Secure Ansible Vault Execution ---

VAULT_PASS_ARGS=""
if [ -f ".vault_pass" ]; then
  echo "Using .vault_pass file for Ansible Vault password."
  VAULT_PASS_ARGS="--vault-password-file .vault_pass"
else
  echo "No .vault_pass file found."
  VAULT_PASS_ARGS="--ask-vault-pass"
fi

echo "Running Ansible playbook against: $INVENTORY"

# Set Host Key Checking to False for ephemeral machines.
export ANSIBLE_HOST_KEY_CHECKING=False

# Execute the playbook.
ansible-playbook -i "$INVENTORY" install_git.yml --user jahnke $VAULT_PASS_ARGS

echo "Playbook execution finished."

