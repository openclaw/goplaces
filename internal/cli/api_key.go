package cli

import (
	"errors"
	"os"
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
	contents, err := os.ReadFile(g.APIKeyFile)
	if err != nil {
		return errors.New("cannot read --api-key-file; select a readable plain-text API key file")
	}
	key := strings.TrimSpace(string(contents))
	if key == "" {
		return errors.New("--api-key-file is empty; populate it with an API key")
	}
	g.APIKey = key
	return nil
}
