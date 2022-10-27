#!/usr/bin/sh
set -euxo pipefail

declare -A virtual_environments=(
  ["kayobe"]="$HOME/venvs/kayobe/bin/activate"
  ["openstack"]="$HOME/src/openstack-config/ansible/openstack-config-venv/bin/activate"
)

declare -A config_directories=(
  ["kayobe"]="$HOME/src/kayobe-config"
  ["openstack"]="$HOME/src/openstack-config"
)

function activate_virt_env () {
  set +u
  source ${virtual_environments[$1]}
  set -u
}

function activate_kayobe_env () {
  set +u
  source ${config_directories[kayobe]}/kayobe-env --environment ci-multinode
  set -u
}

activate_virt_env "kayobe"
activate_kayobe_env

set +x
export KAYOBE_VAULT_PASSWORD=$(cat ~/vault-pw)
set -x

# kayobe control host bootstrap
# kayobe seed host configure
# kayobe overcloud host configure

# kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/cephadm-deploy.yml
# kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/cephadm.yml
# kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/cephadm-gather-keys.yml

# kayobe overcloud service deploy

activate_virt_env "openstack"
activate_kayobe_env

source ${KOLLA_CONFIG_PATH}/public-openrc.sh

~/src/openstack-config/tools/openstack-config