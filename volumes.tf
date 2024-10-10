resource "openstack_blockstorage_volume_v3" "volumes" {
  count = var.storage_count
  name  = format("%s-osd-%02d", var.prefix, count.index + 1)
  size  = 40
  var.volume_type == "" ? null : var.volume_type
}

resource "openstack_compute_volume_attach_v2" "attachments" {
  count       = var.storage_count
  instance_id = openstack_compute_instance_v2.storage.*.id[count.index]
  volume_id   = openstack_blockstorage_volume_v3.volumes.*.id[count.index]
}