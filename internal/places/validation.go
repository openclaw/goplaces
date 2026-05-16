package places

import "fmt"

const maxCircleRadiusM = 50000

func validateLocationBias(bias *LocationBias) error {
	return validateCircle(bias, "location_bias")
}

func validateCircle(bias *LocationBias, fieldPrefix string) error {
	if bias == nil {
		return nil
	}
	if bias.RadiusM <= 0 {
		return ValidationError{Field: fieldPrefix + ".radius_m", Message: "must be > 0"}
	}
	if bias.RadiusM > maxCircleRadiusM {
		return ValidationError{Field: fieldPrefix + ".radius_m", Message: fmt.Sprintf("must be <= %d", maxCircleRadiusM)}
	}
	if bias.Lat < -90 || bias.Lat > 90 {
		return ValidationError{Field: fieldPrefix + ".lat", Message: "must be -90..90"}
	}
	if bias.Lng < -180 || bias.Lng > 180 {
		return ValidationError{Field: fieldPrefix + ".lng", Message: "must be -180..180"}
	}
	return nil
}
