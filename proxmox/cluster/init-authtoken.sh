#! /bin/bash
set -Euo pipefail -o functrace

# Set from arguments / env vars
declare API_BASE=''
declare ROOT_USER=''
declare API_TOKEN_ENV_VAR=''
declare API_TOKEN_ID=''
declare PASSWORD=''

# Set by this script
declare PVE_AUTH_TICKET=''
declare PVE_CSRFPreventionToken=''
declare PVE_API_TOKEN_RESPONSE=''

main() {
    # Ensure arguments
    assert_args_are_valid_and_assign "$@"

    set_auth_ticket
    
    create_api_token "$API_TOKEN_ID" 'API Token for automating node configuration via the API'

    if [[ "$API_TOKEN_ENV_VAR" != "false" ]]; then
        local _api_token="$(jq -r '.data.value' <<< $PVE_API_TOKEN_RESPONSE)"
        echo "export ${API_TOKEN_ENV_VAR}='${_api_token}'" > "$HOME/environment_vars/${API_TOKEN_ENV_VAR}.env"
        echo "API Token written to export file $API_TOKEN_ENV_VAR"
    else
        jq . <<< "$PVE_API_TOKEN_RESPONSE"
    fi
}

assert_args_are_valid_and_assign(){
    # Asserts arguments passed in to this script and environment variables required by this script are valid

syntax_msg=$(cat <<-EOM
ERROR: Missing arguments.
    usage:
      ./init-auth-token.sh {api_base_url} {user} {token_env_var [ENV_VAR_NAME|false]} {token_id} {password}
      PVE_ROOT_PASSWORD='{password}' ./init-auth-token.sh {api_base_url} {user} {token_env_var [ENV_VAR_NAME|false]} {token_id}
      export PVE_ROOT_PASSWORD='{password}' && ./init-auth-token.sh {api_base_url} {user} {token_env_var [ENV_VAR_NAME|false]} {token_id}
    example:
      ./init-auth-token.sh 'https://pve-host-02.local.example.com:8006' 'root@pam' 'PVE_HOST01_API_TOKEN' 'node-automation' 'sdf39dLKHJFde'
EOM
)

    if [ "$#" -lt 4 ]; then
        error ${LINENO} "$syntax_msg" 1
    fi

    API_BASE="$1"
    ROOT_USER="$2"
    API_TOKEN_ENV_VAR="$3"
    API_TOKEN_ID="$4"

    # check that password is set somewhere
    if [[ -n "${5-}" ]]; then
        PASSWORD="$5"
    elif [[ ! -z ${PVE_ROOT_PASSWORD+x} ]]; then
        PASSWORD="${PVE_ROOT_PASSWORD}"
    else
        error ${LINENO} "$syntax_msg" 1
    fi
}

urlEncode() {
    printf %s "${1-}"|jq -sRr @uri
}

set_auth_ticket(){
    local _get_auth_ticket_url="${API_BASE}/api2/json/access/ticket"

    echo "Requesting auth ticket from $_get_auth_ticket_url (username=${ROOT_USER}, password=${PASSWORD})"

    local _get_ticket_result=$(curl --fail -ks --show-error \
                --data-urlencode "username=${ROOT_USER}" \
                --data-urlencode "password=${PASSWORD}" \
                "$_get_auth_ticket_url" )
    PVE_AUTH_TICKET=$(jq -r '.data.ticket' <<< "$_get_ticket_result")
    PVE_CSRFPreventionToken=$(jq -r '.data.CSRFPreventionToken' <<< "$_get_ticket_result")
}

create_api_token(){
    local _api_token_name="${1}"
    local _api_token_comment=''
    if [[ $# -eq 2 ]]; then
        _api_token_comment="${2}"
    fi

    if [[ -z "${PVE_AUTH_TICKET}" ]]; then
        error ${LINENO} "ERROR: PVE_AUTH_TICKET must be set to a valid authorization ticket before calling the create_api_token() function." 1
    fi
    if [[ -z "${PVE_CSRFPreventionToken}" ]]; then
        error ${LINENO} "ERROR: PVE_CSRFPreventionToken must be set to a valid token before calling the create_api_token() function." 1
    fi

    local _api_token_url="${API_BASE}/api2/extjs/access/users/$(urlEncode ${ROOT_USER})/token/$(urlEncode ${_api_token_name})"
    echo "Creating API Token ${_api_token_name} from $_api_token_url for user ${ROOT_USER}"
    local _api_token_result=$(curl --fail --show-error -ks -b "PVEAuthCookie=${PVE_AUTH_TICKET}" \
                        -H "CSRFPreventionToken: ${PVE_CSRFPreventionToken}" \
                        --data "privsep=0" \
                        --data "expire=0" \
                        --data-urlencode "comment=${_api_token_comment}" \
                        "$_api_token_url")
    
    local _api_token_success=$(jq -r '.success' <<< "${_api_token_result}")    
    if [[ $_api_token_success -ne 1 ]]; then
        _formatted_response=$(jq . <<< "$_api_token_result") || $_api_token_result
        error ${LINENO} "API Token Request failed ${_api_token_url}.\nResponse:\n${_formatted_response}" 1
    fi

    PVE_API_TOKEN_RESPONSE="$_api_token_result"
}

error() {
    local last_exit_status="$?"
    local parent_lineno="${1:-0}"
    local message="${2:-(no message ($last_exit_status))}"
    local code="${3:-$last_exit_status}"
    if [[ "$message" != "no message" ]] ; then
        echo -e "Error on line ${parent_lineno}; exiting with status ${code}\n${message}" >&2
        exit ${code}
    else
        echo "Unexpected Error on line ${parent_lineno}; exiting with status code ${code}" >&2
        exit ${code}
    fi
}
trap 'error ${LINENO}' ERR
shopt -s extdebug

main "$@"