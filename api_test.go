package goplaces

import "testing"

func TestFacadeNewClient(t *testing.T) {
	client := NewClient(Options{APIKey: "key"})
	if client == nil {
		t.Fatal("expected client")
	}
}
