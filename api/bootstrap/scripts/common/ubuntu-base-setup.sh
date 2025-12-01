#!/bin/bash
# Ubuntu Base System Setup Script
# Essential system preparation that runs on every Ubuntu VM regardless of role
# Author: Infrastructure Bootstrap System
# Version: 1.0.0

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/ubuntu-base-setup.log"
TIMEZONE="${TIMEZONE:-UTC}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
	echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"
}

log_warn() {
	echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARN:${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
	echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
	log_error "$1"
	exit 1
}

# Check if running as root
check_root() {
	if [[ $EUID -ne 0 ]]; then
		error_exit "This script must be run as root"
	fi
}

# Detect Ubuntu version
detect_ubuntu_version() {
	if [[ ! -f /etc/os-release ]]; then
		error_exit "Cannot detect Ubuntu version - /etc/os-release not found"
	fi

	source /etc/os-release
	if [[ "$ID" != "ubuntu" ]]; then
		error_exit "This script is designed for Ubuntu systems only. Detected: $ID"
	fi

	UBUNTU_VERSION="$VERSION_ID"
	log "Detected Ubuntu $UBUNTU_VERSION"
}

# Update system packages
update_system() {
	log "Updating system packages..."

	# Update package lists
	apt-get update || error_exit "Failed to update package lists"

	# Upgrade existing packages
	DEBIAN_FRONTEND=noninteractive apt-get upgrade -y || error_exit "Failed to upgrade packages"

	# Install essential packages
	local essential_packages=(
		"curl"
		"wget"
		"git"
		"vim"
		"nano"
		"htop"
		"tree"
		"unzip"
		"tar"
		"ca-certificates"
		"gnupg"
		"lsb-release"
		"software-properties-common"
		"apt-transport-https"
		"net-tools"
		"iputils-ping"
		"dnsutils"
		"rsync"
		"jq"
		"python3"
		"python3-pip"
		"build-essential"
	)

	log "Installing essential packages: ${essential_packages[*]}"
	DEBIAN_FRONTEND=noninteractive apt-get install -y "${essential_packages[@]}" || error_exit "Failed to install essential packages"

	# Clean up
	apt-get autoremove -y
	apt-get autoclean

	log "System packages updated successfully"
}

# Configure timezone
configure_timezone() {
	log "Configuring timezone to $TIMEZONE..."

	timedatectl set-timezone "$TIMEZONE" || error_exit "Failed to set timezone"

	# Verify timezone setting
	local current_tz
	current_tz=$(timedatectl show --property=Timezone --value)
	if [[ "$current_tz" == "$TIMEZONE" ]]; then
		log "Timezone set successfully to $TIMEZONE"
	else
		log_warn "Timezone setting may not have applied correctly. Current: $current_tz, Expected: $TIMEZONE"
	fi
}

# Configure locale
configure_locale() {
	log "Configuring system locale..."

	# Ensure en_US.UTF-8 locale is available
	if ! locale -a | grep -q "en_US.utf8"; then
		locale-gen en_US.UTF-8 || log_warn "Failed to generate en_US.UTF-8 locale"
	fi

	# Update locale
	update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 || log_warn "Failed to update locale settings"

	log "Locale configuration completed"
}

# Configure NTP/time synchronization
configure_time_sync() {
	log "Configuring time synchronization..."

	# Enable and start systemd-timesyncd
	systemctl enable systemd-timesyncd || log_warn "Failed to enable systemd-timesyncd"
	systemctl start systemd-timesyncd || log_warn "Failed to start systemd-timesyncd"

	# Verify time sync status
	if timedatectl status | grep -q "System clock synchronized: yes"; then
		log "Time synchronization is working correctly"
	else
		log_warn "Time synchronization may not be working properly"
	fi
}

# Optimize system settings
optimize_system() {
	log "Applying basic system optimizations..."

	# Increase file descriptor limits
	cat >> /etc/security/limits.conf << 'EOF'
# Infrastructure bootstrap system optimizations
* soft nofile 65536
* hard nofile 65536
* soft nproc 32768
* hard nproc 32768
EOF

	# Configure sysctl for better network performance
	cat > /etc/sysctl.d/99-infrastructure-base.conf << 'EOF'
# Infrastructure bootstrap base system optimizations
# Network optimizations
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# File system optimizations
fs.file-max = 1048576
vm.swappiness = 1
EOF

	# Apply sysctl settings
	sysctl -p /etc/sysctl.d/99-infrastructure-base.conf || log_warn "Failed to apply sysctl settings"

	log "System optimizations applied"
}

# Setup basic directory structure
setup_directories() {
	log "Setting up standard directory structure..."

	# Create standard directories
	local directories=(
		"/opt/scripts"
		"/opt/configs"
		"/opt/logs"
		"/var/log/infrastructure"
	)

	for dir in "${directories[@]}"; do
		mkdir -p "$dir" || log_warn "Failed to create directory $dir"
		chmod 755 "$dir"
	done

	log "Standard directories created"
}

# Configure system logging
configure_logging() {
	log "Configuring system logging..."

	# Ensure rsyslog is running
	systemctl enable rsyslog || log_warn "Failed to enable rsyslog"
	systemctl start rsyslog || log_warn "Failed to start rsyslog"

	# Configure log rotation for infrastructure logs
	cat > /etc/logrotate.d/infrastructure << 'EOF'
/var/log/infrastructure/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    copytruncate
}
EOF

	log "System logging configured"
}

# Main execution function
main() {
	log "Starting Ubuntu base system setup..."

	check_root
	detect_ubuntu_version
	update_system
	configure_timezone
	configure_locale
	configure_time_sync
	optimize_system
	setup_directories
	configure_logging

	log "Ubuntu base system setup completed successfully!"

	# Create completion marker
	echo "$(date)" > /var/log/ubuntu-base-setup.completed
}

# Run main function
main "$@"
