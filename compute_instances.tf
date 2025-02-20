data "openstack_networking_network_v2" "multinode_network" {
  name = var.multinode_vm_network
}

resource "openstack_networking_port_v2" "ansible_control_port" {
  network_id = data.openstack_networking_network_v2.multinode_network.id
  security_group_ids = [data.openstack_networking_secgroup_v2.multinode_security_group.id]
}

data "openstack_networking_secgroup_v2" "multinode_security_group" {
  name = var.ansible_control_security_group
}

resource "openstack_networking_floatingip_v2" "ansible_control_fip" {
  count = var.add_ansible_control_fip ? 1 : 0
  pool = var.ansible_control_fip_pool
}

resource "openstack_networking_floatingip_associate_v2" "ansible_control_fip_association" {
  count = var.add_ansible_control_fip ? 1 : 0
  floating_ip = resource.openstack_networking_floatingip_v2.ansible_control_fip.0.address
  port_id = resource.openstack_networking_port_v2.ansible_control_port.id
}

resource "openstack_compute_instance_v2" "ansible_control" {
  name         = format("%s-%s", var.prefix, var.ansible_control_vm_name)
  flavor_name  = var.ansible_control_vm_flavor
  key_pair     = resource.openstack_compute_keypair_v2.keypair.name
  config_drive = true
  user_data    = file("templates/userdata.cfg.tpl")
  network {
    port = resource.openstack_networking_port_v2.ansible_control_port.id
  }

  dynamic "block_device" {
    for_each = var.ansible_control_disk_size > 0 ? [1] : []
    content {
      uuid                  = data.openstack_images_image_v2.multinode_image.id
      source_type           = "image"
      volume_size           = var.ansible_control_disk_size
      boot_index            = 0
      destination_type      = "volume"
      delete_on_termination = true
      volume_type = var.volume_type == "" ? null : var.volume_type
    }
  }
  timeouts {
    create = "90m"
  }
  lifecycle {
    ignore_changes = [
      user_data
    ]
  }
  tags = var.instance_tags
}

resource "openstack_compute_instance_v2" "seed" {
  name         = format("%s-seed", var.prefix)
  flavor_name  = var.seed_vm_flavor
  key_pair     = resource.openstack_compute_keypair_v2.keypair.name
  config_drive = true
  user_data    = file("templates/userdata.cfg.tpl")
  security_groups = var.security_group
  network {
    name = var.multinode_vm_network
  }

  dynamic "block_device" {
    for_each = var.seed_disk_size > 0 ? [1] : []
    content {
      uuid                  = data.openstack_images_image_v2.multinode_image.id
      source_type           = "image"
      volume_size           = var.seed_disk_size
      boot_index            = 0
      destination_type      = "volume"
      delete_on_termination = true
      volume_type = var.volume_type == "" ? null : var.volume_type
    }
  }
  timeouts {
    create = "90m"
  }
  tags = var.instance_tags
}

resource "openstack_compute_instance_v2" "compute" {
  name         = format("%s-compute-%02d", var.prefix, count.index + 1)
  flavor_name  = var.multinode_flavor
  key_pair     = resource.openstack_compute_keypair_v2.keypair.name
  image_name   = var.multinode_image
  config_drive = true
  user_data    = file("templates/userdata.cfg.tpl")
  count        = var.compute_count
  security_groups = var.security_group
  network {
    name = var.multinode_vm_network
  }
  dynamic "block_device" {
    for_each = var.compute_disk_size > 0 ? [1] : []
    content {
      uuid                  = data.openstack_images_image_v2.multinode_image.id
      source_type           = "image"
      volume_size           = var.compute_disk_size
      boot_index            = 0
      destination_type      = "volume"
      delete_on_termination = true
      volume_type = var.volume_type == "" ? null : var.volume_type
    }
  }
  timeouts {
    create = "90m"
  }
  tags = var.instance_tags
}
resource "openstack_compute_instance_v2" "controller" {
  name         = format("%s-controller-%02d", var.prefix, count.index + 1)
  flavor_name  = var.multinode_flavor
  key_pair     = resource.openstack_compute_keypair_v2.keypair.name
  image_name   = var.multinode_image
  config_drive = true
  user_data    = file("templates/userdata.cfg.tpl")
  count        = var.controller_count
  security_groups = var.security_group
  network {
    name = var.multinode_vm_network
  }
  dynamic "block_device" {
    for_each = var.controller_disk_size > 0 ? [1] : []
    content {
      uuid                  = data.openstack_images_image_v2.multinode_image.id
      source_type           = "image"
      volume_size           = var.controller_disk_size
      boot_index            = 0
      destination_type      = "volume"
      delete_on_termination = true
      volume_type = var.volume_type == "" ? null : var.volume_type
    }
  }
  timeouts {
    create = "90m"
  }

  tags = var.instance_tags
}

resource "openstack_compute_instance_v2" "storage" {
  name         = format("%s-storage-%02d", var.prefix, count.index + 1)
  flavor_name  = var.storage_flavor
  key_pair     = resource.openstack_compute_keypair_v2.keypair.name
  image_name   = var.multinode_image
  config_drive = true
  user_data    = file("templates/userdata.cfg.tpl")
  count        = var.storage_count
  security_groups = var.security_group
  network {
    name = var.multinode_vm_network
  }
  dynamic "block_device" {
    for_each = var.storage_disk_size > 0 ? [1] : []
    content {
      uuid                  = data.openstack_images_image_v2.multinode_image.id
      source_type           = "image"
      volume_size           = var.storage_disk_size
      boot_index            = 0
      destination_type      = "volume"
      delete_on_termination = true
      volume_type = var.volume_type == "" ? null : var.volume_type
    }
  }
  timeouts {
    create = "90m"
  }
  tags = var.instance_tags
}

resource "openstack_compute_instance_v2" "wazuh_manager" {
  name         = format("%s-wazuh-manager-%02d", var.prefix, count.index + 1)
  flavor_name  = var.infra_vm_flavor
  key_pair     = resource.openstack_compute_keypair_v2.keypair.name
  image_name   = var.multinode_image
  config_drive = true
  user_data    = file("templates/userdata.cfg.tpl")
  count        = var.deploy_wazuh ? 1 : 0
  security_groups = var.security_group
  network {
    name = var.multinode_vm_network
  }
  block_device {
    uuid                  = data.openstack_images_image_v2.multinode_image.id
    source_type           = "image"
    volume_size           = var.infra_vm_disk_size
    boot_index            = 0
    destination_type      = "volume"
    delete_on_termination = true
    volume_type = var.volume_type == "" ? null : var.volume_type
  }
  timeouts {
    create = "90m"
  }
  tags = var.instance_tags
}
