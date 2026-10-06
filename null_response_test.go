package goplaces

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestPublicObjectResponsesRejectNullButKeepEmptyObjects(t *testing.T) {
	calls := []struct {
		name string
		call func(*Client) error
	}{
		{"search", func(c *Client) error {
			_, err := c.Search(context.Background(), SearchRequest{Query: "coffee"})
			return err
		}},
		{"autocomplete", func(c *Client) error {
			_, err := c.Autocomplete(context.Background(), AutocompleteRequest{Input: "coffee"})
			return err
		}},
		{"nearby", func(c *Client) error {
			_, err := c.NearbySearch(context.Background(), NearbySearchRequest{LocationRestriction: &LocationBias{Lat: 1, Lng: 2, RadiusM: 100}})
			return err
		}},
		{"resolve", func(c *Client) error {
			_, err := c.Resolve(context.Background(), LocationResolveRequest{LocationText: "coffee"})
			return err
		}},
		{"details", func(c *Client) error { _, err := c.Details(context.Background(), "place"); return err }},
		{"photo", func(c *Client) error {
			_, err := c.PhotoMedia(context.Background(), PhotoMediaRequest{Name: "places/place/photos/photo", MaxWidthPx: 100})
			return err
		}},
	}
	for _, tc := range calls {
		t.Run(tc.name, func(t *testing.T) {
			for _, payload := range []string{"null", " \nnull\t ", "{}"} {
				server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { _, _ = w.Write([]byte(payload)) }))
				client := NewClient(Options{APIKey: "test-key", BaseURL: server.URL})
				err := tc.call(client)
				server.Close()
				if payload == "{}" {
					if err != nil {
						t.Errorf("existing empty object behavior changed: %v", err)
					}
				} else if err == nil || !strings.Contains(err.Error(), "null response") {
					t.Errorf("malformed null object accepted: payload=%q err=%v", payload, err)
				}
			}
		})
	}
}
