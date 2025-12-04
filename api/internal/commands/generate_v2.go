package commands

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"pn-infra/api/internal/config"
	"pn-infra/api/internal/template"
)

// generateEnvV2 is the refactored version using master config pattern
func (rt *Runtime) generateEnvV2(args []string) error {
	fs := flag.NewFlagSet("generate env", flag.ContinueOnError)
	envID := fs.String("id", "", "environment identifier (e.g., development)")
	configPackage := fs.String("config", "core", "config package identifier")
	skipValidate := fs.Bool("skip-validate", false, "skip schema/definition validation")
	validateOnly := fs.Bool("validate-only", false, "only validate without generating")

	if err := fs.Parse(args); err != nil {
		return err
	}

	if *envID == "" {
		return errors.New("missing required --id flag")
	}

	fmt.Printf("Generating artifacts for environment: %s\n", *envID)
	fmt.Printf("Using config package: %s\n", *configPackage)

	// Step 1: Load and merge configuration
	fmt.Println("\n[1/7] Loading configuration...")
	loader := config.NewLoader(rt.RepoRoot, *configPackage, *envID)
	mergedConfig, err := loader.LoadAndMerge()
	if err != nil {
		return fmt.Errorf("load configuration: %w", err)
	}
	fmt.Printf("  ✓ Master config loaded (platform: %s, orchestrator: %s)\n",
		mergedConfig.Infrastructure.Platform,
		mergedConfig.ContainerOrchestration.Orchestrator)
	fmt.Printf("  ✓ Loaded %d hosts\n", len(mergedConfig.Hosts))

	// Step 2: Validate environment overrides (if not skipped)
	if !*skipValidate {
		fmt.Println("\n[2/7] Validating environment overrides...")
		if err := rt.validateEnvironments(*envID); err != nil {
			return fmt.Errorf("validation failed: %w", err)
		}
		fmt.Println("  ✓ Environment validation passed")
	} else {
		fmt.Println("\n[2/7] Skipping validation (--skip-validate)")
	}

	if *validateOnly {
		fmt.Println("\nValidation complete (--validate-only)")
		return nil
	}

	// Step 3: Resolve template paths
	fmt.Println("\n[3/7] Resolving template paths...")
	pathResolver := template.NewPathResolver(rt.RepoRoot)
	templatePaths, err := pathResolver.Resolve(&mergedConfig.MasterConfig)
	if err != nil {
		return fmt.Errorf("resolve template paths: %w", err)
	}
	fmt.Printf("  ✓ Infrastructure template: %s\n", filepath.Base(templatePaths.Infrastructure))
	fmt.Printf("  ✓ Orchestrator templates: %s\n", mergedConfig.ContainerOrchestration.Orchestrator)

	// Step 4: Resolve output paths
	fmt.Println("\n[4/7] Resolving output paths...")
	outputPaths := pathResolver.ResolveOutputPaths(*envID, mergedConfig.ContainerOrchestration.Orchestrator)
	if err := os.MkdirAll(outputPaths.OutputDir, 0755); err != nil {
		return fmt.Errorf("create output directory: %w", err)
	}
	fmt.Printf("  ✓ Output directory: %s\n", outputPaths.OutputDir)

	// Step 5: Render templates
	fmt.Println("\n[5/7] Rendering templates...")
	renderer := template.NewRenderer(rt.RepoRoot)

	// Render infrastructure template (skip if platform is "none")
	if templatePaths.Infrastructure != "" {
		if err := renderer.RenderToFile(templatePaths.Infrastructure, outputPaths.Infrastructure, mergedConfig); err != nil {
			return fmt.Errorf("render infrastructure template: %w", err)
		}
		fmt.Printf("  ✓ Generated: %s\n", filepath.Base(outputPaths.Infrastructure))
	} else {
		fmt.Printf("  ⊘ Skipped: Infrastructure (platform=none)\n")
	}

	// Render container orchestration templates
	switch mergedConfig.ContainerOrchestration.Orchestrator {
	case "kubespray":
		if err := os.MkdirAll(outputPaths.ContainerOrchestration.GroupVarsDir, 0755); err != nil {
			return fmt.Errorf("create group_vars directory: %w", err)
		}
		if err := renderer.RenderToFile(templatePaths.ContainerOrchestration.Inventory,
			outputPaths.ContainerOrchestration.Inventory, mergedConfig); err != nil {
			return fmt.Errorf("render kubespray inventory: %w", err)
		}
		if err := renderer.RenderToFile(templatePaths.ContainerOrchestration.GroupVarsAll,
			outputPaths.ContainerOrchestration.GroupVarsAll, mergedConfig); err != nil {
			return fmt.Errorf("render kubespray group_vars/all: %w", err)
		}
		if err := renderer.RenderToFile(templatePaths.ContainerOrchestration.GroupVarsK8s,
			outputPaths.ContainerOrchestration.GroupVarsK8s, mergedConfig); err != nil {
			return fmt.Errorf("render kubespray group_vars/k8s_cluster: %w", err)
		}
		fmt.Printf("  ✓ Generated: kubespray/inventory.ini\n")
		fmt.Printf("  ✓ Generated: kubespray/group_vars/all.yaml\n")
		fmt.Printf("  ✓ Generated: kubespray/group_vars/k8s_cluster.yaml\n")
	case "kubekey", "kind":
		if err := os.MkdirAll(filepath.Dir(outputPaths.ContainerOrchestration.Config), 0755); err != nil {
			return fmt.Errorf("create orchestrator directory: %w", err)
		}
		if err := renderer.RenderToFile(templatePaths.ContainerOrchestration.Config,
			outputPaths.ContainerOrchestration.Config, mergedConfig); err != nil {
			return fmt.Errorf("render %s config: %w", mergedConfig.ContainerOrchestration.Orchestrator, err)
		}
		fmt.Printf("  ✓ Generated: %s/config.yaml\n", mergedConfig.ContainerOrchestration.Orchestrator)
	}

	// Render provisioner template
	if err := renderer.RenderToFile(templatePaths.Provisioner, outputPaths.Provisioner, mergedConfig); err != nil {
		return fmt.Errorf("render provisioner template: %w", err)
	}
	fmt.Printf("  ✓ Generated: %s\n", filepath.Base(outputPaths.Provisioner))

	// Render platform template
	if err := renderer.RenderToFile(templatePaths.Platform, outputPaths.Platform, mergedConfig); err != nil {
		return fmt.Errorf("render platform template: %w", err)
	}
	fmt.Printf("  ✓ Generated: %s\n", filepath.Base(outputPaths.Platform))

	// Render business template
	if err := renderer.RenderToFile(templatePaths.Business, outputPaths.Business, mergedConfig); err != nil {
		return fmt.Errorf("render business template: %w", err)
	}
	fmt.Printf("  ✓ Generated: %s\n", filepath.Base(outputPaths.Business))

	// Step 6: Generate kubesprayConfig.json for compatibility
	fmt.Println("\n[6/7] Generating compatibility artifacts...")
	if mergedConfig.ContainerOrchestration.Orchestrator == "kubespray" {
		kubesprayConfig := map[string]interface{}{
			"image": map[string]string{
				"registry": "quay.io",
				"version":  "v2.28.1",
			},
			"ssh": map[string]interface{}{
				"keyPath": mergedConfig.SSH.KeyPath,
				"user":    mergedConfig.SSH.User,
				"port":    mergedConfig.SSH.Port,
			},
		}
		kubesprayConfigPath := filepath.Join(outputPaths.OutputDir, "kubesprayConfig.json")
		if err := writeJSONFile(kubesprayConfigPath, kubesprayConfig); err != nil {
			return fmt.Errorf("write kubesprayConfig.json: %w", err)
		}
		fmt.Printf("  ✓ Generated: kubesprayConfig.json\n")
	}

	// Step 7: Generate metadata.json
	fmt.Println("\n[7/7] Generating metadata...")
	metadata := map[string]interface{}{
		"environment": *envID,
		"configPackage": map[string]string{
			"id":      *configPackage,
			"version": "v1.0.0",
		},
		"generatedAt": time.Now().UTC().Format(time.RFC3339),
		"masterConfig": map[string]interface{}{
			"platform":     mergedConfig.Infrastructure.Platform,
			"provider":     mergedConfig.Infrastructure.Provider,
			"orchestrator": mergedConfig.ContainerOrchestration.Orchestrator,
		},
		"files": map[string]string{
			"infrastructure":           outputPaths.Infrastructure,
			"provisioner":              outputPaths.Provisioner,
			"platform":                 outputPaths.Platform,
			"business":                 outputPaths.Business,
			"orchestrator_inventory":   outputPaths.ContainerOrchestration.Inventory,
			"orchestrator_config":      outputPaths.ContainerOrchestration.Config,
			"orchestrator_group_vars":  outputPaths.ContainerOrchestration.GroupVarsDir,
		},
	}

	if err := writeJSONFile(outputPaths.Metadata, metadata); err != nil {
		return fmt.Errorf("write metadata.json: %w", err)
	}
	fmt.Printf("  ✓ Generated: metadata.json\n")

	fmt.Printf("\n✅ Environment '%s' artifacts generated successfully!\n", *envID)
	fmt.Printf("📁 Output directory: %s\n", outputPaths.OutputDir)

	return nil
}

// validateEnvironments validates environment override files against schemas
func (rt *Runtime) validateEnvironments(envID string) error {
	// TODO: Implement schema validation using api/schemas/environments/*.yaml
	// For now, just check if files exist
	modules := []string{"infrastructure", "container-orchestration", "platform", "provisioner", "business"}

	for _, module := range modules {
		envPath := filepath.Join(rt.RepoRoot, module, "environments", fmt.Sprintf("%s.yaml", envID))
		if _, err := os.Stat(envPath); err == nil {
			// File exists - in a full implementation, validate against schema
			fmt.Printf("  • Checking %s environment override... ", module)
			fmt.Println("(schema validation not yet implemented)")
		}
	}

	return nil
}

// writeJSONFile writes data as formatted JSON to a file
func writeJSONFile(path string, data interface{}) error {
	file, err := os.Create(path)
	if err != nil {
		return fmt.Errorf("create file: %w", err)
	}
	defer file.Close()

	encoder := json.NewEncoder(file)
	encoder.SetIndent("", "  ")
	return encoder.Encode(data)
}
