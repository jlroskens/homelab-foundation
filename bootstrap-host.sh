#! /bin/bash

# This script bootstraps the foundational host for:
# - building, composing and hosting docker containers
#   - Configures docker networks for external and internal traffic
# - Installs packages required by scripts in this repo and configures PATH when necessary
# - Configures ~/.bashrc and ~/.profile to read in environment variable exports from 
#   the $HOME/environment_vars/ directory.
# - If uncommented, configures the host to use a static IP (needed if hosting DHCP)

main() {
  if [[ -z ${SKIP_PACKAGES+x} ]] || [[ "${SKIP_PACKAGES^^}" != "TRUE" ]]; then
    echo "## Installing apt packages... ##"
    install_packages
  else
    echo "SKIP_PACKAGES flag set. Not installing or updating packages."
  fi
  

  if [[ -z ${SKIP_DOCKER+x} ]] || [[ "${SKIP_DOCKER^^}" != "TRUE" ]]; then
    echo "## Installing and configuring docker... ##"
    install_docker
  else
    echo "SKIP_DOCKER flag set. Not installing or configuring docker."
  fi

  echo "## Configuring ~/.profile and ~/.bashrc PATH and environment variables ##"
  configure_shell_environment

  echo "#############################################################################################"
  echo "PreReqs Installed! If this was the first time installing docker, a reboot is likely required."
}

install_packages() {
  # Install jq, other prereqs and troubleshooting tools
  export DEBIAN_FRONTEND=noninteractive
  sudo apt-get update \
    && sudo apt-get install -y \
      jq \
      wget \
      golang \
      whois \
      dnsutils \
      python3 python3-pip 
      
    # Install yq (requries go environment path to be set up)
    go install github.com/mikefarah/yq/v4@latest

}

install_docker() {
  # Docker
  # Add Docker's official GPG key:
  sudo apt-get update && sudo apt-get install ca-certificates curl -y
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc

  # Add the repository to Apt sources:
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update \
    && sudo apt-get -y upgrade

  # Install Docker
  sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  # Add current user to docker group
  sudo groupadd docker
  sudo usermod -aG docker $USER

  # Create custom docker networks
  # External bridge network
  docker network create -d bridge external-bridge-network
  # Internal docker container network 
  docker network create -d bridge --internal internal-bridge-network
}

configure_shell_environment() {
  # Add Go's bin path
  if ! grep -wq 'PATH="$HOME/go/bin:$PATH"' /$HOME/.profile; then
    echo "Adding $HOME/go/bin to .profile PATH"
    cat <<- 'EOF' >> /$HOME/.profile

      # set PATH so it includes user's go bin if it exists
      if [ -d "$HOME/go/bin" ] ; then
        PATH="$HOME/go/bin:$PATH"
      fi
		EOF
  #^ Spaces before EOF is actually a TAB. Required by HEREDOC. Rest of file is space delimited
  fi
  #.bashrc
  if ! grep -wq 'PATH="$HOME/go/bin:$PATH"' /$HOME/.bashrc; then
    echo "Adding $HOME/go/bin to .bashrc PATH"
    cat <<- 'EOF' >> /$HOME/.bashrc

  # set PATH so it includes user's go bin if it exists
  if [ -d "$HOME/go/bin" ]; then
    PATH="$HOME/go/bin:$PATH"
  fi
		EOF
  fi

  # Create a directory that environment variable exports can be added to.
  mkdir -p $HOME/environment_vars

  # Add snippet to source all environment variable export files to .profile and .bashrc
  if ! grep -wq 'environment_vars_snippet' /$HOME/.profile; then
    echo "Adding environment_vars sourcing to .profile"
    cat <<- 'EOF' >> /$HOME/.profile

# Load any exports from files in the environment_vars.
# environment_vars_snippet
if [ -d "$HOME/environment_vars" ]; then
  for f in $HOME/environment_vars/*; do
    if [ -f "$f" ]; then
      . "$f"
    fi
  done
fi
		EOF
  fi
  #.bashrc environment_vars
  if ! grep -wq 'environment_vars_snippet' /$HOME/.bashrc; then
    echo "Adding environment_vars sourcing to .bashrc"
    cat <<- 'EOF' >> /$HOME/.bashrc

# Load any exports from files in the environment_vars.
# environment_vars_snippet
if [ -d "$HOME/environment_vars" ]; then
  for f in $HOME/environment_vars/*; do
    if [ -f "$f" ]; then
      . "$f"
    fi
  done
fi
		EOF
  fi
}

main

# Uncomment and configure the below for setting a static IP address on this device.
# # Configures a Static IP for when this host will not be a DHCP client, probably because it's a DHCP server.
# # Check output of 'sudo nmcli -p connection show' for network interface name
# interface_name='Wired connection 1'
# # Set static ip to an available IP address for your network and include the CIDR
# static_ip_cidr='192.168.0.2/24'
# # Set the gateway to your router IP address
# gateway='192.168.0.1'
# # Set DNS servers to Google's DNS. This can be updated to 127.0.0.1 after bootstraping the DNS server
# dns_servers='8.8.8.8,8.8.4.4'
# #dns_servers='127.0.0.1,1.1.1.1' # After DNS Server is up and running

# # Configures interface to use a static IP address
# sudo nmcli c mod "$interface_name" ipv4.addresses $static_ip_cidr ipv4.method manual
# # Configures interface's gateway
# sudo nmcli con mod "$interface_name" ipv4.gateway $gateway
# # Configures interface's DNS Servers
# sudo nmcli con mod "$interface_name" ipv4.dns "$dns_servers"
# # Restarts the network interface
# sudo nmcli c down "$interface_name" && sudo nmcli c up "$interface_name"
# # Note: will probably also need to restart Docker after this is done if you did this after docker was up and running.
# # sudo systemctl restart docker