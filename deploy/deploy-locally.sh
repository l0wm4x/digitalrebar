#!/usr/bin/env sh
# public IP address
if [ -z $1 ]; then
    echo "Usage: ./deploy-locally.sh <public-ip-address>/<cidr>"
    echo "E.g.:  ./deploy-locally.sh 10.0.0.1/24 -> choose one of: "
    echo "-------------------------------------------------------------------------"
    ip -4 addr
    exit 1
fi
echo "DO NOT FORGET:"
echo "--------------"
echo ""
echo "Did you updated 'compose/config-dir/api/config/networks/the_admin.json.mac'?"
echo '{'
echo '  "category": "admin",'
echo '  "group": "internal",'
echo '  "deployment": "system",'
echo '  "conduit": "dhcp",'
echo '  "v6prefix": "none",'
echo '  "ranges": ['
echo '    {'
echo '      "name": "dhcp",'
echo '      "first": "147.75.XXXXXXX/28",'
echo '      "last": "147.75.XXXXXXXX/28",'
echo '      "allow_anon_leases": true'
echo '    }'
echo '  ],'
echo '  "router": {'
echo '    "address": "147.75.XXXXXXXX/28",'
echo '    "pref": 10'
echo '  }'
echo '}'
read -p "Press a key to continue..."

./run-in-system.sh --access=HOST --admin-ip=$1 --deploy-admin=local --dr_tag=master --con-provisioner --con-dhcp
