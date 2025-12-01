#!/bin/bash

# Security Hardening Script
# This script implements security best practices for VM hardening
# Author: DevOps Team
# Version: 1.0.0

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/security-hardening.log"
FAIL2BAN_EMAIL="${FAIL2BAN_EMAIL:-admin@example.com}"
SSH_PORT="${SSH_PORT:-22}"
ALLOWED_SSH_USERS="${ALLOWED_SSH_USERS:-root,devops}"

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

# Disable unnecessary services
disable_services() {
	log "Disabling unnecessary services..."

	local services_to_disable=(
		"avahi-daemon"
		"cups"
		"rpcbind"
		"nfs-server"
		"telnet"
		"rsh-server"
		"talk"
		"xinetd"
		"bluetooth"
		"apache2"
		"nginx"
		"mysql"
		"postgresql"
	)

	for service in "${services_to_disable[@]}"; do
		if systemctl is-enabled "$service" &> /dev/null; then
			systemctl disable "$service" || log "Warning: Could not disable $service"
			systemctl stop "$service" || log "Warning: Could not stop $service"
			log "Disabled service: $service"
		fi
	done

	log "Unnecessary services disabled"
}

# Remove unnecessary packages
remove_packages() {
	log "Removing unnecessary packages..."

	export DEBIAN_FRONTEND=noninteractive

	local packages_to_remove=(
		"telnet"
		"rsh-client"
		"rsh-redone-client"
		"talk"
		"ntalk"
		"finger"
		"ldap-utils"
		"whoami"
		"rwho"
		"ruser"
		"rcp"
		"rusers"
		"rlogin"
		"rwall"
		"tftp"
		"tftp-server"
		"xinetd"
	)

	for package in "${packages_to_remove[@]}"; do
		if dpkg -l | grep -q "^ii.*$package"; then
			apt-get remove -y "$package" || log "Warning: Could not remove $package"
			log "Removed package: $package"
		fi
	done

	# Clean up
	apt-get autoremove -y
	apt-get autoclean

	log "Unnecessary packages removed"
}

# Configure firewall
configure_firewall() {
	log "Configuring UFW firewall..."

	# Install ufw if not present
	apt-get install -y ufw || error_exit "Failed to install ufw"

	# Reset UFW to defaults
	ufw --force reset

	# Set default policies
	ufw default deny incoming
	ufw default allow outgoing

	# Allow SSH
	ufw allow "$SSH_PORT"/tcp comment 'SSH'

	# Allow common monitoring ports (can be customized per role)
	ufw allow 9100/tcp comment 'Node Exporter'

	# Allow ping
	ufw allow in on any to any port 22 proto icmp

	# Enable UFW
	ufw --force enable

	# Configure UFW logging
	ufw logging on

	log "UFW firewall configured and enabled"
}

# Install and configure Fail2Ban
setup_fail2ban() {
	log "Setting up Fail2Ban..."

	apt-get install -y fail2ban || error_exit "Failed to install fail2ban"

	# Create custom jail configuration
	cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
# Ban time (seconds)
bantime = 3600

# Find time (seconds)
findtime = 600

# Max retry attempts
maxretry = 3

# Email configuration
destemail = $FAIL2BAN_EMAIL
sender = fail2ban@$(hostname)
mta = sendmail
action = %(action_mwl)s

# Ignore local IPs
ignoreip = 127.0.0.1/8 ::1 10.0.0.0/8 192.168.0.0/16 172.16.0.0/12

[sshd]
enabled = true
port = $SSH_PORT
logpath = /var/log/auth.log
maxretry = 3
bantime = 7200

[sshd-ddos]
enabled = true
port = $SSH_PORT
logpath = /var/log/auth.log
maxretry = 6
bantime = 3600

[apache-auth]
enabled = false

[apache-badbots]
enabled = false

[apache-noscript]
enabled = false

[apache-overflows]
enabled = false

[nginx-http-auth]
enabled = false

[postfix]
enabled = false

[mysql]
enabled = false
EOF

	# Create custom filter for repeated connection attempts
	cat > /etc/fail2ban/filter.d/ssh-repeated.conf << 'EOF'
[Definition]
failregex = ^%(__prefix_line)s(?:error: PAM: )?[aA]uthentication (?:failure|error|failed) for .* from <HOST>( via \S+)?\s*$
            ^%(__prefix_line)s(?:error: )?Received disconnect from <HOST>: 3: .*: Auth fail$
            ^%(__prefix_line)sConnection closed by <HOST> \[preauth\]$
            ^%(__prefix_line)sDisconnected from <HOST> \[preauth\]$
ignoreregex =
EOF

	# Start and enable fail2ban
	systemctl enable fail2ban
	systemctl restart fail2ban

	log "Fail2Ban configured and started"
}

# Configure SSH hardening
harden_ssh() {
	log "Hardening SSH configuration..."

	# Additional SSH hardening
	cat >> /etc/ssh/sshd_config << EOF

# Additional Security Hardening
AllowUsers $ALLOWED_SSH_USERS
DenyUsers nobody
MaxStartups 2
LoginGraceTime 60
PermitUserEnvironment no
Compression no
TCPKeepAlive no
AllowTcpForwarding no
AllowStreamLocalForwarding no
GatewayPorts no
PermitTunnel no

# Disable weak algorithms
KexAlgorithms curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512,diffie-hellman-group14-sha256
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com,hmac-sha2-256,hmac-sha2-512
EOF

	# Test SSH configuration
	sshd -t || error_exit "SSH configuration is invalid after hardening"

	# Restart SSH
	systemctl restart ssh

	log "SSH hardening completed"
}

# Configure kernel security parameters
configure_kernel_security() {
	log "Configuring kernel security parameters..."

	cat > /etc/sysctl.d/99-security.conf << 'EOF'
# Security-related kernel parameters

# Network security
net.ipv4.ip_forward = 0
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
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
# Network stack hardening
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_rfc1337 = 1

# IPv6 security
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# Disable IPv6 if not needed
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1

# Memory protection
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.yama.ptrace_scope = 1
kernel.kexec_load_disabled = 1

# Process restrictions
fs.suid_dumpable = 0
kernel.core_uses_pid = 1

EOF

	# Apply sysctl settings
	sysctl --system || error_exit "Failed to apply security sysctl settings"

	log "Kernel security parameters configured"
}

# Set secure file permissions
secure_file_permissions() {
	log "Setting secure file permissions..."

	# Set permissions on critical files
	chmod 700 /root
	chmod 700 /home/*/.ssh 2> /dev/null || true
	chmod 600 /home/*/.ssh/authorized_keys 2> /dev/null || true
	chmod 600 /etc/ssh/sshd_config
	chmod 600 /etc/shadow
	chmod 600 /etc/gshadow
	chmod 644 /etc/passwd
	chmod 644 /etc/group
	chmod 600 /boot/grub/grub.cfg 2> /dev/null || true
	chmod 600 /boot/grub2/grub.cfg 2> /dev/null || true

	# Remove world-readable permissions from sensitive directories
	chmod o-rwx /etc/ssl/private/ 2> /dev/null || true
	chmod o-rwx /etc/ssh/ 2> /dev/null || true

	# Set sticky bit on tmp directories
	chmod +t /tmp
	chmod +t /var/tmp

	log "File permissions secured"
}

# Configure audit logging
setup_audit_logging() {
	log "Setting up audit logging..."

	apt-get install -y auditd audispd-plugins || error_exit "Failed to install audit packages"

	# Configure audit rules
	cat > /etc/audit/rules.d/audit.rules << 'EOF'
# Delete all previous rules
-D

# Set buffer size
-b 8192

# Set failure mode (0=silent, 1=printk, 2=panic)
-f 1

# Monitor authentication and authorization
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/security/opasswd -p wa -k identity

# Monitor login/logout events
-w /var/log/lastlog -p wa -k logins
-w /var/log/faillog -p wa -k logins

# Monitor network configuration
-w /etc/hosts -p wa -k network
-w /etc/network/ -p wa -k network

# Monitor SSH configuration
-w /etc/ssh/sshd_config -p wa -k sshd

# Monitor system calls
-a always,exit -F arch=b64 -S adjtimex -S settimeofday -S stime -k time-change
-a always,exit -F arch=b32 -S adjtimex -S settimeofday -S stime -k time-change
-a always,exit -F arch=b64 -S clock_settime -k time-change
-a always,exit -F arch=b32 -S clock_settime -k time-change

# Monitor file access
-a always,exit -F arch=b64 -S chmod -S fchmod -S fchmodat -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b32 -S chmod -S fchmod -S fchmodat -F auid>=1000 -F auid!=4294967295 -k perm_mod

# Lock the configuration
-e 2
EOF

	# Start and enable auditd
	systemctl enable auditd
	systemctl restart auditd

	log "Audit logging configured"
}

# Configure automatic security updates
setup_auto_updates() {
	log "Setting up automatic security updates..."

	apt-get install -y unattended-upgrades || error_exit "Failed to install unattended-upgrades"

	# Configure unattended upgrades
	cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};

Unattended-Upgrade::Package-Blacklist {
    // Add packages to blacklist here
};

Unattended-Upgrade::DevRelease "false";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Automatic-Reboot-WithUsers "false";
Unattended-Upgrade::Automatic-Reboot-Time "02:00";

Unattended-Upgrade::SyslogEnable "true";
Unattended-Upgrade::SyslogFacility "daemon";
EOF

	# Enable automatic updates
	echo 'APT::Periodic::Update-Package-Lists "1";' > /etc/apt/apt.conf.d/20auto-upgrades
	echo 'APT::Periodic::Download-Upgradeable-Packages "1";' >> /etc/apt/apt.conf.d/20auto-upgrades
	echo 'APT::Periodic::AutocleanInterval "7";' >> /etc/apt/apt.conf.d/20auto-upgrades
	echo 'APT::Periodic::Unattended-Upgrade "1";' >> /etc/apt/apt.conf.d/20auto-upgrades

	systemctl enable unattended-upgrades
	systemctl start unattended-upgrades

	log "Automatic security updates configured"
}

# Configure system banner
setup_banner() {
	log "Setting up system banner..."

	cat > /etc/issue << 'EOF'
***********************************************************************
*                                                                     *
*  UNAUTHORIZED ACCESS TO THIS DEVICE IS PROHIBITED                   *
*                                                                     *
*  This system is for authorized users only. All activities on       *
*  this system are monitored and logged. By continuing, you          *
*  acknowledge that you have no expectation of privacy and           *
*  consent to monitoring.                                             *
*                                                                     *
***********************************************************************

EOF

	cp /etc/issue /etc/issue.net

	# Configure SSH banner
	echo "Banner /etc/issue.net" >> /etc/ssh/sshd_config

	log "System banner configured"
}

# Create security report
create_security_report() {
	log "Creating security report..."

	local report_file="/etc/security-report.txt"

	cat > "$report_file" << EOF
# Security Hardening Report
Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Hostname: $(hostname)

## Hardening Applied:
- [x] Disabled unnecessary services
- [x] Removed unnecessary packages
- [x] Configured UFW firewall
- [x] Installed and configured Fail2Ban
- [x] Hardened SSH configuration
- [x] Applied kernel security parameters
- [x] Secured file permissions
- [x] Configured audit logging
- [x] Enabled automatic security updates
- [x] Set up system banner

## Configuration Details:
- SSH Port: $SSH_PORT
- Allowed SSH Users: $ALLOWED_SSH_USERS
- Fail2Ban Email: $FAIL2BAN_EMAIL
- UFW Status: $(ufw status | head -1)
- Fail2Ban Status: $(systemctl is-active fail2ban)
- Audit Status: $(systemctl is-active auditd)

## Next Steps:
1. Review and customize firewall rules for specific services
2. Configure log monitoring and alerting
3. Set up intrusion detection system (IDS)
4. Implement file integrity monitoring
5. Regular security audits and vulnerability scans
EOF

	chmod 600 "$report_file"

	log "Security report created at $report_file"
}

# Main function
main() {
	log "Starting security hardening..."

	check_root
	disable_services
	remove_packages
	configure_firewall
	setup_fail2ban
	harden_ssh
	configure_kernel_security
	secure_file_permissions
	setup_audit_logging
	setup_auto_updates
	setup_banner
	create_security_report

	log "Security hardening completed successfully!"
	log "Please review the security report at /etc/security-report.txt"
	log "System requires reboot to apply all kernel security settings"
}

# Execute main function
main "$@"
