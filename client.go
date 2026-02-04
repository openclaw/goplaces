// Package goplaces provides a Go client for the Google Places API (New).
package goplaces

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// DefaultBaseURL is the default endpoint for the Places API (New).
const DefaultBaseURL = "https://places.googleapis.com/v1"

// Client wraps access to the Google Places API.
type Client struct {
	apiKey            string
	baseURL           string
	routesBaseURL     string
	directionsBaseURL string
	httpClient        *http.Client
}

// Options configures the Places client.
type Options struct {
	APIKey            string
	BaseURL           string
	RoutesBaseURL     string
	DirectionsBaseURL string
	HTTPClient        *http.Client
	Timeout           time.Duration
}

// NewClient builds a client with sane defaults.
func NewClient(opts Options) *Client {
	baseURL := strings.TrimRight(opts.BaseURL, "/")
	if baseURL == "" {
		baseURL = DefaultBaseURL
	}
	routesBaseURL := strings.TrimRight(opts.RoutesBaseURL, "/")
	if routesBaseURL == "" {
		routesBaseURL = defaultRoutesBaseURL
	}
	directionsBaseURL := strings.TrimRight(opts.DirectionsBaseURL, "/")
	if directionsBaseURL == "" {
		directionsBaseURL = defaultDirectionsBaseURL
	}

	client := opts.HTTPClient
	if client == nil {
		timeout := opts.Timeout
		if timeout == 0 {
			timeout = 10 * time.Second
		}
		client = &http.Client{Timeout: timeout}
	}

	return &Client{
		apiKey:            opts.APIKey,
		baseURL:           baseURL,
		routesBaseURL:     routesBaseURL,
		directionsBaseURL: directionsBaseURL,
		httpClient:        client,
	}
}

func (c *Client) doRequest(
	ctx context.Context,
	method string,
	endpoint string,
	body any,
	fieldMask string,
) ([]byte, error) {
	if strings.TrimSpace(c.apiKey) == "" {
		return nil, ErrMissingAPIKey
	}

	var reader io.Reader
	if body != nil {
		payload, err := json.Marshal(body)
		if err != nil {
			return nil, fmt.Errorf("goplaces: encode request: %w", err)
		}
		reader = bytes.NewReader(payload)
	}

	request, err := http.NewRequestWithContext(ctx, method, endpoint, reader)
	if err != nil {
		return nil, fmt.Errorf("goplaces: build request: %w", err)
	}

	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("X-Goog-Api-Key", c.apiKey)
	// Field masks trim API payloads and keep responses fast/cheap.
	if strings.TrimSpace(fieldMask) != "" {
		request.Header.Set("X-Goog-FieldMask", fieldMask)
	}

	response, err := c.httpClient.Do(request)
	if err != nil {
		return nil, fmt.Errorf("goplaces: request failed: %w", err)
	}
	defer func() {
		_ = response.Body.Close()
	}()

	// Hard-cap payload size to avoid runaway error bodies.
	payload, err := io.ReadAll(io.LimitReader(response.Body, 1<<20))
	if err != nil {
		return nil, fmt.Errorf("goplaces: read response: %w", err)
	}

	if response.StatusCode >= http.StatusBadRequest {
		apiErr := &APIError{StatusCode: response.StatusCode, Body: strings.TrimSpace(string(payload))}
		return nil, apiErr
	}

	if len(payload) == 0 {
		return nil, errors.New("goplaces: empty response")
	}

	return payload, nil
}

func (c *Client) buildURL(path string, query map[string]string) (string, error) {
	endpoint := c.baseURL + path
	if len(query) == 0 {
		return endpoint, nil
	}

	parsed, err := url.Parse(endpoint)
	if err != nil {
		return "", fmt.Errorf("goplaces: invalid url: %w", err)
	}

	values := parsed.Query()
	for key, value := range query {
		if strings.TrimSpace(value) == "" {
			continue
		}
		values.Set(key, value)
	}
	parsed.RawQuery = values.Encode()
	return parsed.String(), nil
}
