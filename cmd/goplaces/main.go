// Package main implements the goplaces CLI entrypoint.
package main

import (
	"io"
	"os"

	"github.com/steipete/goplaces/internal/cli"
)

var exit = os.Exit

func main() {
	exit(run(os.Args[1:], os.Stdout, os.Stderr))
}

func run(args []string, stdout, stderr io.Writer) int {
	return cli.Run(args, stdout, stderr)
}
