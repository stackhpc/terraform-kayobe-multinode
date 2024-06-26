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

tempest_dir="$HOME/tempest-artifacts"
lock_path=/tmp/deploy-openstack.lock
rc_path=/tmp/deploy-openstack.rc

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

# Use a "lock" directory to ensure that only one instance of this script can run concurrently.
if mkdir "$lock_path"; then
  trap "rmdir $lock_path" EXIT
else
  echo "Refusing to deploy because a deployment is currently in progress."
  echo "If you are sure this is not the case, remove the $lock_path directory and run this script again."
  exit 1
fi

# Write an exit code to a file to allow Ansible to report the result.
echo 1 >$rc_path

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

# NOTE: Previously it was necessary to first deploy HAProxy with TLS disabled.
if [[ -f $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla/globals-tls-config.yml ]]; then
  # Skip os_capacity deployment since it requires admin-openrc.sh which doesn't exist yet.
  kayobe overcloud service deploy --skip-tags os_capacity -kt haproxy
fi

# Deploy hashicorp vault to the controllers
kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/vault-deploy-overcloud.yml
ansible-vault encrypt --vault-password-file ~/vault.password $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/vault/overcloud-vault-keys.json

# Generate external tls certificates
if [[ -f $KAYOBE_CONFIG_PATH/ansible/vault-generate-test-external-tls.yml ]]; then
  kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/vault-generate-test-external-tls.yml
  ansible-vault encrypt --vault-password-file ~/vault.password $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla/certificates/haproxy.pem
fi

# Generate internal tls certificates
kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/vault-generate-internal-tls.yml
ansible-vault encrypt --vault-password-file ~/vault.password $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla/certificates/haproxy-internal.pem

# Generate backend tls certificates
kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/vault-generate-backend-tls.yml
%{ for hostname in controller_hostname ~}
ansible-vault encrypt --vault-password-file ~/vault.password $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla/certificates/${ hostname }-key.pem
%{ endfor ~}

# NOTE: Previously it was necessary to first deploy HAProxy with TLS disabled.
if [[ -f $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla/globals-tls-config.yml ]]; then
  sed -i 's/# kolla_enable_tls_external: true/kolla_enable_tls_external: true/g' $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla.yml
  sed -i 's/# kolla_enable_tls_internal: true/kolla_enable_tls_internal: true/g' $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla.yml
  cat $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla/globals-tls-config.yml >> $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla/globals.yml
fi

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
ansible-vault encrypt --vault-password-file ~/vault.password  $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/wazuh-secrets.yml
kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/wazuh-manager.yml
kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/wazuh-agent.yml
%{ endif }

activate_virt_env "openstack"
activate_kayobe_env

set +x
source $${KOLLA_CONFIG_PATH}/public-openrc.sh
set -x

# Add the Vault CA to the trust store on the seed.
scp -oStrictHostKeyChecking=no $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla/certificates/ca/vault.crt ${ ssh_user }@${ seed_addr }:
if [[ $(grep '^ID=' /etc/os-release | cut -d= -f2) == "ubuntu" ]]; then
  ssh -oStrictHostKeyChecking=no ${ ssh_user }@${ seed_addr } sudo cp vault.crt /usr/local/share/ca-certificates/OS-TLS-ROOT.crt
  ssh -oStrictHostKeyChecking=no ${ ssh_user }@${ seed_addr } sudo update-ca-certificates
else
  ssh -oStrictHostKeyChecking=no ${ ssh_user }@${ seed_addr } sudo cp vault.crt /etc/pki/ca-trust/source/anchors/OS-TLS-ROOT.crt
  ssh -oStrictHostKeyChecking=no ${ ssh_user }@${ seed_addr } sudo update-ca-trust
fi

~/src/openstack-config/tools/openstack-config

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

if [[ -d $tempest_dir ]]; then
  tempest_backup=$${tempest_dir}.$(date --iso-8601=minutes)
  echo "Found previous Tempest test results"
  echo "Moving to $tempest_backup"
  mv $tempest_dir $tempest_backup
fi

# Run tempest
sudo -E docker run --name kayobe_tempest --detach --rm --network host -v $${config_directories[kayobe]}:/stack/kayobe-automation-env/src/kayobe-config -v $tempest_dir:/stack/tempest-artifacts -e KAYOBE_ENVIRONMENT -e KAYOBE_VAULT_PASSWORD -e KAYOBE_AUTOMATION_SSH_PRIVATE_KEY kayobe:latest /stack/kayobe-automation-env/src/kayobe-config/.automation/pipeline/tempest.sh -e ansible_user=stack

# During the initial deployment the seed node must receive the `gwee/rally` image before we can follow the logs.
# Therefore, we must wait a reasonable amount time before attempting to do so.
sleep 360

if ! ssh -oStrictHostKeyChecking=no ${ ssh_user }@${ seed_addr } 'sudo docker logs --follow tempest'; then
  echo "Failed to follow Tempest container logs after waiting 360 seconds"
  echo "Ignoring - this may or may not indicate an error"
fi

# Wait for Kayobe Tempest pipeline to complete to ensure artifacts exist.
sudo docker container wait kayobe_tempest

if [[ ! -f $tempest_dir/failed-tests ]]; then
  echo "Unable to find Tempest test results in $tempest_dir/failed-tests"
  exit 1
fi

if [[ $(wc -l < $tempest_dir/failed-tests) -ne 0 ]]; then
  echo "Some Tempest tests failed"
  exit 1
fi

echo "Tempest testing successful"

# Report success.
echo 0 >$rc_path
