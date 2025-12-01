package commands

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
)

// Runtime carries resolved paths that commands rely on.
type Runtime struct {
	RepoRoot string
}

// NewRuntime walks up from the current working directory until it finds the git root.
func NewRuntime() (*Runtime, error) {
	wd, err := os.Getwd()
	if err != nil {
		return nil, fmt.Errorf("determine working directory: %w", err)
	}

	dir := wd
	for {
		if fileExists(filepath.Join(dir, ".git")) {
			return &Runtime{RepoRoot: dir}, nil
		}

		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}

	return nil, errors.New("unable to locate repository root (no .git directory found)")
}

func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}
