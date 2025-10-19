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

# Create the vault password file
echo "password" > vault_pass.txt

# Clone the repository to a temporary directory
git clone https://github.com/jjjahnke/chezmoi.git /tmp/chezmoi

# Execute the playbook from the local clone
ansible-playbook -i "$INVENTORY" /tmp/chezmoi/install_git.yml --user jahnke --vault-password-file vault_pass.txt

# Clean up the password file
rm vault_pass.txt

echo "Playbook execution finished."
