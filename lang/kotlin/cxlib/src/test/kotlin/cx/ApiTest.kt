package cx

import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import java.nio.file.Paths
import java.nio.file.Files
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.test.assertFalse

class ApiTest {

    private val fixturesDir = run {
        val base = Paths.get(ApiTest::class.java.protectionDomain.codeSource.location.toURI())
        // test-classes(test) → kotlin → classes → build → lang/kotlin/cxlib → lang/kotlin → lang → repo root
        base.parent.parent.parent.parent.parent.parent.parent.resolve("fixtures")
    }

    private fun fx(name: String) = Files.readString(fixturesDir.resolve(name))

    // ── parse / root / get ────────────────────────────────────────────────────

    @Test fun testParseReturnsDocument() {
        val doc = CXDocument.parse(fx("api_config.cx"))
        assertNotNull(doc)
        assertNotNull(doc.root())
    }

    @Test fun testRootReturnsFirstElement() {
        val doc = CXDocument.parse(fx("api_config.cx"))
        assertEquals("config", doc.root()!!.name)
    }

    @Test fun testRootNoneOnEmptyInput() {
        val doc = CXDocument.parse("")
        assertNull(doc.root())
    }

    @Test fun testGetTopLevelByName() {
        val doc = CXDocument.parse(fx("api_config.cx"))
        assertEquals("config", doc.get("config")!!.name)
        assertNull(doc.get("missing"))
    }

    @Test fun testGetMultiTopLevel() {
        val doc = CXDocument.parse(fx("api_multi.cx"))
        assertEquals("auth", doc.get("service")!!.attr("name"))
    }

    @Test fun testParseMultipleTopLevelElements() {
        val doc = CXDocument.parse(fx("api_multi.cx"))
        val services = doc.elements.filterIsInstance<Element>().filter { it.name == "service" }
        assertEquals(3, services.size)
    }

    // ── attr ──────────────────────────────────────────────────────────────────

    @Test fun testAttrString() {
        val srv = CXDocument.parse(fx("api_config.cx")).at("config/server")!!
        assertEquals("localhost", srv.attr("host"))
    }

    @Test fun testAttrInt() {
        val srv = CXDocument.parse(fx("api_config.cx")).at("config/server")!!
        val port = srv.attr("port")
        assertEquals(8080L, port)
        assertTrue(port is Number)
    }

    @Test fun testAttrBool() {
        val srv = CXDocument.parse(fx("api_config.cx")).at("config/server")!!
        assertEquals(false, srv.attr("debug"))
    }

    @Test fun testAttrFloat() {
        val srv = CXDocument.parse(fx("api_config.cx")).at("config/server")!!
        val ratio = srv.attr("ratio") as Number
        assertTrue(Math.abs(ratio.toDouble() - 1.5) < 1e-9)
    }

    @Test fun testAttrMissingReturnsNull() {
        val srv = CXDocument.parse(fx("api_config.cx")).at("config/server")!!
        assertNull(srv.attr("nonexistent"))
    }

    // ── scalar ────────────────────────────────────────────────────────────────

    @Test fun testScalarInt() {
        val el = CXDocument.parse(fx("api_scalars.cx")).at("values/count")!!
        assertEquals(42L, el.scalar())
        assertTrue(el.scalar() is Number)
    }

    @Test fun testScalarFloat() {
        val el = CXDocument.parse(fx("api_scalars.cx")).at("values/ratio")!!
        val v = el.scalar() as Number
        assertTrue(Math.abs(v.toDouble() - 1.5) < 1e-9)
    }

    @Test fun testScalarBoolTrue() {
        val el = CXDocument.parse(fx("api_scalars.cx")).at("values/enabled")!!
        assertEquals(true, el.scalar())
    }

    @Test fun testScalarBoolFalse() {
        val el = CXDocument.parse(fx("api_scalars.cx")).at("values/disabled")!!
        assertEquals(false, el.scalar())
    }

    @Test fun testScalarNull() {
        val el = CXDocument.parse(fx("api_scalars.cx")).at("values/nothing")!!
        assertNull(el.scalar())
    }

    @Test fun testScalarNoneOnElementWithChildren() {
        val doc = CXDocument.parse(fx("api_config.cx"))
        assertNull(doc.root()!!.scalar())
    }

    // ── text ──────────────────────────────────────────────────────────────────

    @Test fun testTextSingleToken() {
        val doc = CXDocument.parse(fx("api_article.cx"))
        assertEquals("Introduction", doc.at("article/body/h1")!!.text())
    }

    @Test fun testTextQuoted() {
        val el = CXDocument.parse(fx("api_scalars.cx")).at("values/label")!!
        assertEquals("hello world", el.text())
    }

    @Test fun testTextEmptyOnElementWithChildren() {
        val doc = CXDocument.parse(fx("api_config.cx"))
        assertEquals("", doc.root()!!.text())
    }

    // ── children / getAll ─────────────────────────────────────────────────────

    @Test fun testChildrenReturnsOnlyElements() {
        val config = CXDocument.parse(fx("api_config.cx")).root()!!
        val kids = config.children()
        assertEquals(3, kids.size)
        assertTrue(kids.all { it is Element })
        assertEquals(listOf("server", "database", "logging"), kids.map { it.name })
    }

    @Test fun testGetAllDirectChildren() {
        val doc = CXDocument.parse("[root [item 1] [item 2] [other x] [item 3]]")
        val items = doc.root()!!.getAll("item")
        assertEquals(3, items.size)
    }

    @Test fun testGetAllReturnsEmptyForMissing() {
        val config = CXDocument.parse(fx("api_config.cx")).root()!!
        assertEquals(emptyList(), config.getAll("missing"))
    }

    // ── at ────────────────────────────────────────────────────────────────────

    @Test fun testAtSingleSegment() {
        val doc = CXDocument.parse(fx("api_config.cx"))
        assertEquals("config", doc.at("config")!!.name)
    }

    @Test fun testAtTwoSegments() {
        val doc = CXDocument.parse(fx("api_config.cx"))
        assertEquals("server", doc.at("config/server")!!.name)
        assertEquals("database", doc.at("config/database")!!.name)
    }

    @Test fun testAtThreeSegments() {
        val doc = CXDocument.parse(fx("api_article.cx"))
        assertEquals("Getting Started with CX", doc.at("article/head/title")!!.text())
        assertEquals("Introduction", doc.at("article/body/h1")!!.text())
    }

    @Test fun testAtMissingSegmentReturnsNull() {
        val doc = CXDocument.parse(fx("api_config.cx"))
        assertNull(doc.at("config/missing"))
    }

    @Test fun testAtMissingRootReturnsNull() {
        val doc = CXDocument.parse(fx("api_config.cx"))
        assertNull(doc.at("missing"))
    }

    @Test fun testAtDeepMissingReturnsNull() {
        val doc = CXDocument.parse(fx("api_config.cx"))
        assertNull(doc.at("config/server/missing/deep"))
    }

    @Test fun testElementAtRelativePath() {
        val doc = CXDocument.parse(fx("api_article.cx"))
        val body = doc.at("article/body")!!
        assertEquals("Details", body.at("section/h2")!!.text())
    }

    // ── findAll ───────────────────────────────────────────────────────────────

    @Test fun testFindAllTopLevel() {
        val doc = CXDocument.parse(fx("api_multi.cx"))
        assertEquals(3, doc.findAll("service").size)
    }

    @Test fun testFindAllDeep() {
        val doc = CXDocument.parse(fx("api_article.cx"))
        val ps = doc.findAll("p")
        assertEquals(3, ps.size)
        assertEquals("First paragraph.", ps[0].text())
        assertEquals("Nested paragraph.", ps[1].text())
        assertEquals("Another nested paragraph.", ps[2].text())
    }

    @Test fun testFindAllMissingReturnsEmpty() {
        val doc = CXDocument.parse(fx("api_config.cx"))
        assertEquals(emptyList(), doc.findAll("missing"))
    }

    @Test fun testFindAllOnElement() {
        val body = CXDocument.parse(fx("api_article.cx")).at("article/body")!!
        assertEquals(3, body.findAll("p").size)
    }

    // ── findFirst ─────────────────────────────────────────────────────────────

    @Test fun testFindFirstReturnsFirstMatch() {
        val doc = CXDocument.parse(fx("api_article.cx"))
        val p = doc.findFirst("p")
        assertNotNull(p)
        assertEquals("First paragraph.", p.text())
    }

    @Test fun testFindFirstMissingReturnsNull() {
        val doc = CXDocument.parse(fx("api_config.cx"))
        assertNull(doc.findFirst("missing"))
    }

    @Test fun testFindFirstDepthFirstOrder() {
        val doc = CXDocument.parse(fx("api_article.cx"))
        assertEquals("Introduction", doc.findFirst("h1")!!.text())
        assertEquals("Details", doc.findFirst("h2")!!.text())
    }

    @Test fun testFindFirstOnElement() {
        val section = CXDocument.parse(fx("api_article.cx")).at("article/body/section")!!
        val p = section.findFirst("p")
        assertNotNull(p)
        assertEquals("Nested paragraph.", p.text())
    }

    // ── mutation — Element ────────────────────────────────────────────────────

    @Test fun testAppendAddsToEnd() {
        val doc = CXDocument.parse(fx("api_config.cx"))
        doc.root()!!.append(Element(name = "cache"))
        val kids = doc.root()!!.children()
        assertEquals("cache", kids.last().name)
        assertEquals(4, kids.size)
    }

    @Test fun testPrependAddsToFront() {
        val doc = CXDocument.parse(fx("api_config.cx"))
        doc.root()!!.prepend(Element(name = "meta"))
        assertEquals("meta", doc.root()!!.children()[0].name)
    }

    @Test fun testInsertAtIndex() {
        val doc = CXDocument.parse("[root [a 1] [c 3]]")
        doc.root()!!.insert(1, Element(name = "b"))
        assertEquals(listOf("a", "b", "c"), doc.root()!!.children().map { it.name })
    }

    @Test fun testRemoveByIdentity() {
        val doc = CXDocument.parse(fx("api_config.cx"))
        val db = doc.at("config/database")!!
        doc.root()!!.remove(db)
        assertNull(doc.at("config/database"))
        assertNotNull(doc.at("config/server"))
    }

    @Test fun testSetAttrNew() {
        val doc = CXDocument.parse(fx("api_config.cx"))
        val srv = doc.at("config/server")!!
        srv.setAttr("env", "production")
        assertEquals("production", srv.attr("env"))
    }

    @Test fun testSetAttrUpdateValue() {
        val doc = CXDocument.parse(fx("api_config.cx"))
        val srv = doc.at("config/server")!!
        srv.setAttr("port", 9090, "int")
        assertEquals(9090, srv.attr("port"))
        assertEquals(4, srv.attrs.size)  // no duplicate; original count unchanged
    }

    @Test fun testSetAttrChangeType() {
        val doc = CXDocument.parse(fx("api_config.cx"))
        val srv = doc.at("config/server")!!
        val originalCount = srv.attrs.size
        srv.setAttr("debug", true, "bool")
        assertEquals(true, srv.attr("debug"))
        assertEquals(originalCount, srv.attrs.size)
    }

    @Test fun testRemoveAttr() {
        val doc = CXDocument.parse(fx("api_config.cx"))
        val srv = doc.at("config/server")!!
        val originalCount = srv.attrs.size
        srv.removeAttr("debug")
        assertNull(srv.attr("debug"))
        assertEquals(originalCount - 1, srv.attrs.size)
    }

    @Test fun testRemoveAttrNonexistentIsNoop() {
        val doc = CXDocument.parse(fx("api_config.cx"))
        val srv = doc.at("config/server")!!
        val originalCount = srv.attrs.size
        srv.removeAttr("nonexistent")
        assertEquals(originalCount, srv.attrs.size)
    }

    // ── mutation — Document ───────────────────────────────────────────────────

    @Test fun testDocAppendElement() {
        val doc = CXDocument.parse(fx("api_config.cx"))
        doc.append(Element(name = "cache", attrs = mutableListOf(Attr("host", "redis"))))
        assertEquals("redis", doc.get("cache")!!.attr("host"))
    }

    @Test fun testDocPrependMakesNewRoot() {
        val doc = CXDocument.parse(fx("api_config.cx"))
        doc.prepend(Element(name = "preamble"))
        assertEquals("preamble", doc.root()!!.name)
        assertNotNull(doc.get("config"))
    }

    // ── round-trips ───────────────────────────────────────────────────────────

    @Test fun testToCxRoundTrip() {
        val original = CXDocument.parse(fx("api_config.cx"))
        val reparsed = CXDocument.parse(original.toCx())
        assertEquals("localhost", reparsed.at("config/server")!!.attr("host"))
        assertEquals(8080L, reparsed.at("config/server")!!.attr("port"))
        assertEquals("myapp", reparsed.at("config/database")!!.attr("name"))
    }

    @Test fun testToCxRoundTripAfterMutation() {
        val doc = CXDocument.parse(fx("api_config.cx"))
        doc.at("config/server")!!.setAttr("env", "production")
        doc.at("config/server")!!.append(
            Element(name = "timeout", items = mutableListOf(ScalarNode("int", 30L)))
        )
        val reparsed = CXDocument.parse(doc.toCx())
        assertEquals("production", reparsed.at("config/server")!!.attr("env"))
        assertEquals(30L, reparsed.at("config/server")!!.findFirst("timeout")!!.scalar())
    }

    @Test fun testToCxPreservesArticleStructure() {
        val original = CXDocument.parse(fx("api_article.cx"))
        val reparsed = CXDocument.parse(original.toCx())
        assertEquals("Getting Started with CX", reparsed.at("article/head/title")!!.text())
        assertEquals(3, reparsed.findAll("p").size)
    }

    // ── loads / dumps ─────────────────────────────────────────────────────────

    @Test fun testLoadsReturnsMap() {
        @Suppress("UNCHECKED_CAST")
        val data = CXDocument.loads(fx("api_config.cx")) as Map<String, Any?>
        assertNotNull(data)
        @Suppress("UNCHECKED_CAST")
        val config = data["config"] as Map<String, Any?>
        @Suppress("UNCHECKED_CAST")
        val server = config["server"] as Map<String, Any?>
        assertEquals("localhost", server["host"])
        val port = server["port"] as Number
        assertEquals(8080L, port.toLong())
    }

    @Test fun testLoadsBoolTypes() {
        @Suppress("UNCHECKED_CAST")
        val data = CXDocument.loads(fx("api_config.cx")) as Map<String, Any?>
        @Suppress("UNCHECKED_CAST")
        val config = data["config"] as Map<String, Any?>
        @Suppress("UNCHECKED_CAST")
        val server = config["server"] as Map<String, Any?>
        assertEquals(false, server["debug"])
    }

    @Test fun testLoadsScalars() {
        @Suppress("UNCHECKED_CAST")
        val data = CXDocument.loads(fx("api_scalars.cx")) as Map<String, Any?>
        @Suppress("UNCHECKED_CAST")
        val values = data["values"] as Map<String, Any?>
        val count = values["count"] as Number
        assertEquals(42L, count.toLong())
        assertEquals(true, values["enabled"])
        assertEquals(false, values["disabled"])
        assertNull(values["nothing"])
    }

    @Test fun testLoadsXml() {
        @Suppress("UNCHECKED_CAST")
        val data = CXDocument.loadsXml("<server host=\"localhost\" port=\"8080\"/>") as Map<String, Any?>
        assertTrue("server" in data)
    }

    @Test fun testLoadsJsonPassthrough() {
        @Suppress("UNCHECKED_CAST")
        val data = CXDocument.loadsJson("{\"port\": 8080, \"debug\": false}") as Map<String, Any?>
        val port = data["port"] as Number
        assertEquals(8080L, port.toLong())
        assertEquals(false, data["debug"])
    }

    @Test fun testLoadsYaml() {
        @Suppress("UNCHECKED_CAST")
        val data = CXDocument.loadsYaml("server:\n  host: localhost\n  port: 8080\n") as Map<String, Any?>
        assertTrue("server" in data)
    }

    @Test fun testDumpsProducesParsableCx() {
        val original = mapOf("app" to mapOf("name" to "myapp", "version" to "1.0", "port" to 8080))
        val cxStr = CXDocument.dumps(original)
        val reparsed = CXDocument.parse(cxStr)
        assertNotNull(reparsed.findFirst("app"))
    }

    @Test fun testLoadsDumpsDataPreserved() {
        val original = mapOf("server" to mapOf("host" to "localhost", "port" to 8080, "debug" to false))
        @Suppress("UNCHECKED_CAST")
        val restored = CXDocument.loads(CXDocument.dumps(original)) as Map<String, Any?>
        @Suppress("UNCHECKED_CAST")
        val server = restored["server"] as Map<String, Any?>
        val port = server["port"] as Number
        assertEquals(8080L, port.toLong())
        assertEquals("localhost", server["host"])
        assertEquals(false, server["debug"])
    }

    // ── error / failure cases ─────────────────────────────────────────────────

    @Test fun testParseErrorUnclosed() {
        assertThrows<RuntimeException> { CXDocument.parse(fx("errors/unclosed.cx")) }
    }

    @Test fun testParseErrorEmptyElementName() {
        assertThrows<RuntimeException> { CXDocument.parse(fx("errors/empty_name.cx")) }
    }

    @Test fun testParseErrorNestedUnclosed() {
        assertThrows<RuntimeException> { CXDocument.parse(fx("errors/nested_unclosed.cx")) }
    }

    @Test fun testAtMissingPathReturnsNullNotError() {
        val doc = CXDocument.parse(fx("api_config.cx"))
        assertNull(doc.at("config/server/missing/deep/path"))
    }

    @Test fun testFindAllOnEmptyDocReturnsEmpty() {
        val doc = CXDocument.parse("")
        assertEquals(emptyList(), doc.findAll("anything"))
    }

    @Test fun testFindFirstOnEmptyDocReturnsNull() {
        val doc = CXDocument.parse("")
        assertNull(doc.findFirst("anything"))
    }

    @Test fun testScalarNullWhenElementHasChildElements() {
        val doc = CXDocument.parse(fx("api_config.cx"))
        assertNull(doc.root()!!.scalar())
    }

    @Test fun testTextEmptyWhenNoTextChildren() {
        val doc = CXDocument.parse(fx("api_config.cx"))
        assertEquals("", doc.root()!!.text())
    }

    @Test fun testRemoveAttrNonexistentDoesNotRaise() {
        val doc = CXDocument.parse(fx("api_config.cx"))
        val srv = doc.at("config/server")!!
        srv.removeAttr("totally_missing")  // should not throw
    }

    @Test fun testParseXmlInvalid() {
        assertThrows<RuntimeException> { CXDocument.parseXml("<unclosed") }
    }

    // ── parse other formats ───────────────────────────────────────────────────

    @Test fun testParseXml() {
        val doc = CXDocument.parseXml("<root><child key=\"val\"/></root>")
        assertEquals("root", doc.root()!!.name)
        assertNotNull(doc.findFirst("child"))
    }

    @Test fun testParseJsonToDocument() {
        val doc = CXDocument.parseJson("{\"server\": {\"port\": 8080}}")
        assertNotNull(doc.findFirst("server"))
    }

    @Test fun testParseYamlToDocument() {
        val doc = CXDocument.parseYaml("server:\n  port: 8080\n")
        assertNotNull(doc.findFirst("server"))
    }

    // ── stream ────────────────────────────────────────────────────────────────

    @Test fun testStreamReturnsStartAndEndDoc() {
        val events = CXDocument.stream("[server host=localhost port=8080]")
        assertTrue(events.any { it.type == "StartDoc" })
        assertTrue(events.any { it.type == "EndDoc" })
    }

    @Test fun testStreamStartElementHasNameAndAttrs() {
        val events = CXDocument.stream("[server host=localhost port=8080]")
        val se = events.first { it.type == "StartElement" }
        assertEquals("server", se.name)
        assertEquals(2, se.attrs.size)
        assertEquals("localhost", se.attrs.first { it.name == "host" }.value)
        assertEquals(8080L, se.attrs.first { it.name == "port" }.value)
    }

    @Test fun testStreamEndElementMatchesStartElement() {
        val events = CXDocument.stream("[server host=localhost]")
        val startName = events.first { it.type == "StartElement" }.name
        val endName   = events.first { it.type == "EndElement" }.name
        assertEquals(startName, endName)
    }

    @Test fun testStreamTextEvent() {
        val events = CXDocument.stream("[msg 'hello world']")
        val text = events.first { it.type == "Text" }
        assertEquals("hello world", text.value)
    }

    @Test fun testStreamScalarTypedInt() {
        val events = CXDocument.stream("[count 42]")
        val scalar = events.first { it.type == "Scalar" }
        assertEquals("int", scalar.dataType)
        assertEquals(42L, scalar.value)
    }

    @Test fun testStreamMultipleElements() {
        val events = CXDocument.stream(fx("api_config.cx"))
        val startElements = events.filter { it.type == "StartElement" }
        assertTrue(startElements.size >= 4)  // config + server + database + logging
        assertNotNull(startElements.firstOrNull { it.name == "config" })
        assertNotNull(startElements.firstOrNull { it.name == "server" })
    }
}
