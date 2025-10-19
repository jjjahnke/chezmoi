#!/bin/bash

set -e

# Check if at least one IP address is provided
if [ "$#" -eq 0 ]; then
  echo "Usage: $0 <ip_address1> [ip_address2]..."
  exit 1
fi

# The inventory can be a comma-separated list of hosts.
# A trailing comma is required if there is only one host.
INVENTORY="$1,"
shift
for ip in "$@"; do
  INVENTORY="$INVENTORY$ip,"
done

echo "Running Ansible playbook against: $INVENTORY"

# Disable host key checking for ephemeral machines
export ANSIBLE_HOST_KEY_CHECKING=False

# Execute the playbook
ansible-playbook -i "$INVENTORY" install_git.yml --user jahnke

echo "Playbook execution finished."
