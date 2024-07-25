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
  # Try another workaround of removing the ControlPersist sockets.
  rm -f ~/.ansible/cp/*
}

function deploy_seed() {
  workaround_ansible_rc13_bug

  kayobe seed host configure
}

function deploy_seed_vault() {
  workaround_ansible_rc13_bug

  # Deploy hashicorp vault to the seed
  kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/vault-deploy-seed.yml
  encrypt_file $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/vault/OS-TLS-INT.pem
  encrypt_file $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/vault/seed-vault-keys.json
  encrypt_file $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/vault/*.key
}

function get_seed_ssh() {
  # NOTE: Bash clears the -e option in subshells when not in Posix mode.
  set -e
  ssh_user=$(kayobe configuration dump --host seed[0] --var-name ansible_user | tr -d '"')
  seed_addr=$(kayobe configuration dump --host seed[0] --var-name ansible_host | tr -d '"')
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
  workaround_ansible_rc13_bug

  kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/cephadm-deploy.yml
  sleep 30
  kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/cephadm.yml
  kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/cephadm-gather-keys.yml
}

function deploy_overcloud_vault() {
  workaround_ansible_rc13_bug

  # NOTE: Previously it was necessary to first deploy HAProxy with TLS disabled.
  if [[ -f $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla/globals-tls-config.yml ]]; then
    # Skip os_capacity deployment since it requires admin-openrc.sh which doesn't exist yet.
    kayobe overcloud service deploy --skip-tags os_capacity -kt haproxy
  fi

  # Deploy hashicorp vault to the controllers
  kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/vault-deploy-overcloud.yml
  encrypt_file $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/vault/overcloud-vault-keys.json
}

function generate_overcloud_certs() {
  workaround_ansible_rc13_bug

  # Generate external tls certificates
  if [[ -f $KAYOBE_CONFIG_PATH/ansible/vault-generate-test-external-tls.yml ]]; then
    kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/vault-generate-test-external-tls.yml
    encrypt_file $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla/certificates/haproxy.pem
  fi

  # Generate internal tls certificates
  kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/vault-generate-internal-tls.yml
  encrypt_file $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla/certificates/haproxy-internal.pem

  # Generate backend tls certificates
  kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/vault-generate-backend-tls.yml
  for cert in $(ls -1 $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla/certificates/*-key.pem); do
    encrypt_file $cert
  done

  # NOTE: Previously it was necessary to first deploy HAProxy with TLS disabled.
  if [[ -f $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla/globals-tls-config.yml ]]; then
    sed -i 's/# kolla_enable_tls_internal: true/kolla_enable_tls_internal: true/g' $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla.yml
    cat $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla/globals-tls-config.yml >> $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla/globals.yml
  fi
}

function generate_barbican_secrets() {
  # Create vault configuration for barbican
  decrypt_file $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/secrets.yml
  sed -i "s/secret_id:.*/secret_id: $(uuidgen)/g" $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/secrets.yml
  encrypt_file $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/secrets.yml
  kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/vault-deploy-barbican.yml
  decrypt_file $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/secrets.yml
  sed -i "s/role_id:.*/role_id: $(cat /tmp/barbican-role-id)/g" $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/secrets.yml
  encrypt_file $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/secrets.yml
  rm /tmp/barbican-role-id
}

function deploy_overcloud() {
  workaround_ansible_rc13_bug

  kayobe overcloud host configure

  workaround_ansible_rc13_bug

  # Update packages to latest available in release train repos.
  kayobe overcloud host package update --packages '*'

  # Reboot into the new kernel if updated.
  kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/reboot.yml

  deploy_ceph

  deploy_seed_vault

  deploy_overcloud_vault

  generate_overcloud_certs

  generate_barbican_secrets

  workaround_ansible_rc13_bug

  # Deploy all services
  kayobe overcloud service deploy

  copy_ca_to_seed
}

function deploy_wazuh() {
  workaround_ansible_rc13_bug

  kayobe infra vm host configure

  # Deploy Wazuh
  kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/wazuh-secrets.yml
  encrypt_file $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/wazuh-secrets.yml
  kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/wazuh-manager.yml
  kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/wazuh-agent.yml
}

function create_resources() {
  activate_virt_env "openstack"
  activate_kayobe_env

  set +x
  source ${KOLLA_CONFIG_PATH}/public-openrc.sh
  set -x

  workaround_ansible_rc13_bug

  ~/src/openstack-config/tools/openstack-config

  # Reactivate Kayobe environment.
  activate_virt_env "kayobe"
  activate_kayobe_env
}

function build_kayobe_image() {
  # Build a Kayobe container image.

  # Set base image for kayobe container. Use rocky 9 for yoga+ CentOS otherwise
  if grep -Eq "(202|zed|yoga)" ${config_directories[kayobe]}/.gitreview; then
      export BASE_IMAGE=rockylinux:9
  else
      export BASE_IMAGE=quay.io/centos/centos:stream8
  fi

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
    tempest_backup=${tempest_dir}.$(date --iso-8601=minutes)
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

function run_stackhpc_openstack_tests() {
  # Run StackHPC OpenStack test suite. Return non-zero if any tests failed.

  sot_results_dir="$HOME/sot-results"

  if [[ ! -f $KAYOBE_CONFIG_PATH/ansible/stackhpc-openstack-tests.yml ]]; then
    echo "StackHPC OpenStack tests playbook not found - skipping"
    return
  fi

  if [[ -d $sot_results_dir ]]; then
    sot_results_backup=${sot_results_dir}.$(date --iso-8601=minutes)
    echo "Found previous StackHPC OpenStack test results"
    echo "Moving to $sot_results_backup"
    mv $sot_results_dir $sot_results_backup
  fi

  workaround_ansible_rc13_bug

  # Run StackHPC OpenStack tests
  kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/stackhpc-openstack-tests.yml

  echo "StackHPC OpenStack test results are available in $sot_results_dir"
  if [[ ! -f $sot_results_dir/failed-tests ]]; then
    echo "Unable to find StackHPC OpenStack test results in $sot_results_dir/failed-tests"
    return 1
  fi

  if [[ $(wc -l < $sot_results_dir/failed-tests) -ne 0 ]]; then
    echo "Some StackHPC OpenStack tests failed"
    return 1
  fi

  echo "StackHPC OpenStack testing successful"
}

function run_tests() {
  # Run both Tempest and StackHPC OpenStack tests to get full results.
  rc=0
  if ! run_tempest; then
    rc=1
  fi
  if ! run_stackhpc_openstack_tests; then
    rc=1
  fi
  return $rc
}

function deploy_full() {
  # End-to-end deployment and testing.

  deploy_seed
  deploy_overcloud
  if kayobe configuration dump --host wazuh-manager --var-name group_names | grep wazuh-manager &>/dev/null; then
    deploy_wazuh
  fi
  create_resources
  run_tests
}

function upgrade_overcloud() {
  workaround_ansible_rc13_bug

  # Generate external tls certificates if it was previously disabled.
  if [[ -f $KAYOBE_CONFIG_PATH/ansible/vault-generate-test-external-tls.yml ]] && [[ ! -f $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla/certificates/haproxy.pem ]]; then
    kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/vault-generate-test-external-tls.yml
    encrypt_file $KAYOBE_CONFIG_PATH/environments/$KAYOBE_ENVIRONMENT/kolla/certificates/haproxy.pem
  fi

  kayobe overcloud host upgrade
  kayobe overcloud host configure
  kayobe overcloud service upgrade
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
  echo "  run_stackhpc_openstack_tests"
  echo "  upgrade_overcloud"
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
    (build_kayobe_image|deploy_full|deploy_seed|deploy_overcloud|deploy_wazuh|create_resources|run_tempest|run_stackhpc_openstack_tests|upgrade_overcloud)
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
