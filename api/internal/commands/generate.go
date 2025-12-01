package commands

import (
	"errors"
	"flag"
	"fmt"
	"path/filepath"
	"time"
)

// RunGenerate handles artifact generation commands (envs, inventories, etc.).
func RunGenerate(rt *Runtime, args []string) error {
	if len(args) == 0 {
		return errors.New("generate command requires a subcommand (env)")
	}

	switch args[0] {
	case "env":
		return rt.generateEnv(args[1:])
	default:
		return fmt.Errorf("unknown generate subcommand: %s", args[0])
	}
}

func (rt *Runtime) generateEnv(args []string) error {
	fs := flag.NewFlagSet("generate env", flag.ContinueOnError)
	envID := fs.String("id", "", "environment identifier (e.g., development)")
	configPackage := fs.String("config", "core", "config package identifier")

	if err := fs.Parse(args); err != nil {
		return err
	}

	if *envID == "" {
		return errors.New("missing required --id flag")
	}

	manifest, err := loadConfigPackage(rt.RepoRoot, *configPackage)
	if err != nil {
		return err
	}

	envFiles, ok := manifest.EnvFiles[*envID]
	if !ok {
		return fmt.Errorf("environment %s not found in config package %s", *envID, *configPackage)
	}

	outputDir := filepath.Join(rt.RepoRoot, "api", "outputs", *envID)
	if err := ensureDir(outputDir); err != nil {
		return err
	}

	for key, relPath := range envFiles {
		src := filepath.Join(manifest.PackagePath, relPath)
		dst := filepath.Join(outputDir, fmt.Sprintf("%s.yml", key))
		if err := copyFile(src, dst); err != nil {
			return err
		}
		fmt.Printf("generated %s -> %s\n", key, dst)
	}

	metadata := map[string]any{
		"environment": *envID,
		"configPackage": map[string]string{
			"id":      manifest.ID,
			"version": manifest.Version,
		},
		"generatedAt": time.Now().UTC().Format(time.RFC3339),
	}

	if err := writeJSON(filepath.Join(outputDir, "metadata.json"), metadata); err != nil {
		return err
	}

	fmt.Printf("environment %s artifacts generated under %s\n", *envID, outputDir)
	return nil
}

type packageManifest struct {
	ID          string                       `json:"id"`
	Version     string                       `json:"version"`
	Description string                       `json:"description"`
	Envs        []packageEnvironment         `json:"environments"`
	EnvFiles    map[string]map[string]string `json:"-"`
	PackagePath string                       `json:"-"`
}

type packageEnvironment struct {
	Name  string            `json:"name"`
	Files map[string]string `json:"files"`
}

func loadConfigPackage(repoRoot, pkgID string) (*packageManifest, error) {
	path := filepath.Join(repoRoot, "config", "packages", pkgID)
	manifestPath := filepath.Join(path, "package.json")

	var manifest packageManifest
	if err := readJSON(manifestPath, &manifest); err != nil {
		return nil, fmt.Errorf("read manifest: %w", err)
	}

	manifest.EnvFiles = make(map[string]map[string]string)
	for _, env := range manifest.Envs {
		manifest.EnvFiles[env.Name] = env.Files
	}
	manifest.PackagePath = path
	return &manifest, nil
}
