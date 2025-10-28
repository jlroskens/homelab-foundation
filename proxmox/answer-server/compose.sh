#! /bin/bash
set -e

main() {
    # Ensure arguments
    assert_args_are_valid "$@"

    # Export env variables
    env_file="$1"
    set -o allexport && source "$env_file" && set +o allexport

    # Ensure ENV vars are set / read in properly
    assert_env_vars_valid
   
    # Compose the container
    echo "INFO: Starting service"
    ENV_FILE="$env_file" docker compose up -d
}

assert_args_are_valid(){
    # Asserts arguments passed in to this script and environment variables required by this script are valid
    if [[ -z "$1" ]]; then
        echo "ERROR: An environment file argument is required by this script." >&2
        echo "         usage: ./compose.sh environments/example.env" >&2
        exit 1
    fi
}

assert_env_vars_valid(){
    # Asserts environment variables required by this script are valid
    assert_env_var_valid "HOST_SERVER_PORT"
    assert_env_var_valid "SERVER_PORT"
    assert_env_var_valid "SSH_ROOT_PUBLIC_KEYS"
    assert_env_var_valid "ROOT_PASSWORD_HASHED"
    assert_env_var_valid "SSH_KEYS_DIR"
    assert_env_var_valid "SSH_ROOT_PUBLIC_KEYS"
}

assert_env_var_valid(){
    var_name=$1
    # Asserts environment variable required by this script are valid
    if [[ -z ${!var_name} ]]; then
        echo "ERROR: ${var_name} not set or empty but is required by this script. Ensure it is included in the .env file or exported prior to running this script." >&2
        echo "         export:" >&2
        echo "           $ export ${var_name}='xxxxx'" >&2
        echo "           $ ./compose.sh" >&2
        echo "        inline:" >&2
        echo "          $ ${var_name}='xxxxx' ./compose.sh" >&2
        exit 1
    fi
}

main "$@"