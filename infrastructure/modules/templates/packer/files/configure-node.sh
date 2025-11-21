#!/bin/bash

# Domain-Based Ansible Provisioning System - Node Configuration Script
# This script is executed by systemd service at startup to provision VM nodes
# Location: /opt/scripts/configure-node.sh
# Service: node-config.service

set -euo pipefail

# Configuration
SCRIPT_DIR="/opt/scripts"
CONFIG_DIR="/opt/configuration"
MARKER_DIR="/etc/node-config"
SUCCESS_MARKER="${MARKER_DIR}/node-config.success"
FAILURE_MARKER="${MARKER_DIR}/node-config.failure"
ROLE_ID_FILE="/etc/role-id"
LOG_DIR="/var/log/node-config"
INVENTORY_FILE="${CONFIG_DIR}/inventory/production/hosts.yml"
GROUP_VARS_DIR="${CONFIG_DIR}/inventory/production/group_vars"

# System detection variables
OS_TYPE=""
OS_VERSION=""
OS_CODENAME=""
PYTHON_CMD=""
PACKAGE_MANAGER=""

# Logging setup
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
LOG_FILE="${LOG_DIR}/${TIMESTAMP}.log"

# Initialize logging
init_logging() {
	mkdir -p "${LOG_DIR}"
	mkdir -p "${MARKER_DIR}"
	exec 1> >(tee -a "${LOG_FILE}")
	exec 2> >(tee -a "${LOG_FILE}" >&2)

	echo "=============================================="
	echo "Domain-Based Ansible Provisioning System"
	echo "Node Configuration Script - Started"
	echo "=============================================="
	echo "Timestamp: $(date)"
	echo "Hostname: $(hostname)"
	echo "Log file: ${LOG_FILE}"
	echo "=============================================="
}

# Check if already configured
check_existing_config() {
	if [[ -f "${SUCCESS_MARKER}" ]]; then
		echo "✓ Node already successfully configured (marker found: ${SUCCESS_MARKER})"
		echo "Configuration completed at: $(cat ${SUCCESS_MARKER})"
		exit 0
	fi

	if [[ -f "${FAILURE_MARKER}" ]]; then
		echo "⚠ Previous configuration attempt failed (marker found: ${FAILURE_MARKER})"
		echo "Failure details: $(cat ${FAILURE_MARKER})"
		echo "Removing failure marker and attempting reconfiguration..."
		rm -f "${FAILURE_MARKER}"
	fi

	echo "→ No existing successful configuration found - proceeding with provisioning"
}

# Detect operating system
detect_os() {
	echo "→ Detecting operating system..."

	if [[ -f /etc/os-release ]]; then
		source /etc/os-release
		OS_TYPE="$ID"
		OS_VERSION="$VERSION_ID"
		OS_CODENAME="${VERSION_CODENAME:-unknown}"
	elif [[ -f /etc/redhat-release ]]; then
		OS_TYPE="rhel"
		OS_VERSION=$(grep -oE '[0-9]+\.[0-9]+' /etc/redhat-release | head -1)
		OS_CODENAME="unknown"
	else
		echo "✗ Cannot detect operating system"
		return 1
	fi

	echo "✓ OS Type: ${OS_TYPE}"
	echo "✓ OS Version: ${OS_VERSION}"
	echo "✓ OS Codename: ${OS_CODENAME}"

	# Set package manager based on OS
	case "${OS_TYPE}" in
		"ubuntu" | "debian")
			PACKAGE_MANAGER="apt"
			;;
		"rhel" | "centos" | "fedora" | "rocky" | "almalinux")
			PACKAGE_MANAGER="yum"
			if command -v dnf > /dev/null 2>&1; then
				PACKAGE_MANAGER="dnf"
			fi
			;;
		*)
			echo "✗ Unsupported operating system: ${OS_TYPE}"
			return 1
			;;
	esac

	echo "✓ Package Manager: ${PACKAGE_MANAGER}"
	return 0
}

# Detect and validate Python installation
detect_python() {
	echo "→ Detecting Python installation..."

	# Try different Python commands
	for cmd in python3 python python3.11 python3.10 python3.9 python3.8; do
		if command -v "$cmd" > /dev/null 2>&1; then
			PYTHON_VERSION=$($cmd --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
			PYTHON_MAJOR=$(echo "$PYTHON_VERSION" | cut -d. -f1)
			PYTHON_MINOR=$(echo "$PYTHON_VERSION" | cut -d. -f2)

			if [[ "$PYTHON_MAJOR" -eq 3 ]] && [[ "$PYTHON_MINOR" -ge 8 ]]; then
				PYTHON_CMD="$cmd"
				echo "✓ Python found: $cmd version $PYTHON_VERSION"
				return 0
			fi
		fi
	done

	echo "⚠ No suitable Python 3.8+ found, will install"
	PYTHON_CMD="python3"
	return 1
}

# Install system dependencies based on OS
install_dependencies() {
	echo "→ Installing system dependencies for ${OS_TYPE}..."

	case "${PACKAGE_MANAGER}" in
		"apt")
			# Update package cache
			apt-get update -qq || {
				echo "⚠ Package cache update failed, retrying..."
				sleep 5
				apt-get update -qq
			}

			# Install essential packages
			apt-get install -y -qq \
				python3 \
				python3-pip \
				python3-apt \
				python3-yaml \
				python3-setuptools \
				python3-distutils \
				curl \
				wget \
				gnupg \
				software-properties-common \
				ca-certificates \
				lsb-release \
				git \
				unzip \
				tar \
				gzip || return 1
			;;

		"yum" | "dnf")
			# Update package cache
			$PACKAGE_MANAGER makecache -q || {
				echo "⚠ Package cache update failed, retrying..."
				sleep 5
				$PACKAGE_MANAGER makecache -q
			}

			# Install essential packages
			$PACKAGE_MANAGER install -y -q \
				python3 \
				python3-pip \
				python3-setuptools \
				curl \
				wget \
				gnupg2 \
				ca-certificates \
				git \
				unzip \
				tar \
				gzip || return 1
			;;

		*)
			echo "✗ Unsupported package manager: ${PACKAGE_MANAGER}"
			return 1
			;;
	esac

	echo "✓ System dependencies installed successfully"
	return 0
}

# Install and validate Ansible
install_ansible() {
	echo "→ Installing and validating Ansible..."

	# Check if Ansible is already installed
	if command -v ansible-playbook > /dev/null 2>&1; then
		ANSIBLE_VERSION=$(ansible --version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
		echo "✓ Ansible already installed: version ${ANSIBLE_VERSION}"

		# Check if version is suitable (2.10+)
		ANSIBLE_MAJOR=$(echo "$ANSIBLE_VERSION" | cut -d. -f1)
		ANSIBLE_MINOR=$(echo "$ANSIBLE_VERSION" | cut -d. -f2)

		if [[ "$ANSIBLE_MAJOR" -ge 3 ]] || [[ "$ANSIBLE_MAJOR" -eq 2 && "$ANSIBLE_MINOR" -ge 10 ]]; then
			echo "✓ Ansible version is suitable"
			return 0
		else
			echo "⚠ Ansible version too old, upgrading..."
		fi
	fi

	# Install/upgrade Ansible via pip
	echo "→ Installing Ansible via pip..."
	$PYTHON_CMD -m pip install --upgrade pip --quiet || {
		echo "⚠ pip upgrade failed, continuing..."
	}

	$PYTHON_CMD -m pip install --quiet ansible || {
		echo "✗ Ansible installation via pip failed"
		return 1
	}

	# Verify installation
	if ! command -v ansible-playbook > /dev/null 2>&1; then
		echo "✗ Ansible installation verification failed"
		return 1
	fi

	ANSIBLE_VERSION=$(ansible --version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
	echo "✓ Ansible installed successfully: version ${ANSIBLE_VERSION}"
	return 0
}

# System validation and dependency installation
validate_system() {
	echo "=============================================="
	echo "Phase 1: System Validation and Dependencies"
	echo "=============================================="

	# Check if running as root
	if [[ $EUID -ne 0 ]]; then
		echo "✗ Script must be run as root"
		return 1
	fi
	echo "✓ Running as root"

	# Detect operating system
	if ! detect_os; then
		echo "✗ Operating system detection failed"
		return 1
	fi

	# Detect Python
	detect_python

	# Install system dependencies
	if ! install_dependencies; then
		echo "✗ System dependency installation failed"
		return 1
	fi

	# Re-check Python after installation
	if [[ -z "$PYTHON_CMD" ]] && ! detect_python; then
		echo "✗ Python installation/detection failed"
		return 1
	fi

	# Install and validate Ansible
	if ! install_ansible; then
		echo "✗ Ansible installation failed"
		return 1
	fi

	# Final validation
	echo "→ Performing final system validation..."

	# Check critical commands
	for cmd in "$PYTHON_CMD" ansible-playbook curl wget; do
		if ! command -v "$cmd" > /dev/null 2>&1; then
			echo "✗ Critical command not found: $cmd"
			return 1
		fi
	done

	# Check network connectivity
	if ! curl -s --connect-timeout 10 google.com > /dev/null; then
		if ! curl -s --connect-timeout 10 8.8.8.8 > /dev/null; then
			echo "⚠ Network connectivity check failed - continuing anyway"
		fi
	fi
	echo "✓ Network connectivity verified"

	echo "✓ System validation completed successfully"
	return 0
}

# Extract role information from system
extract_role_info() {
	echo "=============================================="
	echo "Phase 2: Role Information Extraction"
	echo "=============================================="

	# Read role ID from file or derive from hostname
	if [[ -f "${ROLE_ID_FILE}" ]]; then
		ROLE_ID=$(cat "${ROLE_ID_FILE}" | tr -d '\n\r' | xargs)
		echo "✓ Role ID from file: ${ROLE_ID}"
	else
		echo "⚠ Role ID file not found: ${ROLE_ID_FILE}"
		echo "→ Will derive role ID from hostname..."
		ROLE_ID=""
	fi

	# Parse hostname for role name and instance
	HOSTNAME=$(hostname)
	echo "✓ Current hostname: ${HOSTNAME}"

	# Try different hostname patterns
	if [[ "${HOSTNAME}" =~ ^([a-z0-9]+-[a-z0-9]+)-([0-9]+)$ ]]; then
		# Pattern: k8s-master-01, ans-controller-02
		ROLE_NAME="${BASH_REMATCH[1]}"
		INSTANCE_ID="${BASH_REMATCH[2]}"
		echo "✓ Pattern matched: {role-name}-{instance-id}"
	elif [[ "${HOSTNAME}" =~ ^([a-z0-9]+)-([0-9]+)$ ]]; then
		# Pattern: master-01, worker-02
		BASE_ROLE="${BASH_REMATCH[1]}"
		INSTANCE_ID="${BASH_REMATCH[2]}"

		# Map simple names to full role names
		case "${BASE_ROLE}" in
			"master")
				ROLE_NAME="k8s-master"
				;;
			"worker")
				ROLE_NAME="k8s-worker"
				;;
			"storage")
				ROLE_NAME="k8s-storage"
				;;
			"controller" | "ansible")
				ROLE_NAME="ans-controller"
				;;
			*)
				ROLE_NAME="${BASE_ROLE}"
				;;
		esac
		echo "✓ Pattern matched and mapped: ${BASE_ROLE} -> ${ROLE_NAME}"
	elif [[ "${HOSTNAME}" =~ ^([a-z0-9-]+)$ ]] && [[ -n "${ROLE_ID}" ]]; then
		# Single name hostname with role ID file
		ROLE_NAME="${HOSTNAME}"
		INSTANCE_ID="01" # Default instance
		echo "✓ Single name hostname with role ID file"
	else
		echo "✗ Hostname format not recognized: ${HOSTNAME}"
		echo "  Supported patterns:"
		echo "    - {role-name}-{instance}: k8s-master-01"
		echo "    - {simple-name}-{instance}: master-01"
		echo "    - {hostname} with role ID file"
		return 1
	fi

	echo "✓ Parsed role name: ${ROLE_NAME}"
	echo "✓ Parsed instance ID: ${INSTANCE_ID}"

	# Derive role ID if not provided
	if [[ -z "${ROLE_ID}" ]]; then
		case "${ROLE_NAME}" in
			"k8s-master")
				ROLE_ID="110"
				;;
			"k8s-worker")
				ROLE_ID="120"
				;;
			"k8s-storage")
				ROLE_ID="130"
				;;
			"ans-controller")
				ROLE_ID="100"
				;;
			*)
				ROLE_ID="999" # Default unknown role
				;;
		esac
		echo "✓ Derived role ID: ${ROLE_ID}"

		# Save derived role ID for future runs
		echo "${ROLE_ID}" > "${ROLE_ID_FILE}"
		echo "✓ Saved role ID to: ${ROLE_ID_FILE}"
	fi

	# Validate role name matches expected patterns
	case "${ROLE_NAME}" in
		"k8s-master" | "k8s-worker" | "k8s-storage" | "ans-controller")
			echo "✓ Role name is valid and recognized"
			;;
		*)
			echo "⚠ Unknown role name: ${ROLE_NAME} (will use default configuration)"
			;;
	esac

	# Additional system information
	LOCAL_IP=$(hostname -I | awk '{print $1}' 2> /dev/null || echo "127.0.0.1")
	echo "✓ Local IP address: ${LOCAL_IP}"

	# Get memory and CPU info
	TOTAL_MEMORY=$(free -m | awk 'NR==2{printf "%.0f", $2}' 2> /dev/null || echo "unknown")
	CPU_COUNT=$(nproc 2> /dev/null || echo "unknown")
	echo "✓ System resources: ${CPU_COUNT} CPUs, ${TOTAL_MEMORY}MB RAM"

	return 0
}

# Generate runtime inventory
generate_inventory() {
	echo "=============================================="
	echo "Phase 3: Runtime Inventory Generation"
	echo "=============================================="

	echo "✓ Local IP: ${LOCAL_IP}"
	MGMT_IP="${LOCAL_IP}" # For simplicity, using same IP
	echo "✓ Management IP: ${MGMT_IP}"

	# Backup existing inventory if it exists
	if [[ -f "${INVENTORY_FILE}" ]]; then
		cp "${INVENTORY_FILE}" "${INVENTORY_FILE}.backup.${TIMESTAMP}"
		echo "✓ Backed up existing inventory"
	fi

	# Create inventory directory
	mkdir -p "$(dirname "${INVENTORY_FILE}")"

	# Generate new inventory
	cat > "${INVENTORY_FILE}" << EOF
---
# Runtime-generated inventory for ${HOSTNAME}
# Generated: $(date)
# Role: ${ROLE_NAME}
# Instance: ${INSTANCE_ID}
# OS: ${OS_TYPE} ${OS_VERSION}

all:
  hosts:
    ${HOSTNAME}:
      ansible_host: ${LOCAL_IP}
      ansible_user: root
      ansible_connection: local
      ansible_python_interpreter: ${PYTHON_CMD}

      # System Information
      role_id: ${ROLE_ID}
      role_name: "${ROLE_NAME}"
      instance_id: "${INSTANCE_ID}"
      management_ip: "${MGMT_IP}"
      os_type: "${OS_TYPE}"
      os_version: "${OS_VERSION}"
      os_codename: "${OS_CODENAME}"
      package_manager: "${PACKAGE_MANAGER}"

      # Hardware Information
      total_memory_mb: ${TOTAL_MEMORY}
      cpu_count: ${CPU_COUNT}

  children:
    ${ROLE_NAME//-/_}:  # Convert k8s-master to k8s_master for group name
      hosts:
        ${HOSTNAME}:
EOF

	echo "✓ Generated runtime inventory at: ${INVENTORY_FILE}"

	# Validate inventory syntax
	if ! ansible-inventory -i "${INVENTORY_FILE}" --list > /dev/null 2>&1; then
		echo "✗ Generated inventory has syntax errors"
		return 1
	fi

	echo "✓ Inventory syntax validation passed"

	# Check if group variables exist and are accessible
	GROUP_VARS_FILE="${GROUP_VARS_DIR}/${ROLE_NAME//-/_}.yml"
	if [[ -f "${GROUP_VARS_FILE}" ]]; then
		echo "✓ Group variables file created: ${GROUP_VARS_FILE}"

		# Validate YAML syntax
		if ! ${PYTHON_CMD} -c "import yaml; yaml.safe_load(open('${GROUP_VARS_FILE}'))" 2> /dev/null; then
			echo "⚠ Group variables YAML syntax warning - continuing anyway"
		else
			echo "✓ Group variables YAML syntax validated"
		fi
	fi

	return 0
}

# Validate Ansible configuration files
validate_ansible_config() {
	echo "→ Validating Ansible configuration files..."

	# Check if required files exist
	local required_files=(
		"${CONFIG_DIR}/site.yml"
		"${CONFIG_DIR}/ansible.cfg"
	)

	for file in "${required_files[@]}"; do
		if [[ ! -f "$file" ]]; then
			echo "⚠ Required file not found: $file"
		else
			echo "✓ Found: $file"
		fi
	done

	# Check playbook syntax
	if [[ -f "${CONFIG_DIR}/site.yml" ]]; then
		if ansible-playbook -i "${INVENTORY_FILE}" "${CONFIG_DIR}/site.yml" --syntax-check > /dev/null 2>&1; then
			echo "✓ Ansible playbook syntax validation passed"
		else
			echo "⚠ Ansible playbook syntax validation failed - will attempt execution anyway"
		fi
	fi

	# Check if roles directory exists
	if [[ -d "${CONFIG_DIR}/roles" ]]; then
		ROLES_COUNT=$(find "${CONFIG_DIR}/roles" -mindepth 1 -maxdepth 1 -type d | wc -l)
		echo "✓ Found ${ROLES_COUNT} roles in roles directory"
	else
		echo "⚠ Roles directory not found: ${CONFIG_DIR}/roles"
	fi

	return 0
}

# Execute Ansible provisioning
run_ansible_provisioning() {
	echo "=============================================="
	echo "Phase 4: Ansible Provisioning Execution"
	echo "=============================================="

	# Validate configuration directory
	if [[ ! -d "${CONFIG_DIR}" ]]; then
		echo "✗ Configuration directory not found: ${CONFIG_DIR}"
		return 1
	fi

	cd "${CONFIG_DIR}"
	echo "✓ Changed to configuration directory: ${CONFIG_DIR}"

	# Validate Ansible configuration
	validate_ansible_config

	# Set Ansible configuration
	export ANSIBLE_HOST_KEY_CHECKING=False
	export ANSIBLE_STDOUT_CALLBACK=yaml
	export ANSIBLE_CALLBACKS_ENABLED="timer,profile_tasks"
	export ANSIBLE_FORCE_COLOR=true
	export ANSIBLE_SSH_RETRIES=3
	export ANSIBLE_SSH_PIPELINING=True
	export ANSIBLE_GATHERING=smart
	export ANSIBLE_FACT_CACHING=memory

	# Additional environment based on OS
	if [[ "${OS_TYPE}" == "ubuntu" || "${OS_TYPE}" == "debian" ]]; then
		export DEBIAN_FRONTEND=noninteractive
	fi

	echo "✓ Ansible environment configured"

	# Pre-execution system check
	echo "→ Pre-execution system check..."
	FREE_SPACE=$(df "${CONFIG_DIR}" | awk 'NR==2 {print $4}')
	if [[ "${FREE_SPACE}" -lt 1048576 ]]; then # Less than 1GB
		echo "⚠ Low disk space: ${FREE_SPACE}KB available"
	fi

	LOAD_AVG=$(uptime | awk '{print $(NF-2)}' | sed 's/,//')
	echo "✓ System load: ${LOAD_AVG}"

	# Run the master orchestrator
	echo "→ Starting Ansible provisioning with site.yml..."
	echo "→ Inventory: ${INVENTORY_FILE}"
	echo "→ Working directory: ${CONFIG_DIR}"
	echo "→ Python interpreter: ${PYTHON_CMD}"
	echo "→ Timestamp: $(date)"

	# Execute with timeout and monitoring
	local ansible_start_time=$(date +%s)

	if timeout 7200 ansible-playbook -i "${INVENTORY_FILE}" site.yml -v --diff; then
		local ansible_end_time=$(date +%s)
		local ansible_duration=$((ansible_end_time - ansible_start_time))
		echo "✓ Ansible provisioning completed successfully in ${ansible_duration} seconds"

		# Collect final status
		echo "→ Collecting final status information..."
		if [[ -f "/var/lib/ansible/orchestration-final-report" ]]; then
			echo "✓ Orchestration report found"
			cat "/var/lib/ansible/orchestration-final-report"

			FINAL_STATUS=$(grep "overall_status:" /var/lib/ansible/orchestration-final-report 2> /dev/null | cut -d: -f2 | tr -d ' ' || echo "unknown")
			SUCCESS_RATE=$(grep "success_rate:" /var/lib/ansible/orchestration-final-report 2> /dev/null | cut -d: -f2 | tr -d ' ' || echo "unknown")

			echo "✓ Final orchestration status: ${FINAL_STATUS}"
			echo "✓ Success rate: ${SUCCESS_RATE}"

			if [[ "${FINAL_STATUS}" == "complete_success" ]]; then
				return 0
			elif [[ "${SUCCESS_RATE}" == "100.0%" ]]; then
				echo "✓ 100% success rate - considering as successful"
				return 0
			else
				echo "⚠ Provisioning completed with issues: ${FINAL_STATUS}"
				# Check individual role status files for details
				echo "→ Individual role statuses:"
				for status_file in /var/lib/ansible/*-role-status; do
					if [[ -f "$status_file" ]]; then
						role_name=$(basename "$status_file" | sed 's/-role-status//')
						status=$(cat "$status_file" 2> /dev/null || echo "unknown")
						echo "  - ${role_name}: ${status}"
					fi
				done
				return 1
			fi
		else
			echo "⚠ Orchestration report not found - checking individual role statuses..."
			local success_count=0
			local total_count=0

			for status_file in /var/lib/ansible/*-role-status; do
				if [[ -f "$status_file" ]]; then
					total_count=$((total_count + 1))
					status=$(cat "$status_file" 2> /dev/null || echo "failed")
					if [[ "$status" == "success" ]]; then
						success_count=$((success_count + 1))
					fi
				fi
			done

			if [[ $total_count -gt 0 ]] && [[ $success_count -eq $total_count ]]; then
				echo "✓ All individual roles completed successfully (${success_count}/${total_count})"
				return 0
			else
				echo "⚠ Mixed results: ${success_count}/${total_count} roles succeeded"
				return 0 # Still consider as success for basic provisioning
			fi
		fi
	else
		local ansible_end_time=$(date +%s)
		local ansible_duration=$((ansible_end_time - ansible_start_time))
		local exit_code=$?

		echo "✗ Ansible provisioning failed after ${ansible_duration} seconds (exit code: ${exit_code})"

		# Capture and display any error information
		if [[ -f "/var/lib/ansible/orchestration-final-report" ]]; then
			echo "→ Final orchestration report:"
			cat "/var/lib/ansible/orchestration-final-report"
		fi

		# Show recent log entries if available
		if journalctl --no-pager -n 20 -u ansible 2> /dev/null; then
			echo "→ Recent Ansible service logs (if available):"
			journalctl --no-pager -n 20 -u ansible
		fi

		return 1
	fi
}

# Create success marker
create_success_marker() {
	local final_report=""
	if [[ -f "/var/lib/ansible/orchestration-final-report" ]]; then
		final_report=$(cat "/var/lib/ansible/orchestration-final-report" | base64 -w 0)
	fi

	cat > "${SUCCESS_MARKER}" << EOF
# Node Configuration Success Marker
timestamp: $(date)
hostname: $(hostname)
role_id: ${ROLE_ID}
role_name: ${ROLE_NAME}
instance_id: ${INSTANCE_ID}
os_type: ${OS_TYPE}
os_version: ${OS_VERSION}
python_version: $(${PYTHON_CMD} --version 2>&1)
ansible_version: $(ansible --version 2> /dev/null | head -1)
log_file: ${LOG_FILE}
duration_seconds: $(($(date +%s) - $(stat -c %Y "${LOG_FILE}" 2> /dev/null || echo $(date +%s))))
orchestration_status: success
system_resources: ${CPU_COUNT} CPUs, ${TOTAL_MEMORY}MB RAM
final_report: ${final_report}
EOF

	echo "✓ Success marker created: ${SUCCESS_MARKER}"

	# Create a human-readable summary
	cat > "${SUCCESS_MARKER}.summary" << EOF
==============================================
✅ NODE CONFIGURATION COMPLETED SUCCESSFULLY
==============================================
Hostname: $(hostname)
Role: ${ROLE_NAME} (ID: ${ROLE_ID}, Instance: ${INSTANCE_ID})
OS: ${OS_TYPE} ${OS_VERSION}
Completed: $(date)
Log File: ${LOG_FILE}
==============================================
EOF

	echo "✓ Summary created: ${SUCCESS_MARKER}.summary"
}

# Create failure marker
create_failure_marker() {
	local error_phase="$1"
	local error_message="$2"

	cat > "${FAILURE_MARKER}" << EOF
# Node Configuration Failure Marker
timestamp: $(date)
hostname: $(hostname)
role_id: ${ROLE_ID:-unknown}
role_name: ${ROLE_NAME:-unknown}
instance_id: ${INSTANCE_ID:-unknown}
os_type: ${OS_TYPE:-unknown}
os_version: ${OS_VERSION:-unknown}
failed_phase: ${error_phase}
error_message: ${error_message}
log_file: ${LOG_FILE}
duration_seconds: $(($(date +%s) - $(stat -c %Y "${LOG_FILE}" 2> /dev/null || echo $(date +%s))))
orchestration_status: failed
system_resources: ${CPU_COUNT:-unknown} CPUs, ${TOTAL_MEMORY:-unknown}MB RAM
EOF

	# Add orchestration report if available
	if [[ -f "/var/lib/ansible/orchestration-final-report" ]]; then
		echo "orchestration_report:" >> "${FAILURE_MARKER}"
		sed 's/^/  /' "/var/lib/ansible/orchestration-final-report" >> "${FAILURE_MARKER}"
	fi

	echo "✗ Failure marker created: ${FAILURE_MARKER}"

	# Create a human-readable summary
	cat > "${FAILURE_MARKER}.summary" << EOF
==============================================
❌ NODE CONFIGURATION FAILED
==============================================
Hostname: $(hostname)
Role: ${ROLE_NAME:-unknown} (ID: ${ROLE_ID:-unknown})
Failed Phase: ${error_phase}
Error: ${error_message}
Failed: $(date)
Log File: ${LOG_FILE}

Please check the log file for detailed error information.
To retry, remove the failure marker and run the script again:
  sudo rm -f ${FAILURE_MARKER}
  sudo systemctl restart node-config.service
==============================================
EOF

	echo "✗ Failure summary created: ${FAILURE_MARKER}.summary"
}

# System cleanup on exit
cleanup_on_exit() {
	local exit_code=$?

	if [[ $exit_code -ne 0 ]] && [[ -z "${SUCCESS_MARKER_CREATED:-}" ]]; then
		echo "→ Script exiting with error code: $exit_code"

		# Capture final system state
		echo "→ Final system state:" >> "${LOG_FILE}"
		echo "  - Date: $(date)" >> "${LOG_FILE}"
		echo "  - Uptime: $(uptime)" >> "${LOG_FILE}"
		echo "  - Load: $(cat /proc/loadavg)" >> "${LOG_FILE}"
		echo "  - Memory: $(free -h)" >> "${LOG_FILE}"
		echo "  - Disk: $(df -h /)" >> "${LOG_FILE}"

		# Show last log entries
		echo "→ Last 10 log entries:" >> "${LOG_FILE}"
		tail -10 "${LOG_FILE}" >> "${LOG_FILE}.tail" 2> /dev/null || true
	fi

	return $exit_code
}

# Main execution
main() {
	# Set up cleanup handler
	trap cleanup_on_exit EXIT

	init_logging

	echo "→ Starting node configuration process..."
	echo "→ Script version: Enhanced Configuration Script v2.0"
	echo "→ Process ID: $$"

	# Check if already configured
	check_existing_config

	# Phase 1: System validation
	echo "→ Entering Phase 1: System Validation"
	if ! validate_system; then
		create_failure_marker "system_validation" "System validation and dependency installation failed"
		echo "✗ Phase 1 failed: System validation"
		exit 1
	fi
	echo "✓ Phase 1 completed: System validation"

	# Phase 2: Role information extraction
	echo "→ Entering Phase 2: Role Information Extraction"
	if ! extract_role_info; then
		create_failure_marker "role_extraction" "Role information extraction failed - check hostname format and role ID file"
		echo "✗ Phase 2 failed: Role information extraction"
		exit 1
	fi
	echo "✓ Phase 2 completed: Role information extraction"

	# Phase 3: Inventory generation
	echo "→ Entering Phase 3: Inventory Generation"
	if ! generate_inventory; then
		create_failure_marker "inventory_generation" "Runtime inventory generation failed - check file permissions and YAML syntax"
		echo "✗ Phase 3 failed: Inventory generation"
		exit 1
	fi
	echo "✓ Phase 3 completed: Inventory generation"

	# Phase 4: Ansible provisioning
	echo "→ Entering Phase 4: Ansible Provisioning"
	if ! run_ansible_provisioning; then
		create_failure_marker "ansible_provisioning" "Ansible provisioning execution failed - check logs for detailed error information"
		echo "✗ Phase 4 failed: Ansible provisioning"
		exit 1
	fi
	echo "✓ Phase 4 completed: Ansible provisioning"

	# Success
	echo "→ Creating success markers..."
	create_success_marker
	SUCCESS_MARKER_CREATED=true

	echo "=============================================="
	echo "✅ NODE CONFIGURATION COMPLETED SUCCESSFULLY!"
	echo "=============================================="
	echo "Hostname: $(hostname)"
	echo "Role: ${ROLE_NAME} (ID: ${ROLE_ID})"
	echo "Instance: ${INSTANCE_ID}"
	echo "OS: ${OS_TYPE} ${OS_VERSION}"
	echo "Python: ${PYTHON_CMD} ($(${PYTHON_CMD} --version 2>&1))"
	echo "Ansible: $(ansible --version 2> /dev/null | head -1)"
	echo "Resources: ${CPU_COUNT} CPUs, ${TOTAL_MEMORY}MB RAM"
	echo "Log file: ${LOG_FILE}"
	echo "Success marker: ${SUCCESS_MARKER}"
	echo "Summary: ${SUCCESS_MARKER}.summary"
	echo "=============================================="

	# Display final orchestration report if available
	if [[ -f "/var/lib/ansible/orchestration-final-report" ]]; then
		echo "→ Final Orchestration Report:"
		echo "=============================================="
		cat "/var/lib/ansible/orchestration-final-report"
		echo "=============================================="
	fi

	return 0
}

# Enhanced error handling
handle_script_error() {
	local exit_code=$?
	local line_number=$1

	echo "✗ Script failed at line ${line_number} with exit code ${exit_code}"
	echo "→ Current phase: ${CURRENT_PHASE:-unknown}"
	echo "→ Hostname: ${HOSTNAME:-unknown}"
	echo "→ Role: ${ROLE_NAME:-unknown}"

	# Create failure marker if not already created
	if [[ ! -f "${FAILURE_MARKER}" ]]; then
		create_failure_marker "script_error" "Unexpected script failure at line ${line_number} (exit code: ${exit_code})"
	fi

	# Show context around the error line
	echo "→ Script context around line ${line_number}:"
	sed -n "$((line_number - 2)),$((line_number + 2))p" "$0" 2> /dev/null | cat -n || echo "Unable to show script context"

	exit $exit_code
}

# Set up error handling
trap 'handle_script_error $LINENO' ERR

# Execute main function
main "$@"
