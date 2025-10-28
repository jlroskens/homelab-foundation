#! /bin/bash
set -e

if [[ -z "$1" ]]; then
    echo "An environment file argument is required by this script."
    echo "  usage: ./configure.sh environments/example.env"
    exit 1
fi

env_file="$1"

set -o allexport && source ${env_file} && set +o allexport

if [[ -z ${DNS_ADMIN_PASSWORD+x} ]]; then
    echo "DNS_ADMIN_PASSWORD not set but is required by this script."
    echo "  usage: DNS_ADMIN_PASSWORD='1242!14lksaDjrfe@skL' ./configure.sh"
    return
fi

if [[ -z ${API_HOSTNAME+x} ]] || [[ -z ${ADMIN_USER+x} ]] || [[ -z ${API_TOKEN_NAME+x} ]] || [[ -z ${DNS_ZONE+x} ]] || [[ -z ${DNS_SERVER_NAME+x} ]] || [[ -z ${DNS_HOST_IP+x} ]]; then
    echo "Environment variables not configured properly. Required variables:"
    echo "  API_HOSTNAME: http endpoint of the host (usually http://localhost:5380)"
    echo "  ADMIN_USER: Admin user name (usually admin)"
    echo "  API_TOKEN_NAME: Name for the API token (usually Automation)"
    echo "  DNS_ZONE: The DNS Zone (example: local.example.com)"
    echo "  DNS_SERVER_NAME: The host name for the DNS server (example: dns1)"
    echo "  DNS_HOST_IP: The DNS server's host IP address (example: 192.168.0.6)"
    return
fi

# Start the docker container

if [ "$(docker inspect -f {{.State.Running}} technitium-dns-server)" != "true" ]; then
    if [[ "${DHCP_ENABLED}" == 'true' ]]; then
        docker compose -f docker-compose.dhcp.yml up -d
    else
        docker compose up -d
    fi
    echo "Waiting for technitium-dns-server container to start"
    sleep 5
    until [ "$(docker inspect -f {{.State.Running}} technitium-dns-server)" == "true" ]; do
        sleep 0.1;
    done;
fi

# Configure auth
## - Set Admin Password
## - Create API token
## - Exports API token as TECHNITIUM_API_TOKEN if sourced.
. configure-auth.sh

# Configure initial dns zones
./configure-zones.sh

if [[ "$DHCP_ENABLED" == "true" ]]; then
    if [[ -z ${API_HOSTNAME+x} ]] || [[ -z ${DNS_ZONE+x} ]] \
        || [[ -z ${DHCP_ASSIGNMENT_RANGE+x} ]] \
        || [[ -z ${DHCP_SCOPE_NAME+x} ]] \
        || [[ -z ${DHCP_SUBNET_MASK+x} ]] \
        || [[ -z ${DHCP_ROUTER_ADDRESS+x} ]]; then
        echo "Environment variables not configured properly. Required variables:"
        echo "  API_HOSTNAME: http endpoint of the host (usually http://localhost:5380)"
        echo "  DNS_ZONE: The DNS Zone (example: local.example.com)"
        echo "  DHCP_SCOPE_NAME: The name to give the dhcp scope (example: Local)"
        echo "  DHCP_ASSIGNMENT_RANGE: The assignment range for the dhcp scope (example: '192.168.0.1|192.168.2.254')"
        echo "  DHCP_SUBNET_MASK: The dns mask of the network (example: 255.255.254.0)"
        echo "  DHCP_ROUTER_ADDRESS: The Gateway/Router IP address to configure over dhcp (example: 192.168.0.6)"
        return
    fi
    ./configure-dhcp.sh
fi

echo
echo "## Post Configuration Steps ##"
if [[ "$DHCP_ENABLED" == "true" ]]; then
    echo " DHCP Server was enabled."
    echo "   - Configure a static IP for this host. See comments at the bottom of the init.sh file for an example on how."
    echo "   - Make sure other DHCP servers are disabled (i.e router)."
else
    echo " Configure your router / dhcp server to assign your DNS server's IP address"
    echo "   - DNS Server: $DNS_HOST_IP"
fi
echo " Save the value of the TECHNITIUM_API_TOKEN somewhere secure if you plan on using it in the future."
echo '   echo $TECHNITIUM_API_TOKEN'
echo " Save the value of the DNS_ADMIN_PASSWORD somewhere secure if you haven't already."
echo " Renew your dhcp leases / reboot to pull new DNS configuration. Make sure to save any passwords / tokens above if rebooting!"
echo " Login to your DNS server's web UI using the credentials set by this script."
echo "   - Web UI: http://${DNS_SERVER_NAME}.${DNS_ZONE}:5380"