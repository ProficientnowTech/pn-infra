package config

import (
	"fmt"
	"os"
	"path/filepath"

	"gopkg.in/yaml.v3"
)

// Loader handles loading and merging configuration files
type Loader struct {
	RepoRoot      string
	ConfigPackage string
	Environment   string
}

// NewLoader creates a new config loader
func NewLoader(repoRoot, configPackage, environment string) *Loader {
	return &Loader{
		RepoRoot:      repoRoot,
		ConfigPackage: configPackage,
		Environment:   environment,
	}
}

// LoadMasterConfig loads the master configuration file
func (l *Loader) LoadMasterConfig() (*MasterConfig, error) {
	path := filepath.Join(l.RepoRoot, "config", "packages", l.ConfigPackage, "config.yaml")
	var config MasterConfig
	if err := readYAML(path, &config); err != nil {
		return nil, fmt.Errorf("load master config: %w", err)
	}
	return &config, nil
}

// LoadHosts loads platform-agnostic host definitions
func (l *Loader) LoadHosts() (*HostsConfig, error) {
	path := filepath.Join(l.RepoRoot, "config", "packages", l.ConfigPackage, "hosts.yaml")
	var config HostsConfig
	if err := readYAML(path, &config); err != nil {
		return nil, fmt.Errorf("load hosts config: %w", err)
	}
	return &config, nil
}

// LoadNetworks loads platform-agnostic network configuration
func (l *Loader) LoadNetworks() (*NetworksConfig, error) {
	path := filepath.Join(l.RepoRoot, "config", "packages", l.ConfigPackage, "networks.yaml")
	var config NetworksConfig
	if err := readYAML(path, &config); err != nil {
		return nil, fmt.Errorf("load networks config: %w", err)
	}
	return &config, nil
}

// LoadPlatformConfig loads platform-specific configuration based on master config
func (l *Loader) LoadPlatformConfig(platform string) (interface{}, error) {
	path := filepath.Join(l.RepoRoot, "config", "packages", l.ConfigPackage, "platforms", fmt.Sprintf("%s.yaml", platform))

	switch platform {
	case "proxmox":
		var config ProxmoxConfig
		if err := readYAML(path, &config); err != nil {
			return nil, fmt.Errorf("load proxmox config: %w", err)
		}
		return &config, nil
	case "aws":
		var config AWSConfig
		if err := readYAML(path, &config); err != nil {
			return nil, fmt.Errorf("load aws config: %w", err)
		}
		return &config, nil
	case "gcp":
		var config GCPConfig
		if err := readYAML(path, &config); err != nil {
			return nil, fmt.Errorf("load gcp config: %w", err)
		}
		return &config, nil
	case "azure":
		var config AzureConfig
		if err := readYAML(path, &config); err != nil {
			return nil, fmt.Errorf("load azure config: %w", err)
		}
		return &config, nil
	default:
		return nil, fmt.Errorf("unsupported platform: %s", platform)
	}
}

// LoadOrchestratorConfig loads orchestrator-specific configuration
func (l *Loader) LoadOrchestratorConfig(orchestrator string) (interface{}, error) {
	path := filepath.Join(l.RepoRoot, "config", "packages", l.ConfigPackage, "orchestrators", fmt.Sprintf("%s.yaml", orchestrator))

	switch orchestrator {
	case "kubespray":
		var config KubesprayConfig
		if err := readYAML(path, &config); err != nil {
			return nil, fmt.Errorf("load kubespray config: %w", err)
		}
		return &config, nil
	case "kubekey", "kind":
		// Load as generic map for now (can be extended later)
		var config map[string]interface{}
		if err := readYAML(path, &config); err != nil {
			return nil, fmt.Errorf("load %s config: %w", orchestrator, err)
		}
		return config, nil
	default:
		return nil, fmt.Errorf("unsupported orchestrator: %s", orchestrator)
	}
}

// LoadPlatformStacks loads platform services configuration
func (l *Loader) LoadPlatformStacks() (*PlatformConfig, error) {
	path := filepath.Join(l.RepoRoot, "config", "packages", l.ConfigPackage, "platform", "stacks.yaml")
	var config PlatformConfig
	if err := readYAML(path, &config); err != nil {
		return nil, fmt.Errorf("load platform stacks: %w", err)
	}
	return &config, nil
}

// LoadBusinessApps loads business applications configuration
func (l *Loader) LoadBusinessApps() (*BusinessConfig, error) {
	path := filepath.Join(l.RepoRoot, "config", "packages", l.ConfigPackage, "business", "apps.yaml")
	var config BusinessConfig
	if err := readYAML(path, &config); err != nil {
		return nil, fmt.Errorf("load business apps: %w", err)
	}
	return &config, nil
}

// LoadModuleEnv loads module-specific environment overrides
func (l *Loader) LoadModuleEnv(module string) (map[string]interface{}, error) {
	path := filepath.Join(l.RepoRoot, module, "environments", fmt.Sprintf("%s.yaml", l.Environment))

	// Check if file exists
	if _, err := os.Stat(path); os.IsNotExist(err) {
		// Return empty map if file doesn't exist (no overrides)
		return make(map[string]interface{}), nil
	}

	var config map[string]interface{}
	if err := readYAML(path, &config); err != nil {
		return nil, fmt.Errorf("load module env %s: %w", module, err)
	}
	return config, nil
}

// LoadAndMerge loads all configuration files and merges them
func (l *Loader) LoadAndMerge() (*MergedConfig, error) {
	// 1. Load master config
	masterConfig, err := l.LoadMasterConfig()
	if err != nil {
		return nil, err
	}

	// 2. Load platform-agnostic configs
	hostsConfig, err := l.LoadHosts()
	if err != nil {
		return nil, err
	}

	networksConfig, err := l.LoadNetworks()
	if err != nil {
		return nil, err
	}

	// 3. Load platform-specific config (skip if platform is "none")
	var platformConfig interface{}
	if masterConfig.Infrastructure.Platform != "none" {
		var err error
		platformConfig, err = l.LoadPlatformConfig(masterConfig.Infrastructure.Platform)
		if err != nil {
			return nil, err
		}
	}

	// 4. Load orchestrator-specific config
	orchestratorConfig, err := l.LoadOrchestratorConfig(masterConfig.ContainerOrchestration.Orchestrator)
	if err != nil {
		return nil, err
	}

	// 5. Load platform stacks
	platformStacks, err := l.LoadPlatformStacks()
	if err != nil {
		return nil, err
	}

	// 6. Load business apps
	businessApps, err := l.LoadBusinessApps()
	if err != nil {
		return nil, err
	}

	// 7. Load environment overrides
	infraEnv, err := l.LoadModuleEnv("infrastructure")
	if err != nil {
		return nil, err
	}

	orchestrationEnv, err := l.LoadModuleEnv("container-orchestration")
	if err != nil {
		return nil, err
	}

	// 8. Build merged config
	merged := &MergedConfig{
		ConfigPackage:          l.ConfigPackage,
		Environment:            l.Environment,
		MasterConfig:           *masterConfig,
		Hosts:                  hostsConfig.Hosts,
		Networks:               *networksConfig,
		DNS:                    networksConfig.DNS,
		NTP:                    networksConfig.NTP,
		Infrastructure:         masterConfig.Infrastructure,
		ContainerOrchestration: masterConfig.ContainerOrchestration,
		Stacks:                 platformStacks.Stacks,
		Applications:           businessApps.Applications,
	}

	// Extract SSH config from infrastructure environment
	if sshData, ok := infraEnv["ssh"].(map[string]interface{}); ok {
		merged.SSH = SSHConfig{
			User:      getStringOrDefault(sshData, "user", "ansible"),
			Port:      getIntOrDefault(sshData, "port", 22),
			KeyPath:   getStringOrDefault(sshData, "key_path", ""),
			PublicKey: getStringOrDefault(sshData, "public_key", ""),
		}
	}

	// Populate platform-specific config (skip if platform is "none")
	if platformConfig != nil {
		switch masterConfig.Infrastructure.Platform {
		case "proxmox":
			if cfg, ok := platformConfig.(*ProxmoxConfig); ok {
				merged.Proxmox = &cfg.Proxmox
				// Apply environment overrides
				if proxmoxEnv, ok := infraEnv["proxmox"].(map[string]interface{}); ok {
					applyProxmoxOverrides(merged.Proxmox, proxmoxEnv)
				}
			}
		case "aws":
			if cfg, ok := platformConfig.(*AWSConfig); ok {
				merged.AWS = &cfg.AWS
				// Apply environment overrides
				if awsEnv, ok := infraEnv["aws"].(map[string]interface{}); ok {
					applyAWSOverrides(merged.AWS, awsEnv)
				}
			}
		case "gcp":
			if cfg, ok := platformConfig.(*GCPConfig); ok {
				merged.GCP = &cfg.GCP
				// Apply environment overrides
				if gcpEnv, ok := infraEnv["gcp"].(map[string]interface{}); ok {
					applyGCPOverrides(merged.GCP, gcpEnv)
				}
			}
		case "azure":
			if cfg, ok := platformConfig.(*AzureConfig); ok {
				merged.Azure = &cfg.Azure
				// Apply environment overrides
				if azureEnv, ok := infraEnv["azure"].(map[string]interface{}); ok {
					applyAzureOverrides(merged.Azure, azureEnv)
				}
			}
		}
	}

	// Populate orchestrator-specific config
	switch masterConfig.ContainerOrchestration.Orchestrator {
	case "kubespray":
		if cfg, ok := orchestratorConfig.(*KubesprayConfig); ok {
			merged.Kubespray = &cfg.Kubespray
			// Apply cluster overrides from environment
			if clusterOverrides, ok := orchestrationEnv["cluster_overrides"].(map[string]interface{}); ok {
				merged.ClusterOverrides = clusterOverrides
			}
		}
	case "kind":
		if cfg, ok := orchestratorConfig.(map[string]interface{}); ok {
			// Extract the "kind" key from the loaded map
			if kindCfg, ok := cfg["kind"].(map[string]interface{}); ok {
				merged.Kind = kindCfg
			}
		}
	case "kubekey":
		if cfg, ok := orchestratorConfig.(map[string]interface{}); ok {
			// Extract the "kubekey" key from the loaded map
			if kubekeyCfg, ok := cfg["kubekey"].(map[string]interface{}); ok {
				merged.Kubekey = kubekeyCfg
			}
		}
	}

	return merged, nil
}

// readYAML reads and unmarshals a YAML file
func readYAML(path string, target interface{}) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return fmt.Errorf("read file %s: %w", path, err)
	}

	if err := yaml.Unmarshal(data, target); err != nil {
		return fmt.Errorf("unmarshal yaml %s: %w", path, err)
	}

	return nil
}

// Helper functions to extract values from maps
func getStringOrDefault(m map[string]interface{}, key, defaultVal string) string {
	if val, ok := m[key].(string); ok {
		return val
	}
	return defaultVal
}

func getIntOrDefault(m map[string]interface{}, key string, defaultVal int) int {
	if val, ok := m[key].(int); ok {
		return val
	}
	return defaultVal
}

// Apply environment overrides (simple implementation - can be enhanced)
func applyProxmoxOverrides(config *ProxmoxSettings, overrides map[string]interface{}) {
	if endpoint, ok := overrides["endpoint"].(string); ok {
		// Store in a separate field or handle differently
		_ = endpoint // Endpoint should be in environment override, not base config
	}
}

func applyAWSOverrides(config *AWSSettings, overrides map[string]interface{}) {
	if region, ok := overrides["region"].(string); ok && region != "" {
		config.Region = region
	}
}

func applyGCPOverrides(config *GCPSettings, overrides map[string]interface{}) {
	if region, ok := overrides["region"].(string); ok && region != "" {
		config.Region = region
	}
}

func applyAzureOverrides(config *AzureSettings, overrides map[string]interface{}) {
	if location, ok := overrides["location"].(string); ok && location != "" {
		config.Location = location
	}
}
