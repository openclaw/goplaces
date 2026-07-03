package cli

import "strconv"

var numericValueFlags = map[string]struct{}{
	"--from-lat":      {},
	"--from-lng":      {},
	"--lat":           {},
	"--limit":         {},
	"--lng":           {},
	"--max-height":    {},
	"--max-waypoints": {},
	"--max-width":     {},
	"--min-rating":    {},
	"--price-level":   {},
	"--radius-m":      {},
	"--to-lat":        {},
	"--to-lng":        {},
}

func normalizeNegativeNumericFlagArgs(args []string) []string {
	normalized := make([]string, 0, len(args))
	for i := 0; i < len(args); i++ {
		arg := args[i]
		if _, ok := numericValueFlags[arg]; ok && i+1 < len(args) && isNegativeNumber(args[i+1]) {
			normalized = append(normalized, arg+"="+args[i+1])
			i++
			continue
		}
		normalized = append(normalized, arg)
	}
	return normalized
}

func isNegativeNumber(value string) bool {
	if len(value) < 2 || value[0] != '-' {
		return false
	}
	_, err := strconv.ParseFloat(value, 64)
	return err == nil
}
