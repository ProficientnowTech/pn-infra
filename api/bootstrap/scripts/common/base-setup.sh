#!/bin/bash

# Base VM Setup Script
# This script performs common setup tasks for all VM roles
# Author: DevOps Team
# Version: 1.0.0

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/base-setup.log"
TIMEZONE="${TIMEZONE:-UTC}"
SSH_PORT="${SSH_PORT:-22}"
ROOT_SSH_KEY="${ROOT_SSH_KEY:-}"

# Logging function
log() {
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
	log "ERROR: $1"
	exit 1
}

# Check if running as root
check_root() {
	if [[ $EUID -ne 0 ]]; then
		error_exit "This script must be run as root"
	fi
}

# Update system packages
update_system() {
	log "Updating system packages..."
	export DEBIAN_FRONTEND=noninteractive

	# Update package lists
	apt-get update -y || error_exit "Failed to update package lists"

	# Upgrade existing packages
	apt-get upgrade -y || error_exit "Failed to upgrade packages"

	# Install essential packages
	apt-get install -y \
		curl \
		wget \
		vim \
		htop \
		tree \
		unzip \
		zip \
		git \
		jq \
		net-tools \
		dnsutils \
		telnet \
		tcpdump \
		rsync \
		cron \
		logrotate \
		sudo \
		openssh-server \
		ca-certificates \
		gnupg \
		lsb-release \
		software-properties-common \
		apt-transport-https \
		|| error_exit "Failed to install essential packages"

	log "System packages updated successfully"
}

# Configure timezone
configure_timezone() {
	log "Setting timezone to $TIMEZONE..."
	timedatectl set-timezone "$TIMEZONE" || error_exit "Failed to set timezone"
	log "Timezone set to $TIMEZONE"
}

# Setup NTP synchronization
setup_ntp() {
	log "Setting up NTP synchronization..."
	apt-get install -y chrony || error_exit "Failed to install chrony"

	# Configure chrony
	cat > /etc/chrony/chrony.conf << 'EOF'
# Use public NTP servers
server 0.pool.ntp.org iburst
server 1.pool.ntp.org iburst
server 2.pool.ntp.org iburst
server 3.pool.ntp.org iburst

# Record the rate at which the system clock gains/losses time
driftfile /var/lib/chrony/drift

# Allow the system clock to be stepped in the first three updates
makestep 1.0 3

# Enable kernel synchronization of the real-time clock (RTC)
rtcsync

# Enable hardware timestamping on all interfaces that support it
#hwtimestamp *

# Increase the minimum number of selectable sources required to adjust
# the system clock
#minsources 2

# Allow NTP client access from local network
#allow 192.168.0.0/16

# Serve time even if not synchronized to a time source
#local stratum 10

# Specify file containing keys for NTP authentication
#keyfile /etc/chrony/chrony.keys

# Get TAI-UTC offset and leap seconds from the system tz database
leapsectz right/UTC

# Specify directory for log files
logdir /var/log/chrony

# Select which information is logged
#log measurements statistics tracking
EOF

	systemctl enable chrony || error_exit "Failed to enable chrony"
	systemctl start chrony || error_exit "Failed to start chrony"

	log "NTP synchronization configured"
}

# Configure SSH
configure_ssh() {
	log "Configuring SSH..."

	# Backup original sshd_config
	cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

	# Create SSH configuration
	cat > /etc/ssh/sshd_config << EOF
# SSH Configuration - DevOps Team
Port $SSH_PORT
Protocol 2

# Authentication
PermitRootLogin yes
PasswordAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
ChallengeResponseAuthentication no
UsePAM yes

# Security settings
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server

# Connection settings
ClientAliveInterval 60
ClientAliveCountMax 3
MaxAuthTries 3
MaxSessions 10

# Disable unused authentication methods
HostbasedAuthentication no
IgnoreRhosts yes
PermitEmptyPasswords no

# Logging
SyslogFacility AUTH
LogLevel INFO
EOF

	# Set up root SSH key if provided
	if [[ -n "$ROOT_SSH_KEY" ]]; then
		log "Setting up root SSH key..."
		mkdir -p /root/.ssh
		chmod 700 /root/.ssh
		echo "$ROOT_SSH_KEY" >> /root/.ssh/authorized_keys
		chmod 600 /root/.ssh/authorized_keys
		chown root:root /root/.ssh/authorized_keys
		log "Root SSH key configured"
	fi

	# Test SSH configuration
	sshd -t || error_exit "SSH configuration is invalid"

	# Restart SSH service
	systemctl restart ssh || error_exit "Failed to restart SSH service"
	systemctl enable ssh || error_exit "Failed to enable SSH service"

	log "SSH configured successfully"
}

# Setup system users
setup_users() {
	log "Setting up system users..."

	# Create devops user for administration
	if ! id "devops" &> /dev/null; then
		useradd -m -s /bin/bash -G sudo devops || error_exit "Failed to create devops user"
		log "Created devops user"
	fi

	# Configure sudo for devops user
	echo "devops ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/devops
	chmod 440 /etc/sudoers.d/devops

	# Set up SSH directory for devops user
	mkdir -p /home/devops/.ssh
	chmod 700 /home/devops/.ssh
	chown devops:devops /home/devops/.ssh

	if [[ -n "$ROOT_SSH_KEY" ]]; then
		echo "$ROOT_SSH_KEY" > /home/devops/.ssh/authorized_keys
		chmod 600 /home/devops/.ssh/authorized_keys
		chown devops:devops /home/devops/.ssh/authorized_keys
	fi

	log "System users configured"
}

# Configure hostname
configure_hostname() {
	local hostname="${HOSTNAME:-$(hostname)}"
	log "Setting hostname to $hostname..."

	# Set hostname
	hostnamectl set-hostname "$hostname" || error_exit "Failed to set hostname"

	# Update /etc/hosts
	cat > /etc/hosts << EOF
127.0.0.1 localhost
127.0.1.1 $hostname
::1 localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

	log "Hostname configured to $hostname"
}

# Setup logging and log rotation
setup_logging() {
	log "Setting up logging configuration..."

	# Configure logrotate for custom logs
	cat > /etc/logrotate.d/vm-setup << 'EOF'
/var/log/base-setup.log
/var/log/vm-*.log {
    weekly
    rotate 8
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}
EOF

	# Ensure rsyslog is running
	systemctl enable rsyslog || error_exit "Failed to enable rsyslog"
	systemctl start rsyslog || error_exit "Failed to start rsyslog"

	log "Logging configuration completed"
}

# Setup system limits
configure_limits() {
	log "Configuring system limits..."

	# Set system limits
	cat > /etc/security/limits.d/99-vm-limits.conf << 'EOF'
# VM System Limits
* soft nofile 65536
* hard nofile 65536
* soft nproc 65536
* hard nproc 65536
root soft nofile 65536
root hard nofile 65536
root soft nproc 65536
root hard nproc 65536
EOF

	# Configure kernel parameters
	cat > /etc/sysctl.d/99-vm-tuning.conf << 'EOF'
# VM Kernel Tuning
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 5000
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 12582912 16777216
net.ipv4.tcp_wmem = 4096 12582912 16777216
net.ipv4.tcp_max_syn_backlog = 8096
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_tw_reuse = 1
fs.file-max = 2097152
EOF

	# Apply sysctl settings
	sysctl --system || error_exit "Failed to apply sysctl settings"

	log "System limits configured"
}

# Clean up system
cleanup_system() {
	log "Cleaning up system..."

	# Clean package cache
	apt-get autoremove -y || true
	apt-get autoclean || true

	# Clear temporary files
	find /tmp -type f -atime +7 -delete 2> /dev/null || true
	find /var/tmp -type f -atime +7 -delete 2> /dev/null || true

	# Clear logs older than 30 days
	find /var/log -name "*.log" -type f -mtime +30 -delete 2> /dev/null || true

	log "System cleanup completed"
}

# Create system info file
create_system_info() {
	log "Creating system information file..."

	cat > /etc/vm-info << EOF
# VM Information
VM_ROLE=${VM_ROLE:-unknown}
VM_VERSION=${VM_VERSION:-1.0.0}
SETUP_DATE=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
SETUP_SCRIPT=base-setup.sh
SETUP_VERSION=1.0.0

# System Information
OS_VERSION=$(lsb_release -d | cut -f2)
KERNEL_VERSION=$(uname -r)
HOSTNAME=$(hostname)
IP_ADDRESS=$(hostname -I | awk '{print $1}')
EOF

	chmod 644 /etc/vm-info
	log "System information file created"
}

# Main function
main() {
	log "Starting base VM setup..."

	check_root
	update_system
	configure_timezone
	setup_ntp
	configure_ssh
	setup_users
	configure_hostname
	setup_logging
	configure_limits
	create_system_info
	cleanup_system

	log "Base VM setup completed successfully!"
	log "VM is ready for role-specific configuration"
}

# Execute main function
main "$@"
