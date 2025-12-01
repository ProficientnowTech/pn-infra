#!/bin/bash
# Ubuntu Security Hardening Script
# Essential security configuration that runs on every Ubuntu VM
# Author: Infrastructure Bootstrap System
# Version: 1.0.0

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/ubuntu-security-hardening.log"
SSH_PORT="${SSH_PORT:-22}"

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

# Configure UFW firewall
configure_firewall() {
	log "Configuring UFW firewall..."

	# Install UFW if not present
	if ! command -v ufw &> /dev/null; then
		apt-get update
		apt-get install -y ufw || error_exit "Failed to install UFW"
	fi

	# Reset UFW to defaults
	ufw --force reset

	# Set default policies
	ufw default deny incoming
	ufw default allow outgoing

	# Allow SSH (essential for remote management)
	ufw allow "$SSH_PORT"/tcp comment "SSH access"

	# Enable UFW
	echo "y" | ufw enable || error_exit "Failed to enable UFW"

	log "UFW firewall configured successfully"
}

# Harden SSH configuration
harden_ssh() {
	log "Hardening SSH configuration..."

	# Backup original SSH config
	cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%Y%m%d_%H%M%S)

	# Create hardened SSH configuration
	cat > /etc/ssh/sshd_config.d/99-infrastructure-hardening.conf << EOF
# Infrastructure bootstrap SSH hardening
Protocol 2
Port $SSH_PORT

# Authentication settings
PermitRootLogin prohibit-password
PasswordAuthentication yes
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys

# Security settings
PermitEmptyPasswords no
MaxAuthTries 3
MaxSessions 10
LoginGraceTime 60

# Disable unused features
AllowAgentForwarding no
AllowTcpForwarding no
X11Forwarding no
PrintMotd no

# Cryptography settings
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com,hmac-sha2-256,hmac-sha2-512
KexAlgorithms curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512

# Connection settings
ClientAliveInterval 300
ClientAliveCountMax 2
TCPKeepAlive no
EOF

	# Test SSH configuration
	sshd -t || error_exit "SSH configuration test failed"

	# Restart SSH service
	systemctl restart ssh || error_exit "Failed to restart SSH service"

	log "SSH hardening completed successfully"
}

# Configure fail2ban
configure_fail2ban() {
	log "Installing and configuring fail2ban..."

	# Install fail2ban
	apt-get update
	apt-get install -y fail2ban || error_exit "Failed to install fail2ban"

	# Create fail2ban configuration
	cat > /etc/fail2ban/jail.d/infrastructure.conf << EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[ssh]
enabled = true
port = $SSH_PORT
logpath = /var/log/auth.log
backend = systemd

[ssh-ddos]
enabled = true
port = $SSH_PORT
logpath = /var/log/auth.log
backend = systemd
EOF

	# Enable and start fail2ban
	systemctl enable fail2ban || error_exit "Failed to enable fail2ban"
	systemctl start fail2ban || error_exit "Failed to start fail2ban"

	log "fail2ban configured successfully"
}

# Disable unnecessary services
disable_unnecessary_services() {
	log "Disabling unnecessary services..."

	# List of services to disable (if they exist)
	local services_to_disable=(
		"avahi-daemon"
		"cups"
		"bluetooth"
		"whoopsie"
		"apport"
	)

	for service in "${services_to_disable[@]}"; do
		if systemctl list-unit-files | grep -q "^$service"; then
			systemctl disable "$service" &> /dev/null || log_warn "Could not disable $service"
			systemctl stop "$service" &> /dev/null || log_warn "Could not stop $service"
			log "Disabled service: $service"
		fi
	done

	log "Unnecessary services disabled"
}

# Configure kernel security
configure_kernel_security() {
	log "Configuring kernel security settings..."

	# Create kernel security sysctl configuration
	cat > /etc/sysctl.d/99-infrastructure-security.conf << 'EOF'
# Infrastructure bootstrap security optimizations

# Network security
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.tcp_syncookies = 1

# IPv6 security (disable if not used)
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1

# Memory protection
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.yama.ptrace_scope = 1

# File system security
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
fs.suid_dumpable = 0
EOF

	# Apply sysctl settings
	sysctl -p /etc/sysctl.d/99-infrastructure-security.conf || log_warn "Failed to apply security sysctl settings"

	log "Kernel security settings applied"
}

# Configure automatic security updates
configure_auto_updates() {
	log "Configuring automatic security updates..."

	# Install unattended-upgrades if not present
	apt-get install -y unattended-upgrades || error_exit "Failed to install unattended-upgrades"

	# Configure automatic updates
	cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
EOF

	# Configure unattended-upgrades
	cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};

Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

	# Enable and start unattended-upgrades
	systemctl enable unattended-upgrades || log_warn "Failed to enable unattended-upgrades"
	systemctl start unattended-upgrades || log_warn "Failed to start unattended-upgrades"

	log "Automatic security updates configured"
}

# Set secure file permissions
secure_file_permissions() {
	log "Setting secure file permissions..."

	# Secure important system files
	chmod 600 /etc/ssh/sshd_config* 2> /dev/null || log_warn "Could not secure SSH config permissions"
	chmod 644 /etc/passwd
	chmod 600 /etc/shadow
	chmod 644 /etc/group
	chmod 600 /etc/gshadow
	chmod 600 /boot/grub/grub.cfg 2> /dev/null || log_warn "Could not secure GRUB config permissions"

	# Remove world-writable permissions from system directories
	find /usr -type f -perm -002 -exec chmod o-w {} \; 2> /dev/null || log_warn "Could not remove world-writable permissions from /usr"

	log "File permissions secured"
}

# Main execution function
main() {
	log "Starting Ubuntu security hardening..."

	check_root
	configure_firewall
	harden_ssh
	configure_fail2ban
	disable_unnecessary_services
	configure_kernel_security
	configure_auto_updates
	secure_file_permissions

	log "Ubuntu security hardening completed successfully!"

	# Create completion marker
	echo "$(date)" > /var/log/ubuntu-security-hardening.completed

	log "IMPORTANT: Review firewall rules and SSH configuration before disconnecting!"
}

# Run main function
main "$@"
