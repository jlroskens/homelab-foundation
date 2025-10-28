# Sourced From: https://pve.proxmox.com/wiki/Automated_Installation#Serving_Answer_Files_via_HTTP
import argparse
import logging
import json
import pathlib
import sys
import tomlkit
from aiohttp import web

DEFAULT_ANSWER_FILE_PATH = pathlib.Path("./answer/default.toml")
ANSWER_FILE_DIR = pathlib.Path("./answer/")

parser = argparse.ArgumentParser(description="HTTP Answer service")
parser.add_argument("-p","--port", help="The port the Answer service will listen on for HTTP requests", type=int, required=True)
parser.add_argument("-m","--machine-addresses", help="Comma separated list of MAC addresses. If set, this service will only respond to requests with that match machine addresses in this list or answer/{MAC}.toml files.", type=str, required=False)
parser.add_argument("--ssh-keys-directory", help="Directory containing public SSH keys to include in the root-ssh-keys list of answer responses.", type=str, required=True)
parser.add_argument("--root-password-hashed", help="The pre-hashed password for the root user. Sets the root-password-hashed in the answer. Can be piped in instead.", required=False)
parser.add_argument("--default-answer-disabled", help="When set, will return 404s for unmatched MAC addresses instead of the default answer.", action='store_true')
args = parser.parse_args()

HTTP_PORT=args.port
MACHINE_ADDRESSES: str | None = None
if args.machine_addresses:
    MACHINE_ADDRESSES={x.replace("-", ":").strip().casefold() for x in args.machine_addresses.split(',')}
SSH_KEYS_DIR: pathlib.Path | None = pathlib.Path(args.ssh_keys_directory)

DEFAULT_ANSWER_DISABLED=args.default_answer_disabled

def get_root_password_hashed()-> str:
    """Gets the from an argument or stdin.
       
       Order of precedence is:
       1. stdin
       2. value from the --root-password-hashed argument
    """
    password_hash: str = ''
    
    if args.root_password_hashed:
        password_hash = args.root_password_hashed

    if not sys.stdin.isatty():
        password_hash = sys.stdin.read().strip()
    
    if not password_hash:
        raise SystemExit("A password hash for the root account is required but not found in stdin or the --root-password-hashed argument. One of these must be set!")

    return password_hash

PASSWORD_HASH=get_root_password_hashed()

routes = web.RouteTableDef()


@routes.post("/answer")
async def answer(request: web.Request):
    try:
        request_data = json.loads(await request.text())
    except json.JSONDecodeError as e:
        return web.Response(
            status=500,
            text=f"Internal Server Error: failed to parse request contents: {e}",
        )

    logging.info(
        f"Request data for peer '{request.remote}':\n"
        f"{json.dumps(request_data, indent=1)}"
    )

    try:
        answer = create_answer(request_data)

        if answer:
            logging.debug(f"Answer file for peer '{request.remote}':\n{answer}")
            return web.Response(text=answer)
        else:
            return web.Response(status=404, text=f"Answer for peer Not Found")
    except Exception as e:
        logging.exception(f"failed to create answer: {e}")
        return web.Response(status=500, text=f"Internal Server Error: {e}")


def create_answer(request_data: dict) -> str | None:
    with open(DEFAULT_ANSWER_FILE_PATH) as file:
        default_answer = tomlkit.parse(file.read())
        default_answer = set_answer_root_auth(default_answer)
    for nic in request_data.get("network_interfaces", []):
        if "mac" not in nic:
            continue
        
        answer_mac = lookup_answer_for_mac(nic["mac"])
        if answer_mac is not None:
            logging.info(f"Found custom answer for MAC {nic["mac"]}.")
            return tomlkit.dumps(answer_mac)
    # If no MACHINE_ADDRESSES set then return the default answer
    if MACHINE_ADDRESSES is None or len(MACHINE_ADDRESSES) == 0:
        if not DEFAULT_ANSWER_DISABLED:
            logging.info(f"No custom answer found for MAC {nic["mac"]}. Returning Default answer.")
            return tomlkit.dumps(default_answer)

    return None


def lookup_answer_for_mac(machine_address: str) -> tomlkit.TOMLDocument | None:
    req_mac: str = machine_address.replace("-", ":").strip().casefold()

    for filename in ANSWER_FILE_DIR.glob("*.toml"):
        file_mac: str = filename.stem.replace("-", ":").strip().casefold()
        logging.info(f"Comparing file MAC {file_mac} to request {req_mac}")
        if req_mac == file_mac:
            with open(filename) as mac_file:
                mac_answer = tomlkit.parse(mac_file.read())
            return set_answer_root_auth(mac_answer)
    if MACHINE_ADDRESSES:
        if req_mac in MACHINE_ADDRESSES:
            with open(DEFAULT_ANSWER_FILE_PATH) as file:
                default_answer = tomlkit.parse(file.read())
            return set_answer_root_auth(default_answer)
        
def set_answer_root_auth(answer: tomlkit.TOMLDocument) -> tomlkit.TOMLDocument:
    pub_keys: set[str] = set()
    for filename in SSH_KEYS_DIR.glob("*.pub"):
        file_keys: set[str] = set(pub_key.strip() for pub_key in open(filename))
        logging.info(f"file_keys: {file_keys}")
        logging.info(f"pub_keys: {pub_keys}")
        pub_keys |= file_keys
    
    answer["global"].add("root-ssh-keys", list(pub_keys))
    answer["global"].add("root-password-hashed", PASSWORD_HASH)
    return answer

def assert_default_answer_file_exists():
    if not DEFAULT_ANSWER_FILE_PATH.exists():
        raise RuntimeError(
            f"Default answer file '{DEFAULT_ANSWER_FILE_PATH}' does not exist"
        )


def assert_default_answer_file_parseable():
    with open(DEFAULT_ANSWER_FILE_PATH) as file:
        try:
            tomlkit.parse(file.read())
        except Exception as e:
            raise RuntimeError(
                "Could not parse default answer file "
                f"'{DEFAULT_ANSWER_FILE_PATH}':\n{e}"
            )


def assert_answer_dir_exists():
    if not ANSWER_FILE_DIR.exists():
        raise RuntimeError(f"Answer file directory '{ANSWER_FILE_DIR}' does not exist")


if __name__ == "__main__":
    assert_default_answer_file_exists()
    assert_answer_dir_exists()
    assert_default_answer_file_parseable()

    app = web.Application()

    logging.basicConfig(level=logging.INFO)

    app.add_routes(routes)
    logging.info(f"Starting answer server. Listening on port {HTTP_PORT}.")
    web.run_app(app, host="0.0.0.0", port=HTTP_PORT)