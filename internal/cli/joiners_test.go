package cli

import (
	"bytes"
	"strings"
	"testing"

	"github.com/steipete/goplaces"
)

func TestRenderSearchPreservesUnicodeShapingJoiners(t *testing.T) {
	name := "👩\u200d🔬 می\u200cخواهم"
	output := renderSearch(NewColor(false), goplaces.SearchResponse{Results: []goplaces.PlaceSummary{{Name: name, Address: "👩\u200d🔬"}}})
	if !strings.Contains(output, name) {
		t.Fatalf("name changed: %q", output)
	}
	if strings.Count(output, "\u200d") != 2 {
		t.Fatalf("address joiner lost: %q", output)
	}
}

func TestRenderJoinersStillRemovesTerminalAndBidiControls(t *testing.T) {
	name := "👩\u200d🔬 safe\u202egnirts\u2066\u200b\ufeff\x1b[31m\x07"
	output := renderSearch(NewColor(false), goplaces.SearchResponse{Results: []goplaces.PlaceSummary{{Name: name}}})
	if !strings.Contains(output, "👩\u200d🔬") {
		t.Fatalf("emoji shaping lost: %q", output)
	}
	if strings.ContainsAny(output, "\u202e\u2066\u200b\ufeff\x1b\x07") {
		t.Fatalf("unsafe display controls: %q", output)
	}
}

func TestErrorSanitizerKeepsStrictFormatBoundary(t *testing.T) {
	var buffer bytes.Buffer
	writeError(&buffer, "safe\u200c\u200d\u202e\u2066\u200b\ufeff\x1b")
	output := buffer.String()
	if output != "safe\n" {
		t.Fatalf("error sanitizer changed: %q", output)
	}
}
