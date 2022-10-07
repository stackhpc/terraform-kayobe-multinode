data "openstack_images_image_v2" "image" {
  name        = var.seed_vm_image
  most_recent = true
}

data "openstack_networking_subnet_v2" "network" {
  name = var.multinode_vm_subnet
}

resource "openstack_compute_keypair_v2" "keypair" {
  name = var.multinode_keypair
  public_key = file(var.ssh_public_key)
}

resource "openstack_compute_instance_v2" "kayobe-seed" {
  name         = var.seed_vm_name
  flavor_name  = var.seed_vm_flavor
  key_pair     = var.multinode_keypair
  config_drive = true
  user_data    = file("templates/userdata.cfg.tpl")
  network {
    name = var.multinode_vm_network
  }

  block_device {
    uuid                  = data.openstack_images_image_v2.image.id
    source_type           = "image"
    volume_size           = 100
    boot_index            = 0
    destination_type      = "volume"
    delete_on_termination = true
  }

  provisioner "file" {
    source      = "scripts/hello.sh"
    destination = "/home/centos/hello.sh"

    connection {
      type        = "ssh"
      host        = self.access_ip_v4
      user        = "centos"
      agent       = true
      private_key = file(var.ssh_private_key)
    }
  }

  provisioner "remote-exec" {
    inline = [
      "bash /home/centos/hello.sh"
    ]

    connection {
      type        = "ssh"
      host        = self.access_ip_v4
      user        = "centos"
      agent       = true
      private_key = file(var.ssh_private_key)
    }

  }
}
resource "openstack_compute_instance_v2" "compute" {
  name         = format("%s-compute-%02d", var.prefix, count.index +1)
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
  name         = format("%s-controller-%02d", var.prefix, count.index +1)
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

resource "openstack_blockstorage_volume_v3" "volumes" {
  count = var.cephOSD_count
  name = format("%s-osd-%02d", var.prefix, count.index +1)
  size = 20
}

resource "openstack_compute_instance_v2" "Ceph-OSD" {
  name         = format("%s-cephOSD-%02d", var.prefix, count.index +1)
  flavor_name  = var.ceph_flavor
  key_pair     = var.multinode_keypair
  image_name   = var.multinode_image
  config_drive = true
  user_data    = file("templates/userdata.cfg.tpl")
  count        = var.cephOSD_count
  network {
    name = var.multinode_vm_network
  }
  block_device {
    uuid                  = data.openstack_images_image_v2.image.id
    source_type           = "image"
    volume_size           = 30
    boot_index            = 0
    destination_type      = "volume"
    delete_on_termination = true
  }  
}

resource "openstack_compute_volume_attach_v2" "attachments" {
  count = var.cephOSD_count
  instance_id = openstack_compute_instance_v2.Ceph-OSD.*.id[count.index]
  volume_id = openstack_blockstorage_volume_v3.volumes.*.id[count.index]
}

