#!/usr/bin/env bash

set -eEou pipefail

# Global variables
declare -g LOG_FILE=""
declare -g DEBUG="${DEBUG:-0}"

# Colors (only what we need)
declare -gr RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m'
declare -gr BLUE='\033[0;34m' CYAN='\033[0;36m' NC='\033[0m' DIM='\033[2m'

OS_NAME=""
OS_VERSION=""
OS_FAMILY=""
ROLE_NAME=""
ROLE_DESCRIPTION=""

OUTPUT_DIR="./generated"
TEMPLATE_DIR="./templates"

# Smart date handling (assumes GNU date on Ubuntu/Linux)
utc_timestamp() { date -u +%s; }
iso_timestamp() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
to_epoch() { date -d "${1:-}" +%s 2>/dev/null || {
    echo "Invalid timestamp: $1" >&2
    return 1
}; }

# Enhanced logging with auto-initialization
log() {
    local level="${1^^}" msg="$2" ts="$(iso_timestamp)"
    local colors=([ERROR]="$RED" [WARN]="$YELLOW" [WARNING]="$YELLOW" [INFO]="$BLUE" [SUCCESS]="$GREEN" [DEBUG]="$DIM")
    local clean_msg="[$ts] [$level]: $msg"

    # Auto-initialize logging on first use
    [[ -z "$LOG_FILE" ]] && init_logging "${LOG_DIR:-/tmp}"

    # Console output with colors
    if [[ "$level" == "DEBUG" && "$DEBUG" != "1" ]]; then
        return 0
    elif [[ "$level" == "ERROR" ]]; then
        printf "${CYAN}%s ${colors[$level]:-}[%s]:${NC} %s\n" "$ts" "$level" "$msg" >&2
    else
        printf "${CYAN}%s ${colors[$level]:-}[%s]:${NC} %s\n" "$ts" "$level" "$msg"
    fi

    # File output (clean, no colors)
    echo "$clean_msg" >>"$LOG_FILE"
}

# Smart log initialization
init_logging() {
    local log_dir="${1:-/tmp}"
    [[ ! -d "$log_dir" ]] && { mkdir -p "$log_dir" || fail "Cannot create log dir: $log_dir"; }

    LOG_FILE="$log_dir/$(date -u '+%Y%m%d_%H%M%S').log"
    {
        echo "=== Script: ${0##*/} | Started: $(iso_timestamp) ==="
        echo "Args: ${*:-none} | PID: $$ | User: ${USER:-unknown}"
        echo "===================================================="
    } >"$LOG_FILE"
}

# Enhanced error handling
fail() {
    log error "${1:-Script failed}"
    exit "${2:-1}"
}
trap 'fail "Script failed at line $LINENO with exit code $?" "$?"' ERR

# Utility functions
separator() {
    local line="======================================================"
    printf "${CYAN}%s${NC}\n" "$line"
    echo "$line" >>"${LOG_FILE:-/dev/null}"
}

generate_template() {
    # packer defaults
    local packer_required_version="1.12.0"
    local packer_plugins_ansible_version="1"
    local packer_plugins_git_version="0.6.2"
    local packer_plugins_proxmox_version="1.2.3"
    # vm template defaults
    local vm_bios="ovmf"
    local vm_qemu_agent="true"
    local vm_boot_enabled="true"
    local vm_boot_wait="10s"
    local vm_timeout="30m"
    local vm_cloudinit="true"
    # SSH
    local ssh_port="22"
    # Disk
    local disk_virtio_device="vda"
    local disk_scsi_device="sda"
    local disk_use_swap="false"
    # Boot/BIOS/UEFI
    local boot_bios_commands=["c<wait5>", "linux /casper/vmlinuz --- autoinstall ${local.data_source_command}", "<enter><wait10>", "initrd /casper/initrd", "<enter><wait10>", "boot", "<enter>"]
    local boot_uefi_comands=["<wait3s>c<wait3s>", "linux /casper/vmlinuz --- autoinstall ${local.data_source_command}", "<enter><wait>", "initrd /casper/initrd", "<enter><wait>", "boot", "<enter>"]
    # Ansible
    local ansible_enabled="true"
    local ansible_requirements_file="linux-requirements.yml"
    local ansible_playbook_file="linux_playbook"
    local ansible_python_interpreter="/usr/bin/python3"
    local ansible_galaxy_force_with_deps="true"
    local ansible_extra_vars=[]

    log "Generating main Packer template..."

    jinja2 "${TEMPLATE_DIR}/template.pkr.hcl.j2" \
        -D os.family="${OS_FAMILY}" \
        -D os.name="${OS_NAME}" \
        -D os.version="${OS_VERSION}" \
        -D os.description="$ROLE_DESCRIPTION}" \
        -D packer.required_version="${packer_required_version}" \
        -D packer.plugins.ansible_version="${packer_plugins_ansible_version}" \
        -D packer.plugins.git_version="${packer_plugins_git_version}" \
        -D packer.plugins.proxmox_version="${packer_plugins_proxmox_version}" \
        -D vm.bios="${vm_bios}" \
        -D vm.qemu_agent="${vm_qemu_agent}" \
        -D vm.boot.enabled="${vm_boot_enabled}" \
        -D vm.boot.wait="${vm_boot_wait}" \
        -D vm.timeout="${vm_timeout}" \
        -D vm.cloudinit="${vm_cloudinit}" \
        -D ssh.port="${ssh_port}" \
        -D disk.virtio_device="${disk_virtio_device}" \
        -D disk.scsi_device="${disk_scsi_device}" \
        -D disk.use_swap="${disk_use_swap}" \
        -D boot.bios_commands="${boot_bios_commands}" \
        -D boot.uefi_commands="${boot_uefi_comands}" \
        -D ansible.enabled="${ansible_enabled}" \
        -D ansible.requirements_file="${ansible_requirements_file}" \
        -D ansible.playbook_file="${ansible_playbook_file}" \
        -D ansible.python_interpreter="${ansible_python_interpreter}" \
        -D ansible.galaxy_force_with_deps="${ansible_galaxy_force_with_deps}" \
        -D ansible.extra_vars="${ansible_extra_vars}" \
        >"${OUTPUT_DIR}/${OS_NAME}-${ROLE_NAME}.pkr.hcl"
}

generate_os_vars() {
    log "Generating OS variables..."

    jinja2 "${TEMPLATE_DIR}/os.pkrvars.hcl.j2" \
        -D os.family="${OS_FAMILY}" \
        -D os.name="${OS_NAME}" \
        -D os.version="${OS_VERSION}" \
        -D os.type="l26" \
        -D os.language="en_US" \
        -D os.keyboard="us" \
        -D os.timezone="UTC" \
        -D role_name="${ROLE_NAME}" \
        -D iso.path="template/iso" \
        -D iso.file="ubuntu-22.04.3-live-server-amd64.iso" \
        -D iso.checksum="sha256:a4acfda10b18da50e2ec50ccaf860d7f20b389df8765611142305c0e911d16fd" \
        -D cloudinit.data_source="http" \
        -D cloudinit.http.interface="" \
        -D cloudinit.http.bind_address="" \
        -D cloudinit.http.port_min="8802" \
        -D cloudinit.http.port_max="8812" \
        -D cloudinit.iso_storage="local" \
        -D 'additional_packages=["curl", "wget", "vim", "htop"]' \
        >"${OUTPUT_DIR}/os.pkrvars.hcl"
}

generate_build_vars() {
    log "Generating build account variables..."

    jinja2 "${TEMPLATE_DIR}/build.pkrvars.hcl.j2" \
        -D build_account.username="deploy" \
        -D build_account.password="deploy" \
        -D 'build_account.password_encrypted="$6$MsfTs/5vjdnlgqEt$pkl1uGs645Y1NLpzQu7R/coOohkyzksn2YkY2EgjOuXkA6Tnrr3Yag8LYeotfYaiiyIzn3MyYCWdeqM.2VKAz1"' \
        -D build_account.public_key="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQ... your-public-key-here" \
        >"${OUTPUT_DIR}/build.pkrvars.hcl"
}

generate_network_vars() {
    log "Generating network variables..."

    jinja2 "${TEMPLATE_DIR}/network.pkrvars.hcl.j2" \
        -D network.device="enp6s18" \
        -D network.card_model="virtio" \
        -D network.bridge="vmbr2" \
        -D network.vlan_tag="" \
        -D network.ip="192.168.100.100" \
        -D network.netmask="24" \
        -D network.gateway="192.168.100.1" \
        -D 'network.dns=["8.8.8.8", "8.8.4.4"]' \
        >"${OUTPUT_DIR}/network.pkrvars.hcl"
}

generate_storage_vars() {
    log "Generating storage variables..."

    jinja2 "${TEMPLATE_DIR}/storage.pkrvars.hcl.j2" \
        -D disk.use_swap="true" \
        -D vm.disk.size="20G" \
        -D vm.disk.type="virtio" \
        -D vm.disk.format="raw" \
        -D vm.disk.controller="virtio-scsi-pci" \
        -D vm.disk.device="vda" \
        -D vm.storage_pool="local-lvm" \
        >"${OUTPUT_DIR}/storage.pkrvars.hcl"
}

generate_resource_vars() {
    log "Generating resource variables..."

    jinja2 "${TEMPLATE_DIR}/resource.pkrvars.hcl.j2" \
        -D vm.cpu.sockets="1" \
        -D vm.cpu.cores="2" \
        -D vm.cpu.type="host" \
        -D vm.memory="2048" \
        >"${OUTPUT_DIR}/resource.pkrvars.hcl"
}

generate_proxmox_vars() {
    log "Generating Proxmox variables..."

    jinja2 "${TEMPLATE_DIR}/proxmox.pkrvars.hcl.j2" \
        -D proxmox.api.token_id="name@realm!token" \
        -D proxmox.api.token_secret="<your-token-secret>" \
        -D proxmox.insecure_connection="false" \
        -D proxmox.hostname="proxmox.example.com" \
        -D proxmox.node="pve" \
        >"${OUTPUT_DIR}/proxmox.pkrvars.hcl"
}

generate_ansible_vars() {
    log "Generating Ansible variables..."

    jinja2 "${TEMPLATE_DIR}/ansible.pkrvars.hcl.j2" \
        -D ansible.username="deploy" \
        -D ansible.public_key="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQ... your-ansible-public-key-here" \
        -D build_account.username="deploy" \
        -D build_account.public_key="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQ... your-public-key-here" \
        >"${OUTPUT_DIR}/ansible.pkrvars.hcl"
}

main() {
    log "Starting Packer template generation..."

    # Create output directory
    mkdir -p "${OUTPUT_DIR}"

    # Generate all files
    generate_template
    generate_os_vars
    generate_build_vars
    generate_network_vars
    generate_storage_vars
    generate_resource_vars
    generate_proxmox_vars
    generate_ansible_vars

    log "All files generated successfully in ${OUTPUT_DIR}/"
    log "Generated files:"
    log "  - ${OS_FAMILY}-${OS_NAME}-${OS_VERSION}.pkr.hcl"
    log "  - os.pkrvars.hcl"
    log "  - build.pkrvars.hcl"
    log "  - network.pkrvars.hcl"
    log "  - storage.pkrvars.hcl"
    log "  - resource.pkrvars.hcl"
    log "  - proxmox.pkrvars.hcl"
    log "  - ansible.pkrvars.hcl"

    log "To build with Packer:"
    echo "  cd ${OUTPUT_DIR}"
    echo "  packer build -var-file=\"os.pkrvars.hcl\" -var-file=\"build.pkrvars.hcl\" -var-file=\"network.pkrvars.hcl\" -var-file=\"storage.pkrvars.hcl\" -var-file=\"resource.pkrvars.hcl\" -var-file=\"proxmox.pkrvars.hcl\" -var-file=\"ansible.pkrvars.hcl\" \"${OS_FAMILY}-${OS_NAME}-${OS_VERSION}.pkr.hcl\""
}   

# Run main function
main
    