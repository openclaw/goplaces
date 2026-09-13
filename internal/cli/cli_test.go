package cli

import (
	"bytes"
	"encoding/json"
	"errors"
	"math"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/steipete/goplaces"
)

const (
	placesSearchPath         = "/places:searchText"
	placesNearbyPath         = "/places:searchNearby"
	routesComputePath        = "/directions/v2:computeRoutes"
	directionsPath           = routesComputePath
	directionsModeWalkAPI    = "WALK"
	directionsModeDriveAPI   = "DRIVE"
	directionsModeTransitAPI = "TRANSIT"
	directionsModeWalkingAPI = "walking"
)

func TestNormalizeDirectionsMode(t *testing.T) {
	cases := map[string]string{
		"walk":      directionsModeWalkingAPI,
		"walking":   directionsModeWalkingAPI,
		"drive":     directionsModeDriving,
		"driving":   directionsModeDriving,
		"bike":      "bicycling",
		"bicycle":   "bicycling",
		"bicycling": "bicycling",
		"transit":   "transit",
		"plane":     "",
	}
	for input, want := range cases {
		if got := normalizeDirectionsMode(input); got != want {
			t.Fatalf("normalizeDirectionsMode(%q) = %q, want %q", input, got, want)
		}
	}
}

func TestRunVersion(t *testing.T) {
	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run([]string{"--version"}, &stdout, &stderr)
	if exitCode != 0 {
		t.Fatalf("expected exit code 0, got %d", exitCode)
	}
	if strings.TrimSpace(stdout.String()) != devVersion {
		t.Fatalf("unexpected version: %s", stdout.String())
	}
}

func TestRunMissingCommand(t *testing.T) {
	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run([]string{}, &stdout, &stderr)
	if exitCode == 0 {
		t.Fatalf("expected non-zero exit code")
	}
}

func TestRunParseError(t *testing.T) {
	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run([]string{"search", "--api-key", "x"}, &stdout, &stderr)
	if exitCode == 0 {
		t.Fatalf("expected parse error")
	}
}

func TestRunLocationBiasError(t *testing.T) {
	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run([]string{"search", "coffee", "--lat", "1", "--api-key", "x"}, &stdout, &stderr)
	if exitCode != 2 {
		t.Fatalf("expected validation error exit code 2, got %d", exitCode)
	}
}

func TestRunHelp(t *testing.T) {
	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run([]string{"--help"}, &stdout, &stderr)
	if exitCode != 0 {
		t.Fatalf("expected exit code 0, got %d", exitCode)
	}
	if stdout.Len() == 0 {
		t.Fatalf("expected help output")
	}
}

func TestVersionFlagIsBool(t *testing.T) {
	var flag VersionFlag
	if !flag.IsBool() {
		t.Fatalf("expected IsBool true")
	}
}

func TestWriteJSONError(t *testing.T) {
	err := writeJSON(&bytes.Buffer{}, map[string]any{"bad": func() {}})
	if err == nil {
		t.Fatalf("expected json error")
	}
}

func TestWriteJSON(t *testing.T) {
	var out bytes.Buffer
	if err := writeJSON(&out, map[string]string{"ok": "true"}); err != nil {
		t.Fatalf("writeJSON error: %v", err)
	}
	if !strings.Contains(out.String(), "\"ok\"") {
		t.Fatalf("unexpected json output: %s", out.String())
	}
}

func TestHandleError(t *testing.T) {
	if code := handleError(&bytes.Buffer{}, nil); code != 0 {
		t.Fatalf("expected 0")
	}
	if code := handleError(&bytes.Buffer{}, goplaces.ValidationError{Field: "x", Message: "bad"}); code != 2 {
		t.Fatalf("expected validation exit 2")
	}
	if code := handleError(&bytes.Buffer{}, goplaces.ErrMissingAPIKey); code != 2 {
		t.Fatalf("expected missing api key exit 2")
	}
	if code := handleError(&bytes.Buffer{}, errors.New("boom")); code != 1 {
		t.Fatalf("expected generic exit 1")
	}
}

func assertNestedFloat(t *testing.T, payload map[string]any, want float64, path ...string) {
	t.Helper()

	var current any = payload
	for _, key := range path {
		node, ok := current.(map[string]any)
		if !ok {
			t.Fatalf("payload path %v reached non-object %#v", path, current)
		}
		current, ok = node[key]
		if !ok {
			t.Fatalf("payload missing path %v at %q", path, key)
		}
	}

	got, ok := current.(float64)
	if !ok {
		t.Fatalf("payload path %v = %#v, want float64", path, current)
	}
	if math.Abs(got-want) > 1e-9 {
		t.Fatalf("payload path %v = %v, want %v", path, got, want)
	}
}

func TestRunRadiusAliasMatchesRadiusM(t *testing.T) {
	cases := []struct {
		name       string
		path       string
		args       []string
		radiusPath []string
	}{
		{
			name:       "search",
			path:       placesSearchPath,
			args:       []string{"search", "coffee", "--lat", "1", "--lng", "2"},
			radiusPath: []string{"locationBias", "circle", "radius"},
		},
		{
			name:       "autocomplete",
			path:       "/places:autocomplete",
			args:       []string{"autocomplete", "cof", "--lat", "1", "--lng", "2"},
			radiusPath: []string{"locationBias", "circle", "radius"},
		},
		{
			name:       "nearby",
			path:       placesNearbyPath,
			args:       []string{"nearby", "--lat", "1", "--lng", "2"},
			radiusPath: []string{"locationRestriction", "circle", "radius"},
		},
	}

	for _, tc := range cases {
		for _, flag := range []string{"--radius-m", "--radius", "--radius=1500"} {
			t.Run(tc.name+" "+flag, func(t *testing.T) {
				server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
					if r.URL.Path != tc.path {
						t.Errorf("unexpected path: %s", r.URL.Path)
					}
					var payload map[string]any
					if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
						t.Errorf("decode request: %v", err)
						return
					}
					assertNestedFloat(t, payload, 1500, tc.radiusPath...)
					_, _ = w.Write([]byte(`{"places": [{"id": "abc"}]}`))
				}))
				defer server.Close()

				args := append([]string{}, tc.args...)
				if strings.Contains(flag, "=") {
					args = append(args, flag)
				} else {
					args = append(args, flag, "1500")
				}
				args = append(args, "--api-key", "test-key", "--base-url", server.URL, "--json")

				var stdout, stderr bytes.Buffer
				if exitCode := Run(args, &stdout, &stderr); exitCode != 0 {
					t.Fatalf("expected exit code 0, got %d (stderr=%s)", exitCode, stderr.String())
				}
			})
		}
	}
}
