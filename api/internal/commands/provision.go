package commands

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
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

	meta, err := loadEnvMetadata(rt.RepoRoot, *envID)
	if err != nil {
		return fmt.Errorf("load environment outputs: %w", err)
	}

	if meta.ConfigPackage.ID != *configPackage {
		fmt.Printf("warning: metadata references package %s but --config %s was provided\n", meta.ConfigPackage.ID, *configPackage)
	}

	provPath, ok := meta.Files["provisioner"]
	if !ok {
		return errors.New("provisioner config not generated; run `api generate env` first")
	}

	cfg, err := loadProvisionerConfig(provPath)
	if err != nil {
		return err
	}

	roleCfg, ok := cfg.DynamicConfig.Roles[*role]
	if !ok {
		return fmt.Errorf("role %s not defined in provisioner config", *role)
	}

	localDir := cfg.Artifacts.Local.Directory
	if localDir == "" {
		localDir = filepath.Join("provisioner", "outputs")
	}
	artifactDir := filepath.Join(rt.RepoRoot, localDir, *envID)
	if err := ensureDir(artifactDir); err != nil {
		return err
	}

	artifactPath := filepath.Join(artifactDir, fmt.Sprintf("%s.img", *role))
	payload := fmt.Sprintf("role=%s\npackages=%v\nbuilt_at=%s\n", *role, roleCfg.Packages, time.Now().UTC().Format(time.RFC3339))
	if err := os.WriteFile(artifactPath, []byte(payload), 0o644); err != nil {
		return fmt.Errorf("write artifact %s: %w", artifactPath, err)
	}

	checksum, err := fileChecksum(artifactPath)
	if err != nil {
		return err
	}

	remoteKey := ""
	if cfg.Artifacts.Remote.Prefix != "" {
		remoteKey = filepath.ToSlash(filepath.Join(cfg.Artifacts.Remote.Prefix, filepath.Base(artifactPath)))
	}

	outputPath := filepath.Join(rt.RepoRoot, "api", "outputs", *envID, "provisioner", fmt.Sprintf("%s.json", *role))
	if err := ensureDir(filepath.Dir(outputPath)); err != nil {
		return err
	}

	metaPayload := map[string]any{
		"role":           *role,
		"environment":    *envID,
		"status":         "complete",
		"artifact":       artifactPath,
		"artifactFormat": cfg.StaticConfig["artifactFormat"],
		"artifactChecksum": map[string]string{
			"type":  "sha256",
			"value": checksum,
		},
		"configPackage": map[string]string{
			"id":      meta.ConfigPackage.ID,
			"version": meta.ConfigPackage.Version,
		},
		"generatedAt": time.Now().UTC().Format(time.RFC3339),
		"build": map[string]any{
			"hostnamePrefix": roleCfg.HostnamePrefix,
			"packages":       roleCfg.Packages,
		},
		"remoteStorage": map[string]any{
			"enabled":          cfg.Artifacts.Remote.Enabled,
			"bucket":           cfg.Artifacts.Remote.Bucket,
			"prefix":           cfg.Artifacts.Remote.Prefix,
			"objectKey":        remoteKey,
			"uploaded":         false,
			"uploadPreparedAt": time.Now().UTC().Format(time.RFC3339),
		},
	}

	if err := writeJSON(outputPath, metaPayload); err != nil {
		return err
	}

	fmt.Printf("provision artifact ready at %s (metadata %s)\n", artifactPath, outputPath)
	return nil
}

func loadProvisionerConfig(path string) (*provisionerConfig, error) {
	var cfg provisionerConfig
	if err := readJSON(path, &cfg); err != nil {
		return nil, fmt.Errorf("read provisioner config %s: %w", path, err)
	}
	return &cfg, nil
}

func fileChecksum(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", fmt.Errorf("open artifact for checksum: %w", err)
	}
	defer f.Close()

	hasher := sha256.New()
	if _, err := io.Copy(hasher, f); err != nil {
		return "", fmt.Errorf("hash artifact: %w", err)
	}

	return hex.EncodeToString(hasher.Sum(nil)), nil
}

type provisionerConfig struct {
	StaticConfig  map[string]any `yaml:"staticConfig"`
	DynamicConfig struct {
		Roles map[string]provisionerRole `yaml:"roles"`
	} `yaml:"dynamicConfig"`
	Artifacts struct {
		Local struct {
			Directory string `yaml:"directory"`
		} `yaml:"local"`
		Remote struct {
			Enabled bool   `yaml:"enabled"`
			Bucket  string `yaml:"bucket"`
			Prefix  string `yaml:"prefix"`
		} `yaml:"remote"`
	} `yaml:"artifacts"`
}

type provisionerRole struct {
	HostnamePrefix string            `yaml:"hostnamePrefix"`
	Packages       []string          `yaml:"packages"`
	Filesystems    map[string]string `yaml:"filesystems"`
}
