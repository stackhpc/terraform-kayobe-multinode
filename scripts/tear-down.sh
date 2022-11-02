#!/bin/shell
# This script is capable of destroying your multinode environment via Terraform in targeted manner.
# As Terraform lacks a skip flag when destroying resources it means that you can only delete
# everything or resources explicitly mentioned with the target flag.
#
# This is less than ideal within the multinode environment as we will want to keep intact the Ansible Control Host and keypair.
# So to solve this issue this script provides an easy way to delete everything but those two resources. 
# However, if you so desire you can delete the Ansible Control and Key with the appropriate flag.
#
# ./tear_down.sh (Deletes everything but key/ansible control host)
# ./tear_down.sh -a (Deletes everything including ansible control host yet leaves key)
# ./tear_down.sh -a -k (Deletes everything including ansible control host and key)
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