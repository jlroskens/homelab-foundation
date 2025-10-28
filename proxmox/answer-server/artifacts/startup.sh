#! /bin/bash
set -e

start_server() {
    cd /opt/proxmox/answer-server

    if [[ "${DEFAULT_ANSWER_DISABLED^^}" == "TRUE" ]]; then
        printf "$ROOT_PASSWORD_HASHED" | python3 server.py --port $SERVER_PORT --ssh-keys-directory "$SSH_KEYS_DIR" --default-answer-disabled
    else
        printf "$ROOT_PASSWORD_HASHED" | python3 server.py --port $SERVER_PORT --ssh-keys-directory "$SSH_KEYS_DIR"
    fi
}

root_ssh_key() {
    
    declare -i pub_keys=0
    for file in ${SSH_KEYS_DIR}/*.pub; do
        # Check if the current item is a regular file (not a directory)
        if [[ -f "$file" ]]; then
            # Validate pub files are actually keys
            if ssh-keygen -l -f "$file"; then
                pub_keys=$(( pub_keys+1 ))
            else
                echo "Not a public key: ${file}. Replace or remove this file."
                exit 127
            fi
        fi
    done

    while read pubkey ; do
        set +e
        echo $pubkey | ssh-keygen -l -f - &> /dev/null
        ret_code=$?
        set -e
        if (( ret_code==0 )); then
            # If key is valid, increment key count and write key to a file in the SSH_KEYS_DIR directory.
            pub_keys=$(( pub_keys+1 ))
            # Generate a sha1sum from the key so existing files will be overwritten
            sha_filename=($(echo $pubkey | ssh-keygen -l -f - | sha1sum))
            echo "$pubkey" > "${SSH_KEYS_DIR}/${sha_filename}.pub"
        else
            echo "Invalid public key found in SSH_ROOT_PUBLIC_KEYS. Fix or remove this entry:"
            echo "$pubkey"
            exit 1
        fi
    done <<< "$SSH_ROOT_PUBLIC_KEYS"
    if (( pub_keys==0 )); then
        echo "Public SSH Key not found for root user. Upload public key to file ${SSH_KEYS_DIR}/{name}.pub or to the ssh-config: volume on the host machine."
        exit 127
    else
        echo "Found $pub_keys valid public keys"
    fi
}

echo "Validating Public SSH Keys"
root_ssh_key
echo "Starting Answer Server"
start_server