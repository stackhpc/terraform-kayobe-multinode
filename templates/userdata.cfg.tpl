#cloud-config
# Don't automatically mount ephemeral disk
mounts:
  - [/dev/vdb, null]
packages:
  - openssh-clients
  - git
  - vim
  - tmux
