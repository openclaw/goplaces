package cli

import (
	"bytes"
	"strings"
	"testing"
)

func TestRunRejectsNegativeTimeoutBeforeRequest(t *testing.T) {
	for _, timeout := range []string{"-1ns", "-10s", "-24h"} {
		t.Run(timeout, func(t *testing.T) {
			var out, diagnostics bytes.Buffer
			code := Run([]string{"search", "coffee", "--timeout=" + timeout, "--api-key=test", "--base-url=http://127.0.0.1:1"}, &out, &diagnostics)
			if code != 2 || !strings.Contains(diagnostics.String(), "timeout") || out.Len() != 0 {
				t.Fatalf("code=%d stdout=%q diagnostics=%q", code, out.String(), diagnostics.String())
			}
		})
	}
}

func TestRunAcceptsNonnegativeTimeout(t *testing.T) {
	for _, timeout := range []string{"0s", "1ns", "10s"} {
		t.Run(timeout, func(t *testing.T) {
			t.Setenv("GOOGLE_PLACES_API_KEY", "")
			var out, diagnostics bytes.Buffer
			code := Run([]string{"search", "coffee", "--timeout=" + timeout}, &out, &diagnostics)
			if code != 2 || !strings.Contains(diagnostics.String(), "api key") || strings.Contains(diagnostics.String(), "timeout") || out.Len() != 0 {
				t.Fatalf("code=%d stdout=%q diagnostics=%q", code, out.String(), diagnostics.String())
			}
		})
	}
}
