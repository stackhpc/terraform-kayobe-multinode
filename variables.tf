variable "storage_count" {
  type = string
}

variable "ssh_public_key" {
  type = string
}

variable "ansible_control_vm_name" {
  type = string
}

variable "prefix" {
  type    = string
  default = "kayobe-mn"
}

variable "compute_count" {
  type = string
}

variable "controller_count" {
  type = string
}

variable "ansible_control_vm_image" {
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

variable "multinode_vm_network" {
  type = string
}

variable "multinode_vm_subnet" {
  type = string
}
