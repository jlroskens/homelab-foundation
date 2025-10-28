#! /bin/bash
set -e

assert_environment() {
    if [[ -z ${ANSWER_SERVER_URL+x} ]]; then
        echo "ANSWER_SERVER_URL environment variable is not set but is required by this service."
        echo "  example: ANSWER_SERVER_URL=http://localhost:8000/answer"
        exit 1
    fi
    if [[ -z ${INSTALLER_DIR+x} ]]; then
        echo "INSTALLER_DIR environment variable is not set but is required by this service."
        echo "  example: INSTALLER_DIR=/opt/proxmox/install-assistant/"
        exit 1
    fi
    if [[ -z ${ISO_DIR+x} ]]; then
        echo "ISO_DIR environment variable is not set but is required by this service."
        echo "  example: ISO_DIR=/opt/proxmox/install-assistant/iso"
        exit 1
    fi
    if [[ -z ${ISO_FILE+x} ]]; then
        echo "ISO_FILE environment variable is not set but is required by this service."
        echo "  example: ISO_FILE=proxmox-ve_9.0-1.iso"
        exit 1
    fi
}

main() {
    echo "Updating ${ISO_FILE} to use answer server URL $ANSWER_SERVER_URL."
    proxmox-auto-install-assistant prepare-iso "${ISO_DIR}/${ISO_FILE}" --fetch-from http --url "$ANSWER_SERVER_URL"
    echo "Above directory is mounted on host at:"
    echo "  $HOST_ISO_DIR"
}

assert_environment
main