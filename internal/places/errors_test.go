package places

import (
	"strings"
	"testing"
)

func TestErrorMessages(t *testing.T) {
	validation := ValidationError{Field: "limit", Message: "bad"}
	if !strings.Contains(validation.Error(), "limit") {
		t.Fatalf("unexpected validation error: %s", validation.Error())
	}

	apiErr := &APIError{StatusCode: 500}
	if !strings.Contains(apiErr.Error(), "500") {
		t.Fatalf("unexpected api error: %s", apiErr.Error())
	}

	apiErr = &APIError{StatusCode: 400, Body: "nope"}
	if !strings.Contains(apiErr.Error(), "nope") {
		t.Fatalf("unexpected api error: %s", apiErr.Error())
	}
}
