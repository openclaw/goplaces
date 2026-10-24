package cli

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func TestRunAPIKeyFile(t *testing.T) {
	for _, tc := range []struct {
		name     string
		contents string
		env      string
		unsetEnv bool
		flags    []string
		wantKey  string
	}{
		{name: "file only", contents: "synthetic-file-key", unsetEnv: true, flags: []string{"--api-key-file", "FILE"}, wantKey: "synthetic-file-key"},
		{name: "LF overrides env", contents: "synthetic-file-key\n", env: "synthetic-env-key", flags: []string{"--api-key-file", "FILE"}, wantKey: "synthetic-file-key"},
		{name: "CRLF equals syntax", contents: "synthetic-file-key\r\n", env: "synthetic-env-key", flags: []string{"--api-key-file=FILE"}, wantKey: "synthetic-file-key"},
		{name: "env unchanged without file", env: "synthetic-env-key", wantKey: "synthetic-env-key"},
		{name: "explicit key overrides env", env: "synthetic-env-key", flags: []string{"--api-key", "synthetic-flag-key"}, wantKey: "synthetic-flag-key"},
		{name: "explicit equals key", unsetEnv: true, flags: []string{"--api-key=synthetic-flag-key"}, wantKey: "synthetic-flag-key"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Setenv("GOOGLE_PLACES_API_KEY", tc.env)
			if tc.unsetEnv {
				if err := os.Unsetenv("GOOGLE_PLACES_API_KEY"); err != nil {
					t.Fatal(err)
				}
			}
			path := writeAPIKeyFile(t, tc.contents)
			requests := make(chan string, 1)
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.URL.Path != placesSearchPath {
					t.Errorf("unexpected path: %s", r.URL.Path)
				}
				assertAPIKeyEnv(t, tc.env, !tc.unsetEnv)
				requests <- r.Header.Get("X-Goog-Api-Key")
				_, _ = w.Write([]byte(`{"places":[{"id":"offline-proof"}]}`))
			}))
			defer server.Close()

			flags := make([]string, 0, len(tc.flags))
			for _, flag := range tc.flags {
				flags = append(flags, strings.ReplaceAll(flag, "FILE", path))
			}
			// Exercise global flags before the command and equals/space syntax.
			args := append(flags, "search", "coffee", "--base-url", server.URL, "--json")
			var stdout, stderr bytes.Buffer
			if code := Run(args, &stdout, &stderr); code != 0 {
				t.Fatalf("exit %d: %s", code, stderr.String())
			}
			select {
			case got := <-requests:
				if got != tc.wantKey {
					t.Fatal("request did not use the selected synthetic key")
				}
			default:
				t.Fatal("missing offline request")
			}
			if !strings.Contains(stdout.String(), "offline-proof") || stderr.Len() != 0 {
				t.Fatalf("unexpected output: stdout=%s stderr=%s", &stdout, &stderr)
			}
			assertAPIKeyEnv(t, tc.env, !tc.unsetEnv)
			for _, key := range []string{"synthetic-file-key", "synthetic-env-key", "synthetic-flag-key"} {
				if strings.Contains(stdout.String()+stderr.String(), key) {
					t.Fatal("key leaked into CLI output")
				}
			}
		})
	}
}

func TestRunAPIKeyFileFailures(t *testing.T) {
	for _, tc := range []struct {
		name     string
		contents string
		flags    []string
		want     string
	}{
		{name: "empty", flags: []string{"--api-key-file", "FILE"}, want: "--api-key-file is empty; populate it with an API key"},
		{name: "whitespace", contents: " \r\n\t", flags: []string{"--api-key-file=FILE"}, want: "--api-key-file is empty; populate it with an API key"},
		{name: "missing", flags: []string{"--api-key-file", "MISSING"}, want: "cannot read --api-key-file; select a readable plain-text API key file"},
		{name: "directory", flags: []string{"--api-key-file", "DIR"}, want: "cannot read --api-key-file; select a readable plain-text API key file"},
		{name: "empty path", flags: []string{"--api-key-file="}, want: "cannot read --api-key-file; select a readable plain-text API key file"},
		{name: "unreadable", contents: "synthetic-file-key", flags: []string{"--api-key-file", "FILE"}, want: "cannot read --api-key-file; select a readable plain-text API key file"},
		{name: "explicit conflict", contents: "synthetic-file-key", flags: []string{"--api-key", "synthetic-flag-key", "--api-key-file", "FILE"}, want: "--api-key and --api-key-file cannot be used together"},
		{name: "equals reverse conflict", contents: "synthetic-file-key", flags: []string{"--api-key-file=FILE", "--api-key=synthetic-flag-key"}, want: "--api-key and --api-key-file cannot be used together"},
		{name: "explicit empty key conflict", contents: "synthetic-file-key", flags: []string{"--api-key=", "--api-key-file=FILE"}, want: "--api-key and --api-key-file cannot be used together"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Setenv("GOOGLE_PLACES_API_KEY", "synthetic-env-key")
			path := writeAPIKeyFile(t, tc.contents)
			if tc.name == "unreadable" {
				if runtime.GOOS == "windows" {
					t.Skip("POSIX permission bits do not prevent reads on Windows")
				}
				if err := os.Chmod(path, 0); err != nil {
					t.Fatal(err)
				}
				t.Cleanup(func() {
					if err := os.Chmod(path, 0o600); err != nil {
						t.Error(err)
					}
				})
				if _, err := os.ReadFile(path); err == nil {
					t.Skip("current user can read mode 000 files")
				}
			}
			requests := make(chan struct{}, 1)
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				requests <- struct{}{}
				_, _ = w.Write([]byte(`{"places":[]}`))
			}))
			defer server.Close()
			args := []string{"search", "coffee", "--base-url", server.URL, "--json"}
			replacer := strings.NewReplacer("MISSING", path+"-missing", "DIR", filepath.Dir(path), "FILE", path)
			for _, flag := range tc.flags {
				args = append(args, replacer.Replace(flag))
			}
			var stdout, stderr bytes.Buffer
			if code := Run(args, &stdout, &stderr); code != 2 {
				t.Fatalf("expected exit 2, got %d", code)
			}
			if stdout.Len() != 0 || stderr.String() != tc.want+"\n" {
				t.Fatalf("unexpected output: stdout=%s stderr=%s", &stdout, &stderr)
			}
			select {
			case <-requests:
				t.Fatal("failed file input fell back to env and made a request")
			default:
			}
			assertAPIKeyEnv(t, "synthetic-env-key", true)
		})
	}
}

func writeAPIKeyFile(t *testing.T, contents string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "synthetic-key")
	if err := os.WriteFile(path, []byte(contents), 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

func assertAPIKeyEnv(t *testing.T, want string, present bool) {
	t.Helper()
	if got, exists := os.LookupEnv("GOOGLE_PLACES_API_KEY"); got != want || exists != present {
		t.Error("API key environment was mutated")
	}
}
