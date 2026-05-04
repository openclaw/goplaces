package places

func circlePayload(bias *LocationBias) map[string]any {
	return map[string]any{
		"circle": map[string]any{
			"center": map[string]any{
				"latitude":  bias.Lat,
				"longitude": bias.Lng,
			},
			"radius": bias.RadiusM,
		},
	}
}
