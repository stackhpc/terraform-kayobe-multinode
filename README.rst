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
   sudo apt install terraform

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
OpenStack cloud. Alternatively, download one from Horizon.

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

Export environment variables to use the correct cloud and provide a password:

.. code-block:: console

   export OS_CLOUD=sms-lab
   read -p OS_PASSWORD -s OS_PASSWORD
   export OS_PASSWORD

Or you can source the provided `init.sh` script which shall initialise terraform and export two variables.
`OS_CLOUD` is a variable which is used by Terraform and must match an entry within `clouds.yml`.
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
   ansible_control_vm_flavor = "general.v1.small"
   ansible_control_vm_name   = "ansible-control"
   compute_count    = "2"
   controller_count = "3"
   multinode_flavor     = "changeme"
   multinode_image      = "CentOS-stream8-lvm"
   multinode_keypair    = "changeme"
   multinode_vm_network = "stackhpc-ipv4-vlan-v2"
   multinode_vm_subnet  = "stackhpc-ipv4-vlan-subnet-v2"
   prefix = "changeme"
   seed_vm_flavor = "general.v1.small"
   ssh_public_key = "~/.ssh/changeme.pub"
   storage_count  = "3"
   storage_flavor = "general.v1.small"
   EOF

Generate a plan:

.. code-block:: console

   terraform plan

Apply the changes:

.. code-block:: console

   terraform apply -auto-approve

You should have requested number of resources spawned on Openstack, and ansible_inventory file produced as output for Kayobe.

Copy your generated id_rsa and id_rsa.pub to ~/.ssh/ on Ansible control host if you want Kayobe to automatically pick them up during bootstrap.

Configure Ansible control host

Using the `deploy-openstack-config.yml` playbook you can setup the Ansible control host to include the kayobe/kayobe-config repositories with `hosts` and `admin-oc-networks`.
It shall also setup the kayobe virtual environment, allowing for immediate configure and deployment of OpenStack.

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

Review the vars defined within `defaults.yml` in here you can customise the version of kayobe, kayobe-config or openstack-config. 
However, make sure to define `ssh_key_path` to point to the location of the SSH key in use amongst the nodes and also `vxlan_vni` which should be unique value between 1 to 16,777,215.

Finally run the ansible playbooks. 
You may need to run `fix-homedir-ownership.yml` if you are using an image that has `ansible_user` not owning their own home folder.
You may also need to run `grow-control-host.yml` if you are using LVM images and the LVMs are too small to install Ansible.
If not you can skip that playbook and proceed onto `deploy-openstack-config` which shall configure your Ansible control host in preparation for deployment.

.. code-block:: console

   ANSIBLE_REMOTE_TMP=/tmp/ansible/tmp ansible-playbook -i $(terraform output -raw ansible_control_access_ip_v4), ansible/fix-homedir-ownership.yml
   ansible-playbook -i $(terraform output -raw ansible_control_access_ip_v4), ansible/grow-control-host.yml -e ansible_user=cloud-user
   ansible-playbook -i $(terraform output -raw ansible_control_access_ip_v4), ansible/deploy-openstack-config.yml -e ansible_user=cloud-user

Deploy OpenStack
----------------

Once the Ansible control host has been configured with a Kayobe/OpenStack config present you can then begin the process of deploying OpenStack.
This can be achieved by either manually running the various commands to configures the hosts and deploy the services or automated by using `deploy-openstack.sh`,
which should be available within the homedir on your Ansible control host provided you ran `deploy-openstack-config.yml` earlier.

If you choose to opt for automated method you must first SSH into your Ansible control host and then run the `deploy-openstack.sh` script

.. code-block:: console

   ssh centos@${ansible_ip}
   ~/deploy-openstack.sh

This script will go through the process of performing the following tasks
   * kayobe control host bootstrap
   * kayobe seed host configure
   * kayobe overcloud host configure
   * cephadm deployment
   * kayobe overcloud service deploy
   * openstack configuration
   * tempest testing

Tear Down
---------

After you are finished with the multinode environment please destroy the nodes to free up resources for others.
This can acomplished by using the provided `scripts/tear-down.sh` which will destroy your controllers, compute, seed and storage nodes whilst leaving your Ansible control host and keypair intact.

If you would like to delete your Ansible control host then you can pass the `-a` flag however if you would also like to remove your keypair then pass `-a -k`