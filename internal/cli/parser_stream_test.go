package cli

import (
	"bytes"
	"strings"
	"testing"
)

func TestRunParserErrorsKeepStdoutEmpty(t *testing.T) {
	for _, args := range [][]string{{"--json"}, {"search", "--json"}, {"search", "coffee", "--json", "--limit=invalid"}, {"search", "coffee", "--unknown"}} {
		var stdout, stderr bytes.Buffer
		code := Run(args, &stdout, &stderr)
		if code == 0 {
			t.Fatal("expected parse failure")
		}
		if stdout.Len() != 0 {
			t.Fatalf("parse error contaminated stdout: %q", stdout.String())
		}
		if !strings.Contains(stderr.String(), "Usage:") {
			t.Fatalf("missing usage on stderr: %q", stderr.String())
		}
	}
}

func TestRunHelpKeepsStdout(t *testing.T) {
	var stdout, stderr bytes.Buffer
	if code := Run([]string{"search", "--help"}, &stdout, &stderr); code != 0 {
		t.Fatalf("help code %d", code)
	}
	if !strings.Contains(stdout.String(), "Usage:") || stderr.Len() != 0 {
		t.Fatalf("stdout=%q stderr=%q", stdout.String(), stderr.String())
	}
}
