#!/bin/sh

set -e

if [ -z ${CERTBOT_CONFIG_FILE+x} ]; then
    echo "ERROR: CERTBOT_CONFIG_FILE is unset!"
    exit 1
fi

# Create cloudflare credentials file
secrets_dir=/opt/certbot-config/.secrets/
secrets_ini="${secrets_dir}/cloudflare.ini"
mkdir -p "$secrets_dir"

cat <<EOF > "$secrets_ini"
# Cloudflare API token used by Certbot
dns_cloudflare_api_token = $(cat /run/secrets/cloudflare_dns_api_token)
EOF
chmod 600 "$secrets_ini"

# Run certbot and request certificates
certbot -i nginx \
  --dns-cloudflare \
  --dns-cloudflare-credentials "${secrets_ini}" \
  --config "${CERTBOT_CONFIG_FILE}"

# certbot starts nginx so need to stop it again before the CMD in the nginx layer tries to start it again
service nginx stop

# Setup a cronjob to renew certificates
## Check if job exists and remove if so
if [ -f /etc/crontab ]; then
    if cat /etc/crontab | grep -q 'certbot renew'; then
        cat /etc/crontab | grep -v 'certbot renew' | tee -a /etc/crontab > /dev/null
    fi
fi
## Add cronjob to renew certs
## Cron executes every 12 hours every day
## On start, delays renewal between 0-3600 minutes (random)
delay_timer="import random; import time; time.sleep(random.random() * 3600)"
cert_renew_cmd="certbot renew --quiet -i nginx --dns-cloudflare --dns-cloudflare-credentials \"${secrets_ini}\" --config \"${CERTBOT_CONFIG_FILE}\" --non-interactive"
echo "0 0,12 * * * root /opt/certbot/bin/python -c \"${delay_timer}\" && ${cert_renew_cmd}" | tee -a /etc/crontab > /dev/null

# Start cron so the renewal crontab will execute
service cron start