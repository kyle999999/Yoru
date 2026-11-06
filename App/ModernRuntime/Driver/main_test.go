// SPDX-License-Identifier: GPL-3.0-only
package main

import (
	"reflect"
	"testing"
)

func TestNativeSettingsTypes(t *testing.T) {
	cases := []struct {
		value any
		kind  string
		want  any
	}{
		{[]any{"en", "ja"}, "", []string{"en", "ja"}},
		{float64(12), "int", int32(12)},
		{float64(1.25), "float", float32(1.25)},
		{"AQID", "data", []byte{1, 2, 3}},
		{true, "", true}, {"token", "", "token"},
	}
	for _, c := range cases {
		if got := settingValue(c.value, c.kind); !reflect.DeepEqual(got, c.want) {
			t.Errorf("type %s: got %T %v, want %T %v", c.kind, got, got, c.want, c.want)
		}
	}
}
func TestSourceErrorsAreJSON(t *testing.T) {
	got := run(`{"Op":"load","ID":"missing","Path":"/does-not-exist"}`)
	if len(got) < 10 || got[0] != '{' {
		t.Fatal(got)
	}
}
