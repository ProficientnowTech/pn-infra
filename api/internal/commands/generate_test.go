package commands

import (
	"os"
	"path/filepath"
	"testing"
)

func TestGenerateEnvCopiesFilesAndWritesMetadata(t *testing.T) {
	repo := t.TempDir()
	configDir := filepath.Join(repo, "config", "packages", "core", "environments")
	if err := os.MkdirAll(configDir, 0o755); err != nil {
		t.Fatalf("mkdir configs: %v", err)
	}

	srcFile := filepath.Join(configDir, "development.ansible.yml")
	if err := os.WriteFile(srcFile, []byte("ansible: {}"), 0o644); err != nil {
		t.Fatalf("write source file: %v", err)
	}

	manifestDir := filepath.Join(repo, "config", "packages", "core")
	if err := os.MkdirAll(manifestDir, 0o755); err != nil {
		t.Fatalf("mkdir manifest dir: %v", err)
	}
	manifestJSON := `{
  "id": "core",
  "version": "v0.0.1",
  "description": "test manifest",
  "environments": [
    {
      "name": "development",
      "files": {
        "ansible": "environments/development.ansible.yml"
      }
    }
  ]
}`
	if err := os.WriteFile(filepath.Join(manifestDir, "package.json"), []byte(manifestJSON), 0o644); err != nil {
		t.Fatalf("write manifest: %v", err)
	}

	rt := &Runtime{RepoRoot: repo}
	if err := rt.generateEnv([]string{"--id", "development", "--config", "core", "--skip-validate"}); err != nil {
		t.Fatalf("generateEnv failed: %v", err)
	}

	outputFile := filepath.Join(repo, "api", "outputs", "development", "ansible.yml")
	if _, err := os.Stat(outputFile); err != nil {
		t.Fatalf("expected output file %s: %v", outputFile, err)
	}

	metaPath := filepath.Join(repo, "api", "outputs", "development", "metadata.json")
	var meta envMetadata
	if err := readJSON(metaPath, &meta); err != nil {
		t.Fatalf("read metadata: %v", err)
	}
	if meta.Files["ansible"] != outputFile {
		t.Fatalf("metadata pointing to %s, expected %s", meta.Files["ansible"], outputFile)
	}
}
