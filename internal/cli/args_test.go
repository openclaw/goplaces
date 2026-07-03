package cli

import (
	"reflect"
	"testing"
)

func TestNormalizeNegativeNumericFlagArgs(t *testing.T) {
	tests := []struct {
		name string
		args []string
		want []string
	}{
		{
			name: "negative longitude",
			args: []string{"search", "coffee", "--lat", "42.3467", "--lng", "-71.0972", "--radius-m", "1500"},
			want: []string{"search", "coffee", "--lat", "42.3467", "--lng=-71.0972", "--radius-m", "1500"},
		},
		{
			name: "multiple negative direction coordinates",
			args: []string{"directions", "--from-lat", "-22.8112259", "--from-lng", "-43.2585631", "--to-lat", "-22.9837626", "--to-lng", "-43.2322048"},
			want: []string{"directions", "--from-lat=-22.8112259", "--from-lng=-43.2585631", "--to-lat=-22.9837626", "--to-lng=-43.2322048"},
		},
		{
			name: "equals form unchanged",
			args: []string{"nearby", "--lat=47.6062", "--lng=-122.3321", "--radius-m=1500"},
			want: []string{"nearby", "--lat=47.6062", "--lng=-122.3321", "--radius-m=1500"},
		},
		{
			name: "unknown flag unchanged",
			args: []string{"search", "coffee", "--unknown", "-1"},
			want: []string{"search", "coffee", "--unknown", "-1"},
		},
		{
			name: "invalid numeric value unchanged",
			args: []string{"search", "coffee", "--lng", "-west"},
			want: []string{"search", "coffee", "--lng", "-west"},
		},
	}

	for _, testCase := range tests {
		t.Run(testCase.name, func(t *testing.T) {
			got := normalizeNegativeNumericFlagArgs(testCase.args)
			if !reflect.DeepEqual(got, testCase.want) {
				t.Fatalf("normalizeNegativeNumericFlagArgs() = %#v, want %#v", got, testCase.want)
			}
		})
	}
}
