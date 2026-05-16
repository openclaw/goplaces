package places

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestAutocompleteSuccess(t *testing.T) {
	var gotRequest map[string]any
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			t.Fatalf("expected POST, got %s", r.Method)
		}
		if r.URL.Path != "/v1/places:autocomplete" {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		if r.Header.Get("X-Goog-FieldMask") != autocompleteFieldMask {
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
  "suggestions": [
    {
      "placePrediction": {
        "placeId": "place-1",
        "text": {"text": "Coffee Bar"},
        "structuredFormat": {
          "mainText": {"text": "Coffee"},
          "secondaryText": {"text": "Seattle"}
        },
        "types": ["cafe"]
      }
    },
    {
      "queryPrediction": {
        "text": {"text": "coffee beans"},
        "structuredFormat": {
          "mainText": {"text": "coffee beans"},
          "secondaryText": {"text": "query"}
        }
      }
    }
  ]
}`))
	}))
	defer server.Close()

	client := NewClient(Options{APIKey: "test-key", BaseURL: server.URL + "/v1"})
	response, err := client.Autocomplete(context.Background(), AutocompleteRequest{
		Input:        "cof",
		Limit:        5,
		SessionToken: "session",
		Language:     "en",
		Region:       "US",
		LocationBias: &LocationBias{Lat: 1.1, Lng: 2.2, RadiusM: 100},
	})
	if err != nil {
		t.Fatalf("autocomplete error: %v", err)
	}
	if len(response.Suggestions) != 2 {
		t.Fatalf("expected 2 suggestions, got %d", len(response.Suggestions))
	}
	if response.Suggestions[0].Kind != "place" || response.Suggestions[0].PlaceID != "place-1" {
		t.Fatalf("unexpected place suggestion: %#v", response.Suggestions[0])
	}
	if response.Suggestions[1].Kind != "query" || response.Suggestions[1].Text != "coffee beans" {
		t.Fatalf("unexpected query suggestion: %#v", response.Suggestions[1])
	}

	if gotRequest["input"] != "cof" {
		t.Fatalf("unexpected input: %#v", gotRequest["input"])
	}
	if gotRequest["sessionToken"] != "session" {
		t.Fatalf("unexpected session token: %#v", gotRequest["sessionToken"])
	}
	if gotRequest["languageCode"] != "en" {
		t.Fatalf("unexpected languageCode: %#v", gotRequest["languageCode"])
	}
	if gotRequest["regionCode"] != "US" {
		t.Fatalf("unexpected regionCode: %#v", gotRequest["regionCode"])
	}
	if gotRequest["includeQueryPredictions"] != true {
		t.Fatalf("expected includeQueryPredictions: %#v", gotRequest["includeQueryPredictions"])
	}
	locationBias := gotRequest["locationBias"].(map[string]any)
	if locationBias["circle"] == nil {
		t.Fatalf("missing location bias circle")
	}
}

func TestAutocompleteLimitTrims(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{
  "suggestions": [
    {"queryPrediction": {"text": {"text": "a"}}},
    {"queryPrediction": {"text": {"text": "b"}}}
  ]
}`))
	}))
	defer server.Close()

	client := NewClient(Options{APIKey: "test-key", BaseURL: server.URL})
	response, err := client.Autocomplete(context.Background(), AutocompleteRequest{
		Input: "cof",
		Limit: 1,
	})
	if err != nil {
		t.Fatalf("autocomplete error: %v", err)
	}
	if len(response.Suggestions) != 1 {
		t.Fatalf("expected 1 suggestion, got %d", len(response.Suggestions))
	}
}
