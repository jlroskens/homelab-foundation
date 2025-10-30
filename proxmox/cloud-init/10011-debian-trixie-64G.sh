#! /bin/bash
set -e
# Requires Cloud Init config loaded to /var/lib/vz/snippets/

CLOUD_RELEASE='20251006-2257'
IMAGE_FILE="debian-13-genericcloud-amd64-${CLOUD_RELEASE}.qcow2"
CLOUD_INIT_FILE='debian-cloudinit.yaml'
VM_ID=10011
STORAGE_GB='32G'
VM_TEMPLATE="debian-trixie-${STORAGE_GB}"
ZFS_POOL='local-cluster-zfs'
NETWORK_BRIDGE='vmbr0'
TEMPLATE_TAGS='debian-trixie,cloudinit'

# Download image to temp directory and resize
## Create temporary directory and trap to clean it up on exit
current_dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
cd "$HOME"
tmp_cloudinit_dir=$(mktemp -d "cloudinit.XXXXXXXXXXXXXXXX" -p .)
trap 'echo "Cleaning up temp directory $tmp_cloudinit_dir" && cd "$current_dir" && rm -rf "$tmp_cloudinit_dir"' EXIT
## Download the image to the temp directory
cd "$tmp_cloudinit_dir"
echo "## Downloading $IMAGE_FILE image. ##"
wget -q https://cloud.debian.org/images/cloud/trixie/${CLOUD_RELEASE}/${IMAGE_FILE}

# Resize image otherwise VMs will be created with no free space
echo "## Resizing $IMAGE_FILE image to $STORAGE_GB. ##"
qemu-img resize $IMAGE_FILE $STORAGE_GB

#sleep 5

# Create a VM that will be later converted to a template 
# --ostype l26    # Linux 2.6 - 6.X Kernel 
# --memory 1024   # Memory. Leave at 1024. Configured when creating a VM from this template.
# --agent 1       # Enable/disable communication with the QEMU Guest Agent and its properties. 
# --bios ovmf     # UEFI bios.
# --machine q35   # q35 enables PCIE capabilities
# --efidisk0 local-cluster-zfs:0,pre-enrolled-keys=0   # Disk for storing EFI vars
# --cpu host      # Set to host if all nodes are the same hardware (CPU), otherwise use 'x86-64-v2-AES'. See https://pve.proxmox.com/pve-docs/qm.1.html#_cpu_type
# --sockets 1     # The number of CPU sockets. Configurable on new VM creation.
# --cores 1       # The number of cores. Configurable on new VM creation.
# --vga serial0   # Cloud init images want serial0. No graphical display
# --serial0 socket  # Not entirely sure, but seems to be required for --vga serial0
# --net0 virtio,bridge=vmbr0  # Network config. Virtual Nic using bridge (vmbr0 = public)
echo "## Creating VM $VM_TEMPLATE with ID $VM_ID ##"
qm create $VM_ID --name "$VM_TEMPLATE" --ostype l26 \
    --memory 2048 \
    --agent 1 \
    --bios ovmf --machine q35 --efidisk0 $ZFS_POOL:0,pre-enrolled-keys=0 \
    --cpu host --sockets 1 --cores 1 \
    --vga serial0 --serial0 socket  \
    --net0 virtio,bridge=$NETWORK_BRIDGE

#sleep 5

# Import the image to the VM and configure boot. Enable DHCP
echo "## Importing $IMAGE_FILE image to $ZFS_POOL. Configuring storage and network. ##"
qm importdisk $VM_ID $IMAGE_FILE $ZFS_POOL                      # Use the downloaded and resized image
qm set $VM_ID --scsihw virtio-scsi-pci --virtio0 $ZFS_POOL:vm-$VM_ID-disk-1,discard=on # Attach disk to host zfs storage
qm set $VM_ID --boot order=virtio0                                                     # Boot from attached disk
qm set $VM_ID --scsi1 $ZFS_POOL:cloudinit                                              # Adds cloud-init "cdrom" drive
qm set $VM_ID --ipconfig0 ip=dhcp

#sleep 5

# Add the cloud-init config and tag the image
echo "## Configuring cloud init to use ${CLOUD_INIT_FILE} and Tagging ##"
qm set $VM_ID --cicustom "vendor=shared-vz:snippets/${CLOUD_INIT_FILE}"
qm set $VM_ID --tags "$TEMPLATE_TAGS"


echo "## Waiting 10 seconds for VM and storage reasources to finish provisioning ##"
sleep 10

# Convert to a template
echo "## Converting $VM_TEMPLATE VM to template ##"
qm template $VM_ID