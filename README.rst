==========================
Terraform Kayobe Multinode
==========================

This Terraform configuration deploys a requested amount of instances on an OpenStack cloud, to be
used as a Multinode Kayobe test environment. This includes:

* 1x Ansible control host
* 1x seed host
* controller hosts
* compute hosts
* Ceph storage hosts
* Optional Wazuh manager host

The high-level workflow to deploy a cluster is as follows:

* Prerequisites
* Configure Terraform and Ansible
* Deploy infrastructure on OpenStack using Terraform
* Configure Ansible control host using Ansible
* Deploy multi-node OpenStack using Kayobe

This configuration is typically used with the `ci-multinode` environment in the
`StackHPC Kayobe Configuration
<https://stackhpc-kayobe-config.readthedocs.io/en/stackhpc-yoga/contributor/environments/ci-multinode.html>`__
repository.

Prerequisites
=============

These instructions show how to use this Terraform configuration manually. They
assume you are running an Ubuntu host that will be used to run Terraform. The
machine should have access to the API of the OpenStack cloud that will host the
infrastructure, and network access to the Ansible control host once it has been
deployed. This may be achieved by direct SSH access, a floating IP on the
Ansible control host, or using an SSH bastion.

The OpenStack cloud should have sufficient capacity to deploy the
infrastructure, and a suitable image registered in Glance. Ideally the image
should be one of the overcloud host images defined in StackHPC Kayobe
configuration and available in `Ark <https://ark.stackhpc.com>`__.

Install Terraform:

.. code-block:: console

   wget -qO - terraform.gpg https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/terraform-archive-keyring.gpg
   sudo echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/terraform-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/terraform.list
   sudo apt update
   sudo apt install git terraform

Clone and initialise this Terraform config repository:

.. code-block:: console

   git clone https://github.com/stackhpc/terraform-kayobe-multinode
   cd terraform-kayobe-multinode

Initialise Terraform:

.. code-block:: console

   terraform init

Generate an SSH keypair. The public key will be registered in OpenStack as a
keypair and authorised by the instances deployed by Terraform. The private and
public keys will be transferred to the Ansible control host to allow it to
connect to the other hosts. Note that password-protected keys are not currently
supported.

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

You must ensure that you have `Ansible installed <https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html>`_ on your local machine.

.. code-block:: console

   pip install --user ansible

Install the Ansible galaxy requirements.

.. code-block:: console

   ansible-galaxy install -r ansible/requirements.yml

If the deployed instances are behind an SSH bastion you must ensure that your SSH config is setup appropriately with a proxy jump.

.. code-block::

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

Configure Terraform variables
=============================

Populate Terraform variables in `terraform.tfvars`. Examples are provided in
files named `*.tfvars.example`. The available variables are defined in
`variables.tf` along with their type, description, and optional default.

You will need to set the `multinode_keypair`, `prefix`, and `ssh_public_key`.
By default, Rocky Linux 9 will be used but Ubuntu Jammy is also supported by
changing `multinode_image` to `overcloud-ubuntu-jammy-<release>-<datetime>` and
`ssh_user` to `ubuntu`.

The `multinode_flavor` will change the flavor used for controller and compute
nodes. Both virtual machines and baremetal are supported, but the `*_disk_size`
variables must be set to 0 when using baremetal host. This will stop a block
device being allocated. When any baremetal hosts are deployed, the
`multinode_vm_network` and `multinode_vm_subnet` should also be changed to
a VLAN network and associated subnet.

If `deploy_wazuh` is set to true, an infrastructure VM will be created that
hosts the Wazuh manager. The Wazuh deployment playbooks will also be triggered
automatically to deploy Wazuh agents to the overcloud hosts.

If `add_ansible_control_fip` is set to `true`, a floating IP will be created
and attached to the Ansible control host. In that case
`ansible_control_fip_pool` should be set to the name of the pool (network) from
which to allocate the floating IP, and the floating IP will be used for SSH
access to the control host.

Configure Ansible variables
===========================

Review the vars defined within `ansible/vars/defaults.yml`. In here you can customise the version of kayobe, kayobe-config or openstack-config. 
Make sure to define `ssh_key_path` to point to the location of the SSH key in use by the nodes and also `vxlan_vni` which should be unique value between 1 to 100,000.
VNI should be much smaller than the officially supported limit of 16,777,215 as we encounter errors when attempting to bring interfaces up that use a high VNI.
You must set `vault_password_path`; this should be set to the path to a file containing the Ansible vault password.

Deployment
==========

Generate a plan:

.. code-block:: console

   terraform plan

Apply the changes:

.. code-block:: console

   terraform apply -auto-approve

You should have requested a number of resources to be spawned on Openstack.

Configure Ansible control host
==============================

Run the configure-hosts.yml playbook to configure the Ansible control host.

.. code-block:: console

   ansible-playbook -i ansible/inventory.yml ansible/configure-hosts.yml

This playbook sequentially executes 2 other playbooks:

#. ``grow-control-host.yml`` - Applies LVM configuration to the control host to ensure it has enough space to continue with the rest of the deployment. Tag: ``lvm`` 
#. ``deploy-openstack-config.yml`` - Prepares the Ansible control host as a Kayobe control host, cloning the Kayobe configuration and installing virtual environments. Tag: ``deploy``

These playbooks are tagged so that they can be invoked or skipped using `tags` or `--skip-tags` as required.

Deploy OpenStack
================

Once the Ansible control host has been configured with a Kayobe/OpenStack configuration you can then begin the process of deploying OpenStack.
This can be achieved by either manually running the various commands to configure the hosts and deploy the services or automated by using the generated `deploy-openstack.sh` script.
`deploy-openstack.sh` should be available within the home directory on your Ansible control host provided you ran `deploy-openstack-config.yml` earlier.
This script will go through the process of performing the following tasks:

   * kayobe control host bootstrap
   * kayobe seed host configure
   * kayobe overcloud host configure
   * cephadm deployment
   * kayobe overcloud service deploy
   * openstack configuration
   * tempest testing

Tempest test results will be written to `~/tempest-artifacts`.

If you choose to opt for the automated method you must first SSH into your Ansible control host.

.. code-block:: console

   ssh $(terraform output -raw ssh_user)@$(terraform output -raw ansible_control_access_ip_v4)

Start a `tmux` session to avoid halting the deployment if you are disconnected.

.. code-block:: console

   tmux

Run the `deploy-openstack.sh` script.

.. code-block:: console

   ~/deploy-openstack.sh

Accessing OpenStack
===================

After a successful deployment of OpenStack you make access the OpenStack API and Horizon by proxying your connection via the seed node, as it has an interface on the public network (192.168.39.X).
Using software such as sshuttle will allow for easy access.

.. code-block:: console

   sshuttle -r $(terraform output -raw ssh_user)@$(terraform output -raw seed_access_ip_v4) 192.168.39.0/24

You may also use sshuttle to proxy DNS via the multinode environment. Useful if you are working with Designate. 
Important to node this will proxy all DNS requests from your machine to the first controller within the multinode environment.

.. code-block:: console

   sshuttle -r $(terraform output -raw ssh_user)@$(terraform output -raw seed_access_ip_v4) 192.168.39.0/24 --dns --to-ns 192.168.39.4

Tear Down
=========

After you are finished with the multinode environment please destroy the nodes to free up resources for others.
This can acomplished by using the provided `scripts/tear-down.sh` which will destroy your controllers, compute, seed and storage nodes whilst leaving your Ansible control host and keypair intact.

If you would like to delete your Ansible control host then you can pass the `-a` flag however if you would also like to remove your keypair then pass `-a -k`

Issues & Fixes
==============

Sometimes a compute instance fails to be provisioned by Terraform or fails on boot for any reason.
If this happens the solution is to mark the resource as tainted and perform terraform apply again which shall destroy and rebuild the failed instance.

.. code-block:: console

   terraform taint 'openstack_compute_instance_v2.controller[2]'
   terraform apply

Also sometimes the provider may fail to notice that some resources are functioning as expected due to timeouts or other network issues.
If you can confirm via Horizon or via SSH that the resource is functioning as expected you may untaint the resource preventing Terraform from destroying on subsequent terraform apply.

.. code-block:: console

   terraform untaint 'openstack_compute_instance_v2.controller[2]'
