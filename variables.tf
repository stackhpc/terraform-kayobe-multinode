variable "storage_count" {
  description = "Number of storage hosts"
  type = string
}

variable "ssh_public_key" {
  description = "Path to an SSH public key to register as a keypair in OpenStack"
  type = string
}

variable "ssh_user" {
  description = "Username to use for SSH access to host"
  type = string
}

variable "ansible_control_vm_name" {
  description = "Name of the Ansible control host"
  type = string
}

variable "seed_vm_flavor" {
  description = "OpenStack flavor to use for the seed VM"
  type = string
}

variable "prefix" {
  description = "A prefix to apply the name of all hosts"
  type    = string
}

variable "compute_count" {
  description = "Number of compute hosts"
  type = string
}

variable "controller_count" {
  description = "Number of controller hosts"
  type = string
}

variable "multinode_image" {
  description = "Name of an image registered in Glance with which to deploy hosts"
  type = string
}

variable "multinode_keypair" {
  description = "Name of an SSH keypair to register in OpenStack"
  type = string
}

variable "ansible_control_vm_flavor" {
  description = "OpenStack flavor to use for the Ansible control host"
  type = string
}

variable "multinode_flavor" {
  description = "OpenStack flavor to use for the controller and compute hosts"
  type = string
}

variable "storage_flavor" {
  description = "OpenStack flavor to use for the storage hosts"
  type = string
}

variable "infra_vm_flavor" {
  description = "OpenStack flavor to use for the Wazuh VM"
  type = string
}

variable "multinode_vm_network" {
  description = "OpenStack network to attach hosts to"
  type = string
}

variable "multinode_vm_subnet" {
  description = "OpenStack subnet to attach hosts to"
  type = string
}

variable "compute_disk_size" {
  description = "Block storage root disk size for compute nodes in GB. Set to 0 on baremetal to use physical storage."
  type = number
}

variable "controller_disk_size" {
  description = "Block storage root disk size for controller nodes in GB. Set to 0 on baremetal to use physical storage."
  type = number
}

variable "ansible_control_disk_size" {
  description = "Block storage root disk size for the ansible control node in GB. Set to 0 on baremetal to use physical storage."
  type = number
  default = 100
}

variable "seed_disk_size" {
  description = "Block storage root disk size for the seed node in GB. Set to 0 on baremetal to use physical storage."
  type = number
  default = 100
}

variable "storage_disk_size" {
  description = "Block storage root disk size for storage nodes in GB. Set to 0 on baremetal to use physical storage."
  type = number
  default = 100
}

variable "infra_vm_disk_size" {
  description = "Block storage root disk size for infrastructure VMs."
  type = number
  default = 100
}

variable "deploy_wazuh" {
  description = "Bool, whether or not to deploy Wazuh."
  type = bool
  default = false
}

variable "add_ansible_control_fip" {
  description = "Bool, whether to add a floating IP address to the Ansible control host."
  type = bool
  default = false
}

variable "ansible_control_fip_pool" {
  description = "Pool/network from which to allocate a floating IP for the Ansible control host."
  type = string
  default = ""
}

variable "volume_type" {
  description = "Volume type to use for block storage. Set to empty string to use the default volume type."
  type = string
  default = ""
}

variable "instance_tags" {
  description = "Set of tags to be applied to all instances"
  type = list(string)
  default = []
}

variable "security_group" {
  description = "Set a list of chosen security group to apply to instances. Set to empty string to use the default security group."
  type = list(string)
  default = []
}

variable "ansible_control_security_group" {
  description = "Set a chosen security group for the ansible control host. Set to empty string to use the default security group."
  type = string
  default = ""
}
