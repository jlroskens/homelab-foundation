#! /bin/bash
set -e

# This script can be ran by itself or called from configure.sh.
# To run by itself, a TECHNITIUM_API_TOKEN variable must be set to a valid token with access to create and manage zones.

if [[ -z ${TECHNITIUM_API_TOKEN+x} ]]; then
    echo "TECHNITIUM_API_TOKEN not set but is required by this script."
    echo "  usage: TECHNITIUM_API_TOKEN=6a105966a27eb88c5f6fa5dfb24c701b83de711a7f0bf33c23a5d93ec1a6d86a ./configure-zones.sh"
    exit 1
fi
if [[ -z ${API_HOSTNAME+x} ]] || [[ -z ${DNS_ZONE+x} ]] || [[ -z ${DNS_SERVER_NAME+x} ]] || [[ -z ${DNS_HOST_IP+x} ]]; then
    echo "Environment variables not configured properly. Required variables:"
    echo "  API_HOSTNAME: http endpoint of the host (usually http://localhost:5380)"
    echo "  DNS_ZONE: The DNS Zone (example: local.example.com)"
    echo "  DNS_SERVER_NAME: The host name for the DNS server (example: dns1)"
    echo "  DNS_HOST_IP: The DNS server's host IP address (example: 192.168.0.6)"
    exit 1
fi

echo "Creating zone $DNS_ZONE"
zone_create_response=$(curl -Gs --fail "${API_HOSTNAME}/api/zones/create" \
    -d token="${TECHNITIUM_API_TOKEN}" \
    -d zone="${DNS_ZONE}" \
    -d type='Primary')

jq . <<< $zone_create_response

echo "Adding A record for ${DNS_SERVER_NAME} IP $DNS_HOST_IP in zone $DNS_ZONE"

add_record_response=$(curl -Gs --fail "${API_HOSTNAME}/api/zones/records/add" \
    -d token="${TECHNITIUM_API_TOKEN}" \
    -d zone="${DNS_ZONE}" \
    -d domain="${DNS_SERVER_NAME}.${DNS_ZONE}" \
    -d type=A \
    -d overwrite=true \
    -d ipAddress=${DNS_HOST_IP} \
    -d ptr=true \
    -d createPtrZone=true)

jq . <<< $add_record_response

echo "Zone init complete! Make sure to update your DHCP to use DNS server $DNS_HOST_IP as the primary."