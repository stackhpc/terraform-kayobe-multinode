[seed]

[compute]
%{ for index, ip in compute ~}
${compute_hostname[index]}
%{ endfor ~}
[controllers]
%{ for index, ip in controllers ~}
${controller_hostname[index]}
%{ endfor ~}
[storage]
%{ for index, ip in storage ~}
${storage_hostname[index]}
%{endfor ~}
