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

var errInvalidPolyline = errors.New("goplaces: invalid polyline")

func decodePolyline(encoded string) ([]LatLng, error) {
	if strings.TrimSpace(encoded) == "" {
		return nil, errors.New("goplaces: empty polyline")
	}
	points := make([]LatLng, 0, len(encoded)/4)
	var lat, lng int64
	for i := 0; i < len(encoded); {
		deltaLat, next, err := decodePolylineDelta(encoded, i)
		if err != nil {
			return nil, err
		}
		deltaLng, next, err := decodePolylineDelta(encoded, next)
		if err != nil {
			return nil, err
		}
		i = next
		lat += deltaLat
		lng += deltaLng
		if lat < -90*routePolylinePrecision || lat > 90*routePolylinePrecision ||
			lng < -180*routePolylinePrecision || lng > 180*routePolylinePrecision {
			return nil, errInvalidPolyline
		}

		points = append(points, LatLng{
			Lat: float64(lat) / routePolylinePrecision,
			Lng: float64(lng) / routePolylinePrecision,
		})
	}
	return points, nil
}

func decodePolylineDelta(encoded string, index int) (int64, int, error) {
	var value uint32
	for shift := uint(0); ; shift += 5 {
		if index >= len(encoded) || encoded[index] < 63 || encoded[index] > 126 {
			return 0, index, errInvalidPolyline
		}
		chunk := uint32(encoded[index] - 63)
		index++
		// The seventh group has only two bits left in a 32-bit coordinate.
		if shift == 30 && chunk > 3 {
			return 0, index, errInvalidPolyline
		}
		value |= (chunk & 0x1f) << shift
		if chunk < 0x20 {
			return int64(value>>1) ^ -int64(value&1), index, nil
		}
	}
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
	longitudeDelta := math.Remainder(next.Lng-prev.Lng, 360)
	return LatLng{
		Lat: prev.Lat + (next.Lat-prev.Lat)*fraction,
		Lng: math.Remainder(prev.Lng+longitudeDelta*fraction, 360),
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
	return math.Abs(a.Lat-b.Lat) < epsilon && math.Abs(math.Remainder(a.Lng-b.Lng, 360)) < epsilon
}

func distanceMeters(a, b LatLng) float64 {
	lat1 := a.Lat * math.Pi / 180
	lat2 := b.Lat * math.Pi / 180
	dlat := (b.Lat - a.Lat) * math.Pi / 180
	dlng := (b.Lng - a.Lng) * math.Pi / 180

	sinDLat := math.Sin(dlat / 2)
	sinDLng := math.Sin(dlng / 2)
	value := sinDLat*sinDLat + math.Cos(lat1)*math.Cos(lat2)*sinDLng*sinDLng
	// Roundoff near antipodal points can push the haversine above one.
	return 2 * earthRadiusMeters * math.Asin(math.Sqrt(min(1, value)))
}
