package cxlib

import (
	"math"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

// ── fixture loader ────────────────────────────────────────────────────────────

func fixturesDir() string {
	_, thisFile, _, _ := runtime.Caller(0)
	// thisFile = .../lang/go/cxlib/api_test.go
	return filepath.Join(filepath.Dir(thisFile), "..", "..", "..", "fixtures")
}

func fx(t *testing.T, name string) string {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(fixturesDir(), name))
	if err != nil {
		t.Fatalf("fixture %q: %v", name, err)
	}
	return string(data)
}

// ── parse / root / get ────────────────────────────────────────────────────────

func TestParseReturnsDocument(t *testing.T) {
	doc, err := Parse(fx(t, "api_config.cx"))
	if err != nil {
		t.Fatal(err)
	}
	if doc == nil {
		t.Fatal("expected non-nil Document")
	}
}

func TestRootReturnsFirstElement(t *testing.T) {
	doc, err := Parse(fx(t, "api_config.cx"))
	if err != nil {
		t.Fatal(err)
	}
	root := doc.Root()
	if root == nil || root.Name != "config" {
		t.Fatalf("expected root name 'config', got %v", root)
	}
}

func TestRootNilOnEmptyInput(t *testing.T) {
	doc, err := Parse("")
	if err != nil {
		t.Fatal(err)
	}
	if doc.Root() != nil {
		t.Fatal("expected nil root for empty input")
	}
}

func TestGetTopLevelByName(t *testing.T) {
	doc, err := Parse(fx(t, "api_config.cx"))
	if err != nil {
		t.Fatal(err)
	}
	if doc.Get("config") == nil || doc.Get("config").Name != "config" {
		t.Fatal("expected to find 'config'")
	}
	if doc.Get("missing") != nil {
		t.Fatal("expected nil for missing element")
	}
}

func TestGetMultiTopLevel(t *testing.T) {
	doc, err := Parse(fx(t, "api_multi.cx"))
	if err != nil {
		t.Fatal(err)
	}
	svc := doc.Get("service")
	if svc == nil {
		t.Fatal("expected a service element")
	}
	if svc.Attr("name") != "auth" {
		t.Fatalf("expected first service name 'auth', got %v", svc.Attr("name"))
	}
}

func TestParseMultipleTopLevelElements(t *testing.T) {
	doc, err := Parse(fx(t, "api_multi.cx"))
	if err != nil {
		t.Fatal(err)
	}
	var count int
	for _, e := range doc.Elements {
		if el, ok := e.(*Element); ok && el.Name == "service" {
			count++
		}
	}
	if count != 3 {
		t.Fatalf("expected 3 service elements, got %d", count)
	}
}

// ── attr ──────────────────────────────────────────────────────────────────────

func TestAttrString(t *testing.T) {
	doc, _ := Parse(fx(t, "api_config.cx"))
	srv := doc.At("config/server")
	if srv == nil {
		t.Fatal("config/server not found")
	}
	if srv.Attr("host") != "localhost" {
		t.Fatalf("expected 'localhost', got %v", srv.Attr("host"))
	}
}

func TestAttrInt(t *testing.T) {
	doc, _ := Parse(fx(t, "api_config.cx"))
	srv := doc.At("config/server")
	port := srv.Attr("port")
	if port == nil {
		t.Fatal("port is nil")
	}
	portInt, ok := port.(int64)
	if !ok {
		t.Fatalf("expected int64 port, got %T = %v", port, port)
	}
	if portInt != 8080 {
		t.Fatalf("expected port 8080, got %d", portInt)
	}
}

func TestAttrBool(t *testing.T) {
	doc, _ := Parse(fx(t, "api_config.cx"))
	srv := doc.At("config/server")
	debug := srv.Attr("debug")
	if b, ok := debug.(bool); !ok || b != false {
		t.Fatalf("expected debug=false (bool), got %T=%v", debug, debug)
	}
}

func TestAttrFloat(t *testing.T) {
	doc, _ := Parse(fx(t, "api_config.cx"))
	srv := doc.At("config/server")
	ratio := srv.Attr("ratio")
	f, ok := ratio.(float64)
	if !ok {
		t.Fatalf("expected float64 ratio, got %T=%v", ratio, ratio)
	}
	if math.Abs(f-1.5) > 1e-9 {
		t.Fatalf("expected ratio 1.5, got %v", f)
	}
}

func TestAttrMissingReturnsNil(t *testing.T) {
	doc, _ := Parse(fx(t, "api_config.cx"))
	srv := doc.At("config/server")
	if srv.Attr("nonexistent") != nil {
		t.Fatal("expected nil for missing attr")
	}
}

// ── scalar ────────────────────────────────────────────────────────────────────

func TestScalarInt(t *testing.T) {
	doc, _ := Parse(fx(t, "api_scalars.cx"))
	el := doc.At("values/count")
	if el == nil {
		t.Fatal("values/count not found")
	}
	v := el.Scalar()
	i, ok := v.(int64)
	if !ok {
		t.Fatalf("expected int64, got %T=%v", v, v)
	}
	if i != 42 {
		t.Fatalf("expected 42, got %d", i)
	}
}

func TestScalarFloat(t *testing.T) {
	doc, _ := Parse(fx(t, "api_scalars.cx"))
	el := doc.At("values/ratio")
	v := el.Scalar()
	f, ok := v.(float64)
	if !ok {
		t.Fatalf("expected float64, got %T=%v", v, v)
	}
	if math.Abs(f-1.5) > 1e-9 {
		t.Fatalf("expected 1.5, got %v", f)
	}
}

func TestScalarBoolTrue(t *testing.T) {
	doc, _ := Parse(fx(t, "api_scalars.cx"))
	el := doc.At("values/enabled")
	v := el.Scalar()
	b, ok := v.(bool)
	if !ok || b != true {
		t.Fatalf("expected true (bool), got %T=%v", v, v)
	}
}

func TestScalarBoolFalse(t *testing.T) {
	doc, _ := Parse(fx(t, "api_scalars.cx"))
	el := doc.At("values/disabled")
	v := el.Scalar()
	b, ok := v.(bool)
	if !ok || b != false {
		t.Fatalf("expected false (bool), got %T=%v", v, v)
	}
}

func TestScalarNull(t *testing.T) {
	doc, _ := Parse(fx(t, "api_scalars.cx"))
	el := doc.At("values/nothing")
	v := el.Scalar()
	if v != nil {
		t.Fatalf("expected nil, got %v", v)
	}
}

func TestScalarNilOnElementWithChildren(t *testing.T) {
	doc, _ := Parse(fx(t, "api_config.cx"))
	if doc.Root().Scalar() != nil {
		t.Fatal("expected nil scalar for element with children")
	}
}

// ── text ──────────────────────────────────────────────────────────────────────

func TestTextSingleToken(t *testing.T) {
	doc, _ := Parse(fx(t, "api_article.cx"))
	el := doc.At("article/body/h1")
	if el == nil {
		t.Fatal("article/body/h1 not found")
	}
	if el.Text() != "Introduction" {
		t.Fatalf("expected 'Introduction', got %q", el.Text())
	}
}

func TestTextQuoted(t *testing.T) {
	doc, _ := Parse(fx(t, "api_scalars.cx"))
	el := doc.At("values/label")
	if el.Text() != "hello world" {
		t.Fatalf("expected 'hello world', got %q", el.Text())
	}
}

func TestTextEmptyOnElementWithChildren(t *testing.T) {
	doc, _ := Parse(fx(t, "api_config.cx"))
	if doc.Root().Text() != "" {
		t.Fatalf("expected empty text, got %q", doc.Root().Text())
	}
}

// ── children / GetAll ─────────────────────────────────────────────────────────

func TestChildrenReturnsOnlyElements(t *testing.T) {
	doc, _ := Parse(fx(t, "api_config.cx"))
	kids := doc.Root().Children()
	if len(kids) != 3 {
		t.Fatalf("expected 3 children, got %d", len(kids))
	}
	names := make([]string, len(kids))
	for i, k := range kids {
		names[i] = k.Name
	}
	if strings.Join(names, ",") != "server,database,logging" {
		t.Fatalf("unexpected children names: %v", names)
	}
}

func TestGetAllDirectChildren(t *testing.T) {
	doc, _ := Parse("[root [item 1] [item 2] [other x] [item 3]]")
	if doc == nil {
		t.Fatal("parse failed")
	}
	items := doc.Root().GetAll("item")
	if len(items) != 3 {
		t.Fatalf("expected 3 items, got %d", len(items))
	}
}

func TestGetAllReturnsEmptyForMissing(t *testing.T) {
	doc, _ := Parse(fx(t, "api_config.cx"))
	result := doc.Root().GetAll("missing")
	if len(result) != 0 {
		t.Fatalf("expected empty, got %d", len(result))
	}
}

// ── at ────────────────────────────────────────────────────────────────────────

func TestAtSingleSegment(t *testing.T) {
	doc, _ := Parse(fx(t, "api_config.cx"))
	el := doc.At("config")
	if el == nil || el.Name != "config" {
		t.Fatal("expected config element")
	}
}

func TestAtTwoSegments(t *testing.T) {
	doc, _ := Parse(fx(t, "api_config.cx"))
	srv := doc.At("config/server")
	if srv == nil || srv.Name != "server" {
		t.Fatal("expected server")
	}
	db := doc.At("config/database")
	if db == nil || db.Name != "database" {
		t.Fatal("expected database")
	}
}

func TestAtThreeSegments(t *testing.T) {
	doc, _ := Parse(fx(t, "api_article.cx"))
	title := doc.At("article/head/title")
	if title == nil {
		t.Fatal("article/head/title not found")
	}
	if title.Text() != "Getting Started with CX" {
		t.Fatalf("unexpected title text: %q", title.Text())
	}
	h1 := doc.At("article/body/h1")
	if h1 == nil || h1.Text() != "Introduction" {
		t.Fatal("expected Introduction in h1")
	}
}

func TestAtMissingSegmentReturnsNil(t *testing.T) {
	doc, _ := Parse(fx(t, "api_config.cx"))
	if doc.At("config/missing") != nil {
		t.Fatal("expected nil for missing segment")
	}
}

func TestAtMissingRootReturnsNil(t *testing.T) {
	doc, _ := Parse(fx(t, "api_config.cx"))
	if doc.At("missing") != nil {
		t.Fatal("expected nil for missing root")
	}
}

func TestAtDeepMissingReturnsNil(t *testing.T) {
	doc, _ := Parse(fx(t, "api_config.cx"))
	if doc.At("config/server/missing/deep") != nil {
		t.Fatal("expected nil for deep missing path")
	}
}

func TestElementAtRelativePath(t *testing.T) {
	doc, _ := Parse(fx(t, "api_article.cx"))
	body := doc.At("article/body")
	if body == nil {
		t.Fatal("body not found")
	}
	h2 := body.At("section/h2")
	if h2 == nil || h2.Text() != "Details" {
		t.Fatalf("expected h2 'Details', got %v", h2)
	}
}

// ── FindAll ───────────────────────────────────────────────────────────────────

func TestFindAllTopLevel(t *testing.T) {
	doc, _ := Parse(fx(t, "api_multi.cx"))
	svcs := doc.FindAll("service")
	if len(svcs) != 3 {
		t.Fatalf("expected 3 services, got %d", len(svcs))
	}
}

func TestFindAllDeep(t *testing.T) {
	doc, _ := Parse(fx(t, "api_article.cx"))
	ps := doc.FindAll("p")
	if len(ps) != 3 {
		t.Fatalf("expected 3 p elements, got %d", len(ps))
	}
	expected := []string{"First paragraph.", "Nested paragraph.", "Another nested paragraph."}
	for i, p := range ps {
		if p.Text() != expected[i] {
			t.Fatalf("p[%d]: expected %q, got %q", i, expected[i], p.Text())
		}
	}
}

func TestFindAllMissingReturnsEmpty(t *testing.T) {
	doc, _ := Parse(fx(t, "api_config.cx"))
	result := doc.FindAll("missing")
	if len(result) != 0 {
		t.Fatalf("expected empty, got %d", len(result))
	}
}

func TestFindAllOnElement(t *testing.T) {
	doc, _ := Parse(fx(t, "api_article.cx"))
	body := doc.At("article/body")
	ps := body.FindAll("p")
	if len(ps) != 3 {
		t.Fatalf("expected 3 p elements on body, got %d", len(ps))
	}
}

// ── FindFirst ─────────────────────────────────────────────────────────────────

func TestFindFirstReturnsFirstMatch(t *testing.T) {
	doc, _ := Parse(fx(t, "api_article.cx"))
	p := doc.FindFirst("p")
	if p == nil || p.Text() != "First paragraph." {
		t.Fatalf("expected 'First paragraph.', got %v", p)
	}
}

func TestFindFirstMissingReturnsNil(t *testing.T) {
	doc, _ := Parse(fx(t, "api_config.cx"))
	if doc.FindFirst("missing") != nil {
		t.Fatal("expected nil for missing element")
	}
}

func TestFindFirstDepthFirstOrder(t *testing.T) {
	doc, _ := Parse(fx(t, "api_article.cx"))
	h1 := doc.FindFirst("h1")
	if h1 == nil || h1.Text() != "Introduction" {
		t.Fatal("expected h1 'Introduction'")
	}
	h2 := doc.FindFirst("h2")
	if h2 == nil || h2.Text() != "Details" {
		t.Fatal("expected h2 'Details'")
	}
}

func TestFindFirstOnElement(t *testing.T) {
	doc, _ := Parse(fx(t, "api_article.cx"))
	section := doc.At("article/body/section")
	p := section.FindFirst("p")
	if p == nil || p.Text() != "Nested paragraph." {
		t.Fatalf("expected 'Nested paragraph.', got %v", p)
	}
}

// ── mutation — Element ────────────────────────────────────────────────────────

func TestAppendAddsToEnd(t *testing.T) {
	doc, _ := Parse(fx(t, "api_config.cx"))
	doc.Root().Append(&Element{Name: "cache"})
	kids := doc.Root().Children()
	if len(kids) != 4 || kids[3].Name != "cache" {
		t.Fatalf("expected cache as last child, got %v", kids)
	}
}

func TestPrependAddsToFront(t *testing.T) {
	doc, _ := Parse(fx(t, "api_config.cx"))
	doc.Root().Prepend(&Element{Name: "meta"})
	kids := doc.Root().Children()
	if kids[0].Name != "meta" {
		t.Fatalf("expected meta as first child, got %v", kids[0].Name)
	}
}

func TestInsertAtIndex(t *testing.T) {
	doc, _ := Parse("[root [a 1] [c 3]]")
	doc.Root().Insert(1, &Element{Name: "b"})
	kids := doc.Root().Children()
	names := make([]string, len(kids))
	for i, k := range kids {
		names[i] = k.Name
	}
	if strings.Join(names, ",") != "a,b,c" {
		t.Fatalf("expected a,b,c, got %v", names)
	}
}

func TestRemoveByIdentity(t *testing.T) {
	doc, _ := Parse(fx(t, "api_config.cx"))
	db := doc.At("config/database")
	doc.Root().Remove(db)
	if doc.At("config/database") != nil {
		t.Fatal("database should be removed")
	}
	if doc.At("config/server") == nil {
		t.Fatal("server should still be present")
	}
}

func TestSetAttrNew(t *testing.T) {
	doc, _ := Parse(fx(t, "api_config.cx"))
	srv := doc.At("config/server")
	srv.SetAttr("env", "production", "")
	if srv.Attr("env") != "production" {
		t.Fatalf("expected 'production', got %v", srv.Attr("env"))
	}
}

func TestSetAttrUpdateValue(t *testing.T) {
	doc, _ := Parse(fx(t, "api_config.cx"))
	srv := doc.At("config/server")
	origCount := len(srv.Attrs)
	srv.SetAttr("port", int64(9090), "int")
	if srv.Attr("port") != int64(9090) {
		t.Fatalf("expected port 9090, got %v", srv.Attr("port"))
	}
	if len(srv.Attrs) != origCount {
		t.Fatalf("expected %d attrs, got %d", origCount, len(srv.Attrs))
	}
}

func TestSetAttrChangeType(t *testing.T) {
	doc, _ := Parse(fx(t, "api_config.cx"))
	srv := doc.At("config/server")
	origCount := len(srv.Attrs)
	srv.SetAttr("debug", true, "bool")
	if b, ok := srv.Attr("debug").(bool); !ok || b != true {
		t.Fatalf("expected debug=true, got %v", srv.Attr("debug"))
	}
	if len(srv.Attrs) != origCount {
		t.Fatalf("expected %d attrs, got %d", origCount, len(srv.Attrs))
	}
}

func TestRemoveAttr(t *testing.T) {
	doc, _ := Parse(fx(t, "api_config.cx"))
	srv := doc.At("config/server")
	origCount := len(srv.Attrs)
	srv.RemoveAttr("debug")
	if srv.Attr("debug") != nil {
		t.Fatal("debug should be removed")
	}
	if len(srv.Attrs) != origCount-1 {
		t.Fatalf("expected %d attrs, got %d", origCount-1, len(srv.Attrs))
	}
}

func TestRemoveAttrNonexistentIsNoop(t *testing.T) {
	doc, _ := Parse(fx(t, "api_config.cx"))
	srv := doc.At("config/server")
	origCount := len(srv.Attrs)
	srv.RemoveAttr("nonexistent")
	if len(srv.Attrs) != origCount {
		t.Fatalf("expected %d attrs after noop, got %d", origCount, len(srv.Attrs))
	}
}

// ── mutation — Document ───────────────────────────────────────────────────────

func TestDocAppendElement(t *testing.T) {
	doc, _ := Parse(fx(t, "api_config.cx"))
	doc.Append(&Element{Name: "cache", Attrs: []Attr{{Name: "host", Value: "redis"}}})
	cache := doc.Get("cache")
	if cache == nil || cache.Attr("host") != "redis" {
		t.Fatal("expected cache with host=redis")
	}
}

func TestDocPrependMakesNewRoot(t *testing.T) {
	doc, _ := Parse(fx(t, "api_config.cx"))
	doc.Prepend(&Element{Name: "preamble"})
	if doc.Root().Name != "preamble" {
		t.Fatalf("expected root 'preamble', got %q", doc.Root().Name)
	}
	if doc.Get("config") == nil {
		t.Fatal("config should still be present")
	}
}

// ── round-trips ───────────────────────────────────────────────────────────────

func TestToCxRoundTrip(t *testing.T) {
	original, _ := Parse(fx(t, "api_config.cx"))
	reparsed, err := Parse(original.ToCx())
	if err != nil {
		t.Fatalf("reparse error: %v", err)
	}
	srv := reparsed.At("config/server")
	if srv == nil {
		t.Fatal("config/server not found after round-trip")
	}
	if srv.Attr("host") != "localhost" {
		t.Fatalf("expected 'localhost', got %v", srv.Attr("host"))
	}
	if srv.Attr("port") != int64(8080) {
		t.Fatalf("expected 8080, got %v", srv.Attr("port"))
	}
	db := reparsed.At("config/database")
	if db == nil || db.Attr("name") != "myapp" {
		t.Fatal("expected database/name=myapp")
	}
}

func TestToCxRoundTripAfterMutation(t *testing.T) {
	doc, _ := Parse(fx(t, "api_config.cx"))
	doc.At("config/server").SetAttr("env", "production", "")
	doc.At("config/server").Append(&Element{
		Name:  "timeout",
		Items: []Node{&ScalarNode{DataType: "int", Value: int64(30)}},
	})
	reparsed, err := Parse(doc.ToCx())
	if err != nil {
		t.Fatalf("reparse error: %v", err)
	}
	if reparsed.At("config/server").Attr("env") != "production" {
		t.Fatal("expected env=production after round-trip")
	}
	timeout := reparsed.At("config/server").FindFirst("timeout")
	if timeout == nil || timeout.Scalar() != int64(30) {
		t.Fatalf("expected timeout scalar 30, got %v", timeout)
	}
}

func TestToCxPreservesArticleStructure(t *testing.T) {
	original, _ := Parse(fx(t, "api_article.cx"))
	reparsed, err := Parse(original.ToCx())
	if err != nil {
		t.Fatalf("reparse error: %v", err)
	}
	title := reparsed.At("article/head/title")
	if title == nil || title.Text() != "Getting Started with CX" {
		t.Fatalf("expected title text, got %v", title)
	}
	if len(reparsed.FindAll("p")) != 3 {
		t.Fatalf("expected 3 p elements after round-trip")
	}
}

// ── loads / dumps ─────────────────────────────────────────────────────────────

func TestLoadsReturnsMap(t *testing.T) {
	data, err := Loads(fx(t, "api_config.cx"))
	if err != nil {
		t.Fatal(err)
	}
	m, ok := data.(map[string]any)
	if !ok {
		t.Fatalf("expected map, got %T", data)
	}
	config, ok := m["config"].(map[string]any)
	if !ok {
		t.Fatal("expected config map")
	}
	server, ok := config["server"].(map[string]any)
	if !ok {
		t.Fatal("expected server map")
	}
	if server["host"] != "localhost" {
		t.Fatalf("expected localhost, got %v", server["host"])
	}
	// JSON unmarshals numbers as float64
	port, ok := server["port"].(float64)
	if !ok || port != 8080 {
		t.Fatalf("expected port 8080, got %v", server["port"])
	}
}

func TestLoadsBoolTypes(t *testing.T) {
	data, err := Loads(fx(t, "api_config.cx"))
	if err != nil {
		t.Fatal(err)
	}
	m := data.(map[string]any)
	config := m["config"].(map[string]any)
	server := config["server"].(map[string]any)
	debug, ok := server["debug"].(bool)
	if !ok || debug != false {
		t.Fatalf("expected debug=false, got %v", server["debug"])
	}
}

func TestLoadsScalars(t *testing.T) {
	data, err := Loads(fx(t, "api_scalars.cx"))
	if err != nil {
		t.Fatal(err)
	}
	m := data.(map[string]any)
	values := m["values"].(map[string]any)

	count, ok := values["count"].(float64)
	if !ok || count != 42 {
		t.Fatalf("expected count=42, got %v", values["count"])
	}
	enabled, ok := values["enabled"].(bool)
	if !ok || enabled != true {
		t.Fatalf("expected enabled=true, got %v", values["enabled"])
	}
	disabled, ok := values["disabled"].(bool)
	if !ok || disabled != false {
		t.Fatalf("expected disabled=false, got %v", values["disabled"])
	}
	if values["nothing"] != nil {
		t.Fatalf("expected nothing=nil, got %v", values["nothing"])
	}
}

func TestDumpsProducesParsableCx(t *testing.T) {
	original := map[string]any{
		"app": map[string]any{
			"name":    "myapp",
			"version": "1.0",
			"port":    8080,
		},
	}
	cxStr, err := Dumps(original)
	if err != nil {
		t.Fatal(err)
	}
	reparsed, err := Parse(cxStr)
	if err != nil {
		t.Fatalf("parse after dumps error: %v", err)
	}
	if reparsed.FindFirst("app") == nil {
		t.Fatal("expected to find 'app' element")
	}
}

func TestLoadsDumpsDataPreserved(t *testing.T) {
	original := map[string]any{
		"server": map[string]any{
			"host":  "localhost",
			"port":  8080,
			"debug": false,
		},
	}
	cxStr, err := Dumps(original)
	if err != nil {
		t.Fatal(err)
	}
	restored, err := Loads(cxStr)
	if err != nil {
		t.Fatal(err)
	}
	m := restored.(map[string]any)
	server := m["server"].(map[string]any)

	port, ok := server["port"].(float64)
	if !ok || port != 8080 {
		t.Fatalf("expected port 8080, got %v", server["port"])
	}
	if server["host"] != "localhost" {
		t.Fatalf("expected host localhost, got %v", server["host"])
	}
	debug, ok := server["debug"].(bool)
	if !ok || debug != false {
		t.Fatalf("expected debug=false, got %v", server["debug"])
	}
}

// ── error / failure cases ─────────────────────────────────────────────────────

func TestParseErrorUnclosedBracket(t *testing.T) {
	_, err := Parse(fx(t, "errors/unclosed.cx"))
	if err == nil {
		t.Fatal("expected error for unclosed bracket")
	}
}

func TestParseErrorEmptyElementName(t *testing.T) {
	_, err := Parse(fx(t, "errors/empty_name.cx"))
	if err == nil {
		t.Fatal("expected error for empty element name")
	}
}

func TestParseErrorNestedUnclosed(t *testing.T) {
	_, err := Parse(fx(t, "errors/nested_unclosed.cx"))
	if err == nil {
		t.Fatal("expected error for nested unclosed bracket")
	}
}

func TestAtMissingPathReturnsNilNotError(t *testing.T) {
	doc, _ := Parse(fx(t, "api_config.cx"))
	// should not panic
	result := doc.At("config/server/missing/deep/path")
	if result != nil {
		t.Fatal("expected nil for deep missing path")
	}
}

func TestFindAllOnEmptyDocReturnsEmpty(t *testing.T) {
	doc, _ := Parse("")
	result := doc.FindAll("anything")
	if len(result) != 0 {
		t.Fatalf("expected empty, got %d", len(result))
	}
}

func TestFindFirstOnEmptyDocReturnsNil(t *testing.T) {
	doc, _ := Parse("")
	if doc.FindFirst("anything") != nil {
		t.Fatal("expected nil on empty doc")
	}
}

func TestScalarNilWhenElementHasChildElements(t *testing.T) {
	doc, _ := Parse(fx(t, "api_config.cx"))
	if doc.Root().Scalar() != nil {
		t.Fatal("expected nil scalar for element with children")
	}
}

func TestTextEmptyWhenNoTextChildren(t *testing.T) {
	doc, _ := Parse(fx(t, "api_config.cx"))
	if doc.Root().Text() != "" {
		t.Fatalf("expected empty text, got %q", doc.Root().Text())
	}
}

func TestRemoveAttrNonexistentDoesNotRaise(t *testing.T) {
	doc, _ := Parse(fx(t, "api_config.cx"))
	srv := doc.At("config/server")
	srv.RemoveAttr("totally_missing") // should not panic
}

// ── parse other formats ───────────────────────────────────────────────────────

func TestParseXmlInvalid(t *testing.T) {
	_, err := ParseXml("<unclosed")
	if err == nil {
		t.Fatal("expected error for invalid XML")
	}
}

func TestParseXml(t *testing.T) {
	doc, err := ParseXml(`<root><child key="val"/></root>`)
	if err != nil {
		t.Fatal(err)
	}
	if doc.Root() == nil || doc.Root().Name != "root" {
		t.Fatal("expected root element")
	}
	child := doc.FindFirst("child")
	if child == nil {
		t.Fatal("expected child element")
	}
}

func TestParseJsonToDocument(t *testing.T) {
	doc, err := ParseJson(`{"server": {"port": 8080}}`)
	if err != nil {
		t.Fatal(err)
	}
	if doc.FindFirst("server") == nil {
		t.Fatal("expected server element")
	}
}

func TestParseYamlToDocument(t *testing.T) {
	doc, err := ParseYaml("server:\n  port: 8080\n")
	if err != nil {
		t.Fatal(err)
	}
	if doc.FindFirst("server") == nil {
		t.Fatal("expected server element")
	}
}

func TestParseToml(t *testing.T) {
	doc, err := ParseToml("[server]\nhost = \"localhost\"\nport = 8080\n")
	if err != nil {
		t.Fatal(err)
	}
	if doc.Root() == nil || doc.Root().Name != "server" {
		t.Fatalf("expected root name 'server', got %v", doc.Root())
	}
}

func TestParseMd(t *testing.T) {
	doc, err := ParseMd("# hello\n\nworld\n")
	if err != nil {
		t.Fatal(err)
	}
	if doc == nil || len(doc.Elements) == 0 {
		t.Fatal("expected doc with elements")
	}
}

func TestLoadsXml(t *testing.T) {
	result, err := LoadsXml("<root><item>42</item></root>")
	if err != nil {
		t.Fatal(err)
	}
	m, ok := result.(map[string]any)
	if !ok {
		t.Fatalf("expected map, got %T", result)
	}
	if _, hasRoot := m["root"]; !hasRoot {
		t.Fatalf("expected 'root' key in map, got %v", m)
	}
}

func TestLoadsJson(t *testing.T) {
	result, err := LoadsJson(`{"server":{"host":"localhost"}}`)
	if err != nil {
		t.Fatal(err)
	}
	m, ok := result.(map[string]any)
	if !ok {
		t.Fatalf("expected map, got %T", result)
	}
	if _, hasServer := m["server"]; !hasServer {
		t.Fatalf("expected 'server' key in map, got %v", m)
	}
}

func TestLoadsYaml(t *testing.T) {
	result, err := LoadsYaml("server:\n  host: localhost\n")
	if err != nil {
		t.Fatal(err)
	}
	m, ok := result.(map[string]any)
	if !ok {
		t.Fatalf("expected map, got %T", result)
	}
	if _, hasServer := m["server"]; !hasServer {
		t.Fatalf("expected 'server' key in map, got %v", m)
	}
}

func TestLoadsToml(t *testing.T) {
	result, err := LoadsToml("[server]\nhost = \"localhost\"\n")
	if err != nil {
		t.Fatal(err)
	}
	m, ok := result.(map[string]any)
	if !ok {
		t.Fatalf("expected map, got %T", result)
	}
	if _, hasServer := m["server"]; !hasServer {
		t.Fatalf("expected 'server' key in map, got %v", m)
	}
}

func TestLoadsMd(t *testing.T) {
	result, err := LoadsMd("# hello\n\nworld\n")
	if err != nil {
		t.Fatal(err)
	}
	if result == nil {
		t.Fatal("expected non-nil result")
	}
}

// ── RemoveChild / RemoveAt ────────────────────────────────────────────────────

func TestRemoveChildRemovesAllMatchingChildren(t *testing.T) {
	doc, err := Parse("[parent [a 1] [b 2] [a 3]]")
	if err != nil {
		t.Fatal(err)
	}
	parent := doc.Root()
	parent.RemoveChild("a")
	kids := parent.Children()
	if len(kids) != 1 || kids[0].Name != "b" {
		t.Fatalf("expected only [b] to remain, got %v", kids)
	}
}

func TestRemoveChildNonexistentIsNoop(t *testing.T) {
	doc, err := Parse("[parent [a 1] [b 2]]")
	if err != nil {
		t.Fatal(err)
	}
	parent := doc.Root()
	before := len(parent.Items)
	parent.RemoveChild("z")
	if len(parent.Items) != before {
		t.Fatalf("expected length unchanged (%d), got %d", before, len(parent.Items))
	}
}

func TestRemoveAtRemovesByIndex(t *testing.T) {
	doc, err := Parse("[parent [a 1] [b 2] [c 3]]")
	if err != nil {
		t.Fatal(err)
	}
	parent := doc.Root()
	parent.RemoveAt(1)
	kids := parent.Children()
	if len(kids) != 2 {
		t.Fatalf("expected 2 children after RemoveAt(1), got %d", len(kids))
	}
	if kids[0].Name != "a" || kids[1].Name != "c" {
		t.Fatalf("expected [a, c], got [%s, %s]", kids[0].Name, kids[1].Name)
	}
}

func TestRemoveAtOutOfBoundsIsNoop(t *testing.T) {
	doc, err := Parse("[parent [a 1] [b 2]]")
	if err != nil {
		t.Fatal(err)
	}
	parent := doc.Root()
	before := len(parent.Items)
	parent.RemoveAt(999) // should not panic
	if len(parent.Items) != before {
		t.Fatalf("expected length unchanged after out-of-bounds RemoveAt")
	}
}

// ── SelectAll / Select (CXPath) ───────────────────────────────────────────────

func TestSelectAllDescendantAxis(t *testing.T) {
	doc, _ := Parse(fx(t, "api_multi.cx"))
	results, err := doc.SelectAll("//service")
	if err != nil {
		t.Fatal(err)
	}
	if len(results) != 3 {
		t.Fatalf("expected 3 services, got %d", len(results))
	}
}

func TestSelectAllAttributePredicate(t *testing.T) {
	// Build inline doc with active attr
	doc, err := Parse("[services\n  [service name=auth port=8080 active=true]\n  [service name=api port=9000 active=false]\n  [service name=web port=80 active=true]\n]")
	if err != nil {
		t.Fatal(err)
	}
	results, err := doc.SelectAll("//service[@active=true]")
	if err != nil {
		t.Fatal(err)
	}
	if len(results) != 2 {
		t.Fatalf("expected 2 active services, got %d", len(results))
	}
}

func TestSelectFirstFromSelectAll(t *testing.T) {
	doc, _ := Parse(fx(t, "api_multi.cx"))
	first, err := doc.Select("//service")
	if err != nil {
		t.Fatal(err)
	}
	if first == nil {
		t.Fatal("expected non-nil first service")
	}
	if first.Attr("name") != "auth" {
		t.Fatalf("expected first service name 'auth', got %v", first.Attr("name"))
	}
}

func TestSelectAllChildPath(t *testing.T) {
	doc, _ := Parse(fx(t, "api_config.cx"))
	results, err := doc.SelectAll("config/server")
	if err != nil {
		t.Fatal(err)
	}
	if len(results) != 1 || results[0].Name != "server" {
		t.Fatalf("expected 1 server, got %d", len(results))
	}
}

func TestSelectAllWildcard(t *testing.T) {
	doc, _ := Parse(fx(t, "api_config.cx"))
	// //  * matches all descendants
	results, err := doc.SelectAll("//*")
	if err != nil {
		t.Fatal(err)
	}
	// config has server, database, logging = 4 total (config + 3 children)
	if len(results) < 4 {
		t.Fatalf("expected at least 4 results for //* in config doc, got %d", len(results))
	}
}

func TestSelectAllAttrCmpNumeric(t *testing.T) {
	doc, _ := Parse(fx(t, "api_multi.cx"))
	// ports: auth=8001, api=8080, worker=9000 — all >= 8000
	results, err := doc.SelectAll("//service[@port>=8000]")
	if err != nil {
		t.Fatal(err)
	}
	if len(results) != 3 {
		t.Fatalf("expected 3 services with port>=8000, got %d", len(results))
	}
}

func TestSelectAllPosition(t *testing.T) {
	doc, _ := Parse(fx(t, "api_multi.cx"))
	results, err := doc.SelectAll("//service[2]")
	if err != nil {
		t.Fatal(err)
	}
	if len(results) != 1 {
		t.Fatalf("expected 1 result for service[2], got %d", len(results))
	}
	if results[0].Attr("name") != "api" {
		t.Fatalf("expected 2nd service 'api', got %v", results[0].Attr("name"))
	}
}

func TestSelectAllLastPosition(t *testing.T) {
	doc, _ := Parse(fx(t, "api_multi.cx"))
	results, err := doc.SelectAll("//service[last()]")
	if err != nil {
		t.Fatal(err)
	}
	if len(results) != 1 {
		t.Fatalf("expected 1 result for service[last()], got %d", len(results))
	}
	if results[0].Attr("name") != "worker" {
		t.Fatalf("expected last service 'worker', got %v", results[0].Attr("name"))
	}
}

func TestSelectAllContains(t *testing.T) {
	doc, _ := Parse(fx(t, "api_multi.cx"))
	// 'auth' and 'api' both contain 'a', 'worker' does not
	results, err := doc.SelectAll("//service[contains(@name, 'a')]")
	if err != nil {
		t.Fatal(err)
	}
	if len(results) != 2 {
		t.Fatalf("expected 2 services containing 'a' in name, got %d", len(results))
	}
}

func TestSelectAllStartsWith(t *testing.T) {
	doc, _ := Parse(fx(t, "api_multi.cx"))
	// 'auth' and 'api' start with 'a'
	results, err := doc.SelectAll("//service[starts-with(@name, 'a')]")
	if err != nil {
		t.Fatal(err)
	}
	if len(results) != 2 {
		t.Fatalf("expected 2 services starting with 'a', got %d", len(results))
	}
}

func TestSelectAllBoolAnd(t *testing.T) {
	doc, err := Parse("[services\n  [service name=auth port=8080 active=true]\n  [service name=api port=9000 active=false]\n  [service name=web port=8080 active=true]\n]")
	if err != nil {
		t.Fatal(err)
	}
	results, err := doc.SelectAll("//service[@active=true and @port=8080]")
	if err != nil {
		t.Fatal(err)
	}
	if len(results) != 2 {
		t.Fatalf("expected 2 services with active=true and port=8080, got %d", len(results))
	}
}

func TestSelectOnElement(t *testing.T) {
	doc, err := Parse("[services\n  [service name=auth port=8080 active=true]\n  [service name=api port=9000 active=false]\n  [service name=web port=80 active=true]\n]")
	if err != nil {
		t.Fatal(err)
	}
	servicesEl := doc.Root()
	results, err := servicesEl.SelectAll("service[@active=true]")
	if err != nil {
		t.Fatal(err)
	}
	if len(results) != 2 {
		t.Fatalf("expected 2 active services from element SelectAll, got %d", len(results))
	}
}

func TestSelectInvalidExprReturnsError(t *testing.T) {
	doc, _ := Parse(fx(t, "api_config.cx"))
	_, err := doc.SelectAll("[@]")
	if err == nil {
		t.Fatal("expected error for invalid expression")
	}
}

// ── Transform ─────────────────────────────────────────────────────────────────

func TestTransformReturnsNewDocument(t *testing.T) {
	doc, _ := Parse(fx(t, "api_config.cx"))
	updated := doc.Transform("config/server", func(el *Element) *Element {
		return el
	})
	if updated == doc {
		t.Fatal("expected Transform to return a new *Document pointer")
	}
}

func TestTransformAppliesFunctionToElementAtPath(t *testing.T) {
	doc, _ := Parse(fx(t, "api_config.cx"))
	updated := doc.Transform("config/server", func(el *Element) *Element {
		el.SetAttr("host", "prod.example.com", "")
		return el
	})
	host := updated.At("config/server").Attr("host")
	if host != "prod.example.com" {
		t.Fatalf("expected 'prod.example.com', got %v", host)
	}
}

func TestTransformOriginalDocumentUnchanged(t *testing.T) {
	doc, _ := Parse(fx(t, "api_config.cx"))
	doc.Transform("config/server", func(el *Element) *Element {
		el.SetAttr("host", "prod.example.com", "")
		return el
	})
	host := doc.At("config/server").Attr("host")
	if host != "localhost" {
		t.Fatalf("expected original 'localhost', got %v", host)
	}
}

func TestTransformMissingPathReturnsOriginal(t *testing.T) {
	doc, _ := Parse(fx(t, "api_config.cx"))
	updated := doc.Transform("config/nonexistent", func(el *Element) *Element {
		return el
	})
	// Should return original doc unchanged (same elements)
	if updated.At("config/server") == nil {
		t.Fatal("expected config/server to still exist in result")
	}
}

func TestTransformChained(t *testing.T) {
	doc, _ := Parse(fx(t, "api_config.cx"))
	result := doc.
		Transform("config/server", func(el *Element) *Element {
			el.SetAttr("host", "web.example.com", "")
			return el
		}).
		Transform("config/database", func(el *Element) *Element {
			el.SetAttr("host", "db.example.com", "")
			return el
		})
	if result.At("config/server").Attr("host") != "web.example.com" {
		t.Fatal("expected server host 'web.example.com'")
	}
	if result.At("config/database").Attr("host") != "db.example.com" {
		t.Fatal("expected database host 'db.example.com'")
	}
}

// ── TransformAll ──────────────────────────────────────────────────────────────

func TestTransformAllAppliesToAllMatchingElements(t *testing.T) {
	doc, err := Parse("[services\n  [service name=auth port=8080]\n  [service name=api port=9000]\n]")
	if err != nil {
		t.Fatal(err)
	}
	updated, err := doc.TransformAll("//service", func(el *Element) *Element {
		el.SetAttr("active", true, "bool")
		return el
	})
	if err != nil {
		t.Fatal(err)
	}
	svcs := updated.FindAll("service")
	for _, svc := range svcs {
		if svc.Attr("active") != true {
			t.Fatalf("expected active=true on %s, got %v", svc.Attr("name"), svc.Attr("active"))
		}
	}
}

func TestTransformAllReturnsNewDocument(t *testing.T) {
	doc, _ := Parse(fx(t, "api_config.cx"))
	updated, err := doc.TransformAll("//server", func(el *Element) *Element {
		return el
	})
	if err != nil {
		t.Fatal(err)
	}
	if updated == doc {
		t.Fatal("expected TransformAll to return a new *Document pointer")
	}
}

func TestTransformAllNoMatchesReturnsEquivalentDoc(t *testing.T) {
	doc, _ := Parse(fx(t, "api_config.cx"))
	updated, err := doc.TransformAll("//nonexistent", func(el *Element) *Element {
		el.SetAttr("touched", true, "bool")
		return el
	})
	if err != nil {
		t.Fatal(err)
	}
	// No matches — server should still have original host
	if updated.At("config/server").Attr("host") != "localhost" {
		t.Fatal("expected server host 'localhost' when no matches")
	}
}

func TestTransformAllDeeplyNested(t *testing.T) {
	doc, _ := Parse(fx(t, "api_article.cx"))
	updated, err := doc.TransformAll("//p", func(el *Element) *Element {
		el.SetAttr("processed", true, "bool")
		return el
	})
	if err != nil {
		t.Fatal(err)
	}
	ps := updated.FindAll("p")
	if len(ps) != 3 {
		t.Fatalf("expected 3 p elements, got %d", len(ps))
	}
	for _, p := range ps {
		if p.Attr("processed") != true {
			t.Fatalf("expected processed=true on p, got %v", p.Attr("processed"))
		}
	}
}
