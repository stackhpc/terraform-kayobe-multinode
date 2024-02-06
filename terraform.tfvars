prefix = "manual-deployment"

ansible_control_vm_flavor = "general.v1.small"
ansible_control_vm_name   = "ansible-control"
ansible_control_disk_size = 100

seed_vm_flavor = "general.v1.small"
seed_disk_size = 100

multinode_flavor     = "general.v1.medium"
multinode_image      = "rocky9-lvm"
multinode_keypair    = "test-key-pair"
multinode_vm_network = "stackhpc-ipv4-geneve"
multinode_vm_subnet  = "stackhpc-ipv4-geneve-subnet"
compute_count        = "2"
controller_count     = "3"
compute_disk_size    = 100
controller_disk_size = 100

ssh_user         = "cloud-user"

storage_count     = "3"
storage_flavor    = "general.v1.small"
storage_disk_size = 100

deploy_wazuh       = false
infra_vm_flavor    = "general.v1.small"
infra_vm_disk_size = 100