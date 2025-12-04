package commands

import (
	"errors"
	"os"
	"path/filepath"
	"testing"
)

func TestValidateDefinitionDirInvokesValidator(t *testing.T) {
	dir := t.TempDir()
	file := filepath.Join(dir, "role.yml")
	if err := os.WriteFile(file, []byte("name: test"), 0o644); err != nil {
		t.Fatalf("write sample file: %v", err)
	}

	called := false
	original := yamlValidator
	yamlValidator = func(schema, metadataSchema, schemaName, candidate string) error {
		called = true
		if candidate != file {
			t.Fatalf("expected %s, got %s", file, candidate)
		}
		return nil
	}
	defer func() { yamlValidator = original }()

	rt := &Runtime{}
	if err := rt.validateDefinitionDir(dir, "schema", "meta", "unit"); err != nil {
		t.Fatalf("validateDefinitionDir returned error: %v", err)
	}

	if !called {
		t.Fatalf("expected validator to be called")
	}
}

func TestValidateDefinitionDirPropagatesError(t *testing.T) {
	dir := t.TempDir()
	file := filepath.Join(dir, "role.yml")
	if err := os.WriteFile(file, []byte("name: test"), 0o644); err != nil {
		t.Fatalf("write sample file: %v", err)
	}

	original := yamlValidator
	yamlValidator = func(_, _, _, _ string) error {
		return errors.New("boom")
	}
	defer func() { yamlValidator = original }()

	rt := &Runtime{}
	if err := rt.validateDefinitionDir(dir, "schema", "meta", "unit"); err == nil {
		t.Fatalf("expected error when validator fails")
	}
}
