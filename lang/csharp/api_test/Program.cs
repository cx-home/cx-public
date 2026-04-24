// CX C# Document API test runner.
// Run: dotnet run --project csharp/api_test/api_test.csproj -c Release
using CX;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

// ── fixture path ──────────────────────────────────────────────────────────────

// AppContext.BaseDirectory is e.g. csharp/api_test/bin/Release/net10.0/
// Walk up to find the repo root (contains a "fixtures" directory)
string FindFixturesDir()
{
    var dir = new DirectoryInfo(AppContext.BaseDirectory);
    while (dir != null)
    {
        string candidate = Path.Combine(dir.FullName, "fixtures");
        if (Directory.Exists(candidate) && File.Exists(Path.Combine(candidate, "api_config.cx")))
            return candidate;
        dir = dir.Parent;
    }
    throw new DirectoryNotFoundException("Cannot find fixtures/ directory");
}

string fixtures = FindFixturesDir();

// ── test runner ───────────────────────────────────────────────────────────────

int passed = 0, failed = 0;

void Expect(bool condition, string msg)
{
    if (condition) { Console.WriteLine($"  PASS: {msg}"); passed++; }
    else { Console.Error.WriteLine($"  FAIL: {msg}"); failed++; }
}

string Fx(string name) => File.ReadAllText(Path.Combine(fixtures, name));

void Section(string title) => Console.WriteLine($"\n── {title}");

// ── parse / root / get ────────────────────────────────────────────────────────

Section("parse / root / get");

{
    var doc = CXDocument.Parse(Fx("api_config.cx"));
    Expect(doc is not null, "parse returns CXDocument");
    Expect(doc!.Root()?.Name == "config", "root returns first element");
}

{
    var doc = CXDocument.Parse("");
    Expect(doc.Root() is null, "root is null on empty input");
}

{
    var doc = CXDocument.Parse(Fx("api_config.cx"));
    Expect(doc.Get("config")?.Name == "config", "get top-level by name");
    Expect(doc.Get("missing") is null, "get missing returns null");
}

{
    var doc = CXDocument.Parse(Fx("api_multi.cx"));
    Expect(doc.Get("service")?.Attr("name") as string == "auth", "get multi top-level returns first");
}

{
    var doc = CXDocument.Parse(Fx("api_multi.cx"));
    int count = doc.Elements.OfType<Element>().Count(e => e.Name == "service");
    Expect(count == 3, "parse multiple top-level elements");
}

// ── attr ──────────────────────────────────────────────────────────────────────

Section("attr");

{
    var srv = CXDocument.Parse(Fx("api_config.cx")).At("config/server");
    Expect(srv?.Attr("host") as string == "localhost", "attr string");
    Expect(srv?.Attr("port") is long p && p == 8080L, "attr int");
    Expect(srv?.Attr("debug") is false, "attr bool false");
    double ratio = Convert.ToDouble(srv?.Attr("ratio"));
    Expect(Math.Abs(ratio - 1.5) < 1e-9, "attr float");
    Expect(srv?.Attr("nonexistent") is null, "attr missing returns null");
}

// ── scalar ────────────────────────────────────────────────────────────────────

Section("scalar");

{
    var el = CXDocument.Parse(Fx("api_scalars.cx")).At("values/count");
    var sv = el?.Scalar();
    Expect(sv is long l && l == 42L, "scalar int");
}

{
    var el = CXDocument.Parse(Fx("api_scalars.cx")).At("values/ratio");
    double v = Convert.ToDouble(el?.Scalar());
    Expect(Math.Abs(v - 1.5) < 1e-9, "scalar float");
}

{
    var el = CXDocument.Parse(Fx("api_scalars.cx")).At("values/enabled");
    Expect(el?.Scalar() is true, "scalar bool true");
}

{
    var el = CXDocument.Parse(Fx("api_scalars.cx")).At("values/disabled");
    Expect(el?.Scalar() is false, "scalar bool false");
}

{
    var el = CXDocument.Parse(Fx("api_scalars.cx")).At("values/nothing");
    Expect(el?.Scalar() is null, "scalar null");
}

{
    var doc = CXDocument.Parse(Fx("api_config.cx"));
    Expect(doc.Root()?.Scalar() is null, "scalar null when element has children");
}

// ── text ──────────────────────────────────────────────────────────────────────

Section("text");

{
    var doc = CXDocument.Parse(Fx("api_article.cx"));
    Expect(doc.At("article/body/h1")?.Text() == "Introduction", "text single token");
}

{
    var el = CXDocument.Parse(Fx("api_scalars.cx")).At("values/label");
    Expect(el?.Text() == "hello world", "text quoted");
}

{
    var doc = CXDocument.Parse(Fx("api_config.cx"));
    Expect(doc.Root()?.Text() == "", "text empty when no text children");
}

// ── children / get_all ────────────────────────────────────────────────────────

Section("children / GetAll");

{
    var config = CXDocument.Parse(Fx("api_config.cx")).Root();
    var kids = config?.Children().ToList();
    Expect(kids?.Count == 3, "children count");
    Expect(kids?.All(k => k is Element) == true, "children all elements");
    Expect(kids?.Select(k => k.Name).SequenceEqual(new[] { "server", "database", "logging" }) == true,
        "children names in order");
}

{
    var doc = CXDocument.Parse("[root [item 1] [item 2] [other x] [item 3]]");
    var items = doc.Root()?.GetAll("item").ToList();
    Expect(items?.Count == 3, "get_all direct children");
}

{
    var config = CXDocument.Parse(Fx("api_config.cx")).Root();
    Expect(!config?.GetAll("missing").Any() == true, "get_all empty for missing");
}

// ── at ────────────────────────────────────────────────────────────────────────

Section("at");

{
    var doc = CXDocument.Parse(Fx("api_config.cx"));
    Expect(doc.At("config")?.Name == "config", "at single segment");
    Expect(doc.At("config/server")?.Name == "server", "at two segments (server)");
    Expect(doc.At("config/database")?.Name == "database", "at two segments (database)");
}

{
    var doc = CXDocument.Parse(Fx("api_article.cx"));
    Expect(doc.At("article/head/title")?.Text() == "Getting Started with CX", "at three segments (title)");
    Expect(doc.At("article/body/h1")?.Text() == "Introduction", "at three segments (h1)");
}

{
    var doc = CXDocument.Parse(Fx("api_config.cx"));
    Expect(doc.At("config/missing") is null, "at missing segment returns null");
    Expect(doc.At("missing") is null, "at missing root returns null");
    Expect(doc.At("config/server/missing/deep") is null, "at deep missing returns null");
}

{
    var doc = CXDocument.Parse(Fx("api_article.cx"));
    var body = doc.At("article/body");
    Expect(body?.At("section/h2")?.Text() == "Details", "element at relative path");
}

// ── find_all ──────────────────────────────────────────────────────────────────

Section("find_all");

{
    var doc = CXDocument.Parse(Fx("api_multi.cx"));
    Expect(doc.FindAll("service").Count() == 3, "find_all top-level");
}

{
    var doc = CXDocument.Parse(Fx("api_article.cx"));
    var ps = doc.FindAll("p").ToList();
    Expect(ps.Count == 3, "find_all deep count");
    Expect(ps[0].Text() == "First paragraph.", "find_all deep first");
    Expect(ps[1].Text() == "Nested paragraph.", "find_all deep second");
    Expect(ps[2].Text() == "Another nested paragraph.", "find_all deep third");
}

{
    var doc = CXDocument.Parse(Fx("api_config.cx"));
    Expect(!doc.FindAll("missing").Any(), "find_all missing returns empty");
}

{
    var body = CXDocument.Parse(Fx("api_article.cx")).At("article/body");
    Expect(body?.FindAll("p").Count() == 3, "find_all on element");
}

// ── find_first ────────────────────────────────────────────────────────────────

Section("find_first");

{
    var doc = CXDocument.Parse(Fx("api_article.cx"));
    var p = doc.FindFirst("p");
    Expect(p is not null, "find_first not null");
    Expect(p?.Text() == "First paragraph.", "find_first returns first match");
}

{
    var doc = CXDocument.Parse(Fx("api_config.cx"));
    Expect(doc.FindFirst("missing") is null, "find_first missing returns null");
}

{
    var doc = CXDocument.Parse(Fx("api_article.cx"));
    Expect(doc.FindFirst("h1")?.Text() == "Introduction", "find_first depth-first h1");
    Expect(doc.FindFirst("h2")?.Text() == "Details", "find_first depth-first h2");
}

{
    var section = CXDocument.Parse(Fx("api_article.cx")).At("article/body/section");
    Expect(section?.FindFirst("p")?.Text() == "Nested paragraph.", "find_first on element");
}

// ── mutation — Element ────────────────────────────────────────────────────────

Section("mutation — Element");

{
    var doc = CXDocument.Parse(Fx("api_config.cx"));
    doc.Root()!.Append(new Element("cache"));
    var kids = doc.Root()!.Children().ToList();
    Expect(kids[^1].Name == "cache", "append adds to end");
    Expect(kids.Count == 4, "append increases count");
}

{
    var doc = CXDocument.Parse(Fx("api_config.cx"));
    doc.Root()!.Prepend(new Element("meta"));
    Expect(doc.Root()!.Children().First().Name == "meta", "prepend adds to front");
}

{
    var doc = CXDocument.Parse("[root [a 1] [c 3]]");
    doc.Root()!.Insert(1, new Element("b"));
    var names = doc.Root()!.Children().Select(k => k.Name).ToList();
    Expect(names.SequenceEqual(new[] { "a", "b", "c" }), "insert at index");
}

{
    var doc = CXDocument.Parse(Fx("api_config.cx"));
    var db = doc.At("config/database")!;
    doc.Root()!.Remove(db);
    Expect(doc.At("config/database") is null, "remove clears element");
    Expect(doc.At("config/server") is not null, "remove leaves others intact");
}

{
    var doc = CXDocument.Parse(Fx("api_config.cx"));
    var srv = doc.At("config/server")!;
    srv.SetAttr("env", "production");
    Expect(srv.Attr("env") as string == "production", "set_attr new");
}

{
    var doc = CXDocument.Parse(Fx("api_config.cx"));
    var srv = doc.At("config/server")!;
    srv.SetAttr("port", 9090L, "int");
    Expect(Convert.ToInt64(srv.Attr("port")) == 9090L, "set_attr update value");
    Expect(srv.Attrs.Count == 4, "set_attr no duplicate");
}

{
    var doc = CXDocument.Parse(Fx("api_config.cx"));
    var srv = doc.At("config/server")!;
    int originalCount = srv.Attrs.Count;
    srv.SetAttr("debug", true, "bool");
    Expect(srv.Attr("debug") is true, "set_attr change type value");
    Expect(srv.Attrs.Count == originalCount, "set_attr change type no dup");
}

{
    var doc = CXDocument.Parse(Fx("api_config.cx"));
    var srv = doc.At("config/server")!;
    int originalCount = srv.Attrs.Count;
    srv.RemoveAttr("debug");
    Expect(srv.Attr("debug") is null, "remove_attr removes it");
    Expect(srv.Attrs.Count == originalCount - 1, "remove_attr reduces count");
}

{
    var doc = CXDocument.Parse(Fx("api_config.cx"));
    var srv = doc.At("config/server")!;
    int originalCount = srv.Attrs.Count;
    srv.RemoveAttr("nonexistent");
    Expect(srv.Attrs.Count == originalCount, "remove_attr nonexistent is noop");
}

// ── mutation — Document ───────────────────────────────────────────────────────

Section("mutation — Document");

{
    var doc = CXDocument.Parse(Fx("api_config.cx"));
    doc.Append(new Element("cache") { Attrs = new List<Attr> { new Attr("host", "redis") } });
    Expect(doc.Get("cache")?.Attr("host") as string == "redis", "doc append element");
}

{
    var doc = CXDocument.Parse(Fx("api_config.cx"));
    doc.Prepend(new Element("preamble"));
    Expect(doc.Root()?.Name == "preamble", "doc prepend makes new root");
    Expect(doc.Get("config") is not null, "doc prepend original still present");
}

// ── round-trips ───────────────────────────────────────────────────────────────

Section("round-trips");

{
    var original = CXDocument.Parse(Fx("api_config.cx"));
    var reparsed = CXDocument.Parse(original.ToCx());
    Expect(reparsed.At("config/server")?.Attr("host") as string == "localhost", "round-trip host");
    Expect(Convert.ToInt64(reparsed.At("config/server")?.Attr("port")) == 8080L, "round-trip port");
    Expect(reparsed.At("config/database")?.Attr("name") as string == "myapp", "round-trip database name");
}

{
    var doc = CXDocument.Parse(Fx("api_config.cx"));
    doc.At("config/server")!.SetAttr("env", "production");
    doc.At("config/server")!.Append(new Element("timeout")
    {
        Items = new List<Node> { new ScalarNode("int", 30L) }
    });
    var reparsed = CXDocument.Parse(doc.ToCx());
    Expect(reparsed.At("config/server")?.Attr("env") as string == "production",
        "round-trip after mutation env");
    Expect(Convert.ToInt64(reparsed.At("config/server")?.FindFirst("timeout")?.Scalar()) == 30L,
        "round-trip after mutation scalar");
}

{
    var original = CXDocument.Parse(Fx("api_article.cx"));
    var reparsed = CXDocument.Parse(original.ToCx());
    Expect(reparsed.At("article/head/title")?.Text() == "Getting Started with CX",
        "round-trip article title");
    Expect(reparsed.FindAll("p").Count() == 3, "round-trip article paragraphs");
}

// ── loads / dumps ─────────────────────────────────────────────────────────────

Section("loads / dumps");

{
    var data = CXDocument.Loads(Fx("api_config.cx"));
    Expect(data is Dictionary<string, object?> d, "loads returns dict");
    var config = (Dictionary<string, object?>)((Dictionary<string, object?>)data!)["config"]!;
    var server = (Dictionary<string, object?>)config["server"]!;
    Expect(server["host"] as string == "localhost", "loads server host");
    Expect(Convert.ToInt64(server["port"]) == 8080L, "loads server port");
}

{
    var data = CXDocument.Loads(Fx("api_config.cx"));
    var config = (Dictionary<string, object?>)((Dictionary<string, object?>)data!)["config"]!;
    var server = (Dictionary<string, object?>)config["server"]!;
    Expect(server["debug"] is false, "loads bool false");
}

{
    var data = CXDocument.Loads(Fx("api_scalars.cx"));
    var values = (Dictionary<string, object?>)((Dictionary<string, object?>)data!)["values"]!;
    Expect(Convert.ToInt64(values["count"]) == 42L, "loads scalar int");
    Expect(values["enabled"] is true, "loads scalar bool true");
    Expect(values["disabled"] is false, "loads scalar bool false");
    Expect(values["nothing"] is null, "loads scalar null");
}

{
    var data = CXDocument.LoadsXml("<server host=\"localhost\" port=\"8080\"/>");
    Expect(data is Dictionary<string, object?> d && d.ContainsKey("server"), "loads_xml");
}

{
    var data = CXDocument.LoadsJson("{\"port\": 8080, \"debug\": false}");
    Expect(data is Dictionary<string, object?> d2 && Convert.ToInt64(d2["port"]) == 8080L,
        "loads_json port");
    Expect(data is Dictionary<string, object?> d3 && d3["debug"] is false, "loads_json bool");
}

{
    var data = CXDocument.LoadsYaml("server:\n  host: localhost\n  port: 8080\n");
    Expect(data is Dictionary<string, object?> d && d.ContainsKey("server"), "loads_yaml");
}

{
    var original = new Dictionary<string, object?> {
        ["app"] = new Dictionary<string, object?> {
            ["name"] = "myapp",
            ["version"] = "1.0",
            ["port"] = 8080
        }
    };
    string cxStr = CXDocument.Dumps(original);
    var reparsed = CXDocument.Parse(cxStr);
    Expect(reparsed.FindFirst("app") is not null, "dumps produces parseable cx");
}

{
    var original = new Dictionary<string, object?> {
        ["server"] = new Dictionary<string, object?> {
            ["host"] = "localhost",
            ["port"] = 8080,
            ["debug"] = false
        }
    };
    var restored = CXDocument.Loads(CXDocument.Dumps(original)) as Dictionary<string, object?>;
    var srv2 = restored!["server"] as Dictionary<string, object?>;
    Expect(Convert.ToInt64(srv2!["port"]) == 8080L, "loads_dumps port preserved");
    Expect(srv2["host"] as string == "localhost", "loads_dumps host preserved");
    Expect(srv2["debug"] is false, "loads_dumps debug preserved");
}

// ── error / failure cases ─────────────────────────────────────────────────────

Section("error / failure cases");

{
    bool threw = false;
    try { CXDocument.Parse(Fx("errors/unclosed.cx")); }
    catch { threw = true; }
    Expect(threw, "unclosed bracket should throw");
}

{
    bool threw = false;
    try { CXDocument.Parse(Fx("errors/empty_name.cx")); }
    catch { threw = true; }
    Expect(threw, "empty element name should throw");
}

{
    bool threw = false;
    try { CXDocument.Parse(Fx("errors/nested_unclosed.cx")); }
    catch { threw = true; }
    Expect(threw, "nested unclosed should throw");
}

{
    var doc = CXDocument.Parse(Fx("api_config.cx"));
    Expect(doc.At("config/server/missing/deep/path") is null, "at deep missing returns null (no exception)");
}

{
    var doc = CXDocument.Parse("");
    Expect(!doc.FindAll("anything").Any(), "find_all on empty doc returns empty");
    Expect(doc.FindFirst("anything") is null, "find_first on empty doc returns null");
}

{
    var doc = CXDocument.Parse(Fx("api_config.cx"));
    Expect(doc.Root()?.Scalar() is null, "scalar null when element has child elements");
    Expect(doc.Root()?.Text() == "", "text empty when no text children");
}

{
    var doc = CXDocument.Parse(Fx("api_config.cx"));
    var srv = doc.At("config/server")!;
    srv.RemoveAttr("totally_missing"); // should not throw
    Expect(true, "remove_attr nonexistent does not raise");
}

{
    bool threw = false;
    try { CXDocument.ParseXml("<unclosed"); }
    catch { threw = true; }
    Expect(threw, "parse_xml invalid should throw");
}

// ── parse other formats ───────────────────────────────────────────────────────

Section("parse other formats");

{
    var doc = CXDocument.ParseXml("<root><child key=\"val\"/></root>");
    Expect(doc.Root()?.Name == "root", "parse_xml root");
    Expect(doc.FindFirst("child") is not null, "parse_xml child");
}

{
    var doc = CXDocument.ParseJson("{\"server\": {\"port\": 8080}}");
    Expect(doc.FindFirst("server") is not null, "parse_json server");
}

{
    var doc = CXDocument.ParseYaml("server:\n  port: 8080\n");
    Expect(doc.FindFirst("server") is not null, "parse_yaml server");
}

// ── stream (binary events decoder) ───────────────────────────────────────────

Section("stream");

{
    // Minimal document: StartDoc, StartElement, EndElement, EndDoc
    var events = CXDocument.Stream("[root]");
    Expect(events.Count == 4, "stream [root] yields 4 events");
    Expect(events[0].Type == "StartDoc",     "stream event[0] is StartDoc");
    Expect(events[1].Type == "StartElement", "stream event[1] is StartElement");
    Expect(events[1].Name == "root",         "stream StartElement name is 'root'");
    Expect(events[2].Type == "EndElement",   "stream event[2] is EndElement");
    Expect(events[2].Name == "root",         "stream EndElement name is 'root'");
    Expect(events[3].Type == "EndDoc",       "stream event[3] is EndDoc");
}

{
    // Attributes and typed values
    var events = CXDocument.Stream("[server host=localhost port=8080 debug=false]");
    var start = events.FirstOrDefault(e => e.Type == "StartElement");
    Expect(start is not null,                     "stream attr: StartElement present");
    Expect(start!.Name == "server",               "stream attr: element name");
    Expect(start.Attrs.Count == 3,                "stream attr: 3 attributes");
    Expect(start.Attrs[0].Name == "host",         "stream attr[0] name");
    Expect(start.Attrs[0].Value as string == "localhost", "stream attr[0] value");
    Expect(start.Attrs[1].Value is long p && p == 8080L,  "stream attr[1] int value");
    Expect(start.Attrs[2].Value is false,                 "stream attr[2] bool value");
}

{
    // Text child content
    var events = CXDocument.Stream("[title 'Hello World']");
    var textEv = events.FirstOrDefault(e => e.Type == "Text");
    Expect(textEv is not null,                      "stream text: Text event present");
    Expect(textEv!.Value as string == "Hello World","stream text: value correct");
}

{
    // Scalar child
    var events = CXDocument.Stream("[count 42]");
    var scalar = events.FirstOrDefault(e => e.Type == "Scalar");
    Expect(scalar is not null,               "stream scalar: Scalar event present");
    Expect(scalar!.Value is long v && v == 42L, "stream scalar: int value 42");
}

{
    // Nested elements produce multiple StartElement/EndElement pairs
    var events = CXDocument.Stream("[root [child 'text']]");
    var starts = events.Where(e => e.Type == "StartElement").ToList();
    var ends   = events.Where(e => e.Type == "EndElement").ToList();
    Expect(starts.Count == 2, "stream nested: 2 StartElement events");
    Expect(ends.Count   == 2, "stream nested: 2 EndElement events");
    Expect(starts[0].Name == "root",  "stream nested: first StartElement is root");
    Expect(starts[1].Name == "child", "stream nested: second StartElement is child");
}

{
    // Comment event
    var events = CXDocument.Stream("[root [-a comment]]");
    var comment = events.FirstOrDefault(e => e.Type == "Comment");
    Expect(comment is not null,                       "stream comment: Comment event present");
    Expect(comment!.Value as string == "a comment",   "stream comment: value correct");
}

// ── RemoveChild / RemoveAt ────────────────────────────────────────────────────

Section("RemoveChild / RemoveAt");

{
    var doc = CXDocument.Parse("[root [item a] [item b] [other x] [item c]]");
    var root = doc.Root()!;
    root.RemoveChild("item");
    var kids = root.Children().ToList();
    Expect(kids.Count == 1, "RemoveChild removes all matching children");
    Expect(kids[0].Name == "other", "RemoveChild leaves non-matching intact");
}

{
    var doc = CXDocument.Parse("[root [a] [b] [c]]");
    doc.Root()!.RemoveChild("missing");
    Expect(doc.Root()!.Children().Count() == 3, "RemoveChild nonexistent is no-op");
}

{
    var doc = CXDocument.Parse("[root [a] [b] [c]]");
    doc.Root()!.RemoveAt(1);
    var names = doc.Root()!.Children().Select(k => k.Name).ToList();
    Expect(names.SequenceEqual(new[] { "a", "c" }), "RemoveAt removes by index");
}

{
    var doc = CXDocument.Parse("[root [a] [b]]");
    doc.Root()!.RemoveAt(99);
    Expect(doc.Root()!.Children().Count() == 2, "RemoveAt out-of-bounds is no-op");
}

{
    var doc = CXDocument.Parse("[root [a] [b]]");
    doc.Root()!.RemoveAt(-1);
    Expect(doc.Root()!.Children().Count() == 2, "RemoveAt negative index is no-op");
}

// ── SelectAll / Select ────────────────────────────────────────────────────────

Section("SelectAll / Select");

{
    var doc = CXDocument.Parse(Fx("api_multi.cx"));
    var all = doc.SelectAll("//service").ToList();
    Expect(all.Count == 3, "SelectAll descendant axis matches all");
    Expect(all[0].Attr("name") as string == "auth", "SelectAll first result is auth");
}

{
    var doc = CXDocument.Parse(Fx("api_multi.cx"));
    var first = doc.Select("//service");
    Expect(first is not null, "Select returns first match");
    Expect(first!.Attr("name") as string == "auth", "Select first is auth");
}

{
    var doc = CXDocument.Parse(Fx("api_multi.cx"));
    var matched = doc.SelectAll("//service[@name=auth]").ToList();
    Expect(matched.Count == 1, "SelectAll attr string predicate");
    Expect(matched[0].Attr("name") as string == "auth", "SelectAll attr string value correct");
}

{
    var doc = CXDocument.Parse(Fx("api_multi.cx"));
    var matched = doc.SelectAll("//service[@port>=8080]").ToList();
    Expect(matched.Count == 2, "SelectAll numeric comparison >=");
}

{
    var doc = CXDocument.Parse(Fx("api_multi.cx"));
    var matched = doc.SelectAll("//service[@name=auth or @name=worker]").ToList();
    Expect(matched.Count == 2, "SelectAll boolean or predicate");
}

{
    var doc = CXDocument.Parse(Fx("api_multi.cx"));
    var matched = doc.SelectAll("//service[@port>8000 and @name=api]").ToList();
    Expect(matched.Count == 1, "SelectAll boolean and predicate");
    Expect(matched[0].Attr("name") as string == "api", "SelectAll and result is api");
}

{
    var doc = CXDocument.Parse(Fx("api_multi.cx"));
    var second = doc.Select("//service[2]");
    Expect(second is not null, "Select position predicate [2]");
    Expect(second!.Attr("name") as string == "api", "Select [2] is api");
}

{
    var doc = CXDocument.Parse(Fx("api_multi.cx"));
    var last = doc.Select("//service[last()]");
    Expect(last is not null, "Select last() predicate");
    Expect(last!.Attr("name") as string == "worker", "Select last() is worker");
}

{
    var doc = CXDocument.Parse(Fx("api_multi.cx"));
    var matched = doc.SelectAll("//service[contains(@name, 'or')]").ToList();
    Expect(matched.Count == 1, "SelectAll contains() predicate");
    Expect(matched[0].Attr("name") as string == "worker", "SelectAll contains result is worker");
}

{
    var doc = CXDocument.Parse(Fx("api_multi.cx"));
    var matched = doc.SelectAll("//service[starts-with(@name, 'a')]").ToList();
    Expect(matched.Count == 2, "SelectAll starts-with() predicate");
}

{
    var doc = CXDocument.Parse(Fx("api_article.cx"));
    var matched = doc.SelectAll("article/body/p").ToList();
    Expect(matched.Count == 1, "SelectAll child path (direct child only)");
    Expect(matched[0].Text() == "First paragraph.", "SelectAll child path result correct");
}

{
    var doc = CXDocument.Parse(Fx("api_multi.cx"));
    var matched = doc.SelectAll("//*[@port]").ToList();
    Expect(matched.Count == 3, "SelectAll wildcard with attr existence predicate");
}

{
    // select on Element searches only its subtree
    var body = CXDocument.Parse(Fx("api_article.cx")).At("article/body")!;
    var ps = body.SelectAll("//p").ToList();
    Expect(ps.Count == 3, "SelectAll on element searches subtree");
    Expect(ps[0].Text() == "First paragraph.", "SelectAll on element first result correct");
}

{
    var doc = CXDocument.Parse(Fx("api_multi.cx"));
    Expect(doc.Select("//nonexistent") is null, "Select returns null when no match");
}

// ── Transform ─────────────────────────────────────────────────────────────────

Section("Transform");

{
    var doc = CXDocument.Parse(Fx("api_config.cx"));
    var updated = doc.Transform("config/server", el => { el.SetAttr("host", "prod.example.com"); return el; });
    Expect(!ReferenceEquals(doc, updated), "Transform returns new document");
    Expect(updated.At("config/server")?.Attr("host") as string == "prod.example.com",
        "Transform applies function to element");
}

{
    var doc = CXDocument.Parse(Fx("api_config.cx"));
    var updated = doc.Transform("config/server", el => { el.SetAttr("host", "prod.example.com"); return el; });
    Expect(doc.At("config/server")?.Attr("host") as string == "localhost",
        "Transform original document unchanged");
}

{
    var doc = CXDocument.Parse(Fx("api_config.cx"));
    var same = doc.Transform("config/missing", el => el);
    Expect(ReferenceEquals(doc, same), "Transform missing path returns same document");
}

{
    var doc = CXDocument.Parse(Fx("api_config.cx"));
    var result = doc
        .Transform("config/server", el => { el.SetAttr("host", "web.example.com"); return el; })
        .Transform("config/database", el => { el.SetAttr("host", "db.example.com"); return el; });
    Expect(result.At("config/server")?.Attr("host") as string == "web.example.com",
        "Transform chained — server updated");
    Expect(result.At("config/database")?.Attr("host") as string == "db.example.com",
        "Transform chained — database updated");
}

{
    var doc = CXDocument.Parse(Fx("api_config.cx"));
    var updated = doc.Transform("config", el => { el.SetAttr("version", "2.0"); return el; });
    Expect(updated.Root()?.Attr("version") as string == "2.0",
        "Transform on top-level element");
}

// ── TransformAll ──────────────────────────────────────────────────────────────

Section("TransformAll");

{
    var doc = CXDocument.Parse(Fx("api_multi.cx"));
    var updated = doc.TransformAll("//service", el => { el.SetAttr("active", true); return el; });
    Expect(!ReferenceEquals(doc, updated), "TransformAll returns new document");
    var services = updated.FindAll("service").ToList();
    Expect(services.Count == 3, "TransformAll all matches updated");
    Expect(services.All(s => s.Attr("active") is true), "TransformAll function applied to all");
}

{
    var doc = CXDocument.Parse(Fx("api_multi.cx"));
    doc.TransformAll("//service", el => { el.SetAttr("active", true); return el; });
    var services = doc.FindAll("service").ToList();
    Expect(services.All(s => s.Attr("active") is null), "TransformAll original unchanged");
}

{
    var doc = CXDocument.Parse(Fx("api_config.cx"));
    var same = doc.TransformAll("//nonexistent", el => el);
    Expect(same.ToCx() == doc.ToCx(), "TransformAll no matches returns equivalent document");
}

{
    var doc = CXDocument.Parse(Fx("api_article.cx"));
    var updated = doc.TransformAll("//p", el => { el.SetAttr("class", "para"); return el; });
    var ps = updated.FindAll("p").ToList();
    Expect(ps.Count == 3, "TransformAll deeply nested — all matched");
    Expect(ps.All(p => p.Attr("class") as string == "para"),
        "TransformAll deeply nested — all updated");
}

// ── summary ───────────────────────────────────────────────────────────────────

Console.WriteLine($"\ncsharp/api_test: {passed} passed, {failed} failed  [{(failed == 0 ? "OK" : "FAILED")}]");
if (failed > 0) Environment.Exit(1);
