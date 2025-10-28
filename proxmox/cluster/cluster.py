from dataclasses import dataclass
import time
from typing import Any
from clusterlib import ApiConnectionInfo, ClusterConfig, NodeConfig, RaidConfig, ZfsPool, config_reader
import json
import os
import sys
from proxmoxer import ProxmoxAPI, ProxmoxResource, ResourceException
import argparse
import logging

parser = argparse.ArgumentParser(description='Manages a Proxmox cluster')
# parent parser for shared / parent args
parent_parser = argparse.ArgumentParser(add_help=False)
loglevel_choices=list(dict.fromkeys([logging.getLevelName(l) for l in logging.getLevelNamesMapping().values()]))
parent_parser.add_argument('-f','--var-file', help='Path to the Proxmox cluster values file.', required=True)
parent_parser.add_argument('-l', '--log-level', help='The log level. Defaults to INFO.', required=False, default="INFO", choices=loglevel_choices)
parent_parser.add_argument('--skip-node-storage', help='Skip configuration of node disks.', action='store_true')
parent_parser.add_argument('--skip-network-bridges', help='Skip configuration of network bridges.', action='store_true')

# sub parsers for create and manage operations
sub_parsers = parser.add_subparsers(dest='operation', help='Available operations')
# create operation parser
create_parser = sub_parsers.add_parser('create', parents=[parent_parser], help='Creates a new cluster.')
create_parser.add_argument('-p','--root-password', help='The password for the root@pam user. Setting this, stdin or the environment variable is required for creating a cluster.', required=False)
create_parser.add_argument('--single-node-name', help='When set, initiates a cluster with only this node. Other nodes will need to be added with subsequent join operations.', default=None, required=False)
# join operation parser
join_parser = sub_parsers.add_parser('join', parents=[parent_parser], help='Joins a node in the specified config to an existing cluster.')
join_parser.add_argument('-n','--node-name', help='Name of the ndoe to join. Needs to match a .node_name under the cluster.nodes in the var-file.', required=True)
join_parser.add_argument('-p','--root-password', help='The password for the root@pam user. Setting this, stdin or the environment variable is required for creating a cluster.', required=False)
# manage operation parser
manage_parser = sub_parsers.add_parser('manage', parents=[parent_parser], help='Manages an existing new cluster.')
manage_parser.add_argument('-t','--api-token', help='The API token for logging in to the Proxmox API. Required to manage an existing cluster.', required=False)

args = parser.parse_args()

_var_file: str = args.var_file
_operation: str = args.operation
_skip_node_storage=args.skip_node_storage
_skip_network_bridges=args.skip_network_bridges

_cluster_api_token: str | None = None
_pve_root_password: str | None = None

def main():
    log_level = getattr(logging, args.log_level, None)
    logging.basicConfig(level=log_level,
                            format='%(asctime)s %(levelname)s:%(name)s: '
                                '%(message)s')

    if _operation in ["create", "join"]:
        global _pve_root_password
        _pve_root_password = get_pve_root_password()
    if _operation == "create":
        logging.info("Beginning cluster creation")
        create_cluster(args.single_node_name)
    elif _operation == "join":
        logging.info("Beginning cluster join")
        join_cluster(args.node_name)
    elif _operation == "manage":
        logging.info("Beginning cluster management")
        global _cluster_api_token
        _cluster_api_token = get_cluster_api_token()

def get_pve_root_password()-> str | None:
    """Gets the api token from various sources.
       
       Order of precedence is:
       1. stdin
       2. value from the --root-password argument
       3. PVE_ROOT_PASSWORD environment variable, if set
    """
    root_password: str = ''
    if "PVE_ROOT_PASSWORD" in os.environ:
        root_password = os.getenv("PVE_ROOT_PASSWORD")
    
    if args.root_password:
        root_password = args.root_password

    if not sys.stdin.isatty():
        root_password = sys.stdin.read()
    
    if not root_password:
        raise SystemExit("Creating a new cluster requires the root@pam password. Please provide one via stdin, the --root-password argument or a PVE_ROOT_PASSWORD environment variable.")

    return root_password

def get_cluster_api_token()-> str | None:
    """Gets the api token from various sources.
       
       Order of precedence is:
       1. stdin
       2. value from the --api-token argument
       3. PVE_CLUSTER_API_TOKEN environment variable, if set
    """
    api_token: str = ''
    if "PVE_CLUSTER_API_TOKEN" in os.environ:
        api_token = os.getenv("PVE_CLUSTER_API_TOKEN")
    
    if args.api_token:
        api_token = args.api_token

    if not sys.stdin.isatty():
        api_token = sys.stdin.read()
    
    if not api_token:
        raise SystemExit("Managing an existing cluster requires an API Token. Please provide one via stdin, the --api-token argument or a PVE_CLUSTER_API_TOKEN environment variable.")

    return api_token

def api_connect_node(cnn_info: ApiConnectionInfo)-> ProxmoxAPI:
    return api_connect(cnn_info.hostname, cnn_info.root_user, cnn_info.api_token_id, cnn_info.get_api_token(), False)

def api_connect(host: str, user: str, token_name: str, token_value: str, verify_ssl: bool = True)-> ProxmoxAPI:
    return ProxmoxAPI(host, user=user, token_name=token_name, token_value=token_value, verify_ssl=verify_ssl, service="PVE")

def try_json_format(raw_json: str, indent: int = 2) -> str:
    """Attempts to format the string as json "pretty-print". On failure, returns the raw_json.

    Args:
        raw_json (str): String potentially containing json to format.
        indent (int, optional): Indentation of output. Defaults to 2.

    Returns:
        str: Pretty formatted json.
    """
    try:
        return json.dumps(raw_json, indent=indent)
    except ValueError as e:
        return raw_json

def debug_log_as_json(json_to_log: str):
    
    if logging.getLogger().isEnabledFor(logging.DEBUG):
        logging.debug(try_json_format(json_to_log))

def assert_node_links_are_valid(node_configs: list[NodeConfig]):
    first_node: str | None = None
    node_links: int = 0
    for n in node_configs:
        if not first_node:
            node_links = len(n.cluster_links)
            first_node = n.node_name
            continue
        if node_links != len(n.cluster_links):
            error_msg = f"Node {n.node_name} has a differing amount of network links configured ({len(n.cluster_links)}) than {first_node}'s network links ({node_links})"
            raise ValueError(error_msg)

def assert_can_connect_to_node(node_config: NodeConfig):
    try:
        pve: ProxmoxAPI = api_connect_node(node_config.api_cnn_info)
        logging.debug(f"Requesting node '{node_config.node_name}' status from API endpoint {node_config.api_cnn_info.get_api_url()}.")
        pve_node: ProxmoxResource = pve.nodes(node_config.node_name).status().get()
        debug_log_as_json(pve_node)
        if _operation == "create":
            # The API is hardcoded to only allow the actual root@pam user to complete this operation.
            logging.debug(f"Testing connection to {node_config.api_cnn_info.get_api_url()} with user 'root@pam'.")
            root_user_api = ProxmoxAPI(node_config.api_cnn_info.hostname, user="root@pam", password=_pve_root_password, verify_ssl=False)
            root_user_api.nodes(node_config.node_name).status().get()

    except ResourceException as ex:
        logging.error(f"Failed connection assertion for node {node_config.node_name} on endpoint {node_config.api_cnn_info.get_api_url()}.\nError: {ex}")
        raise SystemExit(ex)
    except Exception as ex:
        logging.error(f"Unexpected Error creating connection for node {node_config.node_name} on endpoint {node_config.api_cnn_info.get_api_url()}.\nError:{ex}")
        raise SystemExit(ex)

@dataclass
class ClusterZfsPool():
    zfs_pool_config: ZfsPool
    matched_disks: list[dict]

def get_zfs_pools_unused_disks(node_config: NodeConfig, cluster_config: ClusterConfig) -> dict[str, ClusterZfsPool]:

    pve = api_connect_node(node_config.api_cnn_info)
    # Get a list of unused disks from the API
    unused_disks: list = pve.nodes(node_config.node_name).disks.get("list?type=unused&include-partitions=0")
    logging.debug(f"Found {len(unused_disks)} unused disks for node {node_config.node_name}:")
    debug_log_as_json(unused_disks)
    zfs_pools: dict[str, ClusterZfsPool] = {}
    for pool_name, zfs_pool in cluster_config.zfs_pools.items():
        if not zfs_pool.name in node_config.zfs_disks:
            error_msg = f"Invalid node zfs configuration. Cluster config section specifies cluster.zfs_pools[\"{pool_name}\"].name=\"{zfs_pool.name}\" for a zfs disk, but no matching zfs disk nodes[\"{node_config.node_name}\"]zfs_disks[*].name was found for the node."
            raise ValueError(error_msg)
        zfs_disk = node_config.zfs_disks[zfs_pool.name]
        disk_filters = zfs_disk.filter.get_set_filters()
        
        raid_disks: list = []
        for i in range(zfs_pool.raid.disks):
            logging.debug(f"Searching for unused node disk {i} with {len(disk_filters)} filters: {disk_filters}")
            matched_disk: dict = None
            for unused in unused_disks:
                logging.debug(f"  Attempting match for unused disk \"{unused.get("model", unused.get("devpath", "unknown"))}\":")
                matched_disk = unused
                for disk_property, filter_value in disk_filters.items():
                    if disk_property in unused:
                        if str(unused[disk_property]).casefold() != str(filter_value).casefold():
                            matched_disk = None
                            logging.debug(f"    Filter mismatch. disk.{disk_property}=\"{unused[disk_property]}; filter.{disk_property}=\"{filter_value}\".")
                    else:
                        # Property not found, log and try next disk
                        matched_disk = None
                        logging.debug(f"    Unused disk \"{unused.get("model", unused.get("devpath", "unknown"))}\" does not contain a property for filter \"{disk_property}\".")

            if matched_disk is None:
                error_msg = f"Invalid node zfs_disks configuration. Unable to locate suitable disks for node {node_config.node_name} zfs disk \"{zfs_disk.name}\" with filter \"{disk_filters}\"."
                raise ValueError(error_msg)
            
            logging.debug(f"    Found unused disk \"{unused.get("model", unused.get("devpath", "unknown"))}\" with serial \"{matched_disk["serial"]}\" for raid disk {i}.")
            raid_disks.append(matched_disk)
            # Removed matched disk from list of unused_disks so it can't be matched again.
            unused_disks.remove(matched_disk)
        
        zfs_pools[pool_name] = ClusterZfsPool(
            zfs_pool,
            raid_disks
        )
    
    return zfs_pools
            
def assert_node_can_join_cluster(node_config: NodeConfig, cluster_config: ClusterConfig):
    pve = api_connect_node(node_config.api_cnn_info)
    logging.debug(f"Requesting cluster nodes from node_config endpoint {node_config.api_cnn_info.get_api_url()}.")
    #/api2/json/cluster/config/nodes
    cluster_nodes: ProxmoxResource = pve.cluster.config.nodes.get()
    debug_log_as_json(cluster_nodes)
    # Verify node_config does not already belong to a cluster
    for cluster_node in cluster_nodes:
        error_msg = f"Can not create cluster. NodeConfig {node_config.node_name} is already part of a cluster. Found cluster member {cluster_node["name"]}"
        raise ValueError(error_msg)
    
    if not _skip_node_storage:
        if len(cluster_config.zfs_pools):
            zfs_pools = get_zfs_pools_unused_disks(node_config, cluster_config)
            logging.info(f"Found unused disks for all {len(cluster_config.zfs_pools)} cluster zfs pools on node {node_config.node_name}.")
            logging.debug(zfs_pools)
        else:
            logging.info(f"No cluster.zfs_pools defined. Skipped unused disk filter checks.")

def log_cluster_zfs_pools(zfs_pools: dict[str, ClusterZfsPool], indent=0):
    for pool_name, zfs_pool in zfs_pools.items():
        pool_config = zfs_pool.zfs_pool_config
        offset = " " * indent
        logging.info(offset + f"Zfs Pool: {pool_name}")
        logging.info(offset + f"  name: {pool_config.name}")
        logging.info(offset +  f"  compression: {pool_config.compression}")
        logging.info(offset + f"  raid.level: {pool_config.raid.level}")
        logging.info(offset + f"  raid.disks: {pool_config.raid.disks}")
        disks = zfs_pool.matched_disks
        for i in range(pool_config.raid.disks):
            disk = disks[i]
            logging.info(offset + f"  disk[{i}]:")
            logging.info(offset + f"    devpath: {disk.get("devpath", None)}")
            logging.info(offset + f"    model: {disk.get("model", None)}")
            logging.info(offset + f"    serial: {disk.get("serial", None)}")
            logging.info(offset + f"    size: {disk.get("size", None)}")
            logging.info(offset + f"    type: {disk.get("type", None)}")
            logging.info(offset + f"    wearout: {disk.get("wearout", None)}")
            logging.info(offset + f"    health: {disk.get("health", None)}")
            logging.info(offset + f"    order: {i}")

def create_node_disks_for_zfs_pools(node_config: NodeConfig, cluster_config: ClusterConfig, add_storage: bool = False):
    pve = api_connect_node(node_config.api_cnn_info)
    logging.info(f"  Creating disk(s) for node {node_config.node_name}'s {len(cluster_config.zfs_pools)} zfs pools.")
    zfs_pools = get_zfs_pools_unused_disks(node_config, cluster_config)
    # log_cluster_zfs_pools(zfs_pools, 4)
    for pool_name, zfs_pool in zfs_pools.items():
        pool_config = zfs_pool.zfs_pool_config
        disks = zfs_pool.matched_disks
        devices=str.join(", ", [disk["devpath"] for disk in disks])
        # create call: https://pve.proxmox.com/pve-docs/api-viewer/index.html#/nodes/{node}/disks/zfs
        logging.info(f"    Creating {pool_config.raid.level} disk for Zfs Pool \"{pool_name}\". devices=\"{devices}\"; compression=\"{pool_config.compression}\"; ashift={pool_config.ashift}")
        pve.nodes(node_config.node_name).disks.zfs.post(
            name=pool_name,
            add_storage=int(add_storage),
            raidlevel=pool_config.raid.level,
            compression=pool_config.compression,
            ashift=pool_config.ashift,
            devices=devices
        )
def create_node_bridges(node_config: NodeConfig):
    if len(node_config.linux_bridges) == 0:
        logging.info(f"Node {node_config.node_name} has no additional linux bridges to configure.")
        return
    pve = api_connect_node(node_config.api_cnn_info)
    logging.info(f"Creating {len(node_config.linux_bridges)} Linux Bridges for Node {node_config.node_name}.")
    for bridge in node_config.linux_bridges:
        bridge_params = {
            "type": "bridge",
            "autostart": 1,
            "iface": bridge.bridge_name,
            "cidr": bridge.ip_cidr,
            "bridge_ports": str.join(" ", bridge.bridge_ports)
        }
        logging.info(f"  Requesting {bridge.bridge_name} ({bridge.ip_cidr}) creation.")
        result = pve.nodes(node_config.node_name).network.post(**bridge_params)
        logging.info(f"  Applying configuration for new {bridge.bridge_name} ({bridge.ip_cidr}) bridge.")
        pve.nodes(node_config.node_name).network.put()
        
def configure_cluster_storage(cluster_config: ClusterConfig, node_configs: list[NodeConfig]):
    pve = api_connect_node(next(iter(node_configs)).api_cnn_info)
    node_names = [n.node_name for n in node_configs]
    for zpool in cluster_config.zfs_pools.keys():
        storage_params = {
            "nodes": node_names,
            "content": ["images", "rootdir"],
            "sparse": 0,
            "disable": 0
        }
        # check if storage already exists. If found, update with a put. Otherwise, create with a post.
        all_storage = pve.storage.get()
        existing_storage = next((s for s in all_storage if s["storage"] == zpool), None)
        if not existing_storage:
            storage_params["storage"] = "local-cluster-zfs"
            storage_params["pool"] = "local-cluster-zfs"
            storage_params["type"] = "zfspool"
            debug_log_as_json(storage_params)
            storage_response = pve.storage.post(**storage_params)
        else:
            storage_response = pve.storage(zpool).put(**storage_params)

        logging.info(f"Configured cluster storage {zpool} for nodes {node_names}.")
        debug_log_as_json(storage_response)

def configure_new_cluster(cluster_config: ClusterConfig, node_config: NodeConfig):

    # The API is hardcoded to only allow the actual root@pam user to complete this operation.
    pve = ProxmoxAPI(node_config.api_cnn_info.hostname, user="root@pam", password=_pve_root_password, verify_ssl=False)
    logging.info(f"Creating cluster {cluster_config.name} with initial node {node_config.node_name}.")
    
    cluster_params = {
        "clustername": cluster_config.name,
        "nodeid": node_config.node_id,
        "votes": node_config.cluster_votes
    }
    
    # add network links
    for i in range(len(node_config.cluster_links)):
        link = node_config.cluster_links[i]
        cluster_params[f"link{i}"] = f"{link.ip_address},priority={link.priority}"
    
    logging.info(f" cluster parameters: {cluster_params}")
    cluster_config = pve.cluster.config.post(**cluster_params)
    logging.info(f"  View Create Cluster Task ID: {cluster_config} on the {node_config.node_name} node.")
    logging.info("  If the cluster creation failed, correct the issue and retry 'create' operation with the '--skip-node-storage' flag.")

def join_node(cluster_config: ClusterConfig, node_config: NodeConfig, preferred_node: NodeConfig, root_password: str):
    """Joins a node to an existing cluster.

    Args:
        cluster_config (ClusterConfig): Configuration for the cluster to be joined.
        node_config (NodeConfig): Node that will join the cluster.
        preferred_node (NodeConfig): An existing cluster member. Typically the preferred node, but can be any node member. Will be queried to find the preferred node for the cluster.
        root_password (str): Superuser (root) password of the preferred member node and the node joining the cluster.
    """
    
    logging.info(f"Joining node {node_config.node_name} to cluster {cluster_config.name}.")
    preferred_node_pve = api_connect_node(preferred_node.api_cnn_info)
    join_info = preferred_node_pve.cluster.config.join.get()
    preferred_node_name = join_info["preferred_node"]
    if preferred_node.node_name != preferred_node_name:
        logging.debug(f"  Node {preferred_node.node_name} thinks {preferred_node_name} is the preferred node to join, not itself. This is fine as long as the root_password provided is valid for the {preferred_node_name} node.")
    
    preferred_node = next((n for n in join_info["nodelist"] if n["name"] == preferred_node_name), None)
    if not preferred_node:
        error_msg = f"  Could not get preferred node details from cluster member ${preferred_node.node_name}. Are you sure this is a cluster member?"
        raise SystemExit(error_msg)

    # The API is hardcoded to only allow the 'root@pam' user to complete this operation.
    join_pve = ProxmoxAPI(node_config.api_cnn_info.hostname, user="root@pam", password=_pve_root_password, verify_ssl=False)
    
    join_params = {
        "fingerprint": preferred_node["pve_fp"],
        "hostname": preferred_node_name,
        "password": root_password,
        "nodeid": node_config.node_id,
        "votes": node_config.cluster_votes
    }
    
    # add network links
    for i in range(len(node_config.cluster_links)):
        link = node_config.cluster_links[i]
        join_params[f"link{i}"] = f"{link.ip_address},priority={link.priority}"
    
    # avoid logging password
    log_params = dict(join_params)
    log_params["password"] = '********'
    logging.info(f" join parameters: {log_params}")
    # join
    join_response = join_pve.cluster.config.join.post(**join_params) 
    logging.info(f"  View Join Task ID: {join_response} on the {node_config.node_name} node.")
    logging.info("  If the join failed, correct the issue and retry with the 'join' operation.")

def create_cluster(node_name: str = None):
    node_configs: dict[int, NodeConfig] = config_reader.get_node_configs(_var_file)
    cluster_config: ClusterConfig = config_reader.get_cluster_config(_var_file)
    
    # If single_node_config is set, then create a cluster with only one node
    single_node_config: NodeConfig = None
    if node_name:
        single_node_config = next((n for n in node_configs.values() if n.node_name == node_name), None)
        if not single_node_config:
            error_msg = f"Invalid --single-node-config specified. Node with name '{node_name}' not found in var file {_var_file}."
            raise ValueError(error_msg)
    
    # Test api connectivity
    logging.info("Validating nodes api connectivity.")
    if single_node_config:
        assert_can_connect_to_node(single_node_config)
    else:
        for node_config in node_configs.values():
            assert_can_connect_to_node(node_config)
        
    # Test that the node(s) are capable of joining a cluster
    logging.info("Validating all nodes are capable of joining a cluster.")
    assert_node_links_are_valid([single_node_config] if single_node_config else node_configs.values())
    if single_node_config:
        assert_node_can_join_cluster(single_node_config, cluster_config)
    else:
        for node_config in node_configs.values():
            assert_node_can_join_cluster(node_config, cluster_config)
        
    # Create ZFS Disk on the node and configure storage
    if len(cluster_config.zfs_pools) and not _skip_node_storage:
        logging.info("Creating zfs disks on all nodes for all cluster zfs pools.")
        if single_node_config:
            create_node_disks_for_zfs_pools(single_node_config, cluster_config, True)
        else:
            add_storage: bool = True
            for node_config in node_configs.values():
                create_node_disks_for_zfs_pools(node_config, cluster_config, add_storage)
                add_storage = False

    # Create linux bridges if any are specified
    if not _skip_network_bridges:
        logging.info("Creating network bridges on all nodes.")
        if single_node_config:
            create_node_bridges(single_node_config)
        else:
            for node_config in node_configs.values():
                create_node_bridges(node_config)

    # There's no cluster yet, preffered node is just the first node in the config (or the node from the --single-node-config arg)
    preferred_node = single_node_config if single_node_config else node_configs[1]
    configure_new_cluster(cluster_config, preferred_node)
    if single_node_config or len(node_configs) == 1:
        logging.info("Single node cluster creation complete. Use 'join' to add additional nodes.")    
        return
    
    # If not a single node cluster, go on to join remaining nodes
    logging.info("** Waiting 30 seconds for cluster creation before attempting to join **")
    time.sleep(30)
    for join_config in list(node_configs.values())[1:]:
        join_node(cluster_config, join_config, preferred_node, _pve_root_password)

    if not _skip_node_storage:
        logging.info("** Waiting 30 seconds for join operations to complete before adding nodes to zfs pool(s). **")
        time.sleep(30)
        configure_cluster_storage(cluster_config, node_configs.values())

def join_cluster(node_name: str):
    node_configs: dict[int, NodeConfig] = config_reader.get_node_configs(_var_file)
    join_config = next(n for n in node_configs.values() if n.node_name == node_name)
    
    # Validations and assertions
    if not join_config:
        error_msg = f"Node {join_config} not found in var file '{_var_file}'. Aborting join."
        raise SystemExit(error_msg)
    cluster_config: ClusterConfig = config_reader.get_cluster_config(_var_file)
    
# ### For testing DELETE WHEN FINISHED    
#     # Create ZFS disks
#     if len(cluster_config.zfs_pools) and not _skip_node_storage:
#         logging.info(f"Creating zfs disks on node {node_name} for all cluster zfs pools.")
#         create_node_disks_for_zfs_pools(join_config, cluster_config)

#     if not _skip_node_storage:
#         logging.info("** Waiting 30 seconds for join operation to complete before configuring zfs pool(s). **")
#         configure_cluster_storage(cluster_config, node_configs.values())
#     return
    preferred_node = node_configs[1]
    logging.info("Validating join node and preferred node api connectivity.")
    assert_can_connect_to_node(preferred_node)
    assert_can_connect_to_node(join_config)
    
    logging.info(f"Validating {node_name} node is capable of joining a cluster.")
    assert_node_links_are_valid(node_configs.values())
    assert_node_can_join_cluster(join_config, cluster_config)

    # Create ZFS disks
    if len(cluster_config.zfs_pools) and not _skip_node_storage:
        logging.info(f"Creating zfs disks on node {node_name} for all cluster zfs pools.")
        create_node_disks_for_zfs_pools(join_config, cluster_config)

    if not _skip_network_bridges:
        # Create any linux bridges specified
        create_node_bridges(join_config)

    # join the node to the cluster
    join_node(cluster_config, join_config, preferred_node, _pve_root_password)

    if not _skip_node_storage:
        logging.info("** Waiting 30 seconds for join operation to complete before configuring zfs pool(s). **")
        time.sleep(30)
        configure_cluster_storage(cluster_config, node_configs.values())

main()