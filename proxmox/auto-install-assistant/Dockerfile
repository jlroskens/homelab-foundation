FROM debian:trixie-slim

ARG INSTALLER_DIR

RUN DEBIAN_FRONTEND=noninteractive \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl wget gnupg openssh-client \
    && wget https://enterprise.proxmox.com/debian/proxmox-archive-keyring-trixie.gpg -O /usr/share/keyrings/proxmox-archive-keyring.gpg
    
# Add proxmox no-subscription source
COPY <<EOF /etc/apt/sources.list.d/proxmox.sources
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF

# Download 
RUN DEBIAN_FRONTEND=noninteractive \
    && apt-get update \
    && apt-get install -y \
        proxmox-auto-install-assistant

COPY scripts/* $INSTALLER_DIR

WORKDIR $INSTALLER_DIR

CMD ["/bin/sh", "-c", "$INSTALLER_DIR/prepare-iso.sh"]