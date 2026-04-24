using CX;

string cxStr = """
[config version='1.0' debug=false
  [server host=localhost port=8080]
  [database url='postgres://localhost/mydb' pool=10]
  [cache enabled=true ttl=300]
]
""";

// ── Document model demo ───────────────────────────────────────────────────────

Console.WriteLine("=== Document Model ===");

// 1. Parse
var doc = CXDocument.Parse(cxStr);

// 2. Read: get server element, print host and port
var server = doc.At("config/server")!;
Console.WriteLine($"host: {server.Attr("host")}");
Console.WriteLine($"port: {server.Attr("port")}");

// 3. Update: change host to prod.example.com
server.SetAttr("host", "prod.example.com");

// 4. Create: add timeout child element to server
var timeout = new Element("timeout");
timeout.Attrs.Add(new Attr("seconds", 30L, "int"));
server.Append(timeout);

// 5. Delete: remove cache from config
var config = doc.Root()!;
var cache = config.Get("cache")!;
config.Remove(cache);

// 6. Print result as CX
Console.WriteLine("\n--- Modified document ---");
Console.WriteLine(doc.ToCx());

// ── Streaming demo ────────────────────────────────────────────────────────────

Console.WriteLine("\n=== Streaming ===");

foreach (var ev in CXDocument.Stream(cxStr))
{
    Console.Write($"event: {ev.Type}");
    if (ev.Type == "StartElement")
    {
        Console.Write($"  name={ev.Name}");
        foreach (var attr in ev.Attrs)
            Console.Write($"  {attr.Name}={attr.Value}");
    }
    Console.WriteLine();
}

// ── CXPath & Transform demo ───────────────────────────────────────────────────

Console.WriteLine("\n=== CXPath & Transform ===");

var servicesSrc = "[services\n  [service name=auth  port=8080 active=true]\n  [service name=api   port=9000 active=false]\n  [service name=web   port=80   active=true]\n]";
var svcDoc = CXDocument.Parse(servicesSrc);

// select: first match
var firstSvc = svcDoc.Select("//service");
Console.WriteLine($"first service: {firstSvc?.Attr("name")}");

// selectAll: filtered by attribute
foreach (var svc in svcDoc.SelectAll("//service[@active=true]"))
    Console.WriteLine($"active: {svc.Attr("name")}");

// transform: immutable update at path
var updatedDoc = svcDoc.Transform("services/service",
    el => { el.SetAttr("name", "renamed-auth"); return el; });
Console.WriteLine("\nAfter transform:");
Console.WriteLine(updatedDoc.ToCx());

// transformAll: apply to every match
var allActiveDoc = svcDoc.TransformAll("//service",
    el => { el.SetAttr("active", true); return el; });
Console.WriteLine($"Active services after transformAll: {allActiveDoc.SelectAll("//service[@active=true]").Count}");
