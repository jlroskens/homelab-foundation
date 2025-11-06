#! /bin/bash
set -Euo pipefail -o functrace
# usage:
#   ./init.sh {var_file} {password}
#   PVE_ROOT_PASSWORD='{password}' ./init.sh {var_file}
#   export PVE_ROOT_PASSWORD='{password}' && ./init-auth-token.sh {var_file}


# Set from arguments / env vars
declare VAR_FILE=''
declare PASSWORD=''

# Set by this script
declare PVE_AUTH_TICKET=''
declare PVE_CSRFPreventionToken=''
declare PVE_API_TOKEN_RESPONSE=''

main() {
    # Ensure arguments
    assert_args_are_valid_and_assign "$@"

    # Create  API Token for All Nodes
    while IFS=$'\t' read -r hostname api_port protocol root_user api_token_env_var api_token_id _; do
        hostname="$(envsubst <<< $hostname)"
        api_port="$(envsubst <<< $api_port)"
        protocol="$(envsubst <<< $protocol)"
        root_user="$(envsubst <<< $root_user)"
        api_token_env_var="$(envsubst <<< $api_token_env_var)"
        api_token_id="$(envsubst <<< $api_token_id)"

        api_base="${protocol}://${hostname}:${api_port}"
        ./init-authtoken.sh "$api_base" "$root_user" "$api_token_env_var" "$api_token_id"
    done < <(yq e '.cluster.nodes[].api | [.hostname, .api_port, .protocol, .root_user, .api_token_env_var, .api_token_id] | @tsv' "$VAR_FILE")
    
    # Source ~/.bashrc to get reload env vars that were added
    . ~/.bashrc
    # Create python environment and download requirements
    . ./init-py.sh

}

assert_args_are_valid_and_assign(){
    # Asserts arguments passed in to this script and environment variables required by this script are valid

syntax_msg=$(cat <<-EOM
ERROR: Missing arguments.
    usage:
      ./init.sh {var_file} {password}
      PVE_ROOT_PASSWORD='{password}' ./init.sh {var_file}
      export PVE_ROOT_PASSWORD='{password}' && ./init-auth-token.sh {var_file}
    examples:
      ./init.sh 'environments/example.yml' 'sdf39dLKHJFde'
      PVE_ROOT_PASSWORD='sdf39dLKHJFde' ./init.sh 'environments/example.yml'
EOM
)

    if [[ $# -eq 0 ]]; then
        echo "$syntax_msg" >&2
        exit 1
    fi
    
    VAR_FILE="$1"
    
    # check that password is set somewhere
    if [[ $# -eq 2 ]]; then
        PASSWORD="$2"
    elif [[ ! -z ${PVE_ROOT_PASSWORD+x} ]]; then
        PASSWORD="${PVE_ROOT_PASSWORD}"
    elif [[ ! -z ${PROXMOX_VE_PASSWORD+x} ]]; then
        PASSWORD="${PROXMOX_VE_PASSWORD}"
    else
        echo "$syntax_msg" >&2
        exit 1
    fi
}

main "$@"