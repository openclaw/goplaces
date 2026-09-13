package places

import (
	"fmt"
	"math"
)

const (
	payloadFieldAddress       = "address"
	validationFieldFrom       = "from"
	validationFieldLimit      = "limit"
	validationFieldPlaceID    = "place_id"
	validationFieldQuery      = "query"
	validationFieldRadiusM    = "radius_m"
	validationMessageRequired = "required"
)

const maxCircleRadiusM = 50000

func validateLocationBias(bias *LocationBias) error {
	return validateCircle(bias, "location_bias")
}

func validateCircle(bias *LocationBias, fieldPrefix string) error {
	if bias == nil {
		return nil
	}
	if err := validateRadius(bias.RadiusM, fieldPrefix+".radius_m"); err != nil {
		return err
	}
	return validateCoordinates(bias.Lat, bias.Lng, fieldPrefix)
}

func validateRadius(radius float64, field string) error {
	if math.IsNaN(radius) || radius <= 0 {
		return ValidationError{Field: field, Message: "must be > 0"}
	}
	if radius > maxCircleRadiusM {
		return ValidationError{Field: field, Message: fmt.Sprintf("must be <= %d", maxCircleRadiusM)}
	}
	return nil
}

func validateCoordinates(lat, lng float64, fieldPrefix string) error {
	if math.IsNaN(lat) || lat < -90 || lat > 90 {
		return ValidationError{Field: fieldPrefix + ".lat", Message: "must be -90..90"}
	}
	if math.IsNaN(lng) || lng < -180 || lng > 180 {
		return ValidationError{Field: fieldPrefix + ".lng", Message: "must be -180..180"}
	}
	return nil
}
