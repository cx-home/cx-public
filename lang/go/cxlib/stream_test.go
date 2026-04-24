package cxlib

import (
	"testing"
)

// ── Stream / events ───────────────────────────────────────────────────────────

func TestStreamStartDocEndDocPresent(t *testing.T) {
	events, err := Stream(fx(t, "stream/stream_events.cx"))
	if err != nil {
		t.Fatal(err)
	}
	if len(events) == 0 {
		t.Fatal("expected at least one event")
	}
	if events[0].Type != "StartDoc" {
		t.Fatalf("expected first event StartDoc, got %q", events[0].Type)
	}
	last := events[len(events)-1]
	if last.Type != "EndDoc" {
		t.Fatalf("expected last event EndDoc, got %q", last.Type)
	}
}

func TestStreamStartElementName(t *testing.T) {
	events, err := Stream("[server host=localhost port=8080]")
	if err != nil {
		t.Fatal(err)
	}
	var found *StreamEvent
	for i := range events {
		if events[i].Type == "StartElement" {
			found = &events[i]
			break
		}
	}
	if found == nil {
		t.Fatal("no StartElement event found")
	}
	if found.Name != "server" {
		t.Fatalf("expected StartElement name 'server', got %q", found.Name)
	}
}

func TestStreamStartElementAttrs(t *testing.T) {
	events, err := Stream("[server host=localhost port=8080 active=true ratio=1.5]")
	if err != nil {
		t.Fatal(err)
	}
	var found *StreamEvent
	for i := range events {
		if events[i].Type == "StartElement" && events[i].Name == "server" {
			found = &events[i]
			break
		}
	}
	if found == nil {
		t.Fatal("StartElement 'server' not found")
	}
	attrMap := make(map[string]any)
	for _, a := range found.Attrs {
		attrMap[a.Name] = a.Value
	}
	if attrMap["host"] != "localhost" {
		t.Fatalf("expected host=localhost, got %v", attrMap["host"])
	}
	if attrMap["port"] != int64(8080) {
		t.Fatalf("expected port=8080 (int64), got %T=%v", attrMap["port"], attrMap["port"])
	}
	if attrMap["active"] != true {
		t.Fatalf("expected active=true, got %v", attrMap["active"])
	}
}

func TestStreamTextEventValue(t *testing.T) {
	events, err := Stream("[greeting Hello world]")
	if err != nil {
		t.Fatal(err)
	}
	var found *StreamEvent
	for i := range events {
		if events[i].Type == "Text" {
			found = &events[i]
			break
		}
	}
	if found == nil {
		t.Fatal("no Text event found")
	}
	text, ok := found.Value.(string)
	if !ok {
		t.Fatalf("expected string value in Text event, got %T", found.Value)
	}
	if text != "Hello world" {
		t.Fatalf("expected 'Hello world', got %q", text)
	}
}

func TestStreamNestedElements(t *testing.T) {
	events, err := Stream(fx(t, "stream/stream_nested.cx"))
	if err != nil {
		t.Fatal(err)
	}
	// Count StartElement events
	var starts []string
	for _, e := range events {
		if e.Type == "StartElement" {
			starts = append(starts, e.Name)
		}
	}
	if len(starts) == 0 {
		t.Fatal("expected StartElement events in nested fixture")
	}
	// The root element should be level1
	if starts[0] != "level1" {
		t.Fatalf("expected first StartElement 'level1', got %q", starts[0])
	}
}

func TestStreamEventOrderConsistent(t *testing.T) {
	events, err := Stream("[doc [a 1] [b 2]]")
	if err != nil {
		t.Fatal(err)
	}
	// Verify StartDoc ... StartElement(doc) StartElement(a) ... EndElement(a) StartElement(b) ... EndElement(b) EndElement(doc) EndDoc
	types := make([]string, len(events))
	for i, e := range events {
		types[i] = e.Type
	}
	if types[0] != "StartDoc" {
		t.Fatalf("expected StartDoc first, got %q", types[0])
	}
	if types[len(types)-1] != "EndDoc" {
		t.Fatalf("expected EndDoc last, got %q", types[len(types)-1])
	}
	// There should be matching StartElement/EndElement pairs
	var startCount, endCount int
	for _, e := range events {
		if e.Type == "StartElement" {
			startCount++
		} else if e.Type == "EndElement" {
			endCount++
		}
	}
	if startCount != endCount {
		t.Fatalf("StartElement count %d != EndElement count %d", startCount, endCount)
	}
}
