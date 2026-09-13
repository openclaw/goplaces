package places

import (
	"errors"
	"fmt"
	"strings"
)

// ErrMissingAPIKey indicates a missing API key.
var ErrMissingAPIKey = errors.New("goplaces: missing api key")

// ValidationError describes an invalid request payload.
type ValidationError struct {
	Field   string
	Message string
}

func (e ValidationError) Error() string {
	return fmt.Sprintf("goplaces: invalid %s: %s", e.Field, e.Message)
}

// APIError represents an HTTP error from the Places API.
type APIError struct {
	StatusCode int
	Body       string
}

func (e *APIError) Error() string {
	if e.Body == "" {
		return fmt.Sprintf("goplaces: api error (%d)", e.StatusCode)
	}
	return fmt.Sprintf("goplaces: api error (%d): %s", e.StatusCode, e.Body)
}

type clientError struct {
	message string
	cause   error
}

func (e *clientError) Error() string { return e.message }
func (e *clientError) Unwrap() error { return e.cause }

func (c *Client) requestError(action string, err error) error {
	return &clientError{
		message: c.redactAPIKey(fmt.Sprintf("goplaces: %s: %v", action, err)),
		cause:   err,
	}
}

func (c *Client) redactAPIKey(message string) string {
	if c.apiKey == "" {
		return message
	}
	return strings.ReplaceAll(message, c.apiKey, "[REDACTED]")
}
