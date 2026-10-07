package cli

import (
	"bytes"
	"errors"
	"strings"
	"testing"
)

type versionErrorWriter struct{}

func (versionErrorWriter) Write(_ []byte) (int, error) { return 0, errors.New("owned output failure") }

func TestRunVersionOutputFailure(t *testing.T) {
	var stderr bytes.Buffer
	code := Run([]string{"--version"}, versionErrorWriter{}, &stderr)
	if code != 1 || !strings.Contains(stderr.String(), "owned output failure") {
		t.Fatalf("code=%d stderr=%q", code, stderr.String())
	}
}
