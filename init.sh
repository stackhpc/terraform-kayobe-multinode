terraform -chdir=$(dirname $0) init
echo -n "OpenStack Cloud Name: "
read OS_CLOUD
export OS_CLOUD

echo -n "Password: "
read -s OS_PASSWORD
export OS_PASSWORD
