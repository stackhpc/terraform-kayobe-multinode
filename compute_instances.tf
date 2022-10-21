resource "openstack_compute_instance_v2" "ansible_control" {
  name         = format("%s-%s", var.prefix, var.ansible_control_vm_name)
  flavor_name  = var.ansible_control_vm_flavor
  key_pair     = var.multinode_keypair
  config_drive = true
  user_data    = file("templates/userdata.cfg.tpl")
  network {
    name = var.multinode_vm_network
  }

  block_device {
    uuid                  = data.openstack_images_image_v2.multinode_image.id
    source_type           = "image"
    volume_size           = 100
    boot_index            = 0
    destination_type      = "volume"
    delete_on_termination = true
  }
}

resource "openstack_compute_instance_v2" "seed" {
  name         = format("%s-seed", var.prefix)
  flavor_name  = var.seed_vm_flavor
  key_pair     = var.multinode_keypair
  config_drive = true
  user_data    = file("templates/userdata.cfg.tpl")
  network {
    name = var.multinode_vm_network
  }

  block_device {
    uuid                  = data.openstack_images_image_v2.multinode_image.id
    source_type           = "image"
    volume_size           = 100
    boot_index            = 0
    destination_type      = "volume"
    delete_on_termination = true
  }
}

resource "openstack_compute_instance_v2" "compute" {
  name         = format("%s-compute-%02d", var.prefix, count.index + 1)
  flavor_name  = var.multinode_flavor
  key_pair     = var.multinode_keypair
  image_name   = var.multinode_image
  config_drive = true
  user_data    = file("templates/userdata.cfg.tpl")
  count        = var.compute_count
  network {
    name = var.multinode_vm_network
  }
}
resource "openstack_compute_instance_v2" "controller" {
  name         = format("%s-controller-%02d", var.prefix, count.index + 1)
  flavor_name  = var.multinode_flavor
  key_pair     = var.multinode_keypair
  image_name   = var.multinode_image
  config_drive = true
  user_data    = file("templates/userdata.cfg.tpl")
  count        = var.controller_count
  network {
    name = var.multinode_vm_network
  }
}

resource "openstack_compute_instance_v2" "storage" {
  name         = format("%s-storage-%02d", var.prefix, count.index + 1)
  flavor_name  = var.storage_flavor
  key_pair     = var.multinode_keypair
  image_name   = var.multinode_image
  config_drive = true
  user_data    = file("templates/userdata.cfg.tpl")
  count        = var.storage_count
  network {
    name = var.multinode_vm_network
  }
  block_device {
    uuid                  = data.openstack_images_image_v2.multinode_image.id
    source_type           = "image"
    volume_size           = 30
    boot_index            = 0
    destination_type      = "volume"
    delete_on_termination = true
  }
}
