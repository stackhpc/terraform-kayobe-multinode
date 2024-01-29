resource "openstack_compute_keypair_v2" "keypair" {
  name       = var.multinode_keypair
  public_key = var.ssh_public_key
}