#! /bin/bash
set -e
# Requires Cloud Init config loaded to /var/lib/vz/snippets/

CLOUD_RELEASE='20251006-2257'
IMAGE_FILE="debian-13-genericcloud-amd64-${CLOUD_RELEASE}.qcow2"
CLOUD_INIT_FILE='debian-docker-cloudinit.yaml'

VM_ID=10016
STORAGE_GB='32G'
VM_TEMPLATE="debian-trixie-docker-${STORAGE_GB}"
PVE_STORAGE='shared-templates'
NETWORK_BRIDGE='vmbr0'
TEMPLATE_TAGS='debian-13,debian-trixie,docker,cloudinit'

# Download image to temp directory and resize
## Create temporary directory and trap to clean it up on exit
current_dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
cd "$HOME"
tmp_cloudinit_dir=$(mktemp -d "cloudinit.XXXXXXXXXXXXXXXX" -p .)
# trap 'echo "Cleaning up temp directory $tmp_cloudinit_dir" && cd "$current_dir" && rm -rf "$tmp_cloudinit_dir"' EXIT
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
# --serial0 socket  # Needed for ubuntu and debian images
# --net0 virtio,bridge=vmbr0  # Network config. Virtual Nic using bridge (vmbr0 = public)
echo "## Creating VM $VM_TEMPLATE with ID $VM_ID ##"
qm create $VM_ID --net0 virtio,bridge=$NETWORK_BRIDGE --name $VM_TEMPLATE \
    --bios ovmf --machine q35 --ostype l26 --agent 1 \
    --vga serial0 --serial0 socket \
    --efidisk0 $PVE_STORAGE:0,pre-enrolled-keys=0 \
    --boot order=virtio0 --scsihw virtio-scsi-pci \
    --virtio0 $PVE_STORAGE:0,import-from=$(realpath $IMAGE_FILE) \
    --scsi1 $PVE_STORAGE:cloudinit \
    --cpu host --sockets 1 --cores 1 \
    --ipconfig0 ip=dhcp \
    --cicustom "vendor=shared-vz:snippets/${CLOUD_INIT_FILE}" \
    --tags "$TEMPLATE_TAGS"

echo "## Waiting 10 seconds for VM and storage reasources to finish provisioning ##"
sleep 10

# Convert to a template
echo "## Converting $VM_TEMPLATE VM to template ##"
qm template $VM_ID
echo "^ When using NFS, then '/usr/bin/chattr: Operation not supported while reading flags' errors can be ignored."