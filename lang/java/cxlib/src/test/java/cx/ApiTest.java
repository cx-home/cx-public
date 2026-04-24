package cx;

import org.junit.jupiter.api.*;
import static org.junit.jupiter.api.Assertions.*;

import java.io.IOException;
import java.nio.file.*;
import java.util.*;
import java.util.function.Function;

/**
 * Document API tests for the Java CX binding.
 *
 * Fixtures are shared with all language bindings — see fixtures/ at the repo root.
 */
public class ApiTest {

    private static Path fixturesDir;

    @BeforeAll
    static void setup() throws Exception {
        // From target/test-classes → target → lang/java/cxlib → lang/java → lang → repo root
        Path base = Paths.get(ApiTest.class.getProtectionDomain()
                .getCodeSource().getLocation().toURI());
        Path repo = base.getParent()   // target
                       .getParent()   // lang/java/cxlib
                       .getParent()   // lang/java
                       .getParent()   // lang
                       .getParent();  // repo root
        fixturesDir = repo.resolve("fixtures");
    }

    static String fx(String name) throws IOException {
        return new String(Files.readAllBytes(fixturesDir.resolve(name)));
    }

    // ── parse / root / get ─────────────────────────────────────────────────────

    @Test
    void testParseReturnsDocument() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_config.cx"));
        assertNotNull(doc);
        assertInstanceOf(CXDocument.class, doc);
    }

    @Test
    void testRootReturnsFirstElement() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_config.cx"));
        assertNotNull(doc.root());
        assertEquals("config", doc.root().name);
    }

    @Test
    void testRootNoneOnEmptyInput() throws Exception {
        CXDocument doc = CXDocument.parse("");
        assertNull(doc.root());
    }

    @Test
    void testGetTopLevelByName() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_config.cx"));
        assertNotNull(doc.get("config"));
        assertEquals("config", doc.get("config").name);
        assertNull(doc.get("missing"));
    }

    @Test
    void testGetMultiTopLevel() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_multi.cx"));
        Element first = doc.get("service");
        assertNotNull(first);
        assertEquals("auth", first.attr("name"));
    }

    @Test
    void testParseMultipleTopLevelElements() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_multi.cx"));
        long count = doc.elements.stream()
                .filter(e -> e instanceof Element el && el.name.equals("service"))
                .count();
        assertEquals(3, count);
    }

    // ── attr ───────────────────────────────────────────────────────────────────

    @Test
    void testAttrString() throws Exception {
        Element srv = CXDocument.parse(fx("api_config.cx")).at("config/server");
        assertEquals("localhost", srv.attr("host"));
    }

    @Test
    void testAttrInt() throws Exception {
        Element srv = CXDocument.parse(fx("api_config.cx")).at("config/server");
        Object port = srv.attr("port");
        assertNotNull(port);
        assertEquals(8080L, ((Number) port).longValue());
        assertInstanceOf(Number.class, port);
    }

    @Test
    void testAttrBool() throws Exception {
        Element srv = CXDocument.parse(fx("api_config.cx")).at("config/server");
        assertEquals(Boolean.FALSE, srv.attr("debug"));
    }

    @Test
    void testAttrFloat() throws Exception {
        Element srv = CXDocument.parse(fx("api_config.cx")).at("config/server");
        Object ratio = srv.attr("ratio");
        assertNotNull(ratio);
        assertEquals(1.5, ((Number) ratio).doubleValue(), 1e-9);
    }

    @Test
    void testAttrMissingReturnsNull() throws Exception {
        Element srv = CXDocument.parse(fx("api_config.cx")).at("config/server");
        assertNull(srv.attr("nonexistent"));
    }

    // ── scalar ─────────────────────────────────────────────────────────────────

    @Test
    void testScalarInt() throws Exception {
        Element el = CXDocument.parse(fx("api_scalars.cx")).at("values/count");
        assertNotNull(el);
        Object v = el.scalar();
        assertNotNull(v);
        assertEquals(42L, ((Number) v).longValue());
    }

    @Test
    void testScalarFloat() throws Exception {
        Element el = CXDocument.parse(fx("api_scalars.cx")).at("values/ratio");
        assertNotNull(el);
        Object v = el.scalar();
        assertNotNull(v);
        assertEquals(1.5, ((Number) v).doubleValue(), 1e-9);
    }

    @Test
    void testScalarBoolTrue() throws Exception {
        Element el = CXDocument.parse(fx("api_scalars.cx")).at("values/enabled");
        assertNotNull(el);
        assertEquals(Boolean.TRUE, el.scalar());
    }

    @Test
    void testScalarBoolFalse() throws Exception {
        Element el = CXDocument.parse(fx("api_scalars.cx")).at("values/disabled");
        assertNotNull(el);
        assertEquals(Boolean.FALSE, el.scalar());
    }

    @Test
    void testScalarNull() throws Exception {
        Element el = CXDocument.parse(fx("api_scalars.cx")).at("values/nothing");
        assertNotNull(el);
        assertNull(el.scalar());
    }

    @Test
    void testScalarNoneOnElementWithChildren() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_config.cx"));
        assertNull(doc.root().scalar());
    }

    // ── text ───────────────────────────────────────────────────────────────────

    @Test
    void testTextSingleToken() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_article.cx"));
        assertEquals("Introduction", doc.at("article/body/h1").text());
    }

    @Test
    void testTextQuoted() throws Exception {
        Element el = CXDocument.parse(fx("api_scalars.cx")).at("values/label");
        assertNotNull(el);
        assertEquals("hello world", el.text());
    }

    @Test
    void testTextEmptyOnElementWithChildren() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_config.cx"));
        assertEquals("", doc.root().text());
    }

    // ── children / getAll ──────────────────────────────────────────────────────

    @Test
    void testChildrenReturnsOnlyElements() throws Exception {
        Element config = CXDocument.parse(fx("api_config.cx")).root();
        List<Element> kids = config.children();
        assertEquals(3, kids.size());
        assertTrue(kids.stream().allMatch(k -> k instanceof Element));
        assertEquals(List.of("server", "database", "logging"),
                     kids.stream().map(k -> k.name).toList());
    }

    @Test
    void testGetAllDirectChildren() throws Exception {
        CXDocument doc = CXDocument.parse("[root [item 1] [item 2] [other x] [item 3]]");
        List<Element> items = doc.root().getAll("item");
        assertEquals(3, items.size());
    }

    @Test
    void testGetAllReturnsEmptyForMissing() throws Exception {
        Element config = CXDocument.parse(fx("api_config.cx")).root();
        assertEquals(List.of(), config.getAll("missing"));
    }

    // ── at ─────────────────────────────────────────────────────────────────────

    @Test
    void testAtSingleSegment() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_config.cx"));
        assertEquals("config", doc.at("config").name);
    }

    @Test
    void testAtTwoSegments() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_config.cx"));
        assertEquals("server",   doc.at("config/server").name);
        assertEquals("database", doc.at("config/database").name);
    }

    @Test
    void testAtThreeSegments() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_article.cx"));
        assertEquals("Getting Started with CX", doc.at("article/head/title").text());
        assertEquals("Introduction",            doc.at("article/body/h1").text());
    }

    @Test
    void testAtMissingSegmentReturnsNull() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_config.cx"));
        assertNull(doc.at("config/missing"));
    }

    @Test
    void testAtMissingRootReturnsNull() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_config.cx"));
        assertNull(doc.at("missing"));
    }

    @Test
    void testAtDeepMissingReturnsNull() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_config.cx"));
        assertNull(doc.at("config/server/missing/deep"));
    }

    @Test
    void testElementAtRelativePath() throws Exception {
        CXDocument doc  = CXDocument.parse(fx("api_article.cx"));
        Element    body = doc.at("article/body");
        assertNotNull(body);
        assertEquals("Details", body.at("section/h2").text());
    }

    // ── findAll ────────────────────────────────────────────────────────────────

    @Test
    void testFindAllTopLevel() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_multi.cx"));
        assertEquals(3, doc.findAll("service").size());
    }

    @Test
    void testFindAllDeep() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_article.cx"));
        List<Element> ps = doc.findAll("p");
        assertEquals(3, ps.size());
        assertEquals("First paragraph.",        ps.get(0).text());
        assertEquals("Nested paragraph.",        ps.get(1).text());
        assertEquals("Another nested paragraph.", ps.get(2).text());
    }

    @Test
    void testFindAllMissingReturnsEmpty() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_config.cx"));
        assertEquals(List.of(), doc.findAll("missing"));
    }

    @Test
    void testFindAllOnElement() throws Exception {
        Element body = CXDocument.parse(fx("api_article.cx")).at("article/body");
        assertNotNull(body);
        assertEquals(3, body.findAll("p").size());
    }

    // ── findFirst ──────────────────────────────────────────────────────────────

    @Test
    void testFindFirstReturnsFirstMatch() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_article.cx"));
        Element p = doc.findFirst("p");
        assertNotNull(p);
        assertEquals("First paragraph.", p.text());
    }

    @Test
    void testFindFirstMissingReturnsNull() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_config.cx"));
        assertNull(doc.findFirst("missing"));
    }

    @Test
    void testFindFirstDepthFirstOrder() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_article.cx"));
        assertEquals("Introduction", doc.findFirst("h1").text());
        assertEquals("Details",      doc.findFirst("h2").text());
    }

    @Test
    void testFindFirstOnElement() throws Exception {
        Element section = CXDocument.parse(fx("api_article.cx")).at("article/body/section");
        assertNotNull(section);
        Element p = section.findFirst("p");
        assertNotNull(p);
        assertEquals("Nested paragraph.", p.text());
    }

    // ── mutation — Element ─────────────────────────────────────────────────────

    @Test
    void testAppendAddsToEnd() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_config.cx"));
        doc.root().append(new Element("cache"));
        List<Element> kids = doc.root().children();
        assertEquals("cache", kids.get(kids.size() - 1).name);
        assertEquals(4, kids.size());
    }

    @Test
    void testPrependAddsToFront() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_config.cx"));
        doc.root().prepend(new Element("meta"));
        assertEquals("meta", doc.root().children().get(0).name);
    }

    @Test
    void testInsertAtIndex() throws Exception {
        CXDocument doc = CXDocument.parse("[root [a 1] [c 3]]");
        doc.root().insert(1, new Element("b"));
        assertEquals(List.of("a", "b", "c"),
                     doc.root().children().stream().map(k -> k.name).toList());
    }

    @Test
    void testRemoveByIdentity() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_config.cx"));
        Element db = doc.at("config/database");
        assertNotNull(db);
        doc.root().remove(db);
        assertNull(doc.at("config/database"));
        assertNotNull(doc.at("config/server"));
    }

    @Test
    void testSetAttrNew() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_config.cx"));
        Element srv = doc.at("config/server");
        assertNotNull(srv);
        srv.setAttr("env", "production");
        assertEquals("production", srv.attr("env"));
    }

    @Test
    void testSetAttrUpdateValue() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_config.cx"));
        Element srv = doc.at("config/server");
        assertNotNull(srv);
        int origCount = srv.attrs.size();
        srv.setAttr("port", 9090L, "int");
        assertEquals(9090L, ((Number) srv.attr("port")).longValue());
        assertEquals(origCount, srv.attrs.size());  // no duplicate
    }

    @Test
    void testSetAttrChangeType() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_config.cx"));
        Element srv = doc.at("config/server");
        assertNotNull(srv);
        int origCount = srv.attrs.size();
        srv.setAttr("debug", true, "bool");
        assertEquals(Boolean.TRUE, srv.attr("debug"));
        assertEquals(origCount, srv.attrs.size());
    }

    @Test
    void testRemoveAttr() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_config.cx"));
        Element srv = doc.at("config/server");
        assertNotNull(srv);
        int origCount = srv.attrs.size();
        srv.removeAttr("debug");
        assertNull(srv.attr("debug"));
        assertEquals(origCount - 1, srv.attrs.size());
    }

    @Test
    void testRemoveAttrNonexistentIsNoop() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_config.cx"));
        Element srv = doc.at("config/server");
        assertNotNull(srv);
        int origCount = srv.attrs.size();
        srv.removeAttr("nonexistent");
        assertEquals(origCount, srv.attrs.size());
    }

    // ── mutation — Document ────────────────────────────────────────────────────

    @Test
    void testDocAppendElement() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_config.cx"));
        Element cache = new Element("cache");
        cache.attrs.add(new Attr("host", "redis"));
        doc.append(cache);
        assertNotNull(doc.get("cache"));
        assertEquals("redis", doc.get("cache").attr("host"));
    }

    @Test
    void testDocPrependMakesNewRoot() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_config.cx"));
        doc.prepend(new Element("preamble"));
        assertEquals("preamble", doc.root().name);
        assertNotNull(doc.get("config"));  // original still present
    }

    // ── round-trips ────────────────────────────────────────────────────────────

    @Test
    void testToCxRoundTrip() throws Exception {
        CXDocument original = CXDocument.parse(fx("api_config.cx"));
        CXDocument reparsed = CXDocument.parse(original.toCx());
        assertEquals("localhost", reparsed.at("config/server").attr("host"));
        assertEquals(8080L, ((Number) reparsed.at("config/server").attr("port")).longValue());
        assertEquals("myapp", reparsed.at("config/database").attr("name"));
    }

    @Test
    void testToCxRoundTripAfterMutation() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_config.cx"));
        doc.at("config/server").setAttr("env", "production");
        Element timeout = new Element("timeout");
        timeout.items.add(new ScalarNode("int", 30L));
        doc.at("config/server").append(timeout);
        CXDocument reparsed = CXDocument.parse(doc.toCx());
        assertEquals("production", reparsed.at("config/server").attr("env"));
        assertNotNull(reparsed.at("config/server").findFirst("timeout"));
        assertEquals(30L, ((Number) reparsed.at("config/server").findFirst("timeout").scalar()).longValue());
    }

    @Test
    void testToCxPreservesArticleStructure() throws Exception {
        CXDocument original = CXDocument.parse(fx("api_article.cx"));
        CXDocument reparsed = CXDocument.parse(original.toCx());
        assertEquals("Getting Started with CX", reparsed.at("article/head/title").text());
        assertEquals(3, reparsed.findAll("p").size());
    }

    // ── loads / dumps ──────────────────────────────────────────────────────────

    @Test
    @SuppressWarnings("unchecked")
    void testLoadsReturnsMap() throws Exception {
        Object data = CXDocument.loads(fx("api_config.cx"));
        assertInstanceOf(Map.class, data);
        Map<String, Object> m = (Map<String, Object>) data;
        Map<String, Object> config = (Map<String, Object>) m.get("config");
        Map<String, Object> server = (Map<String, Object>) config.get("server");
        assertEquals("localhost", server.get("host"));
        assertEquals(8080.0, ((Number) server.get("port")).doubleValue(), 1e-9);
    }

    @Test
    @SuppressWarnings("unchecked")
    void testLoadsBoolTypes() throws Exception {
        Object data = CXDocument.loads(fx("api_config.cx"));
        Map<String, Object> m      = (Map<String, Object>) data;
        Map<String, Object> config = (Map<String, Object>) m.get("config");
        Map<String, Object> server = (Map<String, Object>) config.get("server");
        assertEquals(Boolean.FALSE, server.get("debug"));
    }

    @Test
    @SuppressWarnings("unchecked")
    void testLoadsScalars() throws Exception {
        Object data = CXDocument.loads(fx("api_scalars.cx"));
        Map<String, Object> m      = (Map<String, Object>) data;
        Map<String, Object> values = (Map<String, Object>) m.get("values");
        assertEquals(42.0,          ((Number) values.get("count")).doubleValue(), 1e-9);
        assertEquals(Boolean.TRUE,  values.get("enabled"));
        assertEquals(Boolean.FALSE, values.get("disabled"));
        assertNull(values.get("nothing"));
    }

    @Test
    @SuppressWarnings("unchecked")
    void testLoadsXml() throws Exception {
        Object data = CXDocument.loadsXml("<server host=\"localhost\" port=\"8080\"/>");
        assertInstanceOf(Map.class, data);
        assertTrue(((Map<String, Object>) data).containsKey("server"));
    }

    @Test
    @SuppressWarnings("unchecked")
    void testLoadsJsonPassthrough() throws Exception {
        Object data = CXDocument.loadsJson("{\"port\": 8080, \"debug\": false}");
        Map<String, Object> m = (Map<String, Object>) data;
        assertEquals(8080.0, ((Number) m.get("port")).doubleValue(), 1e-9);
        assertEquals(Boolean.FALSE, m.get("debug"));
    }

    @Test
    @SuppressWarnings("unchecked")
    void testLoadsYaml() throws Exception {
        Object data = CXDocument.loadsYaml("server:\n  host: localhost\n  port: 8080\n");
        assertInstanceOf(Map.class, data);
        assertTrue(((Map<String, Object>) data).containsKey("server"));
    }

    @Test
    void testDumpsProducesParsableCx() throws Exception {
        Map<String, Object> app    = new LinkedHashMap<>();
        app.put("name",    "myapp");
        app.put("version", "1.0");
        app.put("port",    8080);
        Map<String, Object> data = new LinkedHashMap<>();
        data.put("app", app);
        String cxStr   = CXDocument.dumps(data);
        CXDocument doc = CXDocument.parse(cxStr);
        assertNotNull(doc.findFirst("app"));
    }

    @Test
    @SuppressWarnings("unchecked")
    void testLoadsDumpsDataPreserved() throws Exception {
        Map<String, Object> server = new LinkedHashMap<>();
        server.put("host",  "localhost");
        server.put("port",  8080);
        server.put("debug", false);
        Map<String, Object> original = new LinkedHashMap<>();
        original.put("server", server);

        Object restored = CXDocument.loads(CXDocument.dumps(original));
        Map<String, Object> rm = (Map<String, Object>) restored;
        Map<String, Object> rs = (Map<String, Object>) rm.get("server");
        assertEquals(8080.0,         ((Number) rs.get("port")).doubleValue(), 1e-9);
        assertEquals("localhost",    rs.get("host"));
        assertEquals(Boolean.FALSE,  rs.get("debug"));
    }

    // ── error / failure cases ──────────────────────────────────────────────────

    @Test
    void testParseErrorUnclosed() throws Exception {
        assertThrows(RuntimeException.class, () -> CXDocument.parse(fx("errors/unclosed.cx")));
    }

    @Test
    void testParseErrorEmptyElementName() throws Exception {
        assertThrows(RuntimeException.class, () -> CXDocument.parse(fx("errors/empty_name.cx")));
    }

    @Test
    void testParseErrorNestedUnclosed() throws Exception {
        assertThrows(RuntimeException.class, () -> CXDocument.parse(fx("errors/nested_unclosed.cx")));
    }

    @Test
    void testAtMissingPathReturnsNullNotError() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_config.cx"));
        assertNull(doc.at("config/server/missing/deep/path"));  // no exception
    }

    @Test
    void testFindAllOnEmptyDocReturnsEmpty() throws Exception {
        CXDocument doc = CXDocument.parse("");
        assertEquals(List.of(), doc.findAll("anything"));
    }

    @Test
    void testFindFirstOnEmptyDocReturnsNull() throws Exception {
        CXDocument doc = CXDocument.parse("");
        assertNull(doc.findFirst("anything"));
    }

    @Test
    void testScalarNoneWhenElementHasChildElements() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_config.cx"));
        assertNull(doc.root().scalar());
    }

    @Test
    void testTextEmptyWhenNoTextChildren() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_config.cx"));
        assertEquals("", doc.root().text());
    }

    @Test
    void testRemoveAttrNonexistentDoesNotRaise() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_config.cx"));
        Element srv = doc.at("config/server");
        assertNotNull(srv);
        srv.removeAttr("totally_missing");  // should not throw
    }

    @Test
    void testParseXmlInvalid() {
        assertThrows(RuntimeException.class, () -> CXDocument.parseXml("<unclosed"));
    }

    // ── removeChild / removeAt ─────────────────────────────────────────────────

    @Test
    void testRemoveChildRemovesMatchingChildren() throws Exception {
        CXDocument doc = CXDocument.parse("[root [item 1] [item 2] [other x] [item 3]]");
        doc.root().removeChild("item");
        List<Element> items = doc.root().getAll("item");
        assertEquals(0, items.size());
        assertNotNull(doc.root().get("other"));
    }

    @Test
    void testRemoveChildNoMatchIsNoop() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_config.cx"));
        int before = doc.root().children().size();
        doc.root().removeChild("nonexistent");
        assertEquals(before, doc.root().children().size());
    }

    @Test
    void testRemoveAtRemovesNodeAtIndex() throws Exception {
        CXDocument doc = CXDocument.parse("[root [a 1] [b 2] [c 3]]");
        doc.root().removeAt(1);  // removes [b 2]
        List<Element> kids = doc.root().children();
        assertEquals(2, kids.size());
        assertEquals("a", kids.get(0).name);
        assertEquals("c", kids.get(1).name);
    }

    @Test
    void testRemoveAtOutOfBoundsIsNoop() throws Exception {
        CXDocument doc = CXDocument.parse("[root [a 1] [b 2]]");
        int before = doc.root().items.size();
        doc.root().removeAt(99);
        assertEquals(before, doc.root().items.size());
    }

    // ── selectAll / select ─────────────────────────────────────────────────────

    @Test
    void testSelectReturnsFirstMatch() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_multi.cx"));
        Element svc = doc.select("//service");
        assertNotNull(svc);
        assertEquals("service", svc.name);
        assertEquals("auth", svc.attr("name"));
    }

    @Test
    void testSelectReturnsNullOnNoMatch() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_config.cx"));
        assertNull(doc.select("//nonexistent"));
    }

    @Test
    void testSelectAllReturnsAllInDepthFirstOrder() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_multi.cx"));
        List<Element> services = doc.selectAll("//service");
        assertEquals(3, services.size());
        assertEquals("auth",   services.get(0).attr("name"));
        assertEquals("api",    services.get(1).attr("name"));
        assertEquals("worker", services.get(2).attr("name"));
    }

    @Test
    void testSelectAllReturnsEmptyOnNoMatch() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_config.cx"));
        assertEquals(List.of(), doc.selectAll("//nonexistent"));
    }

    @Test
    void testSelectOnElementExcludesSelf() throws Exception {
        CXDocument doc = CXDocument.parse("[root [p outer [p inner]]]");
        Element outerP = doc.at("root/p");
        assertNotNull(outerP);
        Element found = outerP.select("//p");
        assertNotNull(found);
        assertEquals("inner", found.text());
    }

    @Test
    void testDescendantAxisDoubleSlash() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_article.cx"));
        List<Element> ps = doc.selectAll("//p");
        assertEquals(3, ps.size());
    }

    @Test
    void testDescendantAxisPreservesDepthFirstOrder() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_article.cx"));
        List<Element> ps = doc.selectAll("//p");
        assertEquals("First paragraph.",         ps.get(0).text());
        assertEquals("Nested paragraph.",         ps.get(1).text());
        assertEquals("Another nested paragraph.", ps.get(2).text());
    }

    @Test
    void testChildAxisPath() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_config.cx"));
        Element srv = doc.select("config/server");
        assertNotNull(srv);
        assertEquals("server",    srv.name);
        assertEquals("localhost", srv.attr("host"));
    }

    @Test
    void testChildAxisThreeLevelPath() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_article.cx"));
        Element title = doc.select("article/head/title");
        assertNotNull(title);
        assertEquals("Getting Started with CX", title.text());
    }

    @Test
    void testWildcardNameDirectChildren() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_config.cx"));
        List<Element> children = doc.selectAll("config/*");
        assertEquals(3, children.size());
        assertEquals("server",   children.get(0).name);
        assertEquals("database", children.get(1).name);
        assertEquals("logging",  children.get(2).name);
    }

    @Test
    void testAttrExistencePredicate() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_article.cx"));
        List<Element> withId = doc.selectAll("//*[@id]");
        assertEquals(1, withId.size());
        assertEquals("section", withId.get(0).name);
    }

    @Test
    void testAttrEqualityString() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_multi.cx"));
        Element found = doc.select("//service[@name=auth]");
        assertNotNull(found);
        assertEquals("auth", found.attr("name"));
    }

    @Test
    void testAttrInequality() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_multi.cx"));
        List<Element> others = doc.selectAll("//service[@name!=auth]");
        assertEquals(2, others.size());
        for (Element svc : others) assertNotEquals("auth", svc.attr("name"));
    }

    @Test
    void testAndOperatorBothRequired() throws Exception {
        CXDocument doc = CXDocument.parse("[services [service active=true region=us][service active=true region=eu][service active=false region=us]]");
        List<Element> results = doc.selectAll("//service[@active=true and @region=us]");
        assertEquals(1, results.size());
    }

    @Test
    void testOrOperatorEitherMatches() throws Exception {
        CXDocument doc = CXDocument.parse("[services [service port=80][service port=443][service port=8080]]");
        List<Element> webPorts = doc.selectAll("//service[@port=80 or @port=443]");
        assertEquals(2, webPorts.size());
    }

    @Test
    void testNotPredicateAttrInequality() throws Exception {
        CXDocument doc = CXDocument.parse("[services [service active=true][service active=false][service active=true]]");
        List<Element> notFalse = doc.selectAll("//service[not(@active=false)]");
        assertEquals(2, notFalse.size());
    }

    @Test
    void testPositionFirst() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_multi.cx"));
        Element first = doc.select("//service[1]");
        assertNotNull(first);
        assertEquals("auth", first.attr("name"));
    }

    @Test
    void testPositionLast() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_multi.cx"));
        Element last = doc.select("//service[last()]");
        assertNotNull(last);
        assertEquals("worker", last.attr("name"));
    }

    @Test
    void testContainsFunction() throws Exception {
        CXDocument doc = CXDocument.parse("[docs [p class=lead-note text][p class=other text]]");
        List<Element> withNote = doc.selectAll("//p[contains(@class, note)]");
        assertEquals(1, withNote.size());
        assertEquals("lead-note", withNote.get(0).attr("class"));
    }

    @Test
    void testStartsWithFunction() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_multi.cx"));
        List<Element> withA = doc.selectAll("//service[starts-with(@name, a)]");
        assertEquals(2, withA.size());
        for (Element svc : withA) assertTrue(svc.attr("name").toString().startsWith("a"));
    }

    @Test
    void testRelativeSelectScopedToElementSubtree() throws Exception {
        CXDocument doc = CXDocument.parse("[root [a [item inside-a]][b [item inside-b]]]");
        Element aEl = doc.at("root/a");
        assertNotNull(aEl);
        List<Element> items = aEl.selectAll("//item");
        assertEquals(1, items.size());
        assertEquals("inside-a", items.get(0).text());
    }

    @Test
    void testInvalidExpressionRaises() throws Exception {
        assertThrows(IllegalArgumentException.class,
                () -> CXDocument.parse("[root]").select("[@invalid syntax!!!"));
    }

    // ── transform ─────────────────────────────────────────────────────────────

    @Test
    void testTransformReturnsNewDocument() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_config.cx"));
        CXDocument updated = doc.transform("config/server", el -> {
            el.setAttr("host", "newhost");
            return el;
        });
        assertEquals("newhost", updated.at("config/server").attr("host"));
    }

    @Test
    void testTransformAppliesFunctionToElementAtPath() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_config.cx"));
        CXDocument updated = doc.transform("config/server", el -> {
            el.setAttr("host", "transformed");
            return el;
        });
        Element srv = updated.at("config/server");
        assertEquals("transformed", srv.attr("host"));
        assertEquals(8080L, ((Number) srv.attr("port")).longValue());
    }

    @Test
    void testTransformOriginalDocumentUnchanged() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_config.cx"));
        doc.transform("config/server", el -> {
            el.setAttr("host", "changed");
            return el;
        });
        assertEquals("localhost", doc.at("config/server").attr("host"));
    }

    @Test
    void testTransformMissingPathReturnsOriginalUnchanged() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_config.cx"));
        CXDocument updated = doc.transform("config/nonexistent", el -> el);
        assertEquals("localhost", updated.at("config/server").attr("host"));
        assertNull(updated.at("config/nonexistent"));
    }

    @Test
    void testTransformChainedTransforms() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_config.cx"));
        CXDocument updated = doc
                .transform("config/server",   el -> { el.setAttr("host", "host1"); return el; })
                .transform("config/database", el -> { el.setAttr("host", "host2"); return el; });
        assertEquals("host1", updated.at("config/server").attr("host"));
        assertEquals("host2", updated.at("config/database").attr("host"));
        assertEquals("localhost", doc.at("config/server").attr("host"));
    }

    // ── transformAll ──────────────────────────────────────────────────────────

    @Test
    void testTransformAllAppliesToAllMatchingElements() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_multi.cx"));
        CXDocument updated = doc.transformAll("//service", el -> {
            el.setAttr("active", true, "bool");
            return el;
        });
        List<Element> services = updated.findAll("service");
        assertEquals(3, services.size());
        for (Element svc : services) assertEquals(Boolean.TRUE, svc.attr("active"));
    }

    @Test
    void testTransformAllReturnsNewDocument() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_multi.cx"));
        CXDocument updated = doc.transformAll("//service", el -> {
            el.setAttr("version", 2L, "int");
            return el;
        });
        for (Element svc : updated.findAll("service"))
            assertEquals(2L, ((Number) svc.attr("version")).longValue());
        for (Element svc : doc.findAll("service"))
            assertNull(svc.attr("version"));
    }

    @Test
    void testTransformAllNoMatchesReturnsOriginal() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_config.cx"));
        CXDocument updated = doc.transformAll("//nonexistent", el -> el);
        assertEquals("localhost", updated.at("config/server").attr("host"));
        assertEquals(List.of(), updated.findAll("nonexistent"));
    }

    @Test
    void testTransformAllAppliesToDeeplyNestedMatches() throws Exception {
        CXDocument doc = CXDocument.parse(fx("api_article.cx"));
        CXDocument updated = doc.transformAll("//p", el -> {
            el.setAttr("visited", true, "bool");
            return el;
        });
        List<Element> updatedPs = updated.findAll("p");
        assertEquals(3, updatedPs.size());
        for (Element p : updatedPs) assertEquals(Boolean.TRUE, p.attr("visited"));
        for (Element p : doc.findAll("p")) assertNull(p.attr("visited"));
    }

    // ── parse other formats ────────────────────────────────────────────────────

    @Test
    void testParseXml() {
        CXDocument doc = CXDocument.parseXml("<root><child key=\"val\"/></root>");
        assertNotNull(doc);
        assertEquals("root", doc.root().name);
        assertNotNull(doc.findFirst("child"));
    }

    @Test
    void testParseJsonToDocument() {
        CXDocument doc = CXDocument.parseJson("{\"server\": {\"port\": 8080}}");
        assertNotNull(doc);
        assertNotNull(doc.findFirst("server"));
    }

    @Test
    void testParseYamlToDocument() {
        CXDocument doc = CXDocument.parseYaml("server:\n  port: 8080\n");
        assertNotNull(doc);
        assertNotNull(doc.findFirst("server"));
    }

    // ── stream (binary events) ─────────────────────────────────────────────────

    @Test
    void testStreamProducesStartAndEndDoc() throws Exception {
        List<StreamEvent> events = CXDocument.stream("[root hello]");
        assertFalse(events.isEmpty());
        assertEquals("StartDoc",  events.get(0).type);
        assertEquals("EndDoc",    events.get(events.size() - 1).type);
    }

    @Test
    void testStreamStartElementHasNameAndAttrs() throws Exception {
        List<StreamEvent> events = CXDocument.stream("[server host=localhost port=8080]");
        StreamEvent start = events.stream()
                .filter(e -> "StartElement".equals(e.type) && "server".equals(e.name))
                .findFirst().orElse(null);
        assertNotNull(start);
        assertEquals("server", start.name);
        assertNotNull(start.attrs);
        boolean hasHost = start.attrs.stream()
                .anyMatch(a -> "host".equals(a.name) && "localhost".equals(a.value));
        assertTrue(hasHost, "Expected host=localhost attribute");
    }

    @Test
    void testStreamTextEvent() throws Exception {
        List<StreamEvent> events = CXDocument.stream("[title Hello World]");
        StreamEvent text = events.stream()
                .filter(e -> "Text".equals(e.type))
                .findFirst().orElse(null);
        assertNotNull(text);
        assertEquals("Hello World", (String) text.value);
    }

    @Test
    void testStreamScalarIntEvent() throws Exception {
        List<StreamEvent> events = CXDocument.stream("[count 42]");
        StreamEvent scalar = events.stream()
                .filter(e -> "Scalar".equals(e.type))
                .findFirst().orElse(null);
        assertNotNull(scalar);
        assertNotNull(scalar.value);
        assertEquals(42L, ((Number) scalar.value).longValue());
    }

    @Test
    void testStreamEndElementHasName() throws Exception {
        List<StreamEvent> events = CXDocument.stream("[config [server host=localhost]]");
        long endCount = events.stream()
                .filter(e -> "EndElement".equals(e.type))
                .count();
        assertTrue(endCount >= 2, "Expected at least 2 EndElement events");
        boolean hasServer = events.stream()
                .anyMatch(e -> "EndElement".equals(e.type) && "server".equals(e.name));
        assertTrue(hasServer, "Expected EndElement for 'server'");
    }
}
