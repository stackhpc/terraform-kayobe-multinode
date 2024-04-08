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

# Install uuid-runtime on ubuntu
if $(which apt 2>/dev/null >/dev/null); then
    sudo apt update
    sudo apt -y install uuid-runtime
fi

# Configure hosts
kayobe control host bootstrap
kayobe seed host configure
kayobe overcloud host configure
%{ if deploy_wazuh }kayobe infra vm host configure%{ endif }

# Deploy Ceph
kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/cephadm-deploy.yml
sleep 30
kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/cephadm.yml
kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/cephadm-gather-keys.yml

pip install -r $${config_directories[kayobe]}/requirements.txt

# Deploy hashicorp vault to the seed
kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/vault-deploy-seed.yml
ansible-vault encrypt --vault-password-file ~/vault.password $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/vault/OS-TLS-INT.pem
ansible-vault encrypt --vault-password-file ~/vault.password $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/vault/seed-vault-keys.json
ansible-vault encrypt --vault-password-file ~/vault.password $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/vault/*.key

kayobe overcloud service deploy -kt haproxy

# Deploy hashicorp vault to the controllers
kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/vault-deploy-overcloud.yml
ansible-vault encrypt --vault-password-file ~/vault.password $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/vault/overcloud-vault-keys.json

# Generate internal tls certificates
kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/vault-generate-internal-tls.yml
ansible-vault encrypt --vault-password-file ~/vault.password $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla/certificates/haproxy-internal.pem

# Generate backend tls certificates
kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/vault-generate-backend-tls.yml
%{ for hostname in controller_hostname ~}
ansible-vault encrypt --vault-password-file ~/vault.password $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla/certificates/${ hostname }-key.pem
%{ endfor ~}

# Set config to use tls
sed -i 's/# kolla_enable_tls_internal: true/kolla_enable_tls_internal: true/g' $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla.yml
cat $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla/globals-tls-config.yml >> $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla/globals.yml

# Create vault configuration for barbican
ansible-vault decrypt --vault-password-file ~/vault.password $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/secrets.yml
sed -i "s/secret_id:.*/secret_id: $(uuidgen)/g" $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/secrets.yml
ansible-vault encrypt --vault-password-file ~/vault.password $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/secrets.yml
kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/vault-deploy-barbican.yml
ansible-vault decrypt --vault-password-file ~/vault.password $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/secrets.yml
sed -i "s/role_id:.*/role_id: $(cat /tmp/barbican-role-id)/g" $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/secrets.yml
ansible-vault encrypt --vault-password-file ~/vault.password $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/secrets.yml
rm /tmp/barbican-role-id

# Deploy all services
kayobe overcloud service deploy

%{ if deploy_wazuh }
# Deploy Wazuh
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

~/src/openstack-config/tools/openstack-config -- -e ansible_user=${ ssh_user }

git -C $${config_directories[kayobe]} submodule init
git -C $${config_directories[kayobe]} submodule update

# Set base image for kayobe container. Use rocky 9 for zed+ CentOS otherwise
if grep -Eq "(2023|zed)" $${config_directories[kayobe]}/.gitreview; then
    export BASE_IMAGE=rockylinux:9
else
    export BASE_IMAGE=quay.io/centos/centos:stream8
fi

if [[ "$(sudo docker image ls)" == *"kayobe"* ]]; then
  echo "Image already exists skipping docker build"
else
  sudo DOCKER_BUILDKIT=1 docker build --network host --build-arg BASE_IMAGE=$BASE_IMAGE --file $${config_directories[kayobe]}/.automation/docker/kayobe/Dockerfile --tag kayobe:latest $${config_directories[kayobe]}
fi

set +x
export KAYOBE_AUTOMATION_SSH_PRIVATE_KEY=$(cat ~/.ssh/id_rsa)
set -x

# Run tempest
sudo -E docker run --detach --rm --network host -v $${config_directories[kayobe]}:/stack/kayobe-automation-env/src/kayobe-config -v $${config_directories[kayobe]}/tempest-artifacts:/stack/tempest-artifacts -e KAYOBE_ENVIRONMENT -e KAYOBE_VAULT_PASSWORD -e KAYOBE_AUTOMATION_SSH_PRIVATE_KEY kayobe:latest /stack/kayobe-automation-env/src/kayobe-config/.automation/pipeline/tempest.sh -e ansible_user=stack

# During the initial deployment the seed node must receive the `gwee/rally` image before we can follow the logs.
# Therefore, we must wait a reasonable amount time before attempting to do so.
sleep 360

ssh -oStrictHostKeyChecking=no ${ ssh_user }@${ seed_addr } 'sudo docker logs --follow tempest'
