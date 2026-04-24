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

class CXPathTest {

    private val fixturesDir = run {
        val base = Paths.get(CXPathTest::class.java.protectionDomain.codeSource.location.toURI())
        base.parent.parent.parent.parent.parent.parent.parent.resolve("fixtures")
    }

    private fun fx(name: String) = Files.readString(fixturesDir.resolve(name))

    // ── removeChild / removeAt ────────────────────────────────────────────────

    @Test fun testRemoveChildByName() {
        val doc = CXDocument.parse(fx("api_config.cx"))
        val config = doc.root()!!
        config.removeChild("database")
        assertNull(config.get("database"))
        assertNotNull(config.get("server"))
        assertEquals(2, config.children().size)
    }

    @Test fun testRemoveChildNonexistentIsNoop() {
        val doc = CXDocument.parse(fx("api_config.cx"))
        val config = doc.root()!!
        val before = config.children().size
        config.removeChild("nonexistent")
        assertEquals(before, config.children().size)
    }

    @Test fun testRemoveAtRemovesCorrectChild() {
        val doc = CXDocument.parse("[root [a 1] [b 2] [c 3]]")
        val root = doc.root()!!
        root.removeAt(1)
        assertEquals(2, root.children().size)
        assertEquals("a", root.children()[0].name)
        assertEquals("c", root.children()[1].name)
    }

    @Test fun testRemoveAtOutOfBoundsIsNoop() {
        val doc = CXDocument.parse("[root [a 1] [b 2]]")
        val root = doc.root()!!
        root.removeAt(10)
        assertEquals(2, root.children().size)
    }

    // ── selectAll / select ────────────────────────────────────────────────────

    @Test fun testSelectReturnsFirstMatch() {
        val doc = CXDocument.parse(fx("api_multi.cx"))
        val svc = doc.select("//service")
        assertNotNull(svc)
        assertEquals("service", svc.name)
        assertEquals("auth", svc.attr("name"))
    }

    @Test fun testSelectReturnsNullOnNoMatch() {
        val doc = CXDocument.parse(fx("api_config.cx"))
        assertNull(doc.select("//nonexistent"))
    }

    @Test fun testSelectAllReturnsAllInDepthFirstOrder() {
        val doc = CXDocument.parse(fx("api_multi.cx"))
        val services = doc.selectAll("//service")
        assertEquals(3, services.size)
        assertEquals("auth", services[0].attr("name"))
        assertEquals("api", services[1].attr("name"))
        assertEquals("worker", services[2].attr("name"))
    }

    @Test fun testSelectAllReturnsEmptyOnNoMatch() {
        val doc = CXDocument.parse(fx("api_config.cx"))
        assertEquals(emptyList(), doc.selectAll("//nonexistent"))
    }

    @Test fun testSelectOnElementExcludesSelf() {
        val doc = CXDocument.parse("[root [p outer [p inner]]]")
        val outerP = doc.at("root/p")!!
        val found = outerP.select("//p")
        assertNotNull(found)
        assertEquals("inner", found.text())
    }

    @Test fun testDescendantAxisDoubleSlash() {
        val doc = CXDocument.parse(fx("api_article.cx"))
        val ps = doc.selectAll("//p")
        assertEquals(3, ps.size)
    }

    @Test fun testDescendantAxisPreservesDepthFirstOrder() {
        val doc = CXDocument.parse(fx("api_article.cx"))
        val ps = doc.selectAll("//p")
        assertEquals("First paragraph.", ps[0].text())
        assertEquals("Nested paragraph.", ps[1].text())
        assertEquals("Another nested paragraph.", ps[2].text())
    }

    @Test fun testChildAxisPath() {
        val doc = CXDocument.parse(fx("api_config.cx"))
        val srv = doc.select("config/server")
        assertNotNull(srv)
        assertEquals("server", srv.name)
        assertEquals("localhost", srv.attr("host"))
    }

    @Test fun testChildAxisThreeLevelPath() {
        val doc = CXDocument.parse(fx("api_article.cx"))
        val title = doc.select("article/head/title")
        assertNotNull(title)
        assertEquals("Getting Started with CX", title.text())
    }

    @Test fun testWildcardNameDirectChildren() {
        val doc = CXDocument.parse(fx("api_config.cx"))
        val children = doc.selectAll("config/*")
        assertEquals(3, children.size)
        assertEquals("server", children[0].name)
        assertEquals("database", children[1].name)
        assertEquals("logging", children[2].name)
    }

    @Test fun testWildcardDescendantAllElements() {
        val doc = CXDocument.parse("[root [a [b]][c]]")
        val allEls = doc.selectAll("//*")
        assertEquals(4, allEls.size)
    }

    @Test fun testAttrExistencePredicate() {
        val doc = CXDocument.parse(fx("api_article.cx"))
        val withId = doc.selectAll("//*[@id]")
        assertEquals(1, withId.size)
        assertEquals("section", withId[0].name)
    }

    @Test fun testAttrEqualityString() {
        val doc = CXDocument.parse(fx("api_multi.cx"))
        val found = doc.select("//service[@name=auth]")
        assertNotNull(found)
        assertEquals("auth", found.attr("name"))
    }

    @Test fun testAttrInequality() {
        val doc = CXDocument.parse(fx("api_multi.cx"))
        val others = doc.selectAll("//service[@name!=auth]")
        assertEquals(2, others.size)
        for (svc in others) {
            assertTrue(svc.attr("name") != "auth")
        }
    }

    @Test fun testAttrEqualityIntTyped() {
        val doc = CXDocument.parse(fx("api_multi.cx"))
        val found = doc.select("//service[@port=8080]")
        assertNotNull(found)
        assertEquals(8080L, found.attr("port"))
    }

    @Test fun testAttrEqualityBoolTyped() {
        val doc = CXDocument.parse("[services [service active=true name=a][service active=false name=b]]")
        val active = doc.selectAll("//service[@active=true]")
        assertEquals(1, active.size)
        assertEquals("a", active[0].attr("name"))
    }

    @Test fun testAttrNumericRangeGte() {
        val doc = CXDocument.parse("[services [service port=8080][service port=80][service port=9000]]")
        val highPort = doc.selectAll("//service[@port>=8000]")
        assertEquals(2, highPort.size)
    }

    @Test fun testAttrNumericRangeLt() {
        val doc = CXDocument.parse("[services [service port=8080][service port=80][service port=443]]")
        val lowPort = doc.selectAll("//service[@port<1000]")
        assertEquals(2, lowPort.size)
    }

    @Test fun testAndOperatorBothRequired() {
        val doc = CXDocument.parse("[services [service active=true region=us][service active=true region=eu][service active=false region=us]]")
        val results = doc.selectAll("//service[@active=true and @region=us]")
        assertEquals(1, results.size)
    }

    @Test fun testOrOperatorEitherMatches() {
        val doc = CXDocument.parse("[services [service port=80][service port=443][service port=8080]]")
        val webPorts = doc.selectAll("//service[@port=80 or @port=443]")
        assertEquals(2, webPorts.size)
    }

    @Test fun testNotPredicateAttrInequality() {
        val doc = CXDocument.parse("[services [service active=true][service active=false][service active=true]]")
        val notFalse = doc.selectAll("//service[not(@active=false)]")
        assertEquals(2, notFalse.size)
    }

    @Test fun testNotPredicateAttrAbsence() {
        val doc = CXDocument.parse("[config [server host=localhost debug=true][database host=db]]")
        val withoutDebug = doc.selectAll("//*[not(@debug)]")
        assertTrue(withoutDebug.any { it.name == "database" })
        assertFalse(withoutDebug.any { it.name == "server" })
    }

    @Test fun testChildExistencePredicate() {
        val doc = CXDocument.parse("[services [service [tags core]][service name=plain]]")
        val withTags = doc.selectAll("//service[tags]")
        assertEquals(1, withTags.size)
        assertNotNull(withTags[0].get("tags"))
    }

    @Test fun testChildExistenceNegationPredicate() {
        val doc = CXDocument.parse("[services [service [tags core]][service name=plain]]")
        val withoutTags = doc.selectAll("//service[not(tags)]")
        assertEquals(1, withoutTags.size)
        assertNull(withoutTags[0].get("tags"))
    }

    @Test fun testPositionFirst() {
        val doc = CXDocument.parse(fx("api_multi.cx"))
        val firstSvc = doc.select("//service[1]")
        assertNotNull(firstSvc)
        assertEquals("auth", firstSvc.attr("name"))
    }

    @Test fun testPositionSecond() {
        val doc = CXDocument.parse(fx("api_multi.cx"))
        val secondSvc = doc.select("//service[2]")
        assertNotNull(secondSvc)
        assertEquals("api", secondSvc.attr("name"))
    }

    @Test fun testPositionLast() {
        val doc = CXDocument.parse(fx("api_multi.cx"))
        val lastSvc = doc.select("//service[last()]")
        assertNotNull(lastSvc)
        assertEquals("worker", lastSvc.attr("name"))
    }

    @Test fun testContainsFunction() {
        val doc = CXDocument.parse("[docs [p class=lead-note text][p class=other text]]")
        val withNote = doc.selectAll("//p[contains(@class, note)]")
        assertEquals(1, withNote.size)
        assertEquals("lead-note", withNote[0].attr("class"))
    }

    @Test fun testStartsWithFunction() {
        val doc = CXDocument.parse(fx("api_multi.cx"))
        val withA = doc.selectAll("//service[starts-with(@name, a)]")
        assertEquals(2, withA.size)
        for (svc in withA) {
            assertTrue((svc.attr("name") as String).startsWith("a"))
        }
    }

    @Test fun testRelativeSelectAllOnElement() {
        val doc = CXDocument.parse(fx("api_article.cx"))
        val body = doc.at("article/body")!!
        val ps = body.selectAll("//p")
        assertEquals(3, ps.size)
        assertFalse(ps.any { it.name == "body" })
    }

    @Test fun testRelativeSelectNoMatch() {
        val doc = CXDocument.parse("[root [child leaf]]")
        val child = doc.at("root/child")!!
        assertNull(child.select("//nonexistent"))
    }

    @Test fun testRelativeSelectScopedToElementSubtree() {
        val doc = CXDocument.parse("[root [a [item inside-a]][b [item inside-b]]]")
        val aEl = doc.at("root/a")!!
        val items = aEl.selectAll("//item")
        assertEquals(1, items.size)
        assertEquals("inside-a", items[0].text())
    }

    @Test fun testChildThenDescendantAxis() {
        val doc = CXDocument.parse(fx("api_article.cx"))
        val ps = doc.selectAll("article/body//p")
        assertEquals(3, ps.size)
    }

    @Test fun testDescendantThenDescendantAxis() {
        val doc = CXDocument.parse(fx("api_article.cx"))
        val ps = doc.selectAll("//section//p")
        assertEquals(2, ps.size)
        assertEquals("Nested paragraph.", ps[0].text())
        assertEquals("Another nested paragraph.", ps[1].text())
    }

    @Test fun testInvalidExpressionRaises() {
        assertThrows<IllegalArgumentException> {
            CXDocument.parse("[root]").select("[@invalid syntax!!!")
        }
    }

    // ── transform ─────────────────────────────────────────────────────────────

    @Test fun testTransformReturnsNewDocument() {
        val doc = CXDocument.parse(fx("api_config.cx"))
        val updated = doc.transform("config/server") { el ->
            el.setAttr("host", "newhost")
            el
        }
        assertEquals("newhost", updated.at("config/server")!!.attr("host"))
    }

    @Test fun testTransformAppliesFunctionToElementAtPath() {
        val doc = CXDocument.parse(fx("api_config.cx"))
        val updated = doc.transform("config/server") { el ->
            el.setAttr("host", "transformed")
            el
        }
        val srv = updated.at("config/server")!!
        assertEquals("transformed", srv.attr("host"))
        assertEquals(8080L, srv.attr("port"))
    }

    @Test fun testTransformOriginalDocumentUnchanged() {
        val doc = CXDocument.parse(fx("api_config.cx"))
        doc.transform("config/server") { el ->
            el.setAttr("host", "changed")
            el
        }
        assertEquals("localhost", doc.at("config/server")!!.attr("host"))
    }

    @Test fun testTransformMissingPathReturnsOriginalUnchanged() {
        val doc = CXDocument.parse(fx("api_config.cx"))
        val updated = doc.transform("config/nonexistent") { el -> el }
        assertEquals("localhost", updated.at("config/server")!!.attr("host"))
        assertNull(updated.at("config/nonexistent"))
    }

    @Test fun testTransformChainedTransforms() {
        val doc = CXDocument.parse(fx("api_config.cx"))
        val updated = doc
            .transform("config/server") { el -> el.setAttr("host", "host1"); el }
            .transform("config/database") { el -> el.setAttr("host", "host2"); el }
        assertEquals("host1", updated.at("config/server")!!.attr("host"))
        assertEquals("host2", updated.at("config/database")!!.attr("host"))
        assertEquals("localhost", doc.at("config/server")!!.attr("host"))
    }

    // ── transformAll ──────────────────────────────────────────────────────────

    @Test fun testTransformAllAppliesToAllMatchingElements() {
        val doc = CXDocument.parse(fx("api_multi.cx"))
        val updated = doc.transformAll("//service") { el ->
            el.setAttr("active", true)
            el
        }
        val services = updated.findAll("service")
        assertEquals(3, services.size)
        for (svc in services) {
            assertEquals(true, svc.attr("active"))
        }
    }

    @Test fun testTransformAllReturnsNewDocument() {
        val doc = CXDocument.parse(fx("api_multi.cx"))
        val updated = doc.transformAll("//service") { el ->
            el.setAttr("version", 2L)
            el
        }
        for (svc in updated.findAll("service")) {
            assertEquals(2L, svc.attr("version"))
        }
        for (svc in doc.findAll("service")) {
            assertNull(svc.attr("version"))
        }
    }

    @Test fun testTransformAllNoMatchesReturnsOriginal() {
        val doc = CXDocument.parse(fx("api_config.cx"))
        val updated = doc.transformAll("//nonexistent") { el -> el }
        assertEquals("localhost", updated.at("config/server")!!.attr("host"))
        assertEquals(emptyList(), updated.findAll("nonexistent"))
    }

    @Test fun testTransformAllAppliesToDeeplyNestedMatches() {
        val doc = CXDocument.parse(fx("api_article.cx"))
        val updated = doc.transformAll("//p") { el ->
            el.setAttr("visited", true)
            el
        }
        val updatedPs = updated.findAll("p")
        assertEquals(3, updatedPs.size)
        for (p in updatedPs) {
            assertEquals(true, p.attr("visited"))
        }
        for (p in doc.findAll("p")) {
            assertNull(p.attr("visited"))
        }
    }
}
