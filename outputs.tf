output "seed_access_ip_v4" {
  value = openstack_compute_instance_v2.kayobe-seed.access_ip_v4
}

output "access_cidr" {
  value = data.openstack_networking_subnet_v2.network.cidr
}

output "access_gw" {
  value = data.openstack_networking_subnet_v2.network.gateway_ip
}

output "access_interface" {
  value = "eth0"
}

output "controller_ips" {
  value = join("\n", formatlist("%s # %s", openstack_compute_instance_v2.controller.*.name, openstack_compute_instance_v2.controller.*.access_ip_v4))
}

output "compute_ips" {
  value = join("\n", formatlist("%s # %s", openstack_compute_instance_v2.compute.*.name, openstack_compute_instance_v2.compute.*.access_ip_v4))
}

output "CephOSD_ips" {
  value = join("\n", formatlist("%s # %s", openstack_compute_instance_v2.Ceph-OSD.*.name, openstack_compute_instance_v2.Ceph-OSD.*.access_ip_v4))
}