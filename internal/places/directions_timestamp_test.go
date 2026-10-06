package places

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestDirectionsRejectsNonRFC3339BeforeHTTP(t *testing.T) {
	for _, value := range []string{
		"2030-05-10T8:57:00Z",
		"2030-05-10T18:57:00,123Z",
		"2030-05-10T18:57:00+24:00",
		"2030-05-10T18:57:00+00:60",
	} {
		for _, field := range []string{"departure_time", "arrival_time"} {
			t.Run(field+"/"+value, func(t *testing.T) {
				requests := 0
				server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
					requests++
					_, _ = w.Write([]byte(`{"routes":[{"legs":[{"duration":"60s"}]}]}`))
				}))
				defer server.Close()
				req := DirectionsRequest{From: "A", To: "B", Mode: "transit"}
				if field == "departure_time" {
					req.DepartureTime = value
				} else {
					req.ArrivalTime = value
				}
				client := NewClient(Options{APIKey: "fixture-key", DirectionsBaseURL: server.URL})
				_, err := client.Directions(context.Background(), req)
				var validation ValidationError
				if !errors.As(err, &validation) || validation.Field != field {
					t.Errorf("expected %s validation, got %v", field, err)
				}
				if requests != 0 {
					t.Errorf("invalid timestamp reached HTTP server: %d requests", requests)
				}
			})
		}
	}
}

func TestDirectionsAcceptsRFC3339TimestampForms(t *testing.T) {
	for _, value := range []string{
		"2030-05-10T18:57:00Z",
		"2030-05-10T18:57:00.123456789Z",
		"2030-05-10T18:57:00-03:30",
		"2030-05-10T18:57:00+05:45",
		"2030-05-10T18:57:00-00:00",
	} {
		req := applyDirectionsDefaults(DirectionsRequest{From: "A", To: "B", DepartureTime: value})
		if err := validateDirectionsRequest(req); err != nil {
			t.Errorf("valid timestamp %q rejected: %v", value, err)
		}
	}
}
