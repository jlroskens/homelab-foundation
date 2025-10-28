#! /bin/bash
set -e

# Tracks the temporary merged artifacts directory
tmp_artifacts_dir=''

main() {
    assert_args_are_valid "$@"
    
    # Load environment file
    env_file="$1"
    echo "INFO: exporting environment variables from file \"$env_file\""
    set -o allexport && source "$env_file" && set +o allexport
    
    # Ensure ENV vars are set / read in properly
    assert_env_vars_valid

    # Prepare artifacts for the image
    echo "INFO: Preparing image artifacts"
    prepare_artifacts

    # Build the image
    echo "INFO: Building docker image proxmox/answer-server:latest..."

    docker build  --build-arg IMAGE_ARTIFACTS_PATH="${tmp_artifacts_dir}" \
        --build-arg SSH_KEYS_DIR="$SSH_KEYS_DIR" \
        --tag proxmox/answer-server:latest .
}

assert_args_are_valid(){
    # Asserts arguments passed in to this script and environment variables required by this script are valid
    if [[ -z "$1" ]]; then
        echo "ERROR: An environment file argument is required by this script." >&2
        echo "         usage: ./build.sh environments/example.env" >&2
        exit 1
    fi
}

assert_env_vars_valid(){
    # Asserts environment variables required by this script are valid

    if [[ -z ${SSH_KEYS_DIR+x} ]]; then
        echo "ERROR: SSH_KEYS_DIR not set or empty but is required by this script. Ensure it is included in the .env file or exported prior to running this script." >&2
        echo "         export example:" >&2
        echo "         $ export SSH_KEYS_DIR='/opt/proxmox/answer-server/mnt/ssh-config'" >&2
        exit 1
    fi
}

prepare_artifacts() {
    # Merges static artifacts with environment config files into a temporary artifacts folder
    # Sets the tmp_artifacts_dir variable

    # Create temporary directory
    tmp_artifacts_dir=$(mktemp -d "artifacts.XXXXXXXXXXXXXXXX" -p .)
    trap 'rm -rf "$tmp_artifacts_dir"' EXIT

    cp -rf artifacts/* "$tmp_artifacts_dir/"

    answer_dir="${tmp_artifacts_dir}/opt/proxmox/answer-server/answer"
    mkdir -p "${answer_dir}"    
    for answer in environments/answers/*.toml; do
        if [[ -f "$answer" ]] || [[ -L "$answer" ]]; then
            base_name=$(basename "$answer")
            if [[ $base_name != *example* ]]; then
                cp -f "${answer}" "${answer_dir}/${base_name}"
            fi
        fi
    done
}

main "$@"
