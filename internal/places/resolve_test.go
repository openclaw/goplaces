package places

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestResolveSuccess(t *testing.T) {
	var gotRequest map[string]any
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("X-Goog-FieldMask") != resolveFieldMask {
			t.Fatalf("unexpected field mask: %s", r.Header.Get("X-Goog-FieldMask"))
		}
		body, err := io.ReadAll(r.Body)
		if err != nil {
			t.Fatalf("read body: %v", err)
		}
		if err := json.Unmarshal(body, &gotRequest); err != nil {
			t.Fatalf("decode body: %v", err)
		}
		_, _ = w.Write([]byte(`{
  "places": [
    {
      "id": "loc-1",
      "displayName": {"text": "Downtown"},
      "formattedAddress": "Main",
      "location": {"latitude": 1, "longitude": 2},
      "types": ["neighborhood"]
    }
  ]
}`))
	}))
	defer server.Close()

	client := NewClient(Options{APIKey: "test-key", BaseURL: server.URL})
	response, err := client.Resolve(context.Background(), LocationResolveRequest{
		LocationText: "Downtown",
		Language:     "en",
		Region:       "US",
	})
	if err != nil {
		t.Fatalf("resolve error: %v", err)
	}
	if len(response.Results) != 1 {
		t.Fatalf("expected 1 result")
	}
	if gotRequest["languageCode"] != "en" {
		t.Fatalf("unexpected languageCode: %#v", gotRequest["languageCode"])
	}
	if gotRequest["regionCode"] != "US" {
		t.Fatalf("unexpected regionCode: %#v", gotRequest["regionCode"])
	}
}
