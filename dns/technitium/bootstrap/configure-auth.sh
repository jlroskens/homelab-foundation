#! /bin/bash
set -e
trap "exit 1" TERM

if [[ -z ${DNS_ADMIN_PASSWORD+x} ]]; then
    echo "DNS_ADMIN_PASSWORD not set but is required by this script."
    echo "  usage: DNS_ADMIN_PASSWORD='1242!14lksaDjrfe@skL' ./configure-auth.sh"
    exit 1
fi
if [[ -z ${API_HOSTNAME+x} ]] || [[ -z ${ADMIN_USER+x} ]] || [[ -z ${API_TOKEN_NAME+x} ]]; then
    echo "Environment variables not configured properly. Required variables:"
    echo "  API_HOSTNAME: http endpoint of the host (usually http://localhost:5380)"
    echo "  ADMIN_USER: Admin user name (usually admin)"
    echo "  API_TOKEN_NAME: Name for the API token (usually Automation)"
    exit 1
fi

declare -i isResetNeeded=1
declare login_token=''

login() {
    echo "Logging in to ${API_HOSTNAME}/api/user/login"
    api_login_response=$(curl -Gs --fail "${API_HOSTNAME}/api/user/login" \
        -d user="${ADMIN_USER}" \
        -d pass=admin)
    login_token=$(jq -r '.token' <<< $api_login_response)
    if [[ $? -ne 0 ]] || [[ -z ${login_token+x} ]] || [[ "$login_token" == "null" ]]; then
        echo "Login failed with default credentials. Trying password in set in DNS_ADMIN_PASSWORD."
        api_login_response=$(curl -Gs --fail "${API_HOSTNAME}/api/user/login" \
            -d user="${ADMIN_USER}" \
            --data-urlencode pass="${DNS_ADMIN_PASSWORD}")
        login_token=$(jq -r '.token' <<< $api_login_response)
        if [[ $? -ne 0 ]] || [[ -z ${login_token+x} ]]; then
            echo "Unable to login with default \"admin\" or DNS_ADMIN_PASSWORD password. If an admin password is arleady set, make sure DNS_ADMIN_PASSWORD is also set to it."
            exit 1
        else
            isResetNeeded=0
        fi
    fi
}

change_password() {
    echo "Updating password for user ${ADMIN_USER}"
    change_password_response=$(curl -Gs --fail ${API_HOSTNAME}/api/user/changePassword \
        -d token="${login_token}" \
        --data-urlencode pass="${DNS_ADMIN_PASSWORD}")
    password_staus=$(jq -r '.status' <<< $change_password_response)

    if [[ $? -ne 0 ]] || [[ "$password_staus" != "ok" ]]; then
    echo "Password update failed with status \"$password_staus\"!"
    exit 1
    fi
}

declare api_token=''
create_token() {
    # Create API Automation Token
    echo "Creating API token $API_TOKEN_NAME for future API calls."
    api_token_response=$(curl --fail -Gs ${API_HOSTNAME}/api/user/createToken \
        -d user=${ADMIN_USER} \
        --data-urlencode pass="${DNS_ADMIN_PASSWORD}" \
        -d tokenName=${API_TOKEN_NAME})
    api_token=$(jq -r '.token' <<< $api_token_response)
    if [[ $? -ne 0 ]] || [[ -z ${api_token+x} ]]; then
        echo "Token creation failed."
        exit 1
    fi
    if [[ "${EXPORT_API_TOKEN}" != "true" ]]; then
        echo "API Token $API_TOKEN_NAME: $api_token"
        echo "             ^--- Make sure to save this token. It cannot be retreived again and must be recreated!!"
    fi
}

login
if (( isResetNeeded == 1 )); then
    change_password
fi
create_token

if [[ "${EXPORT_API_TOKEN}" == "true" ]]; then
    mkdir -p $HOME/environment_vars
    echo "export TECHNITIUM_API_TOKEN=$api_token" > $HOME/environment_vars/TECHNITIUM_API_TOKEN.env
    echo "Exported API Token to $HOME/environment_vars/TECHNITIUM_API_TOKEN.env"
fi

export TECHNITIUM_API_TOKEN=$api_token