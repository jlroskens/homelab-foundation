#! /bin/bash
set -e

if [[ -z "$1" ]]; then
    echo "An environment file argument is required by this script."
    echo "  usage: ./build.sh environments/example.env"
    exit 1
fi

env_file="$1"
set -o allexport && source "$env_file" && set +o allexport
docker build --build-arg INSTALLER_DIR="${INSTALLER_DIR}" -t proxmox/install-assistant:latest -f Dockerfile .