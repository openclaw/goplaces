package places

const (
	priceLevelFree        = "PRICE_LEVEL_FREE"
	priceLevelInexpensive = "PRICE_LEVEL_INEXPENSIVE"
	priceLevelModerate    = "PRICE_LEVEL_MODERATE"
	priceLevelExpensive   = "PRICE_LEVEL_EXPENSIVE"
	priceLevelVeryExp     = "PRICE_LEVEL_VERY_EXPENSIVE"
)

var priceLevelToEnum = map[int]string{
	0: priceLevelFree,
	1: priceLevelInexpensive,
	2: priceLevelModerate,
	3: priceLevelExpensive,
	4: priceLevelVeryExp,
}

var enumToPriceLevel = map[string]int{
	priceLevelFree:        0,
	priceLevelInexpensive: 1,
	priceLevelModerate:    2,
	priceLevelExpensive:   3,
	priceLevelVeryExp:     4,
}
