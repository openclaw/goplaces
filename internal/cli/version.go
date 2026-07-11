package cli

import (
	"fmt"
	"runtime/debug"
	"strings"

	"github.com/alecthomas/kong"
)

const (
	modulePath    = "github.com/steipete/goplaces"
	devVersion    = "dev"
	vcsSettingKey = "vcs"
)

// Version is the CLI version string set by GoReleaser for official archives.
var Version = devVersion

func currentVersion() string {
	info, ok := debug.ReadBuildInfo()
	if !ok {
		info = nil
	}
	return resolveVersion(Version, info)
}

func resolveVersion(linkedVersion string, info *debug.BuildInfo) string {
	if linkedVersion != "" && linkedVersion != devVersion {
		return linkedVersion
	}
	if info == nil || info.Main.Path != modulePath ||
		!strings.HasPrefix(info.Main.Version, "v") {
		return devVersion
	}
	// Module installs have no repository VCS settings. Go 1.26 can assign a
	// pseudo-version to local VCS builds, which must continue to report dev.
	for _, setting := range info.Settings {
		if setting.Key == vcsSettingKey || strings.HasPrefix(setting.Key, vcsSettingKey+".") {
			return devVersion
		}
	}
	return strings.TrimPrefix(info.Main.Version, "v")
}

// VersionFlag prints the version and exits.
type VersionFlag string

// Decode is a no-op for the boolean version flag.
func (v VersionFlag) Decode(_ *kong.DecodeContext) error { return nil }

// IsBool marks the version flag as boolean.
func (v VersionFlag) IsBool() bool { return true }

// BeforeApply prints the version and exits.
func (v VersionFlag) BeforeApply(app *kong.Kong, vars kong.Vars) error {
	_, _ = fmt.Fprintln(app.Stdout, vars["version"])
	app.Exit(0)
	return nil
}
