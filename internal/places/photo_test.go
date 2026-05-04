package places

import (
	"context"
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
