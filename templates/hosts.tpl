[controllers]
%{ for element in controller_hostname ~}
${ element }
%{ endfor ~}

[compute]
%{ for element in compute_hostname ~}
${ element }
%{ endfor ~}

[seed]
${seed_hostname}

[storage:children]
ceph

[ceph:children]
mons
mgrs
osds
rgws

[mons]
%{ for element in storage_hostname ~}
${ element }
%{ endfor ~}

[mgrs]
%{ for element in storage_hostname ~}
${ element }
%{ endfor ~}

[osds]
%{ for element in storage_hostname ~}
${ element }
%{ endfor ~}

[rgws]

[monitoring:children]
controllers

[wazuh-manager]
%{ for element in wazuh_manager_hostname ~}
${ element }
%{ endfor ~}

[infra-vms:children]
wazuh-manager
