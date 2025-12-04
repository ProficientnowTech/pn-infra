package config

// MasterConfig represents the master configuration (config.yaml)
type MasterConfig struct {
	Version                 string                       `yaml:"version"`
	Infrastructure          InfrastructureChoice         `yaml:"infrastructure"`
	ContainerOrchestration  ContainerOrchestrationChoice `yaml:"container_orchestration"`
	Platform                PlatformDeployment           `yaml:"platform"`
	Business                BusinessDeployment           `yaml:"business"`
}

type InfrastructureChoice struct {
	Platform string `yaml:"platform"` // proxmox, aws, gcp, azure, baremetal
	Provider string `yaml:"provider"` // terraform, pulumi, ansible
}

type ContainerOrchestrationChoice struct {
	Orchestrator string `yaml:"orchestrator"` // kubespray, kubekey, kind
	Provider     string `yaml:"provider"`     // docker, podman, native
}

type PlatformDeployment struct {
	DeploymentMethod string `yaml:"deployment_method"` // helm, kustomize, argocd
}

type BusinessDeployment struct {
	DeploymentMethod string `yaml:"deployment_method"` // argocd, helm, kustomize
}

// HostsConfig represents platform-agnostic host definitions (hosts.yaml)
type HostsConfig struct {
	Hosts []Host `yaml:"hosts"`
}

type Host struct {
	Name   string   `yaml:"name"`
	Role   string   `yaml:"role"`
	IP     string   `yaml:"ip"`
	CPU    int      `yaml:"cpu"`
	Memory int      `yaml:"memory"` // MB
	Disk   int      `yaml:"disk"`   // GB
	Labels []string `yaml:"labels,omitempty"`
	Groups []string `yaml:"groups,omitempty"`
}

// NetworksConfig represents platform-agnostic network topology (networks.yaml)
type NetworksConfig struct {
	Networks []Network   `yaml:"networks"`
	DNS      DNSConfig   `yaml:"dns"`
	NTP      NTPConfig   `yaml:"ntp"`
}

type Network struct {
	Name        string   `yaml:"name"`
	VlanID      int      `yaml:"vlan_id,omitempty"`
	CIDR        string   `yaml:"cidr"`
	Gateway     string   `yaml:"gateway,omitempty"`
	DNSServers  []string `yaml:"dns_servers,omitempty"`
	Description string   `yaml:"description,omitempty"`
}

type DNSConfig struct {
	Domain        string   `yaml:"domain"`
	SearchDomains []string `yaml:"search_domains,omitempty"`
}

type NTPConfig struct {
	Servers []string `yaml:"servers"`
}

// ProxmoxConfig represents Proxmox platform-specific configuration
type ProxmoxConfig struct {
	Proxmox ProxmoxSettings `yaml:"proxmox"`
}

type ProxmoxSettings struct {
	NodeName   string                 `yaml:"node_name"`
	Datastore  string                 `yaml:"datastore"`
	IsoStorage string                 `yaml:"iso_storage"`
	Template   ProxmoxTemplate        `yaml:"template"`
	Network    ProxmoxNetwork         `yaml:"network"`
	VmDefaults ProxmoxVMDefaults      `yaml:"vm_defaults"`
	Cloudinit  ProxmoxCloudinit       `yaml:"cloudinit"`
	Pool       string                 `yaml:"pool,omitempty"`
}

type ProxmoxTemplate struct {
	ID              int    `yaml:"id"`
	Name            string `yaml:"name"`
	CoresPerSocket  int    `yaml:"cores_per_socket"`
	Sockets         int    `yaml:"sockets"`
}

type ProxmoxNetwork struct {
	Bridge   string `yaml:"bridge"`
	Model    string `yaml:"model"`
	Firewall bool   `yaml:"firewall"`
}

type ProxmoxVMDefaults struct {
	OsType    string `yaml:"os_type"`
	BootOrder string `yaml:"boot_order"`
	Scsihw    string `yaml:"scsihw"`
	Agent     string `yaml:"agent"`
	Balloon   int    `yaml:"balloon"`
	CpuType   string `yaml:"cpu_type"`
	Hotplug   string `yaml:"hotplug"`
}

type ProxmoxCloudinit struct {
	Enabled bool   `yaml:"enabled"`
	Storage string `yaml:"storage"`
}

// AWSConfig represents AWS platform-specific configuration
type AWSConfig struct {
	AWS AWSSettings `yaml:"aws"`
}

type AWSSettings struct {
	Region             string              `yaml:"region"`
	AvailabilityZones  []string            `yaml:"availability_zones"`
	VPC                AWSVPCConfig        `yaml:"vpc"`
	Subnets            []AWSSubnet         `yaml:"subnets"`
	InstanceDefaults   AWSInstanceDefaults `yaml:"instance_defaults"`
	SecurityGroups     []interface{}       `yaml:"security_groups"`
	Tags               map[string]string   `yaml:"tags,omitempty"`
}

type AWSVPCConfig struct {
	CIDRBlock          string `yaml:"cidr_block"`
	EnableDNSHostnames bool   `yaml:"enable_dns_hostnames"`
	EnableDNSSupport   bool   `yaml:"enable_dns_support"`
}

type AWSSubnet struct {
	Name                  string `yaml:"name"`
	CIDRBlock             string `yaml:"cidr_block"`
	AvailabilityZone      string `yaml:"availability_zone"`
	MapPublicIPOnLaunch   bool   `yaml:"map_public_ip_on_launch"`
}

type AWSInstanceDefaults struct {
	AMI            string           `yaml:"ami"`
	InstanceType   string           `yaml:"instance_type"`
	KeyName        string           `yaml:"key_name"`
	Monitoring     bool             `yaml:"monitoring"`
	EBSOptimized   bool             `yaml:"ebs_optimized"`
	RootVolume     AWSRootVolume    `yaml:"root_volume"`
}

type AWSRootVolume struct {
	VolumeType          string `yaml:"volume_type"`
	VolumeSize          int    `yaml:"volume_size"`
	DeleteOnTermination bool   `yaml:"delete_on_termination"`
}

// GCPConfig represents GCP platform-specific configuration
type GCPConfig struct {
	GCP GCPSettings `yaml:"gcp"`
}

type GCPSettings struct {
	ProjectID        string              `yaml:"project_id"`
	Region           string              `yaml:"region"`
	Zone             string              `yaml:"zone"`
	Network          GCPNetwork          `yaml:"network"`
	Subnets          []GCPSubnet         `yaml:"subnets"`
	InstanceDefaults GCPInstanceDefaults `yaml:"instance_defaults"`
	FirewallRules    []interface{}       `yaml:"firewall_rules"`
	Labels           map[string]string   `yaml:"labels,omitempty"`
}

type GCPNetwork struct {
	Name                  string `yaml:"name"`
	AutoCreateSubnetworks bool   `yaml:"auto_create_subnetworks"`
}

type GCPSubnet struct {
	Name                   string                   `yaml:"name"`
	IPCIDRRange            string                   `yaml:"ip_cidr_range"`
	Region                 string                   `yaml:"region"`
	PrivateIPGoogleAccess  bool                     `yaml:"private_ip_google_access"`
	SecondaryIPRanges      []GCPSecondaryIPRange    `yaml:"secondary_ip_ranges,omitempty"`
}

type GCPSecondaryIPRange struct {
	RangeName   string `yaml:"range_name"`
	IPCIDRRange string `yaml:"ip_cidr_range"`
}

type GCPInstanceDefaults struct {
	MachineType  string        `yaml:"machine_type"`
	ImageFamily  string        `yaml:"image_family"`
	ImageProject string        `yaml:"image_project"`
	BootDisk     GCPBootDisk   `yaml:"boot_disk"`
	NetworkTags  []string      `yaml:"network_tags"`
}

type GCPBootDisk struct {
	SizeGB int    `yaml:"size_gb"`
	Type   string `yaml:"type"`
}

// AzureConfig represents Azure platform-specific configuration
type AzureConfig struct {
	Azure AzureSettings `yaml:"azure"`
}

type AzureSettings struct {
	Location              string                  `yaml:"location"`
	ResourceGroupName     string                  `yaml:"resource_group_name"`
	VNet                  AzureVNet               `yaml:"vnet"`
	Subnets               []AzureSubnet           `yaml:"subnets"`
	VMDefaults            AzureVMDefaults         `yaml:"vm_defaults"`
	NetworkSecurityGroup  AzureNSG                `yaml:"network_security_group"`
	Tags                  map[string]string       `yaml:"tags,omitempty"`
}

type AzureVNet struct {
	Name         string   `yaml:"name"`
	AddressSpace []string `yaml:"address_space"`
}

type AzureSubnet struct {
	Name            string   `yaml:"name"`
	AddressPrefixes []string `yaml:"address_prefixes"`
}

type AzureVMDefaults struct {
	Size                           string                   `yaml:"size"`
	AdminUsername                  string                   `yaml:"admin_username"`
	DisablePasswordAuthentication  bool                     `yaml:"disable_password_authentication"`
	OSDisk                         AzureOSDisk              `yaml:"os_disk"`
	SourceImageReference           AzureSourceImageRef      `yaml:"source_image_reference"`
}

type AzureOSDisk struct {
	Caching            string `yaml:"caching"`
	StorageAccountType string `yaml:"storage_account_type"`
	DiskSizeGB         int    `yaml:"disk_size_gb"`
}

type AzureSourceImageRef struct {
	Publisher string `yaml:"publisher"`
	Offer     string `yaml:"offer"`
	SKU       string `yaml:"sku"`
	Version   string `yaml:"version"`
}

type AzureNSG struct {
	Name          string            `yaml:"name"`
	SecurityRules []interface{}     `yaml:"security_rules"`
}

// KubesprayConfig represents Kubespray orchestrator configuration
type KubesprayConfig struct {
	Kubespray KubespraySettings `yaml:"kubespray"`
}

type KubespraySettings struct {
	KubeVersion             string                 `yaml:"kube_version"`
	ClusterName             string                 `yaml:"cluster_name"`
	KubeDNSDomain           string                 `yaml:"kube_dns_domain"`
	KubeNetworkPlugin       string                 `yaml:"kube_network_plugin"`
	KubeServiceAddresses    string                 `yaml:"kube_service_addresses"`
	KubePodsSubnet          string                 `yaml:"kube_pods_subnet"`
	DNSMode                 string                 `yaml:"dns_mode"`
	EnableNodelocaldns      bool                   `yaml:"enable_nodelocaldns"`
	NodelocaldnsIP          string                 `yaml:"nodelocaldns_ip,omitempty"`
	ContainerManager        string                 `yaml:"container_manager"`
	KubeapiserverPort       int                    `yaml:"kube_apiserver_port"`
	KubeProxyMode           string                 `yaml:"kube_proxy_mode"`
	EtcdDeploymentType      string                 `yaml:"etcd_deployment_type"`
	EtcdMemoryLimit         string                 `yaml:"etcd_memory_limit,omitempty"`
	EtcdQuotaBackendBytes   string                 `yaml:"etcd_quota_backend_bytes,omitempty"`
	HelmEnabled             bool                   `yaml:"helm_enabled"`
	MetricsServerEnabled    bool                   `yaml:"metrics_server_enabled"`
	IngressNginxEnabled     bool                   `yaml:"ingress_nginx_enabled"`
	CertManagerEnabled      bool                   `yaml:"cert_manager_enabled"`
	DashboardEnabled        bool                   `yaml:"dashboard_enabled"`
	LocalPathProvisionerEnabled bool               `yaml:"local_path_provisioner_enabled"`
	MetallbEnabled          bool                   `yaml:"metallb_enabled"`
	MetallbIPRange          string                 `yaml:"metallb_ip_range,omitempty"`
	DownloadContainer       bool                   `yaml:"download_container"`
	DownloadForceCache      bool                   `yaml:"download_force_cache"`
	DownloadRunOnce         bool                   `yaml:"download_run_once"`
	UpgradeClusterSetup     bool                   `yaml:"upgrade_cluster_setup"`
	DrainNodes              bool                   `yaml:"drain_nodes"`
	DrainGracePeriod        int                    `yaml:"drain_grace_period"`
	DrainTimeout            int                    `yaml:"drain_timeout"`
	KubeletMaxPods          int                    `yaml:"kubelet_max_pods"`
	KubeReadOnlyPort        int                    `yaml:"kube_read_only_port"`
	KubeFeatureGates        []string               `yaml:"kube_feature_gates,omitempty"`
	DockerInsecureRegistries []string              `yaml:"docker_insecure_registries,omitempty"`
	DockerRegistryMirrors   []string               `yaml:"docker_registry_mirrors,omitempty"`
}

// PlatformConfig represents platform services configuration
type PlatformConfig struct {
	Stacks map[string]StackConfig `yaml:"stacks"`
}

type StackConfig struct {
	Enabled             bool                   `yaml:"enabled"`
	SyncWave            int                    `yaml:"sync_wave,omitempty"`
	Components          []string               `yaml:"components,omitempty"`
	Provider            string                 `yaml:"provider,omitempty"`
	DefaultStorageClass string                 `yaml:"defaultStorageClass,omitempty"`
	Controller          string                 `yaml:"controller,omitempty"`
	Backend             string                 `yaml:"backend,omitempty"`
	Retention           map[string]string      `yaml:"retention,omitempty"`
	Storage             map[string]string      `yaml:"storage,omitempty"`
	Schedule            string                 `yaml:"schedule,omitempty"`
}

// BusinessConfig represents business applications configuration
type BusinessConfig struct {
	Applications []Application `yaml:"applications"`
}

type Application struct {
	Name         string                 `yaml:"name"`
	Enabled      bool                   `yaml:"enabled"`
	Namespace    string                 `yaml:"namespace"`
	SyncWave     int                    `yaml:"sync_wave,omitempty"`
	Source       ApplicationSource      `yaml:"source"`
	SyncPolicy   *ApplicationSyncPolicy `yaml:"sync_policy,omitempty"`
	Values       map[string]interface{} `yaml:"values,omitempty"`
	Dependencies []string               `yaml:"dependencies,omitempty"`
}

type ApplicationSource struct {
	Type           string `yaml:"type"`
	Path           string `yaml:"path"`
	TargetRevision string `yaml:"target_revision"`
}

type ApplicationSyncPolicy struct {
	Automated   ApplicationSyncAutomated `yaml:"automated"`
	SyncOptions []string                 `yaml:"sync_options,omitempty"`
}

type ApplicationSyncAutomated struct {
	Prune    bool `yaml:"prune"`
	SelfHeal bool `yaml:"self_heal"`
}

// SSHConfig represents SSH configuration
type SSHConfig struct {
	User      string `yaml:"user"`
	Port      int    `yaml:"port"`
	KeyPath   string `yaml:"key_path"`
	PublicKey string `yaml:"public_key,omitempty"`
}

// MergedConfig represents the final merged configuration
type MergedConfig struct {
	ConfigPackage          string
	Environment            string
	MasterConfig           MasterConfig
	Hosts                  []Host
	Networks               NetworksConfig
	DNS                    DNSConfig
	NTP                    NTPConfig
	SSH                    SSHConfig
	Infrastructure         InfrastructureChoice
	ContainerOrchestration ContainerOrchestrationChoice

	// Platform-specific (only one populated based on master config)
	Proxmox *ProxmoxSettings
	AWS     *AWSSettings
	GCP     *GCPSettings
	Azure   *AzureSettings

	// Orchestrator-specific (only one populated based on master config)
	Kubespray *KubespraySettings
	Kind      map[string]interface{} // Generic map for Kind config
	Kubekey   map[string]interface{} // Generic map for Kubekey config

	// Platform and Business
	Stacks       map[string]StackConfig
	Applications []Application

	// Environment overrides
	ClusterOverrides   map[string]interface{}
	Global             map[string]interface{}
	NamespaceConfigs   map[string]interface{}
}
