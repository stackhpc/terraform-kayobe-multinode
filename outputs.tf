output "ansible_control_access_ip_v4" {
  value = openstack_compute_instance_v2.ansible_control.access_ip_v4
}

resource "local_file" "hosts" {
  content = templatefile(
    "${path.module}/templates/hosts.tpl",
    {
      compute_hostname         = openstack_compute_instance_v2.compute.*.name
      controller_hostname      = openstack_compute_instance_v2.controller.*.name
      ansible_control_hostname = openstack_compute_instance_v2.ansible_control.name
      storage_hostname         = openstack_compute_instance_v2.storage.*.name
      seed_hostname            = openstack_compute_instance_v2.seed.name
      wazuh_manager_hostname   = openstack_compute_instance_v2.wazuh_manager.*.name
    }
  )
  filename        = "ansible/files/hosts"
  file_permission = "0644"
}

resource "local_file" "admin_networks" {
  content = templatefile(
    "${path.module}/templates/admin-oc-networks.tpl",
    {
      access_cidr              = data.openstack_networking_subnet_v2.network.cidr
      compute_hostname         = openstack_compute_instance_v2.compute.*.name
      controller_hostname      = openstack_compute_instance_v2.controller.*.name
      ansible_control_hostname = openstack_compute_instance_v2.ansible_control.name
      ansible_control          = openstack_compute_instance_v2.ansible_control.access_ip_v4
      compute                  = openstack_compute_instance_v2.compute.*.access_ip_v4
      controllers              = openstack_compute_instance_v2.controller.*.access_ip_v4
      storage_hostname         = openstack_compute_instance_v2.storage.*.name
      storage                  = openstack_compute_instance_v2.storage.*.access_ip_v4
      seed_hostname            = openstack_compute_instance_v2.seed.name
      seed                     = openstack_compute_instance_v2.seed.access_ip_v4
      wazuh_manager_hostname   = openstack_compute_instance_v2.wazuh_manager.*.name
      wazuh_manager            = openstack_compute_instance_v2.wazuh_manager.*.access_ip_v4
    }
  )
  filename        = "ansible/files/admin-oc-networks.yml"
  file_permission = "0644"
}

resource "local_file" "openstack_inventory" {
  content = templatefile(
    "${path.module}/templates/openstack-inventory.tpl",
    {
      seed_addr   = openstack_compute_instance_v2.seed.access_ip_v4,
      ssh_user    = var.ssh_user
    }
  )
  filename        = "ansible/files/openstack-inventory"
  file_permission = "0644"
}

resource "local_file" "deploy_openstack" {
  content = templatefile(
    "${path.module}/templates/deploy-openstack.tpl",
    {
      seed_addr           = openstack_compute_instance_v2.seed.access_ip_v4,
      ssh_user            = var.ssh_user,
      deploy_wazuh        = var.deploy_wazuh
      controller_hostname = openstack_compute_instance_v2.controller.*.name
    }
  )
  filename        = "ansible/files/deploy-openstack.sh"
  file_permission = "0755"
}
