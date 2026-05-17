package places

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestDetailsSuccess(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/places/place-123" {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		if r.URL.Query().Get("languageCode") != "en" {
			t.Fatalf("unexpected languageCode: %s", r.URL.Query().Get("languageCode"))
		}
		if r.URL.Query().Get("regionCode") != "US" {
			t.Fatalf("unexpected regionCode: %s", r.URL.Query().Get("regionCode"))
		}
		if r.Header.Get("X-Goog-FieldMask") != detailsFieldMaskBase {
			t.Fatalf("unexpected field mask: %s", r.Header.Get("X-Goog-FieldMask"))
		}
		_, _ = w.Write([]byte(`{
  "id": "place-123",
  "displayName": {"text": "Park"},
  "formattedAddress": "Central",
  "location": {"latitude": 10, "longitude": 20},
  "rating": 4.2,
  "userRatingCount": 1234,
  "priceLevel": "PRICE_LEVEL_FREE",
  "types": ["park"],
  "regularOpeningHours": {"weekdayDescriptions": ["Mon: 9-5"]},
  "currentOpeningHours": {"openNow": false},
  "businessStatus": "CLOSED_TEMPORARILY",
  "nationalPhoneNumber": "+1 555",
  "websiteUri": "https://example.com"
}`))
	}))
	defer server.Close()

	client := NewClient(Options{APIKey: "test-key", BaseURL: server.URL + "/v1"})
	place, err := client.DetailsWithOptions(context.Background(), DetailsRequest{
		PlaceID:  "place-123",
		Language: "en",
		Region:   "US",
	})
	if err != nil {
		t.Fatalf("details error: %v", err)
	}
	if place.PlaceID != "place-123" {
		t.Fatalf("unexpected id: %s", place.PlaceID)
	}
	if place.UserRatingCount == nil || *place.UserRatingCount != 1234 {
		t.Fatalf("unexpected user rating count: %#v", place.UserRatingCount)
	}
	if place.OpenNow == nil || *place.OpenNow != false {
		t.Fatalf("unexpected openNow")
	}
	if place.BusinessStatus != "CLOSED_TEMPORARILY" {
		t.Fatalf("unexpected business status: %s", place.BusinessStatus)
	}
	if len(place.Hours) != 1 {
		t.Fatalf("unexpected hours")
	}
}

func TestDetailsNormalizesPlaceResourceName(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.EscapedPath() != "/v1/places/place%20id" {
			t.Fatalf("unexpected path: %s", r.URL.EscapedPath())
		}
		_, _ = w.Write([]byte(`{"id": "place id"}`))
	}))
	defer server.Close()

	client := NewClient(Options{APIKey: "test-key", BaseURL: server.URL + "/v1"})
	place, err := client.Details(context.Background(), "places/place id")
	if err != nil {
		t.Fatalf("details error: %v", err)
	}
	if place.PlaceID != "place id" {
		t.Fatalf("unexpected id: %s", place.PlaceID)
	}
}

func TestDetailsRejectsInvalidResourceName(t *testing.T) {
	client := NewClient(Options{APIKey: "test-key", BaseURL: "http://example.com"})
	_, err := client.Details(context.Background(), "places/place-123/reviews/1")
	var validationErr ValidationError
	if !errors.As(err, &validationErr) {
		t.Fatalf("expected validation error, got %v", err)
	}
}

func TestDetailsWithReviews(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !strings.Contains(r.Header.Get("X-Goog-FieldMask"), "reviews") {
			t.Fatalf("expected reviews in field mask: %s", r.Header.Get("X-Goog-FieldMask"))
		}
		_, _ = w.Write([]byte(`{
  "id": "place-123",
  "reviews": [
    {
      "name": "places/place-123/reviews/1",
      "rating": 4.5,
      "text": {"text": "Great coffee", "languageCode": "en"},
      "authorAttribution": {"displayName": "Alice", "uri": "https://example.com"},
      "relativePublishTimeDescription": "2 weeks ago",
      "publishTime": "2024-01-01T00:00:00Z",
      "visitDate": {"year": 2024, "month": 1, "day": 2}
    }
  ]
}`))
	}))
	defer server.Close()

	client := NewClient(Options{APIKey: "test-key", BaseURL: server.URL + "/v1"})
	details, err := client.DetailsWithOptions(context.Background(), DetailsRequest{
		PlaceID:        "place-123",
		IncludeReviews: true,
	})
	if err != nil {
		t.Fatalf("details error: %v", err)
	}
	if len(details.Reviews) != 1 {
		t.Fatalf("expected 1 review")
	}
	review := details.Reviews[0]
	if review.Author == nil || review.Author.DisplayName != "Alice" {
		t.Fatalf("unexpected author: %#v", review.Author)
	}
	if review.Text == nil || review.Text.Text != "Great coffee" {
		t.Fatalf("unexpected text: %#v", review.Text)
	}
	if review.VisitDate == nil || review.VisitDate.Year != 2024 {
		t.Fatalf("unexpected visit date: %#v", review.VisitDate)
	}
}

func TestDetailsWithPhotos(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !strings.Contains(r.Header.Get("X-Goog-FieldMask"), "photos") {
			t.Fatalf("expected photos in field mask: %s", r.Header.Get("X-Goog-FieldMask"))
		}
		_, _ = w.Write([]byte(`{
  "id": "place-123",
  "photos": [
    {
      "name": "places/place-123/photos/photo-1",
      "widthPx": 1200,
      "heightPx": 800,
      "authorAttributions": [{"displayName": "Alice", "uri": "https://example.com"}]
    }
  ]
}`))
	}))
	defer server.Close()

	client := NewClient(Options{APIKey: "test-key", BaseURL: server.URL + "/v1"})
	details, err := client.DetailsWithOptions(context.Background(), DetailsRequest{
		PlaceID:       "place-123",
		IncludePhotos: true,
	})
	if err != nil {
		t.Fatalf("details error: %v", err)
	}
	if len(details.Photos) != 1 {
		t.Fatalf("expected 1 photo")
	}
	photo := details.Photos[0]
	if photo.Name == "" || photo.WidthPx != 1200 {
		t.Fatalf("unexpected photo: %#v", photo)
	}
	if len(photo.AuthorAttributions) != 1 {
		t.Fatalf("unexpected photo authors: %#v", photo.AuthorAttributions)
	}
}

func TestDetailsFieldMaskForRequest(t *testing.T) {
	req := DetailsRequest{}
	if got := detailsFieldMaskForRequest(req); got != detailsFieldMaskBase {
		t.Fatalf("unexpected field mask: %s", got)
	}
	req.IncludeReviews = true
	got := detailsFieldMaskForRequest(req)
	if !strings.Contains(got, "reviews") {
		t.Fatalf("expected reviews in field mask: %s", got)
	}
	req = DetailsRequest{IncludePhotos: true}
	got = detailsFieldMaskForRequest(req)
	if !strings.Contains(got, "photos") {
		t.Fatalf("expected photos in field mask: %s", got)
	}
	req = DetailsRequest{IncludeReviews: true, IncludePhotos: true}
	got = detailsFieldMaskForRequest(req)
	if !strings.Contains(got, "reviews") || !strings.Contains(got, "photos") {
		t.Fatalf("expected reviews and photos in field mask: %s", got)
	}
}
