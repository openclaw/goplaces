package cli

import "testing"

func TestColorEmptyNoColorDoesNotDisable(t *testing.T) {
	t.Setenv("TERM", "xterm-256color")
	t.Setenv("NO_COLOR", "")
	if !colorEnabled(false) {
		t.Fatal("empty NO_COLOR must not disable color")
	}
	if colorEnabled(true) {
		t.Fatal("explicit --no-color must remain authoritative")
	}
}

func TestColorNonemptyNoColorDisables(t *testing.T) {
	for _, value := range []string{"1", "0", "false", " "} {
		t.Run(value, func(t *testing.T) {
			t.Setenv("TERM", "xterm-256color")
			t.Setenv("NO_COLOR", value)
			if colorEnabled(false) {
				t.Fatal("nonempty NO_COLOR must disable color regardless of value")
			}
		})
	}
}
