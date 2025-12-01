# VM Testing Guide - Domain-Based Ansible Provisioning System

## Overview

This guide provides instructions for testing the Domain-Based Ansible Provisioning System on fresh Ubuntu VMs using the automated configuration system.

## Required Files

Before testing, ensure you have these three files ready:

1. **configure-node.sh** - Main provisioning script
2. **node-config.service** - Systemd service for automatic execution
3. **Full provisioning directory** - Complete ansible configuration

## VM Preparation Steps

### 1. Create Fresh Ubuntu VM

- Use Ubuntu 22.04 or 24.04 LTS
- Minimum 2GB RAM, 20GB disk
- Network connectivity required
- Root access or sudo privileges

### 2. Set Hostname

Set the VM hostname to match the expected pattern: `{role-name}-{instance-id}`

```bash
# Examples:
sudo hostnamectl set-hostname k8s-master-01
sudo hostnamectl set-hostname k8s-worker-02
sudo hostnamectl set-hostname ans-controller-01
```

### 3. Create Role ID File

Create the role ID file that the script expects:

```bash
# Create role ID file (choose appropriate role)
echo "k8s-master" | sudo tee /etc/role-id
# OR echo "k8s-worker" | sudo tee /etc/role-id
# OR echo "k8s-storage" | sudo tee /etc/role-id
# OR echo "ans-controller" | sudo tee /etc/role-id
```

### 4. Copy Files to VM

Copy the required files to their designated locations:

```bash
# Create directories
sudo mkdir -p /opt/scripts
sudo mkdir -p /opt/configuration
sudo mkdir -p /etc/systemd/system

# Copy the provisioning script
sudo cp configure-node.sh /opt/scripts/
sudo chmod +x /opt/scripts/configure-node.sh

# Copy the systemd service
sudo cp node-config.service /etc/systemd/system/
sudo chmod 644 /etc/systemd/system/node-config.service

# Copy the complete provisioning directory
sudo cp -r . /opt/configuration/
```

## Testing Methods

### Method 1: Automatic Service Testing (Recommended)

Test the full systemd service integration:

```bash
# Enable and start the service
sudo systemctl daemon-reload
sudo systemctl enable node-config.service
sudo systemctl start node-config.service

# Monitor the service status
sudo systemctl status node-config.service

# Follow the logs in real-time
sudo journalctl -u node-config.service -f

# Check service completion
sudo systemctl is-active node-config.service
```

### Method 2: Manual Script Testing

Test the script directly for debugging:

```bash
# Run script manually with full logging
sudo /opt/scripts/configure-node.sh

# Or run with specific environment
sudo ANSIBLE_STDOUT_CALLBACK=yaml /opt/scripts/configure-node.sh
```

### Method 3: Boot Integration Testing

Test the complete boot integration:

```bash
# Enable service for next boot
sudo systemctl enable node-config.service

# Reboot and monitor
sudo reboot

# After reboot, check results
sudo systemctl status node-config.service
cat /etc/node-config/node-config.success
```

## Verification Steps

### 1. Check Success Markers

```bash
# Check for success marker
ls -la /etc/node-config/
cat /etc/node-config/node-config.success

# Check for failure markers (should not exist on success)
ls -la /etc/node-config/node-config.failure 2>/dev/null || echo "No failure marker (good)"
```

### 2. Review Logs

```bash
# Service logs
sudo journalctl -u node-config.service --no-pager

# Script execution logs
ls -la /var/log/node-config/
sudo tail -f /var/log/node-config/$(ls -t /var/log/node-config/ | head -1)
```

### 3. Verify Provisioning Results

```bash
# Check orchestration report
sudo cat /var/lib/ansible/orchestration-final-report

# Check individual role statuses
sudo ls -la /var/lib/ansible/*-status

# Verify key configurations
sudo systemctl status fail2ban
sudo ufw status
sudo cat /etc/ssh/sshd_config | grep -E "Protocol|PermitRootLogin|PasswordAuthentication"
```

## Expected Results

### Successful Execution

**Success Marker Content:**

```yaml
# Node Configuration Success Marker
timestamp: 2024-01-15 10:30:45
hostname: k8s-master-01
role_id: k8s-master
role_name: k8s-master
instance_id: 01
log_file: /var/log/node-config/20240115_103045.log
orchestration_status: success
```

**Orchestration Report:**

```ini
[ORCHESTRATION_SUMMARY]
hostname: k8s-master-01
overall_status: complete_success

[STATISTICS]
success_rate: 100.0%
executed_playbooks: 8
successful_playbooks: 8
failed_playbooks: 0
```

### Service Status

```bash
# Service should show as completed successfully
$ sudo systemctl status node-config.service
● node-config.service - Domain-Based Ansible Provisioning System
   Loaded: loaded (/etc/systemd/system/node-config.service; enabled)
   Active: inactive (dead) since Mon 2024-01-15 10:35:22 UTC; 2min ago
   Process: 1234 ExecStart=/opt/scripts/configure-node.sh (code=exited, status=0/SUCCESS)
```

## Troubleshooting

### Common Issues

**1. Script Permission Denied**

```bash
sudo chmod +x /opt/scripts/configure-node.sh
```

**2. Network Connectivity Issues**

```bash
# Check network connectivity
ping -c3 google.com
ping -c3 8.8.8.8
```

**3. Ansible Installation Failures**

```bash
# Manual Ansible installation
sudo apt update
sudo apt install -y python3-pip
sudo pip3 install ansible
```

**4. Role ID or Hostname Issues**

```bash
# Verify hostname format
hostname
echo $(hostname) | grep -E '^[a-z0-9-]+-[0-9]+$' || echo "Invalid hostname format"

# Verify role ID
cat /etc/role-id
```

### Log Analysis

**Script Execution Phases:**

1. **System Validation** - Dependencies and environment checks
2. **Role Extraction** - Hostname parsing and role ID validation
3. **Inventory Generation** - Runtime Ansible inventory creation
4. **Ansible Provisioning** - Main orchestration execution

**Check Phase-Specific Issues:**

```bash
# Find the latest log file
LOG_FILE=$(ls -t /var/log/node-config/ | head -1)
sudo grep -A5 -B5 "Phase [1-4]:" /var/log/node-config/$LOG_FILE

# Check for specific error patterns
sudo grep -E "✗|ERROR|FAILED" /var/log/node-config/$LOG_FILE
```

### Recovery Procedures

**Failure Recovery:**

```bash
# Remove failure marker and retry
sudo rm -f /etc/node-config/node-config.failure
sudo systemctl restart node-config.service
```

**Clean State Reset:**

```bash
# Full reset for testing
sudo rm -f /etc/node-config/node-config.*
sudo rm -rf /var/log/node-config/*
sudo rm -rf /var/lib/ansible/*
sudo systemctl restart node-config.service
```

## Testing Checklist

- [ ] VM has correct hostname format (`role-name-instance`)
- [ ] Role ID file created at `/etc/role-id`
- [ ] All three files copied to correct locations
- [ ] Script has execute permissions
- [ ] Network connectivity verified
- [ ] Service enabled and started successfully
- [ ] Success marker created
- [ ] Orchestration report shows 100% success
- [ ] All 8 playbooks executed successfully
- [ ] Security configurations applied (SSH, firewall, fail2ban)

## Production Deployment Notes

For production template creation:

1. Package all files into VM template
2. Configure service to run on first boot only
3. Include role ID in template metadata
4. Set appropriate hostname during VM deployment
5. Ensure network connectivity before service execution

This completes the VM testing infrastructure for the Domain-Based Ansible Provisioning System.
