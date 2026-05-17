package goplaces

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"os/exec"
	"strings"
	"testing"
)

func TestFacadeNewClient(t *testing.T) {
	client := NewClient(Options{APIKey: "key"})
	if client == nil {
		t.Fatal("expected client")
	}
}

func TestFacadeZeroClient(t *testing.T) {
	var client Client
	_, err := client.Search(context.Background(), SearchRequest{Query: "coffee"})
	if !errors.Is(err, ErrMissingAPIKey) {
		t.Fatalf("expected missing api key error, got %v", err)
	}
}

func TestFacadeClientSearch(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/places:searchText" {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		_, _ = w.Write([]byte(`{"places": [{"id": "abc", "displayName": {"text": "Cafe"}}]}`))
	}))
	defer server.Close()

	client := NewClient(Options{APIKey: "key", BaseURL: server.URL})
	response, err := client.Search(context.Background(), SearchRequest{Query: "coffee"})
	if err != nil {
		t.Fatalf("search error: %v", err)
	}
	if len(response.Results) != 1 || response.Results[0].PlaceID != "abc" {
		t.Fatalf("unexpected response: %#v", response)
	}
}

func TestFacadeClientSearchGoDoc(t *testing.T) {
	output, err := exec.Command("go", "doc", ".", "Client.Search").CombinedOutput()
	if err != nil {
		t.Fatalf("go doc Client.Search failed: %v\n%s", err, output)
	}
	if !strings.Contains(string(output), "func (c *Client) Search") {
		t.Fatalf("unexpected go doc output: %s", output)
	}
}
