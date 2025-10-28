FROM nginx

RUN DEBIAN_FRONTEND=noninteractive \
    && apt-get update \
    && apt-get remove certbot -y \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        wget \
        gnupg \
        openssh-client \
        python3 python3-dev python3-venv \
        libaugeas-dev \
        gcc \
        cron

# Configure Python Virtual Environment
RUN python3 -m venv /opt/certbot/ \
    && /opt/certbot/bin/pip install --upgrade pip

# Install certbot
RUN /opt/certbot/bin/pip install certbot certbot-nginx \
    && /opt/certbot/bin/pip install certbot-dns-cloudflare \
    && ln -s /opt/certbot/bin/certbot /usr/bin/certbot

# Map letsencrypt logs to stdout
# Very chatty... only enable for debugging
# RUN mkdir -p /var/log/letsencrypt/ && touch /var/log/letsencrypt/letsencrypt.log \
#     && ln -sf /dev/stdout /var/log/letsencrypt/letsencrypt.log

ARG IMAGE_ARTIFACTS_PATH \
    CERTBOT_CONFIG_FILE

ENV CERTBOT_CONFIG_FILE=${CERTBOT_CONFIG_FILE}

COPY ${IMAGE_ARTIFACTS_PATH}/ /