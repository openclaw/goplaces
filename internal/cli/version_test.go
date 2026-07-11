package cli

import (
	"runtime/debug"
	"testing"
)

func TestResolveVersion(t *testing.T) {
	tests := []struct {
		name          string
		linkedVersion string
		buildInfo     *debug.BuildInfo
		want          string
	}{
		{
			name:          "linked release wins",
			linkedVersion: "0.4.5",
			buildInfo: &debug.BuildInfo{
				Main: debug.Module{Path: "example.com/not-goplaces", Version: "v9.9.9"},
				Settings: []debug.BuildSetting{
					{Key: "vcs", Value: "git"},
					{Key: "vcs.modified", Value: "true"},
				},
			},
			want: "0.4.5",
		},
		{
			name:          "go install module fallback",
			linkedVersion: devVersion,
			buildInfo: buildInfo("v0.4.5",
				debug.BuildSetting{Key: "GOOS", Value: "darwin"},
				debug.BuildSetting{Key: "GOARCH", Value: "arm64"}),
			want: "0.4.5",
		},
		{name: "empty linker fallback", buildInfo: buildInfo("v0.4.5"), want: "0.4.5"},
		{name: "local devel build", linkedVersion: devVersion, buildInfo: buildInfo("(devel)"), want: devVersion},
		{
			name:          "local clean VCS build",
			linkedVersion: devVersion,
			buildInfo: buildInfo("v0.4.5-0.20260704050654-fff3de820f27",
				debug.BuildSetting{Key: vcsSettingKey, Value: "git"},
				debug.BuildSetting{Key: "vcs.modified", Value: "false"}),
			want: devVersion,
		},
		{
			name:          "local dirty VCS build",
			linkedVersion: devVersion,
			buildInfo: buildInfo("v0.4.5-0.20260704050654-fff3de820f27",
				debug.BuildSetting{Key: "vcs.modified", Value: "true"}),
			want: devVersion,
		},
		{
			name:          "bare VCS setting",
			linkedVersion: devVersion,
			buildInfo: buildInfo("v0.4.5",
				debug.BuildSetting{Key: vcsSettingKey, Value: "git"}),
			want: devVersion,
		},
		{
			name:          "wrong module",
			linkedVersion: devVersion,
			buildInfo: &debug.BuildInfo{Main: debug.Module{
				Path:    "example.com/not-goplaces",
				Version: "v0.4.5",
			}},
			want: devVersion,
		},
		{name: "missing metadata", want: devVersion},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := resolveVersion(tt.linkedVersion, tt.buildInfo); got != tt.want {
				t.Fatalf("resolveVersion(%q, %#v) = %q, want %q", tt.linkedVersion, tt.buildInfo, got, tt.want)
			}
		})
	}
}

func buildInfo(version string, settings ...debug.BuildSetting) *debug.BuildInfo {
	return &debug.BuildInfo{
		GoVersion: "go1.26.5",
		Path:      "github.com/steipete/goplaces/cmd/goplaces",
		Main: debug.Module{
			Path:    modulePath,
			Version: version,
		},
		Settings: settings,
	}
}
