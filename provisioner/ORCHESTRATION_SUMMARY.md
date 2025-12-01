# Domain-Based Ansible Provisioning System - Master Orchestrator

## Overview

The master orchestrator (`site.yml`) manages the execution of 8 domain-specific playbooks with comprehensive dependency management and status tracking.

## Execution Flow

### Phase 1: Foundation Layer

1. **Base** (`playbooks/base.yml`) - No dependencies
    - Timezone, locale, time sync, logging
    - Sets `base_status`

2. **Software** (`playbooks/software.yml`) - Depends on: base_status == "success"
    - Package installation, repositories
    - Sets `software_status`

### Phase 2: System Configuration Layer

3. **System Settings** (`playbooks/system_settings.yml`) - Depends on: software_status == "success"
    - Kernel modules, sysctl, systemd services
    - Sets `system_settings_status`

4. **Disk Management** (`playbooks/disk_management.yml`) - Depends on: software_status == "success"
    - Partitioning, mounting, fstab
    - Sets `disk_management_status`

### Phase 3: Identity & Infrastructure Layer

5. **Identity & Users** (`playbooks/identity_users.yml`) - Depends on: base_status == "success"
    - User management, SSH configuration
    - Sets `identity_status`

6. **Directories** (`playbooks/directories.yml`) - Depends on: identity_status == "success"
    - Directory creation with cascade permissions
    - Sets `directories_status`

7. **Networking** (`playbooks/networking.yml`) - Depends on: base_status == "success"
    - VLAN configuration, network interfaces
    - Sets `networking_status`

### Phase 4: Security Layer

8. **Security** (`playbooks/security.yml`) - Depends on: base_status, software_status, identity_status, networking_status ALL == "success"
    - System hardening, firewall, fail2ban
    - Sets `security_status`

## Dependency Management

### Execution Logic

- **Continue Independent**: If a role fails, independent roles still execute
- **Skip Dependent**: If prerequisites fail, dependent roles are skipped
- **Multi-Dependency**: Security role requires multiple successful prerequisites

### Status Tracking

- Each playbook sets a status flag: `success` | `failed` | `not_executed`
- Status files written to `/var/lib/ansible/` for persistence
- Comprehensive orchestration report generated at completion

## Safety Features

### Individual Role Safety

- Each role implements 5-phase safety pattern: validate → backup → apply → test → rollback
- Atomic operations within roles
- Comprehensive error handling and recovery

### Orchestration Safety

- Dependency validation before execution
- Graceful handling of partial failures
- Detailed status reporting and recovery guidance
- Critical warnings for system-affecting failures

## Usage

### Standard Execution

```bash
ansible-playbook -i inventory/production site.yml
```

### Validation Only

```bash
ansible-playbook validate-orchestration.yml
```

### Individual Playbook

```bash
ansible-playbook -i inventory/production playbooks/base.yml
```

## Status Files

### Individual Role Status

- `/var/lib/ansible/{role}-role-status` - Detailed role execution status
- `/var/lib/ansible/playbook-{name}-status` - Playbook-level status

### Orchestration Status

- `/var/lib/ansible/orchestration-final-report` - Comprehensive final report
- Contains: success rates, dependency analysis, recovery information

## Recovery Information

### Backup Locations

- `/var/backups/ansible-{role}/` - Role-specific configuration backups
- Each backup includes timestamps and restoration procedures

### Manual Recovery

- Check individual role status files for detailed error information
- Use backup manifests for configuration restoration
- Verify system integrity before rebooting after failures

## Success Criteria

### Complete Success

- All 8 playbooks execute successfully
- 100% success rate
- All status flags set to "success"
- System ready for application deployment

### Partial Success

- Some playbooks succeed, others fail or skip
- Review failed components and resolve issues
- Re-run orchestrator to complete remaining configurations

### Critical Failure

- Foundation layer failures (base/software)
- Disk management failures requiring manual intervention
- Security failures leaving system in inconsistent state

## Integration Points

### External Orchestration

- Status flags available for external systems
- Comprehensive reporting for CI/CD integration
- Atomic role execution for selective re-runs

### Template Packaging

- Designed for VM template packaging
- External service integration via status files
- Self-contained with all dependencies managed
