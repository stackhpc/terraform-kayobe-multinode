variable "owner" {
  type = string
  default = "grzegorzkoper"
}
variable "cephOSD_count" {
  type    = string
}

variable "repo_name" {
  type = string
  default = "stackhpc/stackhpc-kayobe-config"
}

variable "ssh_private_key" {
  type = string
}

variable "ssh_public_key" {
  type = string
}

variable "seed_vm_name" {
  type    = string
  default = "kayobe-seed"
}

variable "prefix" {
  type    = string
  default = "kayobe"
}

variable "compute_count" {
  type    = string
}

variable "controller_count" {
  type    = string
}

variable "seed_vm_image" {
  type    = string
  default = "CentOS-stream8"
}

variable "multinode_image" {
  type    = string
  default = "CentOS-stream8"
}
variable "multinode_keypair" {
  type = string
}

variable "seed_vm_flavor" {
  type = string
}

variable "multinode_flavor" {
  type = string
  default = "general.v1.tiny"
}

variable "seed_vm_network" {
  type = string
}

variable "seed_vm_subnet" {
  type = string
}
