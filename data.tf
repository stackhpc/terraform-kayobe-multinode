data "openstack_images_image_v2" "ansible_image" {
  name        = var.ansible_control_vm_image
  most_recent = true
}

data "openstack_images_image_v2" "seed_image" {
  name        = var.seed_vm_image
  most_recent = true
}

data "openstack_networking_subnet_v2" "network" {
  name = var.multinode_vm_subnet
}