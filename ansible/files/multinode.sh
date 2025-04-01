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

declare -A virtual_environments=(
  ["kayobe"]="$HOME/venvs/kayobe/bin/activate"
  ["openstack"]="$HOME/src/openstack-config/venv/bin/activate"
)

declare -A config_directories=(
  ["kayobe"]="$HOME/src/kayobe-config"
  ["openstack"]="$HOME/src/openstack-config"
)

rc_path=/tmp/deploy-openstack.rc

function activate_virt_env () {
  set +u
  source "${virtual_environments[$1]}"
  set -u
}

function activate_kayobe_env () {
  set +u
  source "${config_directories[kayobe]}/kayobe-env" --environment ci-multinode
  set -u
}

function kayobe_env() {
  activate_virt_env "kayobe"
  activate_kayobe_env

  export KAYOBE_VAULT_PASSWORD=$(cat ~/vault.password)
}

function setup() {
  set -euxo pipefail

  lock_path=/tmp/deploy-openstack.lock
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

  set +x
  kayobe_env
  set -x
}

function report_success() {
  # Report success.
  echo 0 >$rc_path
}

function encrypt_file() {
  file=$1
  # Make it idempotent by skipping encrypted files.
  if [[ ! $(head -n 1 $file) =~ '$ANSIBLE_VAULT;' ]]; then
    ansible-vault encrypt --vault-password-file ~/vault.password $file
  fi
}

function decrypt_file() {
  file=$1
  ansible-vault decrypt --vault-password-file ~/vault.password $file
}

function workaround_ansible_rc13_bug() {
  # Call this function in between long-running Ansible executions to attempt to
  # work around an Ansible race condition.

  # There is a race condition in Ansible that can result in this failure:
  #   msg: |-
  #   MODULE FAILURE
  #   See stdout/stderr for the exact error
  # rc: -13
  # See https://github.com/ansible/ansible/issues/78344 and
  # https://github.com/ansible/ansible/issues/81777.
  # In https://github.com/stackhpc/stackhpc-kayobe-config/pull/1108 we applied
  # a workaround to increase the ControlPersist timeout to 1 hour, but this
  # does not always work.
  # Here we use a different workaround of disabling SSH pipelining. This has
  # performance implications for Ansible, but is a reasonable trade-off for
  # reliability.
  # We set the config option as an environment variable rather than in
  # ansible.cfg in Kayobe configuration, to avoid a merge conflict on upgrade.
  export ANSIBLE_PIPELINING=False
}

function run_kayobe() {
  workaround_ansible_rc13_bug
  kayobe $*
}

function deploy_seed() {
  run_kayobe seed host configure
}

function deploy_seed_vault() {
  # Deploy hashicorp vault to the seed
  run_kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/vault-deploy-seed.yml
  encrypt_file $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/vault/OS-TLS-INT.pem
  encrypt_file $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/vault/seed-vault-keys.json
  encrypt_file $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/vault/*.key
}

function get_seed_ssh() {
  # NOTE: Bash clears the -e option in subshells when not in Posix mode.
  set -e
  ssh_user=$(run_kayobe configuration dump --host seed[0] --var-name ansible_user | tr -d '"')
  seed_addr=$(run_kayobe configuration dump --host seed[0] --var-name ansible_host | tr -d '"')
  echo "${ssh_user}@${seed_addr}"
}

function copy_ca_to_seed() {
  # Add the Vault CA to the trust store on the seed.
  seed_ssh=$(get_seed_ssh)

  scp -oStrictHostKeyChecking=no $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla/certificates/ca/vault.crt ${seed_ssh}:
  if [[ $(grep '^ID=' /etc/os-release | cut -d= -f2) == "ubuntu" ]]; then
    ssh -oStrictHostKeyChecking=no ${seed_ssh} sudo cp vault.crt /usr/local/share/ca-certificates/OS-TLS-ROOT.crt
    ssh -oStrictHostKeyChecking=no ${seed_ssh} sudo update-ca-certificates
  else
    ssh -oStrictHostKeyChecking=no ${seed_ssh} sudo cp vault.crt /etc/pki/ca-trust/source/anchors/OS-TLS-ROOT.crt
    ssh -oStrictHostKeyChecking=no ${seed_ssh} sudo update-ca-trust
  fi
}

function deploy_ceph() {
  run_kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/cephadm-deploy.yml
  sleep 30
  run_kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/cephadm.yml
  run_kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/cephadm-gather-keys.yml
}

function deploy_overcloud_vault() {
  # NOTE: Previously it was necessary to first deploy HAProxy with TLS disabled.
  if [[ -f $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla/globals-tls-config.yml ]]; then
    # Skip os_capacity deployment since it requires admin-openrc.sh which doesn't exist yet.
    run_kayobe overcloud service deploy --skip-tags os_capacity -kt haproxy
  fi

  # Deploy hashicorp vault to the controllers
  run_kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/vault-deploy-overcloud.yml
  encrypt_file $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/vault/overcloud-vault-keys.json
}

function generate_overcloud_certs() {
  # Generate external tls certificates
  if [[ -f $KAYOBE_CONFIG_PATH/ansible/vault-generate-test-external-tls.yml ]]; then
    run_kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/vault-generate-test-external-tls.yml
    encrypt_file $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla/certificates/haproxy.pem
  fi

  # Generate internal tls certificates
  run_kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/vault-generate-internal-tls.yml
  encrypt_file $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla/certificates/haproxy-internal.pem

  # Generate backend tls certificates
  run_kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/vault-generate-backend-tls.yml
  for cert in $(ls -1 $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla/certificates/*-key.pem); do
    encrypt_file $cert
  done

  # NOTE: Previously it was necessary to first deploy HAProxy with TLS disabled.
  if [[ -f $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla/globals-tls-config.yml ]]; then
    sed -i 's/# kolla_enable_tls_internal: true/kolla_enable_tls_internal: true/g' $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla.yml
    # This condition provides some level of idempotency, as well as supporting
    # the case where the content of globals-tls-config.yml has been added to
    # globals.yml within a conditional check for internal TLS.
    if ! grep kolla_copy_ca_into_containers $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla/globals-tls-config.yml &>/dev/null; then
      cat $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla/globals-tls-config.yml >> $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla/globals.yml
    fi
  fi
}

function generate_barbican_secrets() {
  # Create vault configuration for barbican
  decrypt_file $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/secrets.yml
  sed -i "s/secret_id:.*/secret_id: $(uuidgen)/g" $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/secrets.yml
  encrypt_file $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/secrets.yml
  run_kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/vault-deploy-barbican.yml
  decrypt_file $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/secrets.yml
  sed -i "s/role_id:.*/role_id: $(cat /tmp/barbican-role-id)/g" $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/secrets.yml
  encrypt_file $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/secrets.yml
  rm /tmp/barbican-role-id
}

function deploy_overcloud() {
  run_kayobe overcloud host configure

  deploy_ceph

  deploy_seed_vault

  deploy_overcloud_vault

  generate_overcloud_certs

  generate_barbican_secrets

  # Deploy all services
  run_kayobe overcloud service deploy

  copy_ca_to_seed
}

function deploy_wazuh() {
  run_kayobe infra vm host configure

  # Deploy Wazuh
  run_kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/wazuh-secrets.yml
  encrypt_file $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/wazuh-secrets.yml
  run_kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/wazuh-manager.yml
  run_kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/wazuh-agent.yml
}

function create_resources() {
  activate_virt_env "openstack"
  activate_kayobe_env

  set +x
  source ${KOLLA_CONFIG_PATH}/public-openrc.sh
  set -x

  ~/src/openstack-config/tools/openstack-config

  # Reactivate Kayobe environment.
  activate_virt_env "kayobe"
  activate_kayobe_env
}

function build_kayobe_image() {
  # Build a Kayobe container image.

  # Set base image for kayobe container. Use rocky 9 by default
  export BASE_IMAGE=rockylinux:9

  if [[ "$(sudo docker image ls)" == *"kayobe"* ]]; then
    echo "Image already exists skipping docker build"
  else
    sudo DOCKER_BUILDKIT=1 docker build \
      --network host \
      --build-arg BASE_IMAGE=$BASE_IMAGE \
      --file ${config_directories[kayobe]}/.automation/docker/kayobe/Dockerfile \
      --tag kayobe:latest \
      ${config_directories[kayobe]}
  fi
}

function run_tempest() {
  # Run Tempest test suite. Return non-zero if any tests failed.

  tempest_dir="$HOME/tempest-artifacts"

  seed_ssh=$(get_seed_ssh)

  git -C ${config_directories[kayobe]} submodule init
  git -C ${config_directories[kayobe]} submodule update

  build_kayobe_image

  set +x
  export KAYOBE_AUTOMATION_SSH_PRIVATE_KEY=$(cat ~/.ssh/id_rsa)
  set -x

  if [[ -d $tempest_dir ]]; then
    tempest_backup=${tempest_dir}-$(date +%Y%m%dT%H%M%S)
    echo "Found previous Tempest test results"
    echo "Moving to $tempest_backup"
    mv $tempest_dir $tempest_backup
  fi

  # Remove any previous kayobe_tempest container
  sudo docker rm kayobe_tempest || true

  # Run tempest
  sudo -E docker run \
    --name kayobe_tempest \
    --detach --network host \
    -v ${config_directories[kayobe]}:/stack/kayobe-automation-env/src/kayobe-config \
    -v $tempest_dir:/stack/tempest-artifacts \
    -e KAYOBE_ENVIRONMENT -e KAYOBE_VAULT_PASSWORD -e KAYOBE_AUTOMATION_SSH_PRIVATE_KEY \
    kayobe:latest \
    /stack/kayobe-automation-env/src/kayobe-config/.automation/pipeline/tempest.sh \
    -e ansible_user=stack

  # During the initial deployment the seed node must receive the `gwee/rally` image before we can follow the logs.
  # Therefore, we must wait a reasonable amount time before attempting to do so.
  sleep 360

  if ! ssh -oStrictHostKeyChecking=no ${seed_ssh} 'sudo docker logs --follow tempest'; then
    echo "Failed to follow Tempest container logs after waiting 360 seconds"
    echo "Ignoring - this may or may not indicate an error"
  fi

  # Wait for Kayobe Tempest pipeline to complete to ensure artifacts exist.
  kayobe_tempest_rc="$(sudo docker container wait kayobe_tempest)"
  if [[ $kayobe_tempest_rc != "0" ]]; then
    echo "Failed running kayobe_tempest container. Output:"
    sudo docker logs kayobe_tempest
  fi
  sudo docker rm kayobe_tempest

  if [[ ! -f $tempest_dir/failed-tests ]]; then
    echo "Unable to find Tempest test results in $tempest_dir/failed-tests"
    return 1
  fi

  if [[ $(wc -l < $tempest_dir/failed-tests) -ne 0 ]]; then
    echo "Some Tempest tests failed"
    return 1
  fi

  echo "Tempest testing successful"
}

function run_tests() {
  rc=0
  if ! run_tempest; then
    rc=1
  fi
  return $rc
}

function deploy_full() {
  # End-to-end deployment and testing.

  deploy_seed
  deploy_overcloud
  if run_kayobe configuration dump --host wazuh-manager --var-name group_names | grep wazuh-manager &>/dev/null; then
    deploy_wazuh
  fi
  create_resources
  run_tests
}

function upgrade_overcloud() {
  # Generate external tls certificates if it was previously disabled.
  if [[ -f $KAYOBE_CONFIG_PATH/ansible/vault-generate-test-external-tls.yml ]] && [[ ! -f $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla/certificates/haproxy.pem ]]; then
    run_kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/vault-generate-test-external-tls.yml
    encrypt_file $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla/certificates/haproxy.pem
  fi

  run_kayobe overcloud host upgrade
  run_kayobe overcloud host configure
  # FIXME: The overcloud host configure triggers parallel reboots due to an
  # selinux state change. This breaks the database. This should be fixed by
  # serialising the reboots inside kayobe.
  run_kayobe overcloud database recover
  run_kayobe overcloud service upgrade
}

function upgrade_prerequisites() {
  # Run the upgrade prerequisites script if it exists.
  workaround_ansible_rc13_bug
  [[ ! -f $KAYOBE_CONFIG_PATH/../../tools/upgrade-prerequisites.sh ]] || $KAYOBE_CONFIG_PATH/../../tools/upgrade-prerequisites.sh
}

function minor_upgrade() {
  # Perform a minor upgrade of the cloud, upgrading host packages and
  # containers

  # Upgrade Seed host packages
  run_kayobe seed host configure
  set -f
  run_kayobe seed host package update --packages '*'
  set +f
  run_kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/reboot.yml --limit seed

  # Upgrade overcloud host packages
  run_kayobe overcloud host configure
  set -f
  run_kayobe overcloud host package update --packages '*'
  set +f
  run_kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/reboot.yml --limit overcloud

  # Upgrade overcloud containers
  run_kayobe overcloud service deploy
}

function usage() {
  set +x

  echo "Usage: $0 <command>"
  echo
  echo "Commands:"
  echo "  kayobe_env"
  echo "  deploy_full"
  echo "  deploy_seed"
  echo "  deploy_overcloud"
  echo "  deploy_wazuh"
  echo "  create_resources"
  echo "  build_kayobe_image"
  echo "  run_tempest"
  echo "  upgrade_overcloud"
  echo "  upgrade_prerequisites"
  echo "  minor_upgrade"
}

function main() {
  # Script entry point. Accepts a single argument: the command to perform.

  if [[ $# -ne 1 ]]; then
    usage
    exit 1
  fi

  cmd="${1}"
  if [[ -z "$cmd" ]]; then
    usage
    exit 1
  fi

  case "$cmd" in
    # Special case: kayobe_env should be "sourced" to pull in the environment.
    (kayobe_env)
      $cmd
      ;;
    # Standard commands.
    (build_kayobe_image|deploy_full|deploy_seed|deploy_overcloud|deploy_wazuh|create_resources|run_tempest|upgrade_overcloud|upgrade_prerequisites|minor_upgrade)
      setup
      $cmd
      report_success
      ;;
    (*)
      usage
      exit 1
      ;;
  esac
}

main "$@"
