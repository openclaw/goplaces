package cli

import (
	"fmt"

	"github.com/steipete/goplaces"
)

// validateLimit checks the CLI value before library zero-value defaults apply.
func validateLimit(limit, maximum int) error {
	if limit < 1 || limit > maximum {
		return goplaces.ValidationError{Field: "limit", Message: fmt.Sprintf("must be 1-%d", maximum)}
	}
	return nil
}
