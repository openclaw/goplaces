package places

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestPhotoMediaSuccess(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/places/place-1/photos/photo-1/media" {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		query := r.URL.Query()
		if query.Get("skipHttpRedirect") != "true" {
			t.Fatalf("unexpected skipHttpRedirect: %s", query.Get("skipHttpRedirect"))
		}
		if query.Get("maxWidthPx") != "800" {
			t.Fatalf("unexpected maxWidthPx: %s", query.Get("maxWidthPx"))
		}
		if query.Get("maxHeightPx") != "600" {
			t.Fatalf("unexpected maxHeightPx: %s", query.Get("maxHeightPx"))
		}
		_, _ = w.Write([]byte(`{"name": "places/place-1/photos/photo-1", "photoUri": "https://example.com/photo.jpg"}`))
	}))
	defer server.Close()

	client := NewClient(Options{APIKey: "test-key", BaseURL: server.URL + "/v1"})
	response, err := client.PhotoMedia(context.Background(), PhotoMediaRequest{
		Name:        "places/place-1/photos/photo-1",
		MaxWidthPx:  800,
		MaxHeightPx: 600,
	})
	if err != nil {
		t.Fatalf("photo media error: %v", err)
	}
	if response.PhotoURI == "" {
		t.Fatalf("expected photo uri")
	}
}

func TestPhotoMediaNormalizesMediaName(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.EscapedPath() != "/v1/places/place%20id/photos/photo%20id/media" {
			t.Fatalf("unexpected path: %s", r.URL.EscapedPath())
		}
		_, _ = w.Write([]byte(`{"name": "places/place id/photos/photo id", "photoUri": "https://example.com/photo.jpg"}`))
	}))
	defer server.Close()

	client := NewClient(Options{APIKey: "test-key", BaseURL: server.URL + "/v1"})
	response, err := client.PhotoMedia(context.Background(), PhotoMediaRequest{
		Name:       "/places/place id/photos/photo id/media",
		MaxWidthPx: 800,
	})
	if err != nil {
		t.Fatalf("photo media error: %v", err)
	}
	if response.PhotoURI == "" {
		t.Fatalf("expected photo uri")
	}
}

func TestPhotoMediaValidation(t *testing.T) {
	requests := []PhotoMediaRequest{
		{Name: "places/place-1/photos/photo-1"},
		{Name: "places/place-1/photos/photo-1", MaxWidthPx: -1},
		{Name: "places/place-1/photos/photo-1", MaxHeightPx: -1},
		{Name: "places/place-1/photos/photo-1", MaxWidthPx: maxPhotoDimensionPx + 1},
		{Name: "places/place-1/photos/photo-1", MaxHeightPx: maxPhotoDimensionPx + 1},
		{Name: "place-1/photos/photo-1", MaxWidthPx: 800},
		{Name: "places/place-1/photos/photo-1/media/media", MaxWidthPx: 800},
	}
	client := NewClient(Options{APIKey: "test-key", BaseURL: "http://example.com"})
	for _, request := range requests {
		_, err := client.PhotoMedia(context.Background(), request)
		var validationErr ValidationError
		if !errors.As(err, &validationErr) {
			t.Fatalf("expected validation error for %#v, got %v", request, err)
		}
	}
}
