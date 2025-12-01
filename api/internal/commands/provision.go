package commands

import (
	"errors"
	"flag"
	"fmt"
	"path/filepath"
	"time"
)

// RunProvision triggers provisioning-related commands.
func RunProvision(rt *Runtime, args []string) error {
	if len(args) == 0 {
		return errors.New("provision command requires a subcommand (build)")
	}

	switch args[0] {
	case "build":
		return rt.provisionBuild(args[1:])
	default:
		return fmt.Errorf("unknown provision subcommand: %s", args[0])
	}
}

func (rt *Runtime) provisionBuild(args []string) error {
	fs := flag.NewFlagSet("provision build", flag.ContinueOnError)
	role := fs.String("role", "", "role identifier (e.g., k8s-master)")
	envID := fs.String("env", "", "environment identifier (e.g., development)")
	configPackage := fs.String("config", "core", "config package identifier")

	if err := fs.Parse(args); err != nil {
		return err
	}

	if *role == "" || *envID == "" {
		return errors.New("both --role and --env are required")
	}

	manifest, err := loadConfigPackage(rt.RepoRoot, *configPackage)
	if err != nil {
		return err
	}
	if _, ok := manifest.EnvFiles[*envID]; !ok {
		return fmt.Errorf("environment %s not found in config package %s", *envID, manifest.ID)
	}

	artifactPath := filepath.Join(rt.RepoRoot, "provisioner", "outputs", *envID, fmt.Sprintf("%s.img", *role))
	if err := ensureDir(filepath.Dir(artifactPath)); err != nil {
		return err
	}
	meta := map[string]any{
		"role":        *role,
		"environment": *envID,
		"status":      "pending",
		"artifact":    artifactPath,
		"configPackage": map[string]string{
			"id":      manifest.ID,
			"version": manifest.Version,
		},
		"generatedAt": time.Now().UTC().Format(time.RFC3339),
	}

	outputPath := filepath.Join(rt.RepoRoot, "api", "outputs", *envID, "provisioner", fmt.Sprintf("%s.json", *role))
	if err := writeJSON(outputPath, meta); err != nil {
		return err
	}

	fmt.Printf("provision plan recorded at %s (artifact %s)\n", outputPath, artifactPath)
	fmt.Println("NOTE: hook this metadata up to the provisioner build pipeline to produce real images.")
	return nil
}
