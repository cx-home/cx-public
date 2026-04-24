package cx

fun main() {
    val cxInput = """
[config version='1.0' debug=false
  [server host=localhost port=8080]
  [database url='postgres://localhost/mydb' pool=10]
  [cache enabled=true ttl=300]
]""".trimIndent()

    println("=== Document Model ===\n")

    val doc = CXDocument.parse(cxInput)

    val server = doc.at("config/server")!!
    println("host: ${server.attr("host")}")
    println("port: ${server.attr("port")}")

    server.setAttr("host", "prod.example.com")
    val timeout = Element("timeout")
    timeout.items.add(ScalarNode("int", 30L))
    server.append(timeout)

    val config = doc.root()!!
    val cache = config.get("cache")!!
    config.remove(cache)

    println("\n--- Modified document ---")
    println(doc.toCx())

    println("\n=== Streaming ===\n")

    val events = CXDocument.stream(cxInput)
    for (ev in events) {
        if (ev.type == "StartElement") {
            val attrs = ev.attrs.joinToString("  ") { "${it.name}=${it.value}" }
            println("${ev.name}  $attrs")
        }
    }

    val servicesSrc = """
[services
  [service name=auth  port=8080 active=true]
  [service name=api   port=9000 active=false]
  [service name=web   port=80   active=true]
]""".trimIndent()

    println("\n=== CXPath Select ===\n")

    val svcDoc = CXDocument.parse(servicesSrc)
    val first = svcDoc.select("//service")
    println("first service: ${first?.attr("name")}")
    svcDoc.selectAll("//service[@active=true]").forEach { svc ->
        println("active: ${svc.attr("name")}")
    }

    println("\n=== Transform ===\n")

    val updated = svcDoc.transform("services/service") { el ->
        el.setAttr("name", "renamed-auth")
        el
    }
    println(updated.toCx())

    val allActive = svcDoc.transformAll("//service") { el ->
        el.setAttr("active", true)
        el
    }
    val count = allActive.selectAll("//service[@active=true]").size
    println("Active services after transformAll: $count")
}
