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

# --- Secure, Non-Interactive Ansible Vault Execution ---

# 1. Create the temporary vault password file.
echo "password" > vault_pass.txt

echo "Running Ansible playbook against: $INVENTORY"

# 2. Set Host Key Checking to False for ephemeral machines.
export ANSIBLE_HOST_KEY_CHECKING=False

# 3. Execute the playbook.
ansible-playbook -i "$INVENTORY" install_git.yml --user jahnke --vault-password-file vault_pass.txt

# 4. Clean up the temporary password file immediately.
rm vault_pass.txt

echo "Playbook execution finished."

echo "Playbook execution finished."
