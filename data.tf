data "openstack_images_image_v2" "multinode_image" {
  name        = var.multinode_image
  most_recent = true
}

data "openstack_networking_subnet_v2" "network" {
  name = var.multinode_vm_subnet
}