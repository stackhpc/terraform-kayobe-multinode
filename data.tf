data "openstack_images_image_v2" "image" {
  name        = var.ansible-control_vm_image
  most_recent = true
}

data "openstack_networking_subnet_v2" "network" {
  name = var.multinode_vm_subnet
}