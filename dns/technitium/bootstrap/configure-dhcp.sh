#! /bin/bash
set -e

# This script can be ran by itself or called from configure.sh.
# To run by itself, a TECHNITIUM_API_TOKEN variable must be set to a valid token with access to create and manage zones.

if [[ -z ${TECHNITIUM_API_TOKEN+x} ]]; then
    echo "TECHNITIUM_API_TOKEN not set but is required by this script."
    echo "  usage: TECHNITIUM_API_TOKEN=6a105966a27eb88c5f6fa5dfb24c701b83de711a7f0bf33c23a5d93ec1a6d86a ./configure-zones.sh"
    exit 1
fi
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
    exit 1
fi

starting_address=$(echo $DHCP_ASSIGNMENT_RANGE | cut -d"|" -f1)
ending_address=$(echo $DHCP_ASSIGNMENT_RANGE | cut -d"|" -f2)
echo "Creating DHCP Scope ${DHCP_SCOPE_NAME}:"
echo " name: ${DHCP_SCOPE_NAME}"
echo " startingAddress: ${starting_address}"
echo " endingAddress: ${ending_address}"
echo " subnetMask: ${DHCP_SUBNET_MASK}"
echo " routerAddress: ${DHCP_ROUTER_ADDRESS}"

dhcp_result=$(curl -s -X POST "${API_HOSTNAME}/api/dhcp/scopes/set" \
    --data token="${TECHNITIUM_API_TOKEN}" \
    --data-urlencode name="${DHCP_SCOPE_NAME}" \
    --data-urlencode startingAddress="${starting_address}" \
    --data-urlencode endingAddress="${ending_address}" \
    --data-urlencode subnetMask="${DHCP_SUBNET_MASK}" \
    --data leaseTimeMinutes=${DHCP_LEASE_TIME_MINUTES} \
    --data-urlencode offerDelayTime=0 \
    --data pingCheckEnabled=false \
    --data pingCheckTimeout=1000 \
    --data pingCheckRetries=2 \
    --data domainName=${DNS_ZONE} \
    --data-urlencode domainSearchList="${DHCP_DOMAIN_SEARCH_LIST}" \
    --data dnsUpdates="${DHCP_ALLOW_DNS_UPDATES}" \
    --data dnsTtl=${DHCP_DNS_TTL} \
    --data routerAddress="${DHCP_ROUTER_ADDRESS}" \
    --data useThisDnsServer=true \
    --data-urlencode exclusions="${DHCP_EXCLUSION_RANGE}" \
    --data-urlencode reservedLeases="${DHCP_RESERVED_LEASES}" \
    --data allowOnlyReservedLeases=false \
    --data blockLocallyAdministeredMacAddresses=false \
    --data ignoreClientIdentifierOption=${DHCP_IGNORE_CLIENT_IDENTIFIER_OPTION}
)

echo "Result:"
jq . <<< $dhcp_result