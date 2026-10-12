package goplaces

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestDetailsSessionTokenCompletesAutocompletePublicRequests(t *testing.T) {
	const token = "7c9a1efa-0e97-4e8d-af1e-fae4f738467b"
	calls := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		switch r.URL.Path {
		case "/places:autocomplete":
			var body struct {
				SessionToken string `json:"sessionToken"`
			}
			if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
				t.Errorf("decode autocomplete: %v", err)
			}
			if body.SessionToken != token {
				t.Errorf("autocomplete session = %q", body.SessionToken)
			}
			_, _ = w.Write([]byte(`{"suggestions":[{"placePrediction":{"placeId":"selected"}}]}`))
		case "/places/selected":
			if r.URL.Query().Get("sessionToken") != token {
				t.Errorf("details missing matching session: %s", r.URL.RawQuery)
			}
			if r.URL.Query().Get("languageCode") != "en" {
				t.Errorf("locale lost: %s", r.URL.RawQuery)
			}
			_, _ = w.Write([]byte(`{"id":"selected"}`))
		default:
			t.Errorf("unexpected path %s", r.URL.Path)
		}
	}))
	defer server.Close()
	client := NewClient(Options{APIKey: "test-key", BaseURL: server.URL})
	suggestions, err := client.Autocomplete(context.Background(), AutocompleteRequest{Input: "coffee", SessionToken: token})
	if err != nil {
		t.Fatal(err)
	}
	var req DetailsRequest
	if err := json.Unmarshal([]byte(`{"place_id":"`+suggestions.Suggestions[0].PlaceID+`","session_token":"  `+token+`  ","language":"en"}`), &req); err != nil {
		t.Fatal(err)
	}
	details, err := client.DetailsWithOptions(context.Background(), req)
	if err != nil || details.PlaceID != "selected" || calls != 2 {
		t.Fatalf("details=%#v calls=%d err=%v", details, calls, err)
	}
}

func TestDetailsOmitsBlankSessionToken(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if _, ok := r.URL.Query()["sessionToken"]; ok {
			t.Errorf("unexpected empty sessionToken: %s", r.URL.RawQuery)
		}
		_, _ = w.Write([]byte(`{"id":"selected"}`))
	}))
	defer server.Close()
	client := NewClient(Options{APIKey: "test-key", BaseURL: server.URL})
	if _, err := client.Details(context.Background(), "selected"); err != nil {
		t.Fatal(err)
	}
	var req DetailsRequest
	if err := json.Unmarshal([]byte(`{"place_id":"selected","session_token":"   "}`), &req); err != nil {
		t.Fatal(err)
	}
	if _, err := client.DetailsWithOptions(context.Background(), req); err != nil {
		t.Fatal(err)
	}
}
