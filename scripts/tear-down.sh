#!/bin/sh
set -euxo pipefail

ALL=false
KEY=false

while getopts "ak" arg; do
  case $arg in
    a)
      ALL=true
      ;;
    k)
      KEY=true
      ;;
  esac
done

if [ $ALL == true ]; then
    if [ $KEY == false ]; then
      terraform destroy \
        -target=openstack_compute_instance_v2.ansible_control \
        -target=openstack_compute_instance_v2.controller \
        -target=openstack_compute_instance_v2.compute \
        -target=openstack_compute_instance_v2.seed \
        -target=openstack_compute_instance_v2.storage \
        -target=openstack_blockstorage_volume_v3.volumes \
        -target=openstack_compute_volume_attach_v2.attachments
    else
      terraform destroy
    fi
else
  terraform destroy -target=openstack_compute_instance_v2.controller \
    -target=openstack_compute_instance_v2.compute \
    -target=openstack_compute_instance_v2.seed \
    -target=openstack_compute_instance_v2.storage \
    -target=openstack_blockstorage_volume_v3.volumes \
    -target=openstack_compute_volume_attach_v2.attachments
fi