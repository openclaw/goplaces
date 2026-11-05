package cli

import (
	"errors"
	"io"
	"os"
	"runtime"
	"strings"

	"github.com/alecthomas/kong"
)

func (g *GlobalOptions) loadAPIKeyFile(ctx *kong.Context) error {
	var keyFlag, fileFlag bool
	for _, path := range ctx.Path {
		// Resolved values (including inherited env) are not explicit flags.
		if path.Flag == nil || path.Resolved {
			continue
		}
		switch path.Flag.Name {
		case "api-key":
			keyFlag = true
		case "api-key-file":
			fileFlag = true
		}
	}
	if !fileFlag {
		return nil
	}
	if keyFlag {
		return errors.New("--api-key and --api-key-file cannot be used together")
	}
	if runtime.GOOS == "windows" {
		return errors.New("--api-key-file requires POSIX file permissions; use --api-key or GOOGLE_PLACES_API_KEY on Windows")
	}
	const readError = "cannot read --api-key-file; select a readable plain-text API key file"
	info, err := os.Stat(g.APIKeyFile)
	if err != nil || !info.Mode().IsRegular() {
		return errors.New(readError)
	}
	file, err := os.Open(g.APIKeyFile)
	if err != nil {
		return errors.New(readError)
	}
	defer func() { _ = file.Close() }()
	// Check the opened file so a pathname swap cannot bypass the mode check.
	info, err = file.Stat()
	if err != nil || !info.Mode().IsRegular() {
		return errors.New(readError)
	}
	if info.Mode().Perm()&0o077 != 0 {
		return errors.New("--api-key-file must be a private regular file; use chmod 0600")
	}
	contents, err := io.ReadAll(file)
	if err != nil {
		return errors.New(readError)
	}
	key := strings.TrimSpace(string(contents))
	if key == "" {
		return errors.New("--api-key-file is empty; populate it with an API key")
	}
	g.APIKey = key
	return nil
}
