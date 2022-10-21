output "ansible_control_access_ip_v4" {
  value = openstack_compute_instance_v2.ansible_control.access_ip_v4
}

output "access_cidr" {
  value = data.openstack_networking_subnet_v2.network.cidr
}

output "access_gw" {
  value = data.openstack_networking_subnet_v2.network.gateway_ip
}

output "controller_ips" {
  value = join("\n", formatlist("%s:  %s", openstack_compute_instance_v2.controller.*.name, openstack_compute_instance_v2.controller.*.access_ip_v4))
}

output "compute_ips" {
  value = join("\n", formatlist("%s: %s", openstack_compute_instance_v2.compute.*.name, openstack_compute_instance_v2.compute.*.access_ip_v4))
}

output "storage_ips" {
  value = join("\n", formatlist("%s: %s", openstack_compute_instance_v2.storage.*.name, openstack_compute_instance_v2.storage.*.access_ip_v4))
}

resource "local_file" "inventory" {
  content = templatefile(
    "${path.module}/templates/ansible_inventory.tpl",
    {
      user                     = "centos"
      prefix                   = "kayobe"
      compute_hostname         = openstack_compute_instance_v2.compute.*.name
      controller_hostname      = openstack_compute_instance_v2.controller.*.name
      ansible_control_hostname = openstack_compute_instance_v2.ansible_control.name
      ansible_control          = openstack_compute_instance_v2.ansible_control.access_ip_v4
      compute                  = openstack_compute_instance_v2.compute.*.access_ip_v4
      controllers              = openstack_compute_instance_v2.controller.*.access_ip_v4
      storage_hostname         = openstack_compute_instance_v2.storage.*.name
      storage                  = openstack_compute_instance_v2.storage.*.access_ip_v4
      seed_hostname = openstack_compute_instance_v2.seed.name
      seed          = openstack_compute_instance_v2.seed.access_ip_v4
    }
  )
  filename = "ansible_inventory"
}
