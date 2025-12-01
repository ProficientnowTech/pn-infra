### AGENT ARCHITECTURE OVERVIEW

This implementation uses **4 specialized Claude Code agents**, each with expertise in specific domains. This ensures deep technical knowledge, reduces context switching, and maintains consistency within each area of specialization.

### AGENT 1: SYSTEM ENGINEERING AGENT

**Role**: `system-engineering-agent`
**Expertise**: Core system configuration, package management, kernel settings
**Responsible For**:

- Base role (timezone, locale, time sync, logging)
- Software role (package installation, repositories, dependencies)
- System Settings role (kernel modules, sysctl, systemd services, optimization)
- Disk Management role (partitioning, mounting, fstab, filesystem management)

**Technical Skills**:

- Linux system administration
- Package management (apt, yum, repositories)
- Kernel module management and system tuning
- Disk partitioning and filesystem operations
- Service management (systemd, init systems)
- System optimization and performance tuning

**Implementation Phases**: Phase 1-2 (Responses 1-4)

---

### AGENT 2: SECURITY ENGINEERING AGENT

**Role**: `security-engineering-agent`
**Expertise**: Security hardening, identity management, access control
**Responsible For**:

- Identity & Users role (user management, SSH setup, groups, permissions)
- Security role (firewall, fail2ban, SSH hardening, system hardening)

**Technical Skills**:

- User and group management
- SSH configuration and hardening
- Firewall management (UFW, iptables)
- Security scanning and hardening
- Access control and permission management
- Audit logging and compliance
- Fail2ban and intrusion prevention

**Implementation Phases**: Phase 2-4 (Responses 5, 8)

---

### AGENT 3: NETWORK ENGINEERING AGENT

**Role**: `network-engineering-agent`
**Expertise**: Network configuration, VLANs, connectivity management
**Responsible For**:

- Networking role (VLAN configuration, network interfaces, routing)

**Technical Skills**:

- VLAN configuration and management
- Network interface management (netplan, ifconfig)
- Routing and gateway configuration
- Network troubleshooting and validation
- Network security (firewall rules, port management)
- Network performance optimization

**Implementation Phases**: Phase 3 (Response 7)

---

### AGENT 4: DEVOPS INTEGRATION AGENT

**Role**: `devops-integration-agent`
**Expertise**: Infrastructure automation, CI/CD, integration patterns
**Responsible For**:

- Directories role (directory management with cascade permissions)
- Master Orchestrator (site.yml, dependency management, status tracking)
- Integration Testing (validation scripts, testing procedures)
- Documentation and deployment guides

**Technical Skills**:

- Ansible orchestration and workflow management
- Dependency management and status tracking
- File system permissions and ownership management
- Integration testing and validation
- CI/CD pipeline patterns
- Infrastructure as Code best practices
- Documentation and technical writing

**Implementation Phases**: Phase 3-5 (Responses 6, 9-10)

---

## AGENT INTERACTION PROTOCOL

### HANDOFF PROCEDURES

**Between Agents**:

1. **Status Documentation**: Each agent documents completion status, issues encountered, integration points
2. **Dependency Mapping**: Clear specification of what the next agent can depend on
3. **Variable Contracts**: Exact variable structure and naming conventions for integration
4. **Testing Results**: Validation results and any known limitations

**Shared Standards**:

- All agents follow the 5-phase safety pattern (validate→backup→apply→test→rollback)
- Consistent error handling and logging approaches
- Standardized variable naming and inventory structure
- Uniform code quality standards and documentation

### COMMUNICATION POINTS

**System → Security Agent Handoff**:

- Users and groups created by System Agent
- Base packages installed for security tools
- System services configured for security dependencies

**Security → Network Agent Handoff**:

- SSH hardening completed (affects network access)
- Base firewall rules established
- User accounts available for network tool management

**Network → DevOps Agent Handoff**:

- Network connectivity validated and working
- VLANs properly configured
- Network-dependent directory paths accessible

**All Agents → DevOps Agent Integration**:

- Status flags properly set by all previous agents
- Integration points clearly documented
- Testing procedures defined and working

---

## AGENT-SPECIFIC REQUIREMENTS

### SYSTEM ENGINEERING AGENT REQUIREMENTS

**Deliverables**:

- Complete base role with timezone, locale, time sync, logging
- Software role with package management and repository configuration
- System settings role with kernel modules, sysctl, systemd management
- Disk management role with partitioning, mounting, fstab management

**Quality Gates**:

- All system services properly configured and tested
- Package installation idempotent and validated
- Disk operations safe with proper backup/rollback
- System optimization settings properly applied

**Integration Points**:

- Sets `base_status`, `software_status`, `system_settings_status`, `disk_status` flags
- Provides foundation for security hardening
- Ensures base packages available for other agents

### SECURITY ENGINEERING AGENT REQUIREMENTS

**Deliverables**:

- Identity & users role with comprehensive user management
- Security role with system hardening and access control

**Quality Gates**:

- SSH access properly configured and tested
- No security regressions or lockouts
- Proper user permissions and group memberships
- Security hardening applied without breaking functionality

**Integration Points**:

- Depends on `base_status` and `software_status` from System Agent
- Sets `identity_status` and `security_status` flags
- Provides secure foundation for network and application deployment

### NETWORK ENGINEERING AGENT REQUIREMENTS

**Deliverables**:

- Networking role with VLAN configuration and network management

**Quality Gates**:

- Network connectivity maintained throughout configuration
- VLAN configuration properly applied and tested
- No network interruptions during deployment
- Network performance optimized

**Integration Points**:

- Depends on `base_status` from System Agent
- May integrate with security firewall rules
- Sets `networking_status` flag
- Provides network foundation for application deployment

### DEVOPS INTEGRATION AGENT REQUIREMENTS

**Anti-Overengineering Specific to DevOps Domain:**

- **Don't create complex orchestration frameworks** - simple dependency checking only
- **Don't add CI/CD pipelines** unless explicitly required
- **Don't create elaborate testing suites** - basic validation only
- **Don't add deployment automation** beyond basic orchestration
- **Don't create complex directory permission schemes** - follow cascade specification exactly
- **Don't add monitoring dashboards** unless specified
- **Don't create complex logging systems** - simple status tracking only
- **Don't add configuration management tools** beyond Ansible
- **Don't optimize orchestration** - functional dependency management only

**Deliverables**:

- Directories role with cascade permission management
- Master orchestrator with dependency management
- Integration testing and validation procedures
- Complete documentation and deployment guides

**Quality Gates**:

- Directory permissions properly cascaded and secured
- Orchestrator handles all dependency scenarios correctly
- Integration testing covers success and failure paths
- Documentation complete and accurate

**Integration Points**:

- Depends on status flags from all other agents
- Validates integration between all roles
- Provides final system validation and testing
- Creates deployment and operational documentation

---

## IMPLEMENTATION SEQUENCE BY AGENT

### PHASE 1: SYSTEM FOUNDATION (System Engineering Agent)

**Response 1**: Base role implementation
**Response 2**: Software role implementation

### PHASE 2: SYSTEM CORE (System Engineering Agent + Security Engineering Agent)

**Response 3**: System Settings role (System Agent)
**Response 4**: Disk Management role (System Agent)
**Response 5**: Identity & Users role (Security Agent)

### PHASE 3: INFRASTRUCTURE (DevOps Integration Agent + Network Engineering Agent)

**Response 6**: Directories role (DevOps Agent)
**Response 7**: Networking role (Network Agent)

### PHASE 4: SECURITY & INTEGRATION (Security Engineering Agent + DevOps Integration Agent)

**Response 8**: Security role (Security Agent)
**Response 9**: Master Orchestrator (DevOps Agent)

### PHASE 5: FINALIZATION (DevOps Integration Agent)

**Response 10**: Integration Testing & Documentation (DevOps Agent)

---

## AGENT SELECTION GUIDE

**For System-Level Work**: Use System Engineering Agent

- Base system configuration, packages, kernel settings, disk management

**For Security Work**: Use Security Engineering Agent

- User management, SSH configuration, system hardening, access control

**For Network Work**: Use Network Engineering Agent

- VLAN configuration, network interfaces, connectivity management

**For Integration Work**: Use DevOps Integration Agent

- Orchestration, testing, directory management, documentation

---

## QUALITY ASSURANCE ACROSS AGENTS

**Consistent Standards**:

- All agents implement the 5-phase safety pattern
- Uniform error handling and rollback mechanisms
- Standardized logging and status reporting
- Consistent code quality and documentation standards

**Cross-Agent Validation**:

- Each agent validates prerequisites from previous agents
- Integration points clearly defined and tested
- Status flags properly managed and checked
- Dependency failures handled gracefully

**Final Integration**:

- DevOps Integration Agent performs comprehensive system validation
- All agent deliverables integrated and tested together
- Complete documentation covers entire system
- Deployment procedures validated end-to-end

This multi-agent approach ensures deep expertise in each domain while maintaining system-wide consistency and integration.
