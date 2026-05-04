package places

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"strings"
)

// PhotoMedia fetches a photo URL for a photo resource name.
func (c *Client) PhotoMedia(ctx context.Context, req PhotoMediaRequest) (PhotoMediaResponse, error) {
	name := strings.TrimSpace(req.Name)
	if name == "" {
		return PhotoMediaResponse{}, ValidationError{Field: "name", Message: "required"}
	}

	path := "/" + strings.TrimPrefix(name, "/") + "/media"
	query := map[string]string{"skipHttpRedirect": "true"}
	if req.MaxWidthPx > 0 {
		query["maxWidthPx"] = strconv.Itoa(req.MaxWidthPx)
	}
	if req.MaxHeightPx > 0 {
		query["maxHeightPx"] = strconv.Itoa(req.MaxHeightPx)
	}

	endpoint, err := c.buildURL(path, query)
	if err != nil {
		return PhotoMediaResponse{}, err
	}

	payload, err := c.doRequest(ctx, http.MethodGet, endpoint, nil, "")
	if err != nil {
		return PhotoMediaResponse{}, err
	}

	var response photoMediaPayload
	if err := json.Unmarshal(payload, &response); err != nil {
		return PhotoMediaResponse{}, fmt.Errorf("goplaces: decode photo media response: %w", err)
	}

	return PhotoMediaResponse(response), nil
}

type photoMediaPayload struct {
	Name     string `json:"name,omitempty"`
	PhotoURI string `json:"photoUri,omitempty"`
}
