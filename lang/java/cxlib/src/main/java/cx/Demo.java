package cx;

import java.util.List;

/**
 * Quick-start demo for the CX Java binding.
 *
 * Run from the repo root:
 *   mvn -f lang/java/cxlib/pom.xml -q package -DskipTests
 *   mvn -f lang/java/cxlib/pom.xml -q exec:java -Dexec.mainClass=cx.Demo
 */
public class Demo {

    static final String CX_INPUT = """
            [config version='1.0' debug=false
              [server host=localhost port=8080]
              [database url='postgres://localhost/mydb' pool=10]
              [cache enabled=true ttl=300]
            ]""";

    public static void main(String[] args) throws Exception {
        documentModelDemo();
        streamingDemo();
        cxPathDemo();
    }

    // ── Document model demo ────────────────────────────────────────────────────

    static void documentModelDemo() throws Exception {
        System.out.println("=== Document Model ===\n");

        // 1. Parse
        CXDocument doc = CXDocument.parse(CX_INPUT);

        // 2. Read — get server element and print attrs
        Element server = doc.at("config/server");
        System.out.println("host: " + server.attr("host"));
        System.out.println("port: " + server.attr("port"));

        // 3. Update — change host to production value
        server.setAttr("host", "prod.example.com");

        // 4. Create — add a timeout child element to server
        Element timeout = new Element("timeout");
        timeout.items.add(new ScalarNode("int", 30L));
        server.append(timeout);

        // 5. Delete — remove the cache child from config
        Element config = doc.root();
        Element cache  = config.get("cache");
        config.remove(cache);

        // 6. Emit result as CX
        System.out.println("\n--- Result CX ---");
        System.out.println(doc.toCx());
    }

    // ── CXPath & Transform demo ────────────────────────────────────────────────

    static void cxPathDemo() throws Exception {
        System.out.println("\n=== CXPath & Transform ===\n");

        String servicesSrc = "[services\n  [service name=auth  port=8080 active=true]\n  [service name=api   port=9000 active=false]\n  [service name=web   port=80   active=true]\n]";
        CXDocument sdoc = CXDocument.parse(servicesSrc);

        // select: first match
        Element first = sdoc.select("//service");
        System.out.println("first service: " + first.attr("name"));

        // selectAll: filtered by attribute
        List<Element> active = sdoc.selectAll("//service[@active=true]");
        active.forEach(svc -> System.out.println("active: " + svc.attr("name")));

        // transform: immutable update at path
        CXDocument updated = sdoc.transform("services/service",
            el -> { el.setAttr("name", "renamed-auth"); return el; });
        System.out.println("\nAfter transform:");
        System.out.println(updated.toCx());

        // transformAll: apply to every match
        CXDocument allActive = sdoc.transformAll("//service",
            el -> { el.setAttr("active", true); return el; });
        long count = allActive.selectAll("//service[@active=true]").size();
        System.out.println("Active services after transformAll: " + count);
    }

    // ── Streaming demo ─────────────────────────────────────────────────────────

    static void streamingDemo() throws Exception {
        System.out.println("\n=== Streaming ===\n");

        List<StreamEvent> events = CXDocument.stream(CX_INPUT);
        for (StreamEvent ev : events) {
            System.out.print("event: " + ev.type);
            if ("StartElement".equals(ev.type)) {
                System.out.print("  name=" + ev.name);
                if (ev.attrs != null && !ev.attrs.isEmpty()) {
                    ev.attrs.forEach(a -> System.out.print("  " + a.name + "=" + a.value));
                }
            }
            System.out.println();
        }
    }
}
