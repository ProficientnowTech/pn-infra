package commands

import (
	"errors"
	"fmt"
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
	// Use the new V2 implementation with master config pattern
	return rt.generateEnvV2(args)
}

// Legacy code removed - see generate_v2.go for new implementation
