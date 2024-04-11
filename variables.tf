variable "storage_count" {
  type = string
}

variable "ssh_public_key" {
  type = string
}

variable "ssh_user" {
  type = string
}

variable "ansible_control_vm_name" {
  type = string
}

variable "seed_vm_flavor" {
  type = string
}

variable "prefix" {
  type    = string
}

variable "compute_count" {
  type = string
}

variable "controller_count" {
  type = string
}

variable "multinode_image" {
  type = string
}

variable "multinode_keypair" {
  type = string
}

variable "ansible_control_vm_flavor" {
  type = string
}

variable "multinode_flavor" {
  type = string
}

variable "storage_flavor" {
  type = string
}

variable "infra_vm_flavor" {
  type = string
}

variable "multinode_vm_network" {
  type = string
}

variable "multinode_vm_subnet" {
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
