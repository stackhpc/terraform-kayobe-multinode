mydir=$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)
tofu -chdir="$mydir" init
echo -n "OpenStack Cloud Name: "
read OS_CLOUD
export OS_CLOUD

echo -n "Password: "
read -s OS_PASSWORD
export OS_PASSWORD
