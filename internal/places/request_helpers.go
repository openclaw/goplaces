package places

import "strings"

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

func setLocale(body map[string]any, language, region string) {
	if language = strings.TrimSpace(language); language != "" {
		body["languageCode"] = language
	}
	if region = strings.TrimSpace(region); region != "" {
		body["regionCode"] = region
	}
}
