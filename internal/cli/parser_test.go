package cli

import (
	"bytes"
	"strings"
	"testing"
)

func TestRunParserErrorsSanitizeTerminalControls(t *testing.T) {
	for _, args := range [][]string{{"search", "coffee", "--bad\x1b[31m"}, {"bad\u202ecommand"}} {
		var stdout, stderr bytes.Buffer
		if code := Run(args, &stdout, &stderr); code == 0 {
			t.Fatal("expected parse error")
		}
		for _, output := range []string{stdout.String(), stderr.String()} {
			if strings.ContainsAny(output, "\x1b\u202e") {
				t.Fatalf("unsafe diagnostic: %q", output)
			}
		}
		if !strings.Contains(stderr.String(), "bad") {
			t.Fatalf("missing diagnostic: %q", stderr.String())
		}
	}
}
