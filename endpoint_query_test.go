package goplaces

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestPlacesEndpointOverridePreservesProxyQuery(t *testing.T) {
	paths := []string{}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		paths = append(paths, r.URL.EscapedPath())
		if r.URL.Query().Get("tenant") != "one & two" || r.URL.Query().Get("access") != "fixture" {
			t.Errorf("proxy query corrupted: %s", r.URL.RawQuery)
		}
		switch r.URL.EscapedPath() {
		case "/v1/places:searchText":
			_, _ = w.Write([]byte(`{"places":[]}`))
		case "/v1/places/has%3Fquery":
			if r.URL.Query().Get("languageCode") != "en" {
				t.Errorf("locale missing: %s", r.URL.RawQuery)
			}
			_, _ = w.Write([]byte(`{"id":"has?query"}`))
		case "/v1/places/has%3Fquery/photos/has%23fragment/media":
			if r.URL.Query().Get("maxWidthPx") != "100" || r.URL.Query().Get("skipHttpRedirect") != "true" {
				t.Errorf("photo params missing: %s", r.URL.RawQuery)
			}
			_, _ = w.Write([]byte(`{"photoUri":"https://fixture.invalid/photo"}`))
		default:
			t.Errorf("endpoint appended outside path: %s", r.URL.String())
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer server.Close()
	client := NewClient(Options{APIKey: "test-key", BaseURL: server.URL + "/v1/?tenant=one%20%26%20two&access=fixture"})
	if _, err := client.Search(context.Background(), SearchRequest{Query: "coffee"}); err != nil {
		t.Errorf("search: %v", err)
	}
	if _, err := client.DetailsWithOptions(context.Background(), DetailsRequest{PlaceID: "has?query", Language: "en"}); err != nil {
		t.Errorf("details: %v", err)
	}
	if _, err := client.PhotoMedia(context.Background(), PhotoMediaRequest{Name: "places/has?query/photos/has#fragment", MaxWidthPx: 100}); err != nil {
		t.Errorf("photo: %v", err)
	}
	if len(paths) != 3 {
		t.Fatalf("requests: %#v", paths)
	}
}

func TestDirectionsEndpointOverridePreservesQueryAndCompletePath(t *testing.T) {
	for _, path := range []string{"/proxy", "/proxy/directions/v2:computeRoutes"} {
		t.Run(path, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.URL.Path != "/proxy/directions/v2:computeRoutes" {
					t.Errorf("endpoint path = %s", r.URL.Path)
				}
				if r.URL.Query().Get("tenant") != "one/" {
					t.Errorf("query changed: %s", r.URL.RawQuery)
				}
				_, _ = w.Write([]byte(`{"routes":[{"legs":[{"duration":"60s"}]}]}`))
			}))
			defer server.Close()
			_, err := NewClient(Options{APIKey: "test-key", DirectionsBaseURL: server.URL + path + "?tenant=one/"}).Directions(context.Background(), DirectionsRequest{From: "A", To: "B"})
			if err != nil {
				t.Fatal(err)
			}
		})
	}
}

func TestPlacesEndpointOverrideRetainsEscapedProxyPath(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.EscapedPath() != "/tenant%2Fone/places/has%3Fquery" {
			t.Errorf("escaped path changed: %s", r.URL.EscapedPath())
		}
		if r.URL.Query().Get("tenant") != "one/" {
			t.Errorf("trailing slash query changed: %s", r.URL.RawQuery)
		}
		_, _ = w.Write([]byte(`{"id":"has?query"}`))
	}))
	defer server.Close()
	_, err := NewClient(Options{APIKey: "test-key", BaseURL: server.URL + "/tenant%2Fone/?tenant=one/"}).Details(context.Background(), "has?query")
	if err != nil {
		t.Fatal(err)
	}
}
