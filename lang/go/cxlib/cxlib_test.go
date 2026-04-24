package cxlib

import (
	"testing"
)

func TestVersion(t *testing.T) {
	v := Version()
	if v == "" {
		t.Fatal("Version() returned empty string")
	}
}

func TestToCx(t *testing.T) {
	out, err := ToCx("[p Hello]")
	if err != nil {
		t.Fatal(err)
	}
	if out == "" {
		t.Fatal("ToCx returned empty string")
	}
}

func TestToJson(t *testing.T) {
	out, err := ToJson("[port :int 8080]")
	if err != nil {
		t.Fatal(err)
	}
	if out == "" {
		t.Fatal("ToJson returned empty string")
	}
}

func TestError(t *testing.T) {
	_, err := ToCx("[unclosed")
	if err == nil {
		t.Fatal("expected error for unclosed bracket")
	}
}
