#! /bin/bash
set -e

if [[ -z "$1" ]]; then
    echo "An environment file argument is required by this script."
    echo "  usage: ./compose.sh environments/example.env"
    exit 1
fi

env_file="$1"
set -o allexport && source "$env_file" && set +o allexport

mkdir -p $HOME/images

ENV_FILE="$env_file" docker compose up