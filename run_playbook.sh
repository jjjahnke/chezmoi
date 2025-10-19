#!/bin/bash

set -e

# Check if at least one IP address is provided
if [ "$#" -eq 0 ]; then
  echo "Usage: $0 <ip_address1> [ip_address2]..."
  exit 1
fi

# Build the inventory string from all arguments.
# Ansible requires a trailing comma for a single host.
INVENTORY=""
for ip in "$@"; do
  INVENTORY="$INVENTORY$ip,"
done

echo "Running Ansible playbook against: $INVENTORY"

# Disable host key checking for ephemeral machines
export ANSIBLE_HOST_KEY_CHECKING=False

# Execute the playbook
ansible-playbook -i "$INVENTORY" install_git.yml --user jahnke --vault-password-file vault_pass.txt

echo "Playbook execution finished."
