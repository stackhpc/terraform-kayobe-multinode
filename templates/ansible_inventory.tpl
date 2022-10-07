[seed]
${seed_hostname}
[compute]
%{ for index, ip in compute ~}
${compute_hostname[index]}
%{ endfor ~}
[controllers]
%{ for index, ip in controllers ~}
${controller_hostname[index]}
%{ endfor ~}
[cephOSDs]
%{ for index, ip in cephOSDs ~}
${cephOSD_hostname[index]}
%{endfor ~}
