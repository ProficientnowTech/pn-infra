package template

import (
	"fmt"
	"path/filepath"

	"pn-infra/api/internal/config"
)

// PathResolver resolves template paths based on master config selections
type PathResolver struct {
	RepoRoot string
}

// NewPathResolver creates a new template path resolver
func NewPathResolver(repoRoot string) *PathResolver {
	return &PathResolver{RepoRoot: repoRoot}
}

// TemplatePaths holds all resolved template paths for an environment
type TemplatePaths struct {
	Infrastructure           string
	ContainerOrchestration   ContainerOrchestrationPaths
	Provisioner              string
	Platform                 string
	Business                 string
}

// ContainerOrchestrationPaths holds orchestrator-specific template paths
type ContainerOrchestrationPaths struct {
	Inventory     string
	Config        string
	GroupVarsAll  string
	GroupVarsK8s  string
}

// Resolve resolves all template paths based on master config
func (r *PathResolver) Resolve(masterConfig *config.MasterConfig) (*TemplatePaths, error) {
	paths := &TemplatePaths{}

	// Infrastructure template path (skip if platform is "none")
	platform := masterConfig.Infrastructure.Platform
	provider := masterConfig.Infrastructure.Provider
	if platform != "none" {
		paths.Infrastructure = filepath.Join(
			r.RepoRoot,
			"api", "templates", "infrastructure",
			platform, provider, "terraform.tfvars.tmpl",
		)
	}

	// Container orchestration template paths
	orchestrator := masterConfig.ContainerOrchestration.Orchestrator
	switch orchestrator {
	case "kubespray":
		paths.ContainerOrchestration = ContainerOrchestrationPaths{
			Inventory: filepath.Join(
				r.RepoRoot,
				"api", "templates", "container-orchestration",
				"kubespray", "inventory.ini.tmpl",
			),
			GroupVarsAll: filepath.Join(
				r.RepoRoot,
				"api", "templates", "container-orchestration",
				"kubespray", "group_vars", "all.yaml.tmpl",
			),
			GroupVarsK8s: filepath.Join(
				r.RepoRoot,
				"api", "templates", "container-orchestration",
				"kubespray", "group_vars", "k8s_cluster.yaml.tmpl",
			),
		}
	case "kubekey":
		paths.ContainerOrchestration = ContainerOrchestrationPaths{
			Config: filepath.Join(
				r.RepoRoot,
				"api", "templates", "container-orchestration",
				orchestrator, "config.yaml.tmpl",
			),
		}
	case "kind":
		paths.ContainerOrchestration = ContainerOrchestrationPaths{
			Config: filepath.Join(
				r.RepoRoot,
				"api", "templates", "container-orchestration",
				"kind", "config-simple.yaml.tmpl",
			),
		}
	default:
		return nil, fmt.Errorf("unsupported orchestrator: %s", orchestrator)
	}

	// Provisioner template path
	paths.Provisioner = filepath.Join(
		r.RepoRoot,
		"api", "templates", "provisioner", "provisioner.json.tmpl",
	)

	// Platform template path
	paths.Platform = filepath.Join(
		r.RepoRoot,
		"api", "templates", "platform", "platform.yaml.tmpl",
	)

	// Business template path
	paths.Business = filepath.Join(
		r.RepoRoot,
		"api", "templates", "business", "business.yaml.tmpl",
	)

	return paths, nil
}

// OutputPaths holds all output file paths for an environment
type OutputPaths struct {
	OutputDir                string
	Metadata                 string
	Infrastructure           string
	ContainerOrchestration   ContainerOrchestrationOutputs
	Provisioner              string
	Platform                 string
	Business                 string
}

// ContainerOrchestrationOutputs holds orchestrator-specific output paths
type ContainerOrchestrationOutputs struct {
	Directory    string
	Inventory    string
	Config       string
	GroupVarsDir string
	GroupVarsAll string
	GroupVarsK8s string
}

// ResolveOutputPaths resolves all output file paths for an environment
func (r *PathResolver) ResolveOutputPaths(environment string, orchestrator string) *OutputPaths {
	outputDir := filepath.Join(r.RepoRoot, "api", "outputs", environment)

	paths := &OutputPaths{
		OutputDir:      outputDir,
		Metadata:       filepath.Join(outputDir, "metadata.json"),
		Infrastructure: filepath.Join(outputDir, "terraform.tfvars"),
		Provisioner:    filepath.Join(outputDir, "provisioner.json"),
		Platform:       filepath.Join(outputDir, "platform.yaml"),
		Business:       filepath.Join(outputDir, "business.yaml"),
	}

	// Container orchestration outputs
	switch orchestrator {
	case "kubespray":
		kubesprayDir := filepath.Join(outputDir, "kubespray")
		groupVarsDir := filepath.Join(kubesprayDir, "group_vars")
		paths.ContainerOrchestration = ContainerOrchestrationOutputs{
			Directory:    kubesprayDir,
			Inventory:    filepath.Join(kubesprayDir, "inventory.ini"),
			GroupVarsDir: groupVarsDir,
			GroupVarsAll: filepath.Join(groupVarsDir, "all.yaml"),
			GroupVarsK8s: filepath.Join(groupVarsDir, "k8s_cluster.yaml"),
		}
	case "kubekey":
		paths.ContainerOrchestration = ContainerOrchestrationOutputs{
			Config: filepath.Join(outputDir, "kubekey", "config.yaml"),
		}
	case "kind":
		paths.ContainerOrchestration = ContainerOrchestrationOutputs{
			Config: filepath.Join(outputDir, "kind", "config.yaml"),
		}
	}

	return paths
}
