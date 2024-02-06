#!/bin/bash

# # Update apt and apt-get
# sudo apt update -y
# sudo apt-get update -y

# # Install Brew
# NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" && (echo; echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"') >> /home/ubuntu/.profile && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

# #Check if the terraform and ansible are installed
# brew install terraform openstackclient
# pip install --user ansible

# # Install ansible requirements
# ansible-galaxy install -r requirements.yml

# Make inventory directory and hosts file
mkdir -p inventory
echo '[openstack]' > inventory/hosts
echo 'localhost ansible_connection=local ansible_python_interpreter=/usr/bin/python3' >> inventory/hosts

# Create clouds.yaml file
cat << EOF > clouds.yaml
clouds:
  sms-lab:
    auth:
      auth_url: https://api.sms-lab.cloud:5000
      username: <set_OS_username>
      project_name: <set_OS_project_name>
      domain_name: default
    interface: "public"
    identity_api_version: 3
    region_name: "RegionOne"
EOF

# Run init.sh
export OS_CLOUD=sms-lab
read -p OS_PASSWORD -s OS_PASSWORD
export OS_PASSWORD

export ssh_public_key_path="~/.ssh/id_rsa.pub"

#Deploy terraform infrastructure via ansible
ansible-playbook multinode-app.yml -i inventory -e manual_deployment=true -e ssh_public_key_path=$ssh_public_key_path -e OS_CLOUD=sms-lab -e OS_PASSWORD=$OS_PASSWORD -e OS_CLIENT_CONFIG_FILE=./clouds.yaml


