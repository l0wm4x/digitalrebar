#!/usr/bin/env sh
# public IP address
if [ -z $1 ]; then
    echo "Usage: ./deploy-locally.sh <public-ip-address>/<cidr>"
    echo "E.g.:  ./deploy-locally.sh 10.0.0.1/24 -> choose one of: "
    echo "-------------------------------------------------------------------------"
    ip -4 addr
fi
echo "CHECKLIST:"
echo "----------"
echo ""
echo "Did you updated 'compose/config-dir/api/config/networks/the_admin.json.mac'?"
read -p "Press a key to continue..."
. ./run-in-system.sh --access=HOST --admin-ip=$1 --deploy-admin=local --dr_tag=master --con-provisioner --con-dhcp
