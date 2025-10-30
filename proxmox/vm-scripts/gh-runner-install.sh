#! /bin/bash
# Expects 2 arguments, 
# - Relative path of the repository {org|user}/{repo} (or org only for org runners)
# - Token from https://github.com/${repo_path}/settings/actions/runners/new
# - Interactive. GitHub's script asks for inputs.

set -e

if [[ -z "$1" ]]; then
    echo "A relative path to the repository or organization is require."
    echo "  usage: ./gh-runner-install.sh {your-org-or-username}/{repo-name} {token}"
    exit 1
fi

repo_path=$2

if [[ -z "$2" ]]; then
    echo "An token is required."
    echo "  usage: ./gh-runner-install.sh"
    echo "Tokens are generated when creating a new runner on GitHub."
    echo "https://github.com/${repo_path}/settings/actions/runners/new"
    exit 1
fi

token="$1"

echo "Downloading actions-runner install"
# Create a folder
mkdir actions-runner && cd actions-runner
# Download the latest runner package
curl -o actions-runner-linux-x64-2.329.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.329.0/actions-runner-linux-x64-2.329.0.tar.gz
# Optional: Validate the hash
echo "194f1e1e4bd02f80b7e9633fc546084d8d4e19f3928a324d512ea53430102e1d  actions-runner-linux-x64-2.329.0.tar.gz" | shasum -a 256 -c
# Extract the installer
tar xzf ./actions-runner-linux-x64-2.329.0.tar.gz

echo "Running Configuration script."
./config.sh --url https://github.com/${repo_path} --token $token

echo "Installing runner as a service"
sudo ./svc.sh install

echo "Starting runner service"
sudo ./svc.sh start