package cli

import "github.com/steipete/goplaces"

func optionalLocationBias(lat, lng, radius *float64) (*goplaces.LocationBias, error) {
	if lat == nil && lng == nil && radius == nil {
		return nil, nil
	}
	if lat == nil || lng == nil || radius == nil {
		return nil, goplaces.ValidationError{Field: "location_bias", Message: locationCoordinatesRequired}
	}
	return &goplaces.LocationBias{Lat: *lat, Lng: *lng, RadiusM: *radius}, nil
}
