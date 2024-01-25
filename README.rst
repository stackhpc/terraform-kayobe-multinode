==========================
Terraform Kayobe Multinode
==========================

This Terraform configuration deploys a requested amount of Instances on an OpenStack cloud, to be
used as a Multinode Kayobe test environment.

Usage
=====

These instructions show how to use this Terraform configuration manually. They
assume you are running an Ubuntu host that will be used to run Terraform. The
machine should have network access to the environment that will be created by this
configuration.

Install Terraform:

.. code-block:: console

   wget -qO - terraform.gpg https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/terraform-archive-keyring.gpg
   sudo echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/terraform-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/terraform.list
   sudo apt update
   sudo apt install git terraform

Clone and initialise the Kayobe config:

.. code-block:: console

   git clone https://github.com/stackhpc/terraform-kayobe-multinode
   cd terraform-kayobe-multinode


Initialise Terraform:

.. code-block:: console

   terraform init

Generate an SSH keypair:

.. code-block:: console

   ssh-keygen -f id_rsa -N ''

Create an OpenStack clouds.yaml file with your credentials to access an
OpenStack cloud. Alternatively, download and source an openrc file from Horizon.

.. code-block:: console

   cat << EOF > clouds.yaml
   ---
   clouds:
     sms-lab:
       auth:
         auth_url: https://api.sms-lab.cloud:5000
         username: <username>
         project_name: <project>
         domain_name: default
       interface: public
   EOF

Export environment variables to use the correct cloud and provide a password (you shouldn't do this if you have sourced the openrc file):

.. code-block:: console

   export OS_CLOUD=sms-lab
   read -p OS_PASSWORD -s OS_PASSWORD
   export OS_PASSWORD

Or you can source the provided `init.sh` script which shall initialise terraform and export two variables.
`OS_CLOUD` is a variable which is used by Terraform and must match an entry within `clouds.yml` (Not needed if you have sourced the openrc file).
`OS_PASSWORD` is the password used to authenticate when signing into OpenStack.

.. code-block:: console
   source ./init.sh

   Initializing the backend...

   Initializing provider plugins...
   - Reusing previous version of terraform-provider-openstack/openstack from the dependency lock file
   - Reusing previous version of hashicorp/local from the dependency lock file
   - Using previously-installed terraform-provider-openstack/openstack v1.48.0
   - Using previously-installed hashicorp/local v2.2.3

   Terraform has been successfully initialized!

   You may now begin working with Terraform. Try running "terraform plan" to see
   any changes that are required for your infrastructure. All Terraform commands
   should now work.

   If you ever set or change modules or backend configuration for Terraform,
   rerun this command to reinitialize your working directory. If you forget, other
   commands will detect it and remind you to do so if necessary.
   OpenStack Cloud Name: sms-lab
   Password:

Generate Terraform variables:

.. code-block:: console

   cat << EOF > terraform.tfvars
   prefix = "changeme"

   ansible_control_vm_flavor = "general.v1.small"
   ansible_control_vm_name   = "ansible-control"
   ansible_control_disk_size = 100

   seed_vm_flavor = "general.v1.small"
   seed_disk_size = 100

   multinode_flavor     = "general.v1.medium"
   multinode_image      = "Rocky9-lvm"
   multinode_keypair    = "changeme"
   multinode_vm_network = "stackhpc-ipv4-geneve"
   multinode_vm_subnet  = "stackhpc-ipv4-geneve-subnet"
   compute_count        = "2"
   controller_count     = "3"
   compute_disk_size    = 100
   controller_disk_size = 100

   ssh_public_key = "~/.ssh/changeme.pub"
   ssh_user       = "cloud-user"

   storage_count     = "3"
   storage_flavor    = "general.v1.small"
   storage_disk_size = 100

   deploy_wazuh       = true
   infra_vm_flavor    = "general.v1.small"
   infra_vm_disk_size = 100

   EOF

You will need to set the `multinode_keypair`, `prefix`, and `ssh_public_key`.
By default, Rocky Linux 9 will be used but Ubuntu Jammy is also supported by
changing `multinode_image` to `Ubuntu-22.04-lvm` and `ssh_user` to `ubuntu`.
Other LVM images should also work but are untested.

The `multinode_flavor` will change the flavor used for controller and compute
nodes. Both virtual machines and baremetal are supported, but the `*_disk_size`
variables must be set to 0 when using baremetal host. This will stop a block
device being allocated. When any baremetal hosts are deployed, the
`multinode_vm_network` and `multinode_vm_subnet` should also be changed to
`stackhpc-ipv4-vlan-v2` and `stackhpc-ipv4-vlan-subnet-v2` respectively.

If `deploy_wazuh` is set to true, an infrastructure VM will be created that
hosts the Wazuh manager. The Wazuh deployment playbooks will also be triggered
automatically to deploy Wazuh agents to the overcloud hosts.

Generate a plan:

.. code-block:: console

   terraform plan

Apply the changes:

.. code-block:: console

   terraform apply -auto-approve

You should have requested a number of resources spawned on Openstack, and an ansible_inventory file produced as output for Kayobe.

Copy your generated id_rsa and id_rsa.pub to ~/.ssh/ on Ansible control host if you want Kayobe to automatically pick them up during bootstrap.

Configure Ansible control host

Using the `deploy-openstack-config.yml` playbook you can setup the Ansible control host to include the kayobe/kayobe-config repositories with `hosts` and `admin-oc-networks`.
It shall also setup the kayobe virtual environment, allowing for immediate configuration and deployment of OpenStack.

First you must ensure that you have `Ansible installed <https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html>`_ on your local machine.

.. code-block:: console

   pip install --user ansible

Secondly if the machines are behind an SSH bastion you must ensure that your ssh config is setup appropriately with a proxy jump

.. code-block:: console

   Host lab-bastion
      HostName BastionIPAddr
      User username
      IdentityFile ~/.ssh/key

   Host 10.*
      ProxyJump=lab-bastion
      ForwardAgent no
      IdentityFile ~/.ssh/key
      UserKnownHostsFile /dev/null
      StrictHostKeyChecking no

Install the ansible requirements.

.. code-block:: console

   ansible-galaxy install -r ansible/requirements.yml

Review the vars defined within `ansible/vars/defaults.yml`. In here you can customise the version of kayobe, kayobe-config or openstack-config. 
However, make sure to define `ssh_key_path` to point to the location of the SSH key in use amongst the nodes and also `vxlan_vni` which should be unique value between 1 to 100,000.
VNI should be much smaller than the officially supported limit of 16,777,215 as we encounter errors when attempting to bring interfaces up that use a high VNI. You must set``vault_password_path``; this should be set to the path to a file containing the Ansible vault password.

Finally, run the configure-hosts playbook.

.. code-block:: console

   ansible-playbook -i ansible/inventory.yml ansible/configure-hosts.yml

This playbook sequentially executes 4 other playbooks:

#. ``fix-homedir-ownership.yml`` - Ensures the ``ansible_user`` owns their home directory. Tag: ``fix-homedir``
#. ``add-fqdn.yml`` - Ensures FQDNs are added to ``/etc/hosts``. Tag: ``fqdn``
#. ``grow-control-host.yml`` - Applies LVM configuration to the control host to ensure it has enough space to continue with the rest of the deployment. Tag: ``lvm`` 
#. ``deploy-openstack-config.yml`` - Deploys the OpenStack configuration to the control host. Tag: ``deploy``

These playbooks are tagged so that they can be invoked or skipped as required. For example, if designate is not being deployed, some time can be saved by skipping the FQDN playbook:

.. code-block:: console

   ansible-playbook -i ansible/inventory.yml ansible/configure-hosts.yml --skip-tags fqdn

Deploy OpenStack
----------------

Once the Ansible control host has been configured with a Kayobe/OpenStack configuration you can then begin the process of deploying OpenStack.
This can be achieved by either manually running the various commands to configures the hosts and deploy the services or automated by using `deploy-openstack.sh`,
which should be available within the homedir on your Ansible control host provided you ran `deploy-openstack-config.yml` earlier.

If you choose to opt for automated method you must first SSH into your Ansible control host and then run the `deploy-openstack.sh` script

.. code-block:: console

   ssh $(terraform output -raw ssh_user)@$(terraform output -raw ansible_control_access_ip_v4)
   ~/deploy-openstack.sh

This script will go through the process of performing the following tasks
   * kayobe control host bootstrap
   * kayobe seed host configure
   * kayobe overcloud host configure
   * cephadm deployment
   * kayobe overcloud service deploy
   * openstack configuration
   * tempest testing

**Note**: When setting up a multinode on a cloud which doesn't have access to test pulp (i.e. everywhere except SMS lab) a separate local pulp must be deployed. Before doing so, it is a good idea to make sure your seed VM has sufficient disk space by setting ``seed_disk_size`` in your ``terraform.tfvars`` to an appropriate value (100-200 GB should suffice). In order to set up the local pulp service on the seed, first obtain/generate a set of Ark credentials using `this workflow <https://github.com/stackhpc/stackhpc-release-train-clients/actions/workflows/create-client-credentials.yml>`_, then add the following configuration to ``etc/kayobe/environments/ci-multinode/stackhpc-ci.yml``

.. code-block:: yaml

   stackhpc_release_pulp_username: <ark-credentials-username>
   stackhpc_release_pulp_password: !vault |
          <vault-encrypted-ark-password>

   pulp_username: admin
   pulp_password: <randomly-generated-password-to-set-for-local-pulp-admin-user>

You may also need to comment out many of the other config overrides in ``stackhpc-ci.yml`` such as ``stackhpc_repo_mirror_url`` plus all of the ``stackhpc_repo_*`` and ``stackhpc_docker_registry*`` variables which only apply to local pulp. 

To create the local pulp as part of the automated deployment, add the following commands to the ``deploy-openstack.sh`` script in between ``kayobe seed service deploy`` and ``kayobe overcloud host configure``:

.. code-block:: console
   
   kayobe seed service deploy --tags seed-deploy-containers --kolla-tags none -e deploy_containers_registry_attempt_login=false
   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp-repo-sync.yml
   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp-repo-publish.yml
   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp-container-sync.yml
   kayobe playbook run $KAYOBE_CONFIG_PATH/ansible/pulp-container-publish.yml


Accessing OpenStack
-------------------

After a successful deployment of OpenStack you make access the OpenStack API and Horizon by proxying your connection via the seed node, as it has an interface on the public network (192.168.39.X).
Using software such as sshuttle will allow for easy access.

.. code-block:: console

   sshuttle -r $(terraform output -raw ssh_user)@$(terraform output -raw seed_access_ip_v4) 192.168.39.0/24

You may also use sshuttle to proxy DNS via the multinode environment. Useful if you are working with Designate. 
Important to node this will proxy all DNS requests from your machine to the first controller within the multinode environment.

.. code-block:: console

   sshuttle -r $(terraform output -raw ssh_user)@$(terraform output -raw seed_access_ip_v4) 192.168.39.0/24 --dns --to-ns 192.168.39.4

Tear Down
---------

After you are finished with the multinode environment please destroy the nodes to free up resources for others.
This can acomplished by using the provided `scripts/tear-down.sh` which will destroy your controllers, compute, seed and storage nodes whilst leaving your Ansible control host and keypair intact.

If you would like to delete your Ansible control host then you can pass the `-a` flag however if you would also like to remove your keypair then pass `-a -k`

Issues & Fixes
--------------

Sometimes a compute instance fails to be provisioned by Terraform or fails on boot for any reason.
If this happens the solution is to mark the resource as tainted and perform terraform apply again which shall destroy and rebuild the failed instance.

.. code-block:: console

   terraform taint 'openstack_compute_instance_v2.controller[2]'
   terraform apply

Also sometimes the provider may fail to notice that some resources are functioning as expected due to timeouts or other network issues.
If you can confirm via Horizon or via SSH that the resource is functioning as expected you may untaint the resource preventing Terraform from destroying on subsequent terraform apply.

.. code-block:: console

   terraform untaint 'openstack_compute_instance_v2.controller[2]'
