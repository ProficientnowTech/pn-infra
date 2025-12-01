package commands

import (
	"errors"
	"flag"
	"fmt"
	"os/exec"
	"path/filepath"
	"strings"
)

// RunValidate dispatches to specific validation routines.
func RunValidate(rt *Runtime, args []string) error {
	fs := flag.NewFlagSet("validate", flag.ContinueOnError)
	target := fs.String("target", "definitions", "validation target (definitions)")

	if err := fs.Parse(args); err != nil {
		return err
	}

	switch *target {
	case "definitions":
		return rt.validateDefinitions()
	default:
		return fmt.Errorf("unsupported validation target: %s", *target)
	}
}

func (rt *Runtime) validateDefinitions() error {
	if _, err := exec.LookPath("yaml-validator-cli"); err != nil {
		return errors.New("yaml-validator-cli not found; install via `cargo install yaml-validator-cli`")
	}

	baseDir := filepath.Join(rt.RepoRoot, "api", "definitions")
	schemaDir := filepath.Join(rt.RepoRoot, "api", "schemas")
	metadataSchema := filepath.Join(schemaDir, "metadata.schema.yml")

	targets := []struct {
		name       string
		dir        string
		schema     string
		schemaName string
	}{
		{"sizes", filepath.Join(baseDir, "sizes"), filepath.Join(schemaDir, "size.schema.yml"), "sizes_schema"},
		{"roles", filepath.Join(baseDir, "roles"), filepath.Join(schemaDir, "role.schema.yml"), "roles_schema"},
		{"vlans", filepath.Join(baseDir, "vlans"), filepath.Join(schemaDir, "vlan.schema.yml"), "vlans_schema"},
		{"disks", filepath.Join(baseDir, "disks"), filepath.Join(schemaDir, "disk.schema.yml"), "disks_schema"},
	}

	for _, target := range targets {
		if err := rt.validateDefinitionDir(target.dir, target.schema, metadataSchema, target.schemaName); err != nil {
			return fmt.Errorf("%s: %w", target.name, err)
		}
	}

	fmt.Println("Definitions validated successfully.")
	return nil
}

func (rt *Runtime) validateDefinitionDir(dir, schema, metadataSchema, schemaName string) error {
	files, err := filepath.Glob(filepath.Join(dir, "*.yml"))
	if err != nil {
		return fmt.Errorf("list files in %s: %w", dir, err)
	}

	if len(files) == 0 {
		fmt.Printf("warning: no definition files found in %s\n", dir)
		return nil
	}

	for _, file := range files {
		if err := runYamlValidator(schema, metadataSchema, schemaName, file); err != nil {
			return err
		}
	}
	return nil
}

func runYamlValidator(schema, metadataSchema, schemaName, file string) error {
	cmd := exec.Command(
		"yaml-validator-cli",
		"-s", schema, metadataSchema,
		"-u", schemaName,
		file,
	)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("validation failed for %s: %s", file, strings.TrimSpace(string(output)))
	}
	fmt.Printf("validated %s\n", file)
	return nil
}
