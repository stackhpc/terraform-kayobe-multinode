#!/bin/bash

# This script performs a complete multi-node cluster deployment.

set -eux
set -o pipefail

# Check for dependencies
if ! type tofu; then
  echo "Unable to find OpenTofu"
  exit 1
fi
if ! type ansible; then
  echo "Unable to find Ansible"
  exit 1
fi

# Deploy infrastructure using OpenTofu.
tofu plan
tofu apply -auto-approve

# Configure the Ansible control host.
ansible-playbook -i ansible/inventory.yml ansible/configure-hosts.yml

# Deploy OpenStack.
ansible-playbook -i ansible/inventory.yml ansible/deploy-openstack.yml
