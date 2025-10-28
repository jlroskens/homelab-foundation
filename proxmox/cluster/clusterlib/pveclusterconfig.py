from dataclasses import asdict, dataclass
from dotenv import dotenv_values
from enum import StrEnum
from pathlib import Path
import os
import yaml

class ZfsCompression(StrEnum):
    on = "on"
    off = "off"
    lz4 = "lz4"
    gzip = "gzip"
    lzjb = "lzjb"
    zle = "zle"
    zsdt = "zsdt"

class RaidLevel(StrEnum):
    single = "single"
    mirror = "mirror"
    raid10 = "raid10"
    raidz = "raidz"
    raidz2 = "raidz2"
    raidz3 = "raidz3"

@dataclass
class ApiConnectionInfo:
    hostname: str
    api_port: int
    protocol: str
    root_user: str
    api_token_env_var: str
    api_token_id: str

    def get_api_url(self)-> str:
        return f"{self.protocol}://{self.hostname}:{self.api_port}"
    def get_api_token(self)-> str:
        if self.api_token_env_var in os.environ:
            return os.getenv(self.api_token_env_var)
        else:
            env_file = f"{os.path.expanduser('~')}/environment_vars/{self.api_token_env_var}.env"
            if os.path.isfile(env_file):
                env_vars = dotenv_values(env_file)
                if self.api_token_env_var in env_vars:
                    return env_vars[self.api_token_env_var]

        raise ValueError(f"Could not get value for variable '{self.api_token_env_var}'. Check this variable has been exported to your environment prior to running this script.")

@dataclass
class RaidConfig:
    level: RaidLevel
    disks: int

    @property
    def disks(self) -> int:
        return self._disks

    @disks.setter
    def disks(self, value: int) -> None:
        self._disks = max(value, 1)

@dataclass 
class ZfsPool:
    name: str
    compression: ZfsCompression
    ashift: int
    raid: RaidConfig

@dataclass 
class DiskFilter:
    model: str | None
    vendor: str | None
    type: str | None
    size: int | None
    devpath: str | None
    serial: str | None
    
    def get_set_filters(self)-> dict[str, str | int]: 
        return {k: str(v) for k, v in asdict(self).items() if v}

@dataclass 
class ZfsDisk:
    name: str
    order: int
    filter: DiskFilter

@dataclass
class LinuxBridge:
    bridge_name: str
    ip_cidr: str
    bridge_ports: list[str]

@dataclass
class NodeClusterLink:
    ip_address: str
    priority: int

@dataclass
class ClusterConfig:
    name: str
    api_cnn_info: ApiConnectionInfo
    zfs_pools: dict[str, ZfsPool]

@dataclass
class NodeConfig:
    node_id: int
    node_name: str
    cluster_votes: int
    api_cnn_info: ApiConnectionInfo
    zfs_disks: dict[str, ZfsDisk]
    linux_bridges: list[LinuxBridge]
    cluster_links: list[NodeClusterLink]

def get_api_connection_info(api_section) -> ApiConnectionInfo:
    return ApiConnectionInfo(
                api_section["hostname"],
                api_section["api_port"],
                api_section["protocol"],
                api_section["root_user"],
                api_section["api_token_env_var"],
                api_section["api_token_id"]
            )

def get_node_zfs_disks(zfs_disks_section) -> dict[str, ZfsDisk]:
    """Gets a dictionary of ZfsDisks for a specific node's zfs_disks configuration.

    Args:
        zfs_disks_section : Loaded cluster.nodes[*].zfs_disks section to parse.

    Returns:
        dict[str, ZfsDisk]: Dictionary of ZfsDisks indexed by their name, ordered by the 'order' property in the configuration, otherwise follows the order they appear in the file.
    """
    zfs_disks: list[ZfsDisk] = []
    natural_order: int = 0
    for disk in zfs_disks_section:
        zfs_disks.append(
            ZfsDisk(
                disk["name"],
                disk.get("order", natural_order),
                DiskFilter(
                    disk["filter"].get("model", None),
                    disk["filter"].get("vendor", None),
                    disk["filter"].get("type", None),
                    disk["filter"].get("size", None),
                    disk["filter"].get("devpath", None),
                    disk["filter"].get("serial", None)
                )
            )
        )
        natural_order += 1
    
    # sort disks by order and return indexed by their disk name
    sorted_disks=sorted(zfs_disks, key=lambda disk: disk.order)
    return {disk.name: disk for disk in sorted_disks}

def get_linux_bridges(bridges_section) -> list[LinuxBridge]:
    bridges: list[LinuxBridge] = []
    for bridge in bridges_section:
        bridges.append(
            LinuxBridge(
                bridge["bridge_name"],
                bridge["ip_cidr"],
                bridge["bridge_ports"]
            )
        )
    
    return bridges

def get_node_cluster_links(links_section) -> list[NodeClusterLink]:
    links: list[NodeClusterLink] = []
    for link in links_section:
        links.append(
            NodeClusterLink(
                link["ip_address"],
                link["priority"]
            )
        )
    
    return links

class config_reader:
    @staticmethod
    def get_cluster_config(config_file: Path | str) -> ClusterConfig:
        with open(Path(config_file), 'r') as file_io:
            env_config = yaml.safe_load(file_io)
        
        cluster = env_config["cluster"]
        zfs_pools: dict[str, ZfsPool] = {}

        for zfs_pool in cluster["zfs_pools"]:
            zfs_name = zfs_pool["name"]
            zfs_pools[zfs_name] = ZfsPool(
                zfs_name,
                zfs_pool["compression"],
                zfs_pool["ashift"],
                RaidConfig(
                    zfs_pool["raid"]["level"].lower(),
                    zfs_pool["raid"]["disks"]
                )
            )

        return ClusterConfig(
            cluster["name"],
            get_api_connection_info(cluster["api"]),
            zfs_pools
        )

    @staticmethod
    def get_node_configs(config_file: Path | str) -> dict[int, NodeConfig]:
        with open(Path(config_file), 'r') as file_io:
            env_config = yaml.safe_load(file_io)
        
        nodes: dict[int, NodeConfig] = {}
        for node_cfg in env_config["cluster"]["nodes"]:
            nodes[node_cfg["node_id"]] = NodeConfig(
                node_cfg["node_id"],
                node_cfg["node_name"],
                node_cfg["cluster_votes"],
                get_api_connection_info(node_cfg["api"]),
                get_node_zfs_disks(node_cfg["zfs_disks"]),
                get_linux_bridges(node_cfg["network"]["bridges"]),
                get_node_cluster_links(node_cfg["network"]["links"])
            )
        # return nodes sorted by key (node_id)
        sorted_nodes: dict[int, NodeConfig] = dict(sorted(nodes.items()))
        return sorted_nodes
    