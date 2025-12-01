package main

import (
	"fmt"
	"os"

	"pn-infra/api/internal/commands"
)

func main() {
	if len(os.Args) < 2 {
		commands.PrintUsage()
		os.Exit(1)
	}

	rt, err := commands.NewRuntime()
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to initialize runtime: %v\n", err)
		os.Exit(1)
	}

	var cmdErr error

	switch os.Args[1] {
	case "validate":
		cmdErr = commands.RunValidate(rt, os.Args[2:])
	case "generate":
		cmdErr = commands.RunGenerate(rt, os.Args[2:])
	case "provision":
		cmdErr = commands.RunProvision(rt, os.Args[2:])
	case "help", "--help", "-h":
		commands.PrintUsage()
	default:
		cmdErr = fmt.Errorf("unknown command: %s", os.Args[1])
	}

	if cmdErr != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", cmdErr)
		os.Exit(1)
	}
}
