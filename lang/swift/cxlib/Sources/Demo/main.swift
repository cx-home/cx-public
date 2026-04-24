import CXLib

// ── Document Model Demo ───────────────────────────────────────────────────────

let cxInput = """
[config version='1.0' debug=false
  [server host=localhost port=8080]
  [database url='postgres://localhost/mydb' pool=10]
  [cache enabled=true ttl=300]
]
"""

print("=== Document Model ===\n")

// 1. Parse
let doc = try CXDocument.parse(cxInput)

// 2. Read: get server element, print host and port attrs
let server = doc.at("config/server")!
print("host:", server.attr("host") ?? "nil")
print("port:", server.attr("port") ?? "nil")

// 3. Update: change host to prod.example.com
server.setAttr("host", value: "prod.example.com")

// 4. Create: add a new timeout child to server
let timeout = Element("timeout", attrs: [Attr("seconds", 30, dataType: "int")])
server.append(.element(timeout))

// 5. Delete: remove cache child from config
let config = doc.at("config")!
let cache = config.get("cache")!
config.remove(.element(cache))

// 6. Print result
print("\nModified document:")
print(doc.toCx())

// ── Streaming Demo ────────────────────────────────────────────────────────────

print("\n=== Streaming ===\n")

let events = try CXDocument.stream(cxInput)
for ev in events {
    if ev.type == "StartElement" {
        let attrStr = ev.attrs.map { "\($0.name)=\($0.value ?? "nil")" }.joined(separator: " ")
        print("\(ev.type) \(ev.name ?? "") \(attrStr)")
    } else {
        print(ev.type)
    }
}

// ── CXPath & Transform Demo ───────────────────────────────────────────────────

print("\n=== CXPath & Transform ===\n")

let servicesSrc = """
[services
  [service name=auth  port=8080 active=true]
  [service name=api   port=9000 active=false]
  [service name=web   port=80   active=true]
]
"""

let svcDoc = try CXDocument.parse(servicesSrc)

// select: first match
let firstSvc = try svcDoc.select("//service")
print("first service:", firstSvc?.attr("name") as Any)

// selectAll: filtered
let activeSvcs = try svcDoc.selectAll("//service[@active=true]")
for svc in activeSvcs {
    print("active:", svc.attr("name") as Any)
}

// transform: immutable update
let updatedDoc = svcDoc.transform("services/service") { el in
    el.setAttr("name", value: "renamed-auth")
    return el
}
print("\nAfter transform:")
print(updatedDoc.toCx())

// transformAll
let allActiveDoc = try svcDoc.transformAll("//service") { el in
    el.setAttr("active", value: true)
    return el
}
print("Active services after transformAll:", try allActiveDoc.selectAll("//service[@active=true]").count)
