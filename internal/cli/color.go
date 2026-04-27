package cli

import (
	"os"
	"strings"
)

// Color renders ANSI color sequences.
type Color struct {
	enabled bool
}

// NewColor returns a color helper, optionally disabled.
func NewColor(enabled bool) Color {
	return Color{enabled: enabled}
}

// Bold wraps a string in bold ANSI codes.
func (c Color) Bold(value string) string {
	return c.wrap("1", value)
}

// Cyan wraps a string in cyan ANSI codes.
func (c Color) Cyan(value string) string {
	return c.wrap("36", value)
}

// Green wraps a string in green ANSI codes.
func (c Color) Green(value string) string {
	return c.wrap("32", value)
}

// Yellow wraps a string in yellow ANSI codes.
func (c Color) Yellow(value string) string {
	return c.wrap("33", value)
}

// Dim wraps a string in dim ANSI codes.
func (c Color) Dim(value string) string {
	return c.wrap("2", value)
}

func (c Color) wrap(code, value string) string {
	if !c.enabled {
		return value
	}
	return "\x1b[" + code + "m" + value + "\x1b[0m"
}

func colorEnabled(noColor bool) bool {
	if noColor {
		return false
	}
	if _, ok := os.LookupEnv("NO_COLOR"); ok {
		return false
	}
	term := strings.TrimSpace(os.Getenv("TERM"))
	if term == "" || term == "dumb" {
		return false
	}
	return true
}
