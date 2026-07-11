package main

import (
	"bytes"
	"os"
	"strings"
	"testing"
)

func TestRunVersion(t *testing.T) {
	var stdout bytes.Buffer
	var stderr bytes.Buffer

	code := run([]string{"--version"}, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("expected exit code 0, got %d", code)
	}
	if strings.TrimSpace(stdout.String()) != "dev" {
		t.Fatalf("unexpected version output: %s", stdout.String())
	}
	if stderr.Len() != 0 {
		t.Fatalf("unexpected stderr: %s", stderr.String())
	}
}

func TestMain(t *testing.T) {
	prevExit := exit
	prevArgs := os.Args
	defer func() {
		exit = prevExit
		os.Args = prevArgs
	}()

	var gotCode int
	exit = func(code int) { gotCode = code }
	os.Args = []string{"goplaces", "--version"}

	main()
	if gotCode != 0 {
		t.Fatalf("expected exit code 0, got %d", gotCode)
	}
}
