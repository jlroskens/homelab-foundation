FROM debian:trixie-slim

RUN DEBIAN_FRONTEND=noninteractive \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl wget gnupg openssh-client \
        python3 \
        python3-aiohttp \
        python3-tomlkit

ARG SSH_KEYS_DIR \
    IMAGE_ARTIFACTS_PATH
    
COPY ${IMAGE_ARTIFACTS_PATH}/ /

RUN mkdir -p "${SSH_KEYS_DIR}" \
    && chmod 700 "${SSH_KEYS_DIR}"

WORKDIR /opt/proxmox/answer-server

CMD ["/bin/sh", "-c", "/startup.sh"]