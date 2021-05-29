#!/bin/bash
source /opt/ivy/bash_functions.sh

IS_MASTER=$1
NODE_NAME=$2

CONFIGFILE="/etc/sysconfig/consul"
SYSENV=$(get_sysenv)
SYSENV_ALIAS=$(get_sysenv_alias)
TAG=$(get_ivy_tag)

sed -i -e '/^#.*__IVY_TAG__/s/^#//' -e "s/__IVY_TAG__/${TAG}/" /etc/dnsmasq.d/10-dnsmasq

CONSUL_MASTERS=""
if [[ $(get_cloud) -eq "aws" ]]; then
   MESOS_IPS=($(aws ec2 describe-network-interfaces --region $(get_region) \
                   --filters Name=tag:"${TAG}:sysenv",Values="${SYSENV}"   \
                             Name=tag:"${TAG}:service",Values="Mesos"      \
                   --query 'NetworkInterfaces[*].PrivateIpAddress'         \
                   --output text))

    for IP in "${MESOS_IPS[@]}"; do
      CONSUL_MASTERS="${CONSUL_MASTERS} -retry-join=${IP}"
    done

    # Use tag key of $prefix:consul_master = $env
    # Disabled - cloud auto join finds instance ips, not ENIs
    #CONSUL_MASTERS="-retry-join 'provider=aws tag_key=${TAG}:consul_master tag_value=${SYSENV_ALIAS}'"
fi

# nuke existing config file
echo "" > ${CONFIGFILE}

CLIENT="0.0.0.0"

if [ "${IS_MASTER}" = "master" ]; then
    echo "Configuring as master..."
    echo 'SERVER_FLAGS="-server -bootstrap-expect=3 -ui"' >> ${CONFIGFILE}
fi

#...
# Enable this if you want to lock consul to listen only on localhost
#else
#    # set this to make non-servers only listen on localhost
#    CLIENT="127.0.0.1"
#
#    # If machine has docker, start forwarder to forward requests from docker containers to localhost
#    # This is a workaround for iptables local routing issues with docker
#    if ip link show docker0 > /dev/null 2>&1; then
#        systemctl enable consul-forwarder
#        systemctl start consul-forwarder
#    fi
#fi

cat <<EOF >> ${CONFIGFILE}
CONSUL_MASTERS="${CONSUL_MASTERS}"
CONSUL_FLAGS="-datacenter=${SYSENV_ALIAS} -domain=${TAG}. -client=${CLIENT} -advertise='{{ GetDefaultInterfaces | limit 1 | attr \"address\" }}' -bind=0.0.0.0 -config-dir=/etc/consul.d -data-dir=/opt/consul/data"
EOF

if [ ! -z "${NODE_NAME}" ]; then
    echo "Setting node name"
    echo "NODE_NAME=\"-node ${NODE_NAME}\"" >> ${CONFIGFILE}
fi

echo "Restarting dnsmasq"
systemctl restart dnsmasq

echo "Enabling consul service for DC=${SYSENV_ALIAS}"
systemctl daemon-reload
systemctl enable consul

echo "Starting consul"
systemctl start consul

