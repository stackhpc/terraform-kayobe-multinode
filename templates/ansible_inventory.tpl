[seed]
${seed_hostname} ansible_host=${seed} ansible_user=${user}
[computes]
%{ for index, ip in computes ~}
${compute_hostname[index]} ansible_host=${ip} ansible_user=${user}
%{ endfor ~}
[controllers]
%{ for index, ip in controllers ~}
${controller_hostname[index]} ansible_host=${ip} ansible_user=${user}
%{ endfor ~}
[cephOSDs]
%{ for index, ip in cephOSDs ~}
${cephOSD_hostname[index]} ansible_host=${ip} ansible_user=${user}
%{endfor ~}