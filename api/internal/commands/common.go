package commands

import (
	"encoding/json"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
)

// PrintUsage prints the top-level CLI help text.
func PrintUsage() {
	fmt.Println(`Usage: api <command> [options]

Commands:
  validate     Run schema/definition validation
  generate     Generate artifacts (env configs, inventories, etc.)
  provision    Orchestrate provisioner builds

Run "api <command> --help" for command-specific options.`)
}

func ensureDir(path string) error {
	return os.MkdirAll(path, 0o755)
}

func copyFile(src, dst string) error {
	if err := ensureDir(filepath.Dir(dst)); err != nil {
		return err
	}

	in, err := os.Open(src)
	if err != nil {
		return fmt.Errorf("open source %s: %w", src, err)
	}
	defer in.Close()

	out, err := os.Create(dst)
	if err != nil {
		return fmt.Errorf("create destination %s: %w", dst, err)
	}
	defer out.Close()

	if _, err := io.Copy(out, in); err != nil {
		return fmt.Errorf("copy data from %s to %s: %w", src, dst, err)
	}

	return out.Sync()
}

func writeJSON(path string, data any) error {
	if err := ensureDir(filepath.Dir(path)); err != nil {
		return err
	}

	file, err := os.Create(path)
	if err != nil {
		return fmt.Errorf("create %s: %w", path, err)
	}
	defer file.Close()

	enc := json.NewEncoder(file)
	enc.SetIndent("", "  ")
	return enc.Encode(data)
}

func readJSON(path string, target any) error {
	file, err := os.Open(path)
	if err != nil {
		return fmt.Errorf("open %s: %w", path, err)
	}
	defer file.Close()

	dec := json.NewDecoder(file)
	return dec.Decode(target)
}

func removeIfExists(path string) error {
	if _, err := os.Stat(path); err == nil {
		return os.RemoveAll(path)
	}
	return nil
}

func copyDir(src, dst string) error {
	if err := ensureDir(dst); err != nil {
		return err
	}

	return filepath.WalkDir(src, func(path string, entry fs.DirEntry, err error) error {
		if err != nil {
			return err
		}

		rel, err := filepath.Rel(src, path)
		if err != nil {
			return err
		}

		target := filepath.Join(dst, rel)
		if rel == "." {
			return nil
		}

		if entry.IsDir() {
			return ensureDir(target)
		}
		return copyFile(path, target)
	})
}

func copyPath(src, dst string) error {
	info, err := os.Stat(src)
	if err != nil {
		return fmt.Errorf("stat %s: %w", src, err)
	}

	if info.IsDir() {
		if err := removeIfExists(dst); err != nil {
			return err
		}
		return copyDir(src, dst)
	}
	return copyFile(src, dst)
}

type metadataPackageRef struct {
	ID      string `json:"id"`
	Version string `json:"version"`
}

type envMetadata struct {
	Environment   string             `json:"environment"`
	ConfigPackage metadataPackageRef `json:"configPackage"`
	GeneratedAt   string             `json:"generatedAt"`
	Files         map[string]string  `json:"files"`
}

func loadEnvMetadata(repoRoot, envID string) (*envMetadata, error) {
	metaPath := filepath.Join(repoRoot, "api", "outputs", envID, "metadata.json")
	var meta envMetadata
	if err := readJSON(metaPath, &meta); err != nil {
		return nil, fmt.Errorf("read metadata %s: %w", metaPath, err)
	}
	return &meta, nil
}
