#!/bin/bash
# Ubuntu User Management Script
# Essential user and SSH key management that runs on every Ubuntu VM
# Author: Infrastructure Bootstrap System
# Version: 1.0.0

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/ubuntu-user-management.log"

# Environment variables (can be overridden)
ADMIN_USER="${ADMIN_USER:-ubuntu}"
ADMIN_SSH_KEY="${ADMIN_SSH_KEY:-}"
DISABLE_ROOT_LOGIN="${DISABLE_ROOT_LOGIN:-true}"

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

# Create admin user if it doesn't exist
create_admin_user() {
	log "Setting up admin user: $ADMIN_USER"

	# Check if user already exists
	if id "$ADMIN_USER" &> /dev/null; then
		log "User $ADMIN_USER already exists, configuring..."
	else
		# Create user
		useradd -m -s /bin/bash "$ADMIN_USER" || error_exit "Failed to create user $ADMIN_USER"
		log "Created user: $ADMIN_USER"
	fi

	# Add user to sudo group
	usermod -aG sudo "$ADMIN_USER" || error_exit "Failed to add $ADMIN_USER to sudo group"

	# Configure sudo without password (for automation)
	cat > "/etc/sudoers.d/$ADMIN_USER" << EOF
# Allow $ADMIN_USER to run sudo without password
$ADMIN_USER ALL=(ALL) NOPASSWD:ALL
EOF

	chmod 440 "/etc/sudoers.d/$ADMIN_USER"

	log "Admin user $ADMIN_USER configured with sudo access"
}

# Setup SSH keys for admin user
setup_ssh_keys() {
	log "Setting up SSH keys for user: $ADMIN_USER"

	local user_home
	user_home=$(eval echo "~$ADMIN_USER")
	local ssh_dir="$user_home/.ssh"

	# Create .ssh directory
	mkdir -p "$ssh_dir"
	chmod 700 "$ssh_dir"
	chown "$ADMIN_USER:$ADMIN_USER" "$ssh_dir"

	# Setup authorized_keys file
	local auth_keys_file="$ssh_dir/authorized_keys"

	# Add provided SSH key if available
	if [[ -n "$ADMIN_SSH_KEY" ]]; then
		echo "$ADMIN_SSH_KEY" > "$auth_keys_file"
		log "Added provided SSH key to authorized_keys"
	else
		# Create empty authorized_keys file
		touch "$auth_keys_file"
		log_warn "No SSH key provided via ADMIN_SSH_KEY environment variable"
	fi

	# Set proper permissions
	chmod 600 "$auth_keys_file"
	chown "$ADMIN_USER:$ADMIN_USER" "$auth_keys_file"

	# Check for SSH keys in common locations
	local key_locations=(
		"/tmp/ssh-keys/authorized_keys"
		"/opt/ssh-keys/authorized_keys"
		"/root/.ssh/authorized_keys"
	)

	for key_file in "${key_locations[@]}"; do
		if [[ -f "$key_file" ]]; then
			log "Found SSH keys in $key_file, adding to authorized_keys"
			cat "$key_file" >> "$auth_keys_file"
			# Remove duplicates
			sort -u "$auth_keys_file" > "$auth_keys_file.tmp"
			mv "$auth_keys_file.tmp" "$auth_keys_file"
			chmod 600 "$auth_keys_file"
			chown "$ADMIN_USER:$ADMIN_USER" "$auth_keys_file"
		fi
	done

	log "SSH keys configured for user: $ADMIN_USER"
}

# Generate SSH key pair for the admin user (for outgoing connections)
generate_ssh_keypair() {
	log "Generating SSH key pair for user: $ADMIN_USER"

	local user_home
	user_home=$(eval echo "~$ADMIN_USER")
	local ssh_dir="$user_home/.ssh"
	local private_key="$ssh_dir/id_rsa"
	local public_key="$ssh_dir/id_rsa.pub"

	# Only generate if keys don't exist
	if [[ ! -f "$private_key" ]]; then
		sudo -u "$ADMIN_USER" ssh-keygen -t rsa -b 4096 -f "$private_key" -N "" -C "$ADMIN_USER@$(hostname)" || error_exit "Failed to generate SSH key pair"
		log "Generated SSH key pair for $ADMIN_USER"
	else
		log "SSH key pair already exists for $ADMIN_USER"
	fi

	# Set proper permissions
	chmod 600 "$private_key"
	chmod 644 "$public_key"
	chown "$ADMIN_USER:$ADMIN_USER" "$private_key" "$public_key"
}

# Configure SSH client settings
configure_ssh_client() {
	log "Configuring SSH client settings for user: $ADMIN_USER"

	local user_home
	user_home=$(eval echo "~$ADMIN_USER")
	local ssh_config="$user_home/.ssh/config"

	# Create SSH client config
	cat > "$ssh_config" << 'EOF'
# SSH client configuration for infrastructure automation
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    PasswordAuthentication no
    PubkeyAuthentication yes
    IdentitiesOnly yes
    LogLevel ERROR
    ServerAliveInterval 60
    ServerAliveCountMax 3
    ConnectTimeout 10
EOF

	chmod 600 "$ssh_config"
	chown "$ADMIN_USER:$ADMIN_USER" "$ssh_config"

	log "SSH client configuration completed"
}

# Create infrastructure service user
create_service_user() {
	log "Creating infrastructure service user"

	local service_user="infra-service"

	# Check if user already exists
	if id "$service_user" &> /dev/null; then
		log "Service user $service_user already exists"
	else
		# Create system user (no shell, no home directory for login)
		useradd -r -s /usr/sbin/nologin "$service_user" || error_exit "Failed to create service user $service_user"
		log "Created service user: $service_user"
	fi

	# Create service directories
	local service_dirs=(
		"/var/lib/infra-service"
		"/var/log/infra-service"
		"/etc/infra-service"
	)

	for dir in "${service_dirs[@]}"; do
		mkdir -p "$dir"
		chown "$service_user:$service_user" "$dir"
		chmod 755 "$dir"
	done

	log "Service user infrastructure created"
}

# Lock down root account
lockdown_root() {
	if [[ "$DISABLE_ROOT_LOGIN" == "true" ]]; then
		log "Locking down root account"

		# Disable root password login
		passwd -l root 2> /dev/null || log_warn "Could not lock root password"

		# Remove root's authorized_keys if it exists
		if [[ -f /root/.ssh/authorized_keys ]]; then
			mv /root/.ssh/authorized_keys /root/.ssh/authorized_keys.disabled.$(date +%Y%m%d_%H%M%S)
			log "Disabled root SSH key authentication"
		fi

		log "Root account locked down"
	else
		log "Root account lockdown disabled via DISABLE_ROOT_LOGIN=false"
	fi
}

# Set password policies
configure_password_policies() {
	log "Configuring password policies"

	# Install libpam-pwquality if not present
	apt-get update
	apt-get install -y libpam-pwquality || log_warn "Failed to install libpam-pwquality"

	# Configure password quality requirements
	cat > /etc/security/pwquality.conf << 'EOF'
# Infrastructure bootstrap password policy
minlen = 12
dcredit = -1
ucredit = -1
lcredit = -1
ocredit = -1
minclass = 3
maxrepeat = 2
maxclasrepeat = 2
EOF

	# Configure account lockout policy
	cat > /etc/pam.d/common-auth << 'EOF'
# Infrastructure bootstrap PAM authentication configuration
auth    [success=1 default=ignore]      pam_unix.so nullok_secure
auth    requisite                       pam_deny.so
auth    required                        pam_permit.so
auth    optional                        pam_cap.so 
auth    required                        pam_faillock.so preauth silent audit deny=3 unlock_time=600
auth    [default=die]                   pam_faillock.so authfail audit deny=3 unlock_time=600
EOF

	log "Password policies configured"
}

# Main execution function
main() {
	log "Starting Ubuntu user management setup..."

	check_root
	create_admin_user
	setup_ssh_keys
	generate_ssh_keypair
	configure_ssh_client
	create_service_user
	lockdown_root
	configure_password_policies

	log "Ubuntu user management setup completed successfully!"

	# Create completion marker
	echo "$(date)" > /var/log/ubuntu-user-management.completed

	# Display important information
	log "========================================"
	log "IMPORTANT SETUP INFORMATION:"
	log "Admin user: $ADMIN_USER"
	log "Admin user has sudo access without password"
	log "SSH key authentication configured"
	if [[ "$DISABLE_ROOT_LOGIN" == "true" ]]; then
		log "Root login has been disabled"
	fi
	log "Service user 'infra-service' created for system processes"
	log "========================================"
}

# Run main function
main "$@"
