package commands

import (
	"encoding/json"
	"fmt"
	"io"
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
