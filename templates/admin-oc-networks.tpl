---
admin_oc_cidr: ${ access_cidr }
admin_oc_allocation_pool_start: 0.0.0.0
admin_oc_allocation_pool_end: 0.0.0.0
admin_oc_bootproto: dhcp

admin_oc_ips:
%{ for hostname, addr in zipmap(controller_hostname, controllers) ~}
  ${ hostname }: ${ addr }
%{ endfor ~}
%{ for hostname, addr in zipmap(compute_hostname, compute) ~}
  ${ hostname }: ${ addr }
%{ endfor ~}
  ${seed_hostname}: ${seed}
%{ for hostname, addr in zipmap(storage_hostname, storage) ~}
  ${ hostname }: ${ addr }
%{ endfor ~}