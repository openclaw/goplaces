package places

import (
	"errors"
	"math"
	"sort"
	"strings"
)

const (
	earthRadiusMeters      = 6371000.0
	routePolylinePrecision = 1e5
)

func decodePolyline(encoded string) ([]LatLng, error) {
	if strings.TrimSpace(encoded) == "" {
		return nil, errors.New("goplaces: empty polyline")
	}
	points := make([]LatLng, 0, len(encoded)/4)
	var lat, lng int
	for i := 0; i < len(encoded); {
		var delta int
		var shift uint
		for {
			if i >= len(encoded) {
				return nil, errors.New("goplaces: invalid polyline")
			}
			b := int(encoded[i]) - 63
			i++
			delta |= (b & 0x1f) << shift
			shift += 5
			if b < 0x20 {
				break
			}
		}
		lat += (delta >> 1) ^ (-(delta & 1))

		delta = 0
		shift = 0
		for {
			if i >= len(encoded) {
				return nil, errors.New("goplaces: invalid polyline")
			}
			b := int(encoded[i]) - 63
			i++
			delta |= (b & 0x1f) << shift
			shift += 5
			if b < 0x20 {
				break
			}
		}
		lng += (delta >> 1) ^ (-(delta & 1))

		points = append(points, LatLng{
			Lat: float64(lat) / routePolylinePrecision,
			Lng: float64(lng) / routePolylinePrecision,
		})
	}
	return points, nil
}

func sampleWaypoints(points []LatLng, maxWaypoints int) []LatLng {
	if len(points) == 0 || maxWaypoints <= 0 {
		return nil
	}
	if len(points) == 1 {
		return []LatLng{points[0]}
	}
	if maxWaypoints == 1 {
		return []LatLng{pointAtDistance(points, totalDistance(points)/2)}
	}
	if maxWaypoints >= len(points) {
		return uniqueWaypoints(points)
	}

	cumulative := cumulativeDistances(points)
	total := cumulative[len(cumulative)-1]
	if total == 0 {
		return []LatLng{points[0]}
	}
	spacing := total / float64(maxWaypoints-1)

	sampled := make([]LatLng, 0, maxWaypoints)
	for i := 0; i < maxWaypoints; i++ {
		target := spacing * float64(i)
		point := pointAtCumulative(points, cumulative, target)
		if len(sampled) == 0 || !samePoint(sampled[len(sampled)-1], point) {
			sampled = append(sampled, point)
		}
	}
	return sampled
}

func cumulativeDistances(points []LatLng) []float64 {
	distances := make([]float64, len(points))
	for i := 1; i < len(points); i++ {
		distances[i] = distances[i-1] + distanceMeters(points[i-1], points[i])
	}
	return distances
}

func totalDistance(points []LatLng) float64 {
	if len(points) < 2 {
		return 0
	}
	var total float64
	for i := 1; i < len(points); i++ {
		total += distanceMeters(points[i-1], points[i])
	}
	return total
}

func pointAtDistance(points []LatLng, target float64) LatLng {
	if len(points) == 0 {
		return LatLng{}
	}
	cumulative := cumulativeDistances(points)
	return pointAtCumulative(points, cumulative, target)
}

func pointAtCumulative(points []LatLng, cumulative []float64, target float64) LatLng {
	if target <= 0 {
		return points[0]
	}
	total := cumulative[len(cumulative)-1]
	if target >= total {
		return points[len(points)-1]
	}
	index := sort.Search(len(cumulative), func(i int) bool {
		return cumulative[i] >= target
	})
	if index == 0 {
		return points[0]
	}
	prev := points[index-1]
	next := points[index]
	segment := cumulative[index] - cumulative[index-1]
	if segment <= 0 {
		return next
	}
	fraction := (target - cumulative[index-1]) / segment
	return LatLng{
		Lat: prev.Lat + (next.Lat-prev.Lat)*fraction,
		Lng: prev.Lng + (next.Lng-prev.Lng)*fraction,
	}
}

func uniqueWaypoints(points []LatLng) []LatLng {
	result := make([]LatLng, 0, len(points))
	for _, point := range points {
		if len(result) == 0 || !samePoint(result[len(result)-1], point) {
			result = append(result, point)
		}
	}
	return result
}

func samePoint(a, b LatLng) bool {
	const epsilon = 1e-6
	return math.Abs(a.Lat-b.Lat) < epsilon && math.Abs(a.Lng-b.Lng) < epsilon
}

func distanceMeters(a, b LatLng) float64 {
	lat1 := a.Lat * math.Pi / 180
	lat2 := b.Lat * math.Pi / 180
	dlat := (b.Lat - a.Lat) * math.Pi / 180
	dlng := (b.Lng - a.Lng) * math.Pi / 180

	sinDLat := math.Sin(dlat / 2)
	sinDLng := math.Sin(dlng / 2)
	value := sinDLat*sinDLat + math.Cos(lat1)*math.Cos(lat2)*sinDLng*sinDLng
	return 2 * earthRadiusMeters * math.Asin(math.Sqrt(value))
}
