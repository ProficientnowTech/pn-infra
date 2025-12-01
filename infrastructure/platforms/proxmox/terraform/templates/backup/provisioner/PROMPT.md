# SYSTEM IMPLEMENTATION PROMPT
## Domain-Based Ansible Provisioning System

### WHAT WE'RE BUILDING

You are implementing a **domain-driven Ansible provisioning system** for infrastructure automation with these key characteristics:

**Purpose**: Provision VM nodes with 8 domain-specific configurations (base system, software, networking, security, etc.)
**Architecture**: 8 separate playbooks with dependency management and atomic rollback safety
**Execution Context**: Code gets packaged into VM templates, executed by external orchestrator
**Safety Focus**: Production-ready with validate→backup→apply→test→rollback pattern for every role
**Simplicity**: Clean, focused structure without over-engineering

### MULTI-AGENT IMPLEMENTATION APPROACH

**This system uses 4 specialized Claude Code agents** with different expertise areas:

1. **System Engineering Agent** - Base system, software, system settings, disk management (Responses 1-4)
2. **Security Engineering Agent** - Identity/users, security hardening (Responses 5, 8)
3. **Network Engineering Agent** - Networking, VLANs (Response 7)
4. **DevOps Integration Agent** - Directories, orchestration, testing (Responses 6, 9-10)

**Agent Selection**: Use the appropriate specialized agent based on the implementation phase and technical domain.

**You will implement this system incrementally, with the appropriate agent for each component:**

**Phase 1: Foundation** (System Engineering Agent)
1. **Base role** - timezone, locale, time sync, logging
2. **Software role** - package installation with validation

**Phase 2: System Core** (System Engineering Agent + Security Engineering Agent)
3. **System Settings role** - kernel modules, sysctl, systemd services (System Agent)
4. **Disk Management role** - partitioning, mounting, fstab (System Agent)
5. **Identity & Users role** - user management, SSH setup (Security Agent)

**Phase 3: Infrastructure** (DevOps Integration Agent + Network Engineering Agent)
6. **Directories role** - directory creation with cascade control (DevOps Agent)
7. **Networking role** - VLAN configuration (Network Agent)

**Phase 4: Security & Integration** (Security Engineering Agent + DevOps Integration Agent)
8. **Security role** - firewall, fail2ban, hardening (Security Agent)
9. **Master orchestrator** - dependency management (DevOps Agent)

**Phase 5: Finalization** (DevOps Integration Agent)
10. **Integration testing** - validation and documentation (DevOps Agent)

### COMPLETE IMPLEMENTATION PLAN

[ATTACH THE COMPLETE PLAN DOCUMENT HERE - it contains all architectural decisions, folder structure, dependency diagrams, variable organization, and detailed specifications]

### CRITICAL IMPLEMENTATION RULES

**1. SAFETY PATTERN (MANDATORY FOR ALL ROLES)**
Every role MUST implement this exact 5-phase pattern:
```yaml
# Phase 1: VALIDATE - Check prerequisites, set validation flags
# Phase 2: BACKUP - Save current state if applicable
# Phase 3: APPLY - Implement changes (may have sub-tasks)
# Phase 4: TEST - Validate new configuration works
# Phase 5: RESULT HANDLER - Commit success or rollback failure
```

**2. ATOMIC OPERATIONS**
- Each role succeeds completely or fails completely
- No partial states or half-configured systems
- Failed roles set status flags for dependency checking

**3. DEPENDENCY ENFORCEMENT**
- Base and Software are foundational - most roles depend on them
- Security depends on almost all other roles
- Independent roles can continue even if others fail
- Use status flags: `base_status`, `software_status`, etc.

**4. ERROR HANDLING STRATEGY**
- Continue with independent tasks/roles/playbooks if dependency failures
- Skip dependent tasks/roles/playbooks if prerequisites failed
- Log all failures with clear context
- Set appropriate status flags for orchestrator

**5. DIRECTORY CASCADE CONTROL**
For directories role, implement cascade ownership and permissions:
```yaml
directories:
  - path: /opt/scripts/system/
    owner: root
    group: root
    mode: '0755'
    cascade_ownership: true   # Apply to entire path
    cascade_permissions: true # Apply to entire path
```

### RESPONSE FORMAT REQUIREMENTS

**Each implementation response must contain:**

1. **Complete working code** for the assigned component
2. **All 5 task files** for roles (validate.yml, backup.yml, apply.yml, test.yml, result_handler.yml)
3. **Handlers and templates** as needed
4. **Integration points** - how it connects with other roles
5. **Testing procedures** - how to verify it works
6. **Error scenarios** - what can go wrong and how it's handled

**Code Quality Requirements:**
- Production-ready: comprehensive error handling, logging, validation
- Idempotent: can run multiple times safely
- Atomic: all-or-nothing operations within each role
- Well-documented: clear comments explaining complex logic
- Template-ready: no hardcoded values, proper variable usage

### CURRENT STATUS

**Starting Phase 1, Response 1: Base Role Implementation**

Implement the **base role** with these specifications:
- **Domain**: timezone, locale, time synchronization, logging configuration
- **Dependencies**: None (this is foundational)
- **Location**: `roles/base/` directory structure
- **Playbook**: `playbooks/base.yml`
- **Safety**: Full validate→backup→apply→test→rollback pattern
- **Integration**: Sets `base_status` flag for other playbooks to check

**Variable Usage**:
Read from inventory `base:` section:
```yaml
base:
  timezone: Asia/Kolkata
  locale: en_US
  time_sync: true
  logging: true
```

**Expected Deliverable**:
Complete base role implementation with all task files, handlers, templates, and the base.yml playbook. Include comprehensive error handling, rollback mechanisms, and clear logging.

### KEY CONSTRAINTS

**DO NOT:**
- Create run.sh or validate.sh files (handled externally)
- Over-engineer the solution - keep it focused and simple
- Create duplicate functionality across roles
- Skip the safety pattern for any role
- Hardcode values - use inventory variables

**DO:**
- Follow the exact folder structure specified in the plan
- Implement comprehensive safety mechanisms
- Create atomic, idempotent operations
- Use proper Ansible best practices
- Include clear error messages and logging
- Test rollback scenarios thoroughly

### SUCCESS CRITERIA

**Technical Validation:**
- Role can run independently and atomically
- Proper dependency status flag setting
- Safe rollback on any failure
- Comprehensive logging and error reporting
- Idempotent operation (can run multiple times)

**Integration Validation:**
- Works with inventory variable structure
- Integrates properly with orchestrator pattern
- Sets appropriate status flags for dependent roles
- Handles both success and failure scenarios gracefully

**START IMPLEMENTING NOW:**

**Remember the OVERENGINEERING WARNING above - build exactly what's specified, nothing more.**

**Current Agent**: System Engineering Agent
**Current Task**: Base role implementation (Response 1 of 10)
**Domain**: Timezone, locale, time synchronization, logging
**Dependencies**: None (foundational role)
**Deliverable**: Complete base role + base.yml playbook with full safety pattern

**Build the simplest solution that meets these exact requirements. Resist any urge to add features, optimizations, or "improvements" not specified above.**
