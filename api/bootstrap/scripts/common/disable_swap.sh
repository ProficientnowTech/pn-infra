#!/bin/bash
# disable_swap.sh - Disable swap for containerized environments
# Part of the infrastructure bootstrap system
# Used by: Kubernetes nodes, container-based roles

set -euo pipefail

# Configuration
SCRIPT_NAME="disable_swap.sh"
LOG_FILE="/var/log/bootstrap.log"

# Logging function
log() {
	local level="$1"
	shift
	echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $SCRIPT_NAME: $*" | tee -a "$LOG_FILE"
}

# Check if running as root
check_root() {
	if [[ $EUID -ne 0 ]]; then
		log "ERROR" "This script must be run as root"
		exit 1
	fi
}

# Disable swap immediately
disable_swap_immediate() {
	log "INFO" "Disabling swap immediately..."

	if swapon --show | grep -q "/"; then
		log "INFO" "Swap is currently enabled, turning it off..."
		swapoff -a
		log "INFO" "Swap disabled successfully"
	else
		log "INFO" "Swap is already disabled"
	fi
}

# Disable swap permanently by modifying /etc/fstab
disable_swap_permanent() {
	log "INFO" "Disabling swap permanently in /etc/fstab..."

	if grep -q "swap" /etc/fstab; then
		log "INFO" "Found swap entries in /etc/fstab, commenting them out..."

		# Create backup of fstab
		cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d_%H%M%S)
		log "INFO" "Created backup of /etc/fstab"

		# Comment out swap lines
		sed -i.bak '/swap/s/^/#/' /etc/fstab

		# Verify the changes
		if grep -q "^[^#].*swap" /etc/fstab; then
			log "ERROR" "Failed to comment out all swap entries in /etc/fstab"
			return 1
		else
			log "INFO" "Successfully commented out swap entries in /etc/fstab"
		fi
	else
		log "INFO" "No swap entries found in /etc/fstab"
	fi
}

# Remove swap files if they exist
remove_swap_files() {
	log "INFO" "Checking for swap files to remove..."

	# Common swap file locations
	local swap_files=(
		"/swapfile"
		"/swap.img"
		"/var/swap"
		"/tmp/swap"
	)

	for swap_file in "${swap_files[@]}"; do
		if [[ -f "$swap_file" ]]; then
			log "INFO" "Found swap file: $swap_file"

			# Make sure it's not currently in use
			if swapon --show | grep -q "$swap_file"; then
				log "INFO" "Disabling swap file: $swap_file"
				swapoff "$swap_file"
			fi

			log "INFO" "Removing swap file: $swap_file"
			rm -f "$swap_file"
		fi
	done
}

# Disable swap-related systemd services
disable_swap_services() {
	log "INFO" "Disabling swap-related systemd services..."

	local swap_services=(
		"dphys-swapfile"
		"swap.target"
	)

	for service in "${swap_services[@]}"; do
		if systemctl is-enabled "$service" > /dev/null 2>&1; then
			log "INFO" "Disabling systemd service: $service"
			systemctl disable "$service" || log "WARN" "Failed to disable $service (may not exist)"
		fi

		if systemctl is-active "$service" > /dev/null 2>&1; then
			log "INFO" "Stopping systemd service: $service"
			systemctl stop "$service" || log "WARN" "Failed to stop $service (may not be running)"
		fi
	done
}

# Set vm.swappiness to 0 for better performance
configure_swappiness() {
	log "INFO" "Configuring vm.swappiness..."

	# Set immediately
	echo 0 > /proc/sys/vm/swappiness

	# Make permanent
	if ! grep -q "vm.swappiness" /etc/sysctl.conf; then
		echo "vm.swappiness = 0" >> /etc/sysctl.conf
		log "INFO" "Added vm.swappiness = 0 to /etc/sysctl.conf"
	else
		sed -i 's/vm.swappiness.*/vm.swappiness = 0/' /etc/sysctl.conf
		log "INFO" "Updated vm.swappiness in /etc/sysctl.conf"
	fi
}

# Verify swap is disabled
verify_swap_disabled() {
	log "INFO" "Verifying swap is disabled..."

	if free | awk '/^Swap:/ {exit ($2 != 0)}'; then
		log "INFO" "✓ Swap is successfully disabled"
		return 0
	else
		log "ERROR" "✗ Swap is still enabled"
		return 1
	fi
}

# Main function
main() {
	log "INFO" "Starting swap disable process..."

	# Check prerequisites
	check_root

	# Disable swap
	disable_swap_immediate
	disable_swap_permanent
	remove_swap_files
	disable_swap_services
	configure_swappiness

	# Verify results
	if verify_swap_disabled; then
		log "INFO" "Swap disable process completed successfully"

		# Show current memory status
		log "INFO" "Current memory status:"
		free -h | while IFS= read -r line; do
			log "INFO" "  $line"
		done

		exit 0
	else
		log "ERROR" "Swap disable process failed"
		exit 1
	fi
}

# Handle script interruption
cleanup() {
	log "WARN" "Script interrupted, cleaning up..."
	exit 130
}

trap cleanup SIGINT SIGTERM

# Run main function
main "$@"
