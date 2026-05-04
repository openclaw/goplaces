package places

func validateLocationBias(bias *LocationBias) error {
	if bias == nil {
		return nil
	}
	if bias.RadiusM <= 0 {
		return ValidationError{Field: "location_bias.radius_m", Message: "must be > 0"}
	}
	if bias.Lat < -90 || bias.Lat > 90 {
		return ValidationError{Field: "location_bias.lat", Message: "must be -90..90"}
	}
	if bias.Lng < -180 || bias.Lng > 180 {
		return ValidationError{Field: "location_bias.lng", Message: "must be -180..180"}
	}
	return nil
}
