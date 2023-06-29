#!/bin/bash
# This script is responsible for deploying OpenStack.
# It is intended that you run this script from an Ansible control host that has
# network access to the various nodes you intend to form your openstack environment.
# The Ansible control host must also have the following;
# - Kayobe config
# - OpenStack config
# - Virtual environments
#   -- kayobe
#   -- openstack
# - Vault password
# - Docker
# - RSA keypair which is authorised on the nodes
set -euxo pipefail

declare -A virtual_environments=(
  ["kayobe"]="$HOME/venvs/kayobe/bin/activate"
  ["openstack"]="$HOME/src/openstack-config/venv/bin/activate"
)

declare -A config_directories=(
  ["kayobe"]="$HOME/src/kayobe-config"
  ["openstack"]="$HOME/src/openstack-config"
)

function activate_virt_env () {
  set +u
  source $${virtual_environments[$1]}
  set -u
}

function activate_kayobe_env () {
  set +u
  source $${config_directories[kayobe]}/kayobe-env --environment ci-multinode
  set -u
}

activate_virt_env "kayobe"
activate_kayobe_env

set +x
export KAYOBE_VAULT_PASSWORD=$(cat ~/vault.password)
set -x

kayobe control host bootstrap
kayobe seed host configure
kayobe overcloud host configure
%{ if deploy_wazuh }kayobe infra vm host configure%{ endif }

kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/cephadm-deploy.yml
sleep 30
kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/cephadm.yml
kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/cephadm-gather-keys.yml

kayobe overcloud service deploy

%{ if deploy_wazuh }
kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/wazuh-secrets.yml
ansible-vault encrypt --vault-password-file ~/vault.password  $KAYOBE_CONFIG_PATH/environments/ci-multinode/wazuh-secrets.yml
kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/wazuh-manager.yml
kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/wazuh-agent.yml
%{ endif }

activate_virt_env "openstack"
activate_kayobe_env

set +x
source $${KOLLA_CONFIG_PATH}/public-openrc.sh
set -x

~/src/openstack-config/tools/openstack-config

git -C $${config_directories[kayobe]} submodule init
git -C $${config_directories[kayobe]} submodule update

if [[ "$(sudo docker image ls)" == *"kayobe"* ]]; then
  echo "Image already exists skipping docker build"
else
  sudo DOCKER_BUILDKIT=1 docker build --network host --file $${config_directories[kayobe]}/.automation/docker/kayobe/Dockerfile --tag kayobe:latest $${config_directories[kayobe]}
fi

set +x
export KAYOBE_AUTOMATION_SSH_PRIVATE_KEY=$(cat ~/.ssh/id_rsa)
set -x

sudo -E docker run --detach --rm --network host -v $${config_directories[kayobe]}:/stack/kayobe-automation-env/src/kayobe-config -v $${config_directories[kayobe]}/tempest-artifacts:/stack/tempest-artifacts -e KAYOBE_ENVIRONMENT -e KAYOBE_VAULT_PASSWORD -e KAYOBE_AUTOMATION_SSH_PRIVATE_KEY kayobe:latest /stack/kayobe-automation-env/src/kayobe-config/.automation/pipeline/tempest.sh -e ansible_user=stack

# During the initial deployment the seed node must receive the `gwee/rally` image before we can follow the logs.
# Therefore, we must wait a reasonable amount time before attempting to do so.
sleep 360

ssh -oStrictHostKeyChecking=no ${ ssh_user }@${ seed_addr } 'sudo docker logs --follow $(sudo docker ps -q)'
