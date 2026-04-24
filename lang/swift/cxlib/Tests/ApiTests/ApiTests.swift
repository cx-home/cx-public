import XCTest
import CXLib
import Foundation

final class ApiTests: XCTestCase {

    // ── fixture loader ────────────────────────────────────────────────────────

    static var fixturesDir: URL = {
        // Tests/ApiTests/ApiTests.swift → Tests/ApiTests → Tests → lang/swift/cxlib → lang/swift → lang → repo root
        var url = URL(fileURLWithPath: #file)
        for _ in 0..<6 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("fixtures")
    }()

    func fx(_ name: String) throws -> String {
        let url = Self.fixturesDir.appendingPathComponent(name)
        return try String(contentsOf: url, encoding: .utf8)
    }

    // ── parse / root / get ────────────────────────────────────────────────────

    func testParseReturnsCXDocument() throws {
        let doc = try CXDocument.parse(fx("api_config.cx"))
        XCTAssertNotNil(doc)
    }

    func testRootReturnsFirstElement() throws {
        let doc = try CXDocument.parse(fx("api_config.cx"))
        XCTAssertEqual(doc.root()?.name, "config")
    }

    func testRootNilOnEmptyInput() throws {
        let doc = try CXDocument.parse("")
        XCTAssertNil(doc.root())
    }

    func testGetTopLevelByName() throws {
        let doc = try CXDocument.parse(fx("api_config.cx"))
        XCTAssertEqual(doc.get("config")?.name, "config")
        XCTAssertNil(doc.get("missing"))
    }

    func testGetMultiTopLevel() throws {
        let doc = try CXDocument.parse(fx("api_multi.cx"))
        let val = doc.get("service")?.attr("name")
        XCTAssertEqual(val as? String, "auth")
    }

    func testParseMultipleTopLevelElements() throws {
        let doc = try CXDocument.parse(fx("api_multi.cx"))
        let services = doc.elements.compactMap { node -> Element? in
            if case .element(let e) = node, e.name == "service" { return e }
            return nil
        }
        XCTAssertEqual(services.count, 3)
    }

    // ── attr ──────────────────────────────────────────────────────────────────

    func testAttrString() throws {
        let srv = try CXDocument.parse(fx("api_config.cx")).at("config/server")
        XCTAssertEqual(srv?.attr("host") as? String, "localhost")
    }

    func testAttrInt() throws {
        let srv = try CXDocument.parse(fx("api_config.cx")).at("config/server")
        let port = srv?.attr("port") as? NSNumber
        XCTAssertEqual(port?.intValue, 8080)
    }

    func testAttrBool() throws {
        let srv = try CXDocument.parse(fx("api_config.cx")).at("config/server")
        let debug = srv?.attr("debug") as? NSNumber
        XCTAssertNotNil(debug)
        XCTAssertFalse(debug!.boolValue)
    }

    func testAttrFloat() throws {
        let srv = try CXDocument.parse(fx("api_config.cx")).at("config/server")
        let ratio = srv?.attr("ratio") as? NSNumber
        XCTAssertNotNil(ratio)
        XCTAssertEqual(ratio!.doubleValue, 1.5, accuracy: 1e-9)
    }

    func testAttrMissingReturnsNil() throws {
        let srv = try CXDocument.parse(fx("api_config.cx")).at("config/server")
        XCTAssertNil(srv?.attr("nonexistent"))
    }

    // ── scalar ────────────────────────────────────────────────────────────────

    func testScalarInt() throws {
        let el = try CXDocument.parse(fx("api_scalars.cx")).at("values/count")
        let v = el?.scalar() as? NSNumber
        XCTAssertEqual(v?.intValue, 42)
    }

    func testScalarFloat() throws {
        let el = try CXDocument.parse(fx("api_scalars.cx")).at("values/ratio")
        let v = el?.scalar() as? NSNumber
        XCTAssertNotNil(v)
        XCTAssertEqual(v!.doubleValue, 1.5, accuracy: 1e-9)
    }

    func testScalarBoolTrue() throws {
        let el = try CXDocument.parse(fx("api_scalars.cx")).at("values/enabled")
        let v = el?.scalar() as? NSNumber
        XCTAssertNotNil(v)
        XCTAssertTrue(v!.boolValue)
    }

    func testScalarBoolFalse() throws {
        let el = try CXDocument.parse(fx("api_scalars.cx")).at("values/disabled")
        let v = el?.scalar() as? NSNumber
        XCTAssertNotNil(v)
        XCTAssertFalse(v!.boolValue)
    }

    func testScalarNull() throws {
        let el = try CXDocument.parse(fx("api_scalars.cx")).at("values/nothing")
        let v = el?.scalar()
        // scalar() returns nil when AST value is null/NSNull
        let isNullish = v == nil || v is NSNull
        XCTAssertTrue(isNullish, "expected nil or NSNull for null scalar")
    }

    func testScalarNilOnElementWithChildren() throws {
        let doc = try CXDocument.parse(fx("api_config.cx"))
        XCTAssertNil(doc.root()?.scalar())
    }

    // ── text ──────────────────────────────────────────────────────────────────

    func testTextSingleToken() throws {
        let doc = try CXDocument.parse(fx("api_article.cx"))
        XCTAssertEqual(doc.at("article/body/h1")?.text(), "Introduction")
    }

    func testTextQuoted() throws {
        let el = try CXDocument.parse(fx("api_scalars.cx")).at("values/label")
        XCTAssertEqual(el?.text(), "hello world")
    }

    func testTextEmptyOnElementWithChildren() throws {
        let doc = try CXDocument.parse(fx("api_config.cx"))
        XCTAssertEqual(doc.root()?.text(), "")
    }

    // ── children / getAll ─────────────────────────────────────────────────────

    func testChildrenReturnsOnlyElements() throws {
        let config = try CXDocument.parse(fx("api_config.cx")).root()
        let kids = config!.children()
        XCTAssertEqual(kids.count, 3)
        XCTAssertEqual(kids.map { $0.name }, ["server", "database", "logging"])
    }

    func testGetAllDirectChildren() throws {
        let doc = try CXDocument.parse("[root [item 1] [item 2] [other x] [item 3]]")
        let items = doc.root()!.getAll("item")
        XCTAssertEqual(items.count, 3)
    }

    func testGetAllReturnsEmptyForMissing() throws {
        let config = try CXDocument.parse(fx("api_config.cx")).root()
        XCTAssertTrue(config!.getAll("missing").isEmpty)
    }

    // ── at ────────────────────────────────────────────────────────────────────

    func testAtSingleSegment() throws {
        let doc = try CXDocument.parse(fx("api_config.cx"))
        XCTAssertEqual(doc.at("config")?.name, "config")
    }

    func testAtTwoSegments() throws {
        let doc = try CXDocument.parse(fx("api_config.cx"))
        XCTAssertEqual(doc.at("config/server")?.name, "server")
        XCTAssertEqual(doc.at("config/database")?.name, "database")
    }

    func testAtThreeSegments() throws {
        let doc = try CXDocument.parse(fx("api_article.cx"))
        XCTAssertEqual(doc.at("article/head/title")?.text(), "Getting Started with CX")
        XCTAssertEqual(doc.at("article/body/h1")?.text(), "Introduction")
    }

    func testAtMissingSegmentReturnsNil() throws {
        let doc = try CXDocument.parse(fx("api_config.cx"))
        XCTAssertNil(doc.at("config/missing"))
    }

    func testAtMissingRootReturnsNil() throws {
        let doc = try CXDocument.parse(fx("api_config.cx"))
        XCTAssertNil(doc.at("missing"))
    }

    func testAtDeepMissingReturnsNil() throws {
        let doc = try CXDocument.parse(fx("api_config.cx"))
        XCTAssertNil(doc.at("config/server/missing/deep"))
    }

    func testElementAtRelativePath() throws {
        let doc = try CXDocument.parse(fx("api_article.cx"))
        let body = doc.at("article/body")
        XCTAssertEqual(body?.at("section/h2")?.text(), "Details")
    }

    // ── findAll ───────────────────────────────────────────────────────────────

    func testFindAllTopLevel() throws {
        let doc = try CXDocument.parse(fx("api_multi.cx"))
        XCTAssertEqual(doc.findAll("service").count, 3)
    }

    func testFindAllDeep() throws {
        let doc = try CXDocument.parse(fx("api_article.cx"))
        let ps = doc.findAll("p")
        XCTAssertEqual(ps.count, 3)
        XCTAssertEqual(ps[0].text(), "First paragraph.")
        XCTAssertEqual(ps[1].text(), "Nested paragraph.")
        XCTAssertEqual(ps[2].text(), "Another nested paragraph.")
    }

    func testFindAllMissingReturnsEmpty() throws {
        let doc = try CXDocument.parse(fx("api_config.cx"))
        XCTAssertTrue(doc.findAll("missing").isEmpty)
    }

    func testFindAllOnElement() throws {
        let body = try CXDocument.parse(fx("api_article.cx")).at("article/body")
        XCTAssertEqual(body!.findAll("p").count, 3)
    }

    // ── findFirst ─────────────────────────────────────────────────────────────

    func testFindFirstReturnsFirstMatch() throws {
        let doc = try CXDocument.parse(fx("api_article.cx"))
        let p = doc.findFirst("p")
        XCTAssertNotNil(p)
        XCTAssertEqual(p?.text(), "First paragraph.")
    }

    func testFindFirstMissingReturnsNil() throws {
        let doc = try CXDocument.parse(fx("api_config.cx"))
        XCTAssertNil(doc.findFirst("missing"))
    }

    func testFindFirstDepthFirstOrder() throws {
        let doc = try CXDocument.parse(fx("api_article.cx"))
        XCTAssertEqual(doc.findFirst("h1")?.text(), "Introduction")
        XCTAssertEqual(doc.findFirst("h2")?.text(), "Details")
    }

    func testFindFirstOnElement() throws {
        let section = try CXDocument.parse(fx("api_article.cx")).at("article/body/section")
        let p = section?.findFirst("p")
        XCTAssertNotNil(p)
        XCTAssertEqual(p?.text(), "Nested paragraph.")
    }

    // ── mutation — Element ────────────────────────────────────────────────────

    func testAppendAddsToEnd() throws {
        let doc = try CXDocument.parse(fx("api_config.cx"))
        let cache = Element("cache")
        doc.root()!.append(.element(cache))
        let kids = doc.root()!.children()
        XCTAssertEqual(kids.last?.name, "cache")
        XCTAssertEqual(kids.count, 4)
    }

    func testPrependAddsToFront() throws {
        let doc = try CXDocument.parse(fx("api_config.cx"))
        let meta = Element("meta")
        doc.root()!.prepend(.element(meta))
        XCTAssertEqual(doc.root()!.children()[0].name, "meta")
    }

    func testInsertAtIndex() throws {
        let doc = try CXDocument.parse("[root [a 1] [c 3]]")
        doc.root()!.insert(1, .element(Element("b")))
        XCTAssertEqual(doc.root()!.children().map { $0.name }, ["a", "b", "c"])
    }

    func testRemoveByIdentity() throws {
        let doc = try CXDocument.parse(fx("api_config.cx"))
        let db = doc.at("config/database")!
        doc.root()!.remove(.element(db))
        XCTAssertNil(doc.at("config/database"))
        XCTAssertNotNil(doc.at("config/server"))
    }

    func testSetAttrNew() throws {
        let doc = try CXDocument.parse(fx("api_config.cx"))
        let srv = doc.at("config/server")!
        srv.setAttr("env", value: "production")
        XCTAssertEqual(srv.attr("env") as? String, "production")
    }

    func testSetAttrUpdateValue() throws {
        let doc = try CXDocument.parse(fx("api_config.cx"))
        let srv = doc.at("config/server")!
        srv.setAttr("port", value: 9090, dataType: "int")
        let port = srv.attr("port") as? NSNumber
        XCTAssertEqual(port?.intValue, 9090)
        XCTAssertEqual(srv.attrs.count, 4)  // no duplicate
    }

    func testSetAttrChangeType() throws {
        let doc = try CXDocument.parse(fx("api_config.cx"))
        let srv = doc.at("config/server")!
        let originalCount = srv.attrs.count
        srv.setAttr("debug", value: true, dataType: "bool")
        let debug = srv.attr("debug") as? NSNumber
        XCTAssertNotNil(debug)
        XCTAssertTrue(debug!.boolValue)
        XCTAssertEqual(srv.attrs.count, originalCount)
    }

    func testRemoveAttr() throws {
        let doc = try CXDocument.parse(fx("api_config.cx"))
        let srv = doc.at("config/server")!
        let originalCount = srv.attrs.count
        srv.removeAttr("debug")
        XCTAssertNil(srv.attr("debug"))
        XCTAssertEqual(srv.attrs.count, originalCount - 1)
    }

    func testRemoveAttrNonexistentIsNoop() throws {
        let doc = try CXDocument.parse(fx("api_config.cx"))
        let srv = doc.at("config/server")!
        let originalCount = srv.attrs.count
        srv.removeAttr("nonexistent")
        XCTAssertEqual(srv.attrs.count, originalCount)
    }

    // ── mutation — Document ───────────────────────────────────────────────────

    func testDocAppendElement() throws {
        let doc = try CXDocument.parse(fx("api_config.cx"))
        let cache = Element("cache", attrs: [Attr("host", "redis")])
        doc.append(.element(cache))
        XCTAssertEqual(doc.get("cache")?.attr("host") as? String, "redis")
    }

    func testDocPrependMakesNewRoot() throws {
        let doc = try CXDocument.parse(fx("api_config.cx"))
        doc.prepend(.element(Element("preamble")))
        XCTAssertEqual(doc.root()?.name, "preamble")
        XCTAssertNotNil(doc.get("config"))
    }

    // ── round-trips ───────────────────────────────────────────────────────────

    func testToCxRoundTrip() throws {
        let original = try CXDocument.parse(fx("api_config.cx"))
        let reparsed = try CXDocument.parse(original.toCx())
        XCTAssertEqual(reparsed.at("config/server")?.attr("host") as? String, "localhost")
        XCTAssertEqual(reparsed.at("config/server")?.attr("port") as? NSNumber, 8080)
        XCTAssertEqual(reparsed.at("config/database")?.attr("name") as? String, "myapp")
    }

    func testToCxRoundTripAfterMutation() throws {
        let doc = try CXDocument.parse(fx("api_config.cx"))
        doc.at("config/server")!.setAttr("env", value: "production")
        let timeout = Element("timeout", items: [.scalar(dataType: "int", value: 30)])
        doc.at("config/server")!.append(.element(timeout))
        let reparsed = try CXDocument.parse(doc.toCx())
        XCTAssertEqual(reparsed.at("config/server")?.attr("env") as? String, "production")
        let tv = reparsed.at("config/server")?.findFirst("timeout")?.scalar() as? NSNumber
        XCTAssertEqual(tv?.intValue, 30)
    }

    func testToCxPreservesArticleStructure() throws {
        let original = try CXDocument.parse(fx("api_article.cx"))
        let reparsed = try CXDocument.parse(original.toCx())
        XCTAssertEqual(reparsed.at("article/head/title")?.text(), "Getting Started with CX")
        XCTAssertEqual(reparsed.findAll("p").count, 3)
    }

    // ── loads / dumps ─────────────────────────────────────────────────────────

    func testLoadsReturnsDict() throws {
        let data = try CXDocument.loads(fx("api_config.cx")) as? [String: Any]
        XCTAssertNotNil(data)
        let server = (data?["config"] as? [String: Any])?["server"] as? [String: Any]
        XCTAssertEqual(server?["host"] as? String, "localhost")
        XCTAssertEqual((server?["port"] as? NSNumber)?.intValue, 8080)
    }

    func testLoadsBoolTypes() throws {
        let data = try CXDocument.loads(fx("api_config.cx")) as? [String: Any]
        let server = (data?["config"] as? [String: Any])?["server"] as? [String: Any]
        let debug = server?["debug"] as? NSNumber
        XCTAssertNotNil(debug)
        XCTAssertFalse(debug!.boolValue)
    }

    func testLoadsScalars() throws {
        let data = try CXDocument.loads(fx("api_scalars.cx")) as? [String: Any]
        let values = data?["values"] as? [String: Any]
        XCTAssertEqual((values?["count"] as? NSNumber)?.intValue, 42)
        XCTAssertTrue((values?["enabled"] as? NSNumber)?.boolValue == true)
        XCTAssertFalse((values?["disabled"] as? NSNumber)?.boolValue == true)
        XCTAssertTrue(values?["nothing"] == nil || values?["nothing"] is NSNull)
    }

    func testLoadsXml() throws {
        let data = try CXDocument.loads(try CXLib.xmlToCx("<server host=\"localhost\" port=\"8080\"/>")) as? [String: Any]
        XCTAssertNotNil(data?["server"])
    }

    func testLoadsJsonPassthrough() throws {
        let data = try CXDocument.loads(try CXLib.jsonToCx("{\"port\": 8080, \"debug\": false}")) as? [String: Any]
        XCTAssertEqual((data?["port"] as? NSNumber)?.intValue, 8080)
        XCTAssertFalse((data?["debug"] as? NSNumber)?.boolValue == true)
    }

    func testDumpsProducesParsableCx() throws {
        let original: [String: Any] = ["app": ["name": "myapp", "version": "1.0", "port": 8080]]
        let cxStr = try CXDocument.dumps(original)
        let reparsed = try CXDocument.parse(cxStr)
        XCTAssertNotNil(reparsed.findFirst("app"))
    }

    func testLoadsDumpsDataPreserved() throws {
        let original: [String: Any] = ["server": ["host": "localhost", "port": 8080, "debug": false]]
        let restored = try CXDocument.loads(try CXDocument.dumps(original)) as? [String: Any]
        let server = restored?["server"] as? [String: Any]
        XCTAssertEqual((server?["port"] as? NSNumber)?.intValue, 8080)
        XCTAssertEqual(server?["host"] as? String, "localhost")
        XCTAssertFalse((server?["debug"] as? NSNumber)?.boolValue == true)
    }

    func testLoadsXmlDirect() throws {
        let data = try CXDocument.loadsXml("<root><item>42</item></root>")
        XCTAssertNotNil(data)
    }

    func testLoadsJsonDirect() throws {
        let data = try CXDocument.loadsJson("{\"server\":{\"host\":\"localhost\"}}")
        let dict = data as! [String: Any]
        XCTAssertNotNil(dict["server"])
    }

    func testLoadsYaml() throws {
        let data = try CXDocument.loadsYaml("server:\n  host: localhost\n")
        XCTAssertNotNil(data)
    }

    func testLoadsToml() throws {
        let data = try CXDocument.loadsToml("[server]\nhost = \"localhost\"\n")
        XCTAssertNotNil(data)
    }

    func testLoadsMd() throws {
        let data = try CXDocument.loadsMd("# hello\n\nworld\n")
        XCTAssertNotNil(data)
    }

    // ── error / failure cases ─────────────────────────────────────────────────

    func testParseErrorUnclosedBracket() throws {
        XCTAssertThrowsError(try CXDocument.parse(fx("errors/unclosed.cx")))
    }

    func testParseErrorEmptyElementName() throws {
        XCTAssertThrowsError(try CXDocument.parse(fx("errors/empty_name.cx")))
    }

    func testParseErrorNestedUnclosed() throws {
        XCTAssertThrowsError(try CXDocument.parse(fx("errors/nested_unclosed.cx")))
    }

    func testAtMissingPathReturnsNilNotError() throws {
        let doc = try CXDocument.parse(fx("api_config.cx"))
        XCTAssertNil(doc.at("config/server/missing/deep/path"))
    }

    func testFindAllOnEmptyDocReturnsEmpty() throws {
        let doc = try CXDocument.parse("")
        XCTAssertTrue(doc.findAll("anything").isEmpty)
    }

    func testFindFirstOnEmptyDocReturnsNil() throws {
        let doc = try CXDocument.parse("")
        XCTAssertNil(doc.findFirst("anything"))
    }

    func testScalarNilWhenElementHasChildElements() throws {
        let doc = try CXDocument.parse(fx("api_config.cx"))
        XCTAssertNil(doc.root()?.scalar())
    }

    func testTextEmptyWhenNoTextChildren() throws {
        let doc = try CXDocument.parse(fx("api_config.cx"))
        XCTAssertEqual(doc.root()?.text(), "")
    }

    func testRemoveAttrNonexistentDoesNotRaise() throws {
        let doc = try CXDocument.parse(fx("api_config.cx"))
        let srv = doc.at("config/server")!
        srv.removeAttr("totally_missing")  // should not throw
    }

    func testParseXmlInvalid() throws {
        XCTAssertThrowsError(try CXDocument.parseXml("<unclosed"))
    }

    // ── parse other formats ───────────────────────────────────────────────────

    func testParseXml() throws {
        let doc = try CXDocument.parseXml("<root><child key=\"val\"/></root>")
        XCTAssertEqual(doc.root()?.name, "root")
        XCTAssertNotNil(doc.findFirst("child"))
    }

    func testParseJsonToDocument() throws {
        let doc = try CXDocument.parseJson("{\"server\": {\"port\": 8080}}")
        XCTAssertNotNil(doc.findFirst("server"))
    }

    func testParseYamlToDocument() throws {
        let doc = try CXDocument.parseYaml("server:\n  port: 8080\n")
        XCTAssertNotNil(doc.findFirst("server"))
    }

    // ── streaming ─────────────────────────────────────────────────────────────

    func testStreamStartDocEndDoc() throws {
        let events = try CXDocument.stream("[root]")
        let types = events.map { $0.type }
        XCTAssertTrue(types.contains("StartDoc"), "expected StartDoc")
        XCTAssertTrue(types.contains("EndDoc"), "expected EndDoc")
    }

    func testStreamStartAndEndElement() throws {
        let events = try CXDocument.stream("[config host=localhost]")
        let startEvents = events.filter { $0.type == "StartElement" }
        let endEvents   = events.filter { $0.type == "EndElement" }
        XCTAssertFalse(startEvents.isEmpty, "expected at least one StartElement")
        XCTAssertFalse(endEvents.isEmpty,   "expected at least one EndElement")
        let start = startEvents.first { $0.name == "config" }
        XCTAssertNotNil(start, "expected StartElement with name 'config'")
        let end = endEvents.first { $0.name == "config" }
        XCTAssertNotNil(end, "expected EndElement with name 'config'")
    }

    func testStreamAttrsTyped() throws {
        let events = try CXDocument.stream("[server host=localhost port=8080 debug=false ratio=1.5]")
        let start = events.first { $0.isStartElement("server") }
        XCTAssertNotNil(start, "expected StartElement 'server'")
        let attrs = start!.attrs
        let host  = attrs.first { $0.name == "host" }
        let port  = attrs.first { $0.name == "port" }
        let debug = attrs.first { $0.name == "debug" }
        let ratio = attrs.first { $0.name == "ratio" }
        XCTAssertEqual(host?.value as? String, "localhost")
        XCTAssertEqual((port?.value as? Int), 8080)
        XCTAssertEqual((debug?.value as? Bool), false)
        XCTAssertEqual((ratio?.value as? Double ?? 0.0), 1.5, accuracy: 1e-9)
    }

    func testStreamNestedElements() throws {
        let events = try CXDocument.stream("[root [child foo]]")
        let starts = events.filter { $0.type == "StartElement" }.map { $0.name }
        XCTAssertTrue(starts.contains("root"),  "expected StartElement 'root'")
        XCTAssertTrue(starts.contains("child"), "expected StartElement 'child'")
    }

    func testStreamTextEvent() throws {
        let events = try CXDocument.stream("[p Hello]")
        let textEvents = events.filter { $0.type == "Text" }
        XCTAssertFalse(textEvents.isEmpty, "expected at least one Text event")
        XCTAssertEqual(textEvents.first?.value as? String, "Hello")
    }

    func testStreamScalarEvent() throws {
        let events = try CXDocument.stream("[count :int 42]")
        let scalarEvents = events.filter { $0.type == "Scalar" }
        XCTAssertFalse(scalarEvents.isEmpty, "expected at least one Scalar event")
        let scalar = scalarEvents.first!
        XCTAssertEqual(scalar.dataType, "int")
        XCTAssertEqual(scalar.value as? Int, 42)
    }

    func testStreamHelperMethods() throws {
        let events = try CXDocument.stream("[root [child]]")
        let first = events.first { $0.isStartElement() }
        XCTAssertNotNil(first)
        let rootStart = events.first { $0.isStartElement("root") }
        XCTAssertNotNil(rootStart)
        let childEnd = events.first { $0.isEndElement("child") }
        XCTAssertNotNil(childEnd)
    }

    // ── removeChild / removeAt ────────────────────────────────────────────────

    func testRemoveChildByName() throws {
        let doc = try CXDocument.parse(fx("api_config.cx"))
        let config = doc.root()!
        config.removeChild("database")
        XCTAssertNil(config.get("database"))
        XCTAssertNotNil(config.get("server"))
        XCTAssertNotNil(config.get("logging"))
    }

    func testRemoveChildNonexistentIsNoop() throws {
        let doc = try CXDocument.parse(fx("api_config.cx"))
        let config = doc.root()!
        let before = config.children().count
        config.removeChild("missing")
        XCTAssertEqual(config.children().count, before)
    }

    func testRemoveChildRemovesAllMatching() throws {
        let doc = try CXDocument.parse("[root [item 1] [item 2] [other x] [item 3]]")
        doc.root()!.removeChild("item")
        XCTAssertTrue(doc.root()!.getAll("item").isEmpty)
        XCTAssertNotNil(doc.root()!.get("other"))
    }

    func testRemoveAtInBounds() throws {
        let doc = try CXDocument.parse("[root [a 1] [b 2] [c 3]]")
        // items: [.element(a), .element(b), .element(c)] — index 1 is b
        doc.root()!.removeAt(1)
        let names = doc.root()!.children().map { $0.name }
        XCTAssertEqual(names, ["a", "c"])
    }

    func testRemoveAtOutOfBoundsIsNoop() throws {
        let doc = try CXDocument.parse("[root [a 1] [b 2]]")
        let before = doc.root()!.items.count
        doc.root()!.removeAt(99)
        XCTAssertEqual(doc.root()!.items.count, before)
        doc.root()!.removeAt(-1)
        XCTAssertEqual(doc.root()!.items.count, before)
    }

    // ── select / selectAll ────────────────────────────────────────────────────

    func testSelectAllDescendant() throws {
        let doc = try CXDocument.parse(fx("api_config.cx"))
        let results = try doc.selectAll("//server")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].name, "server")
    }

    func testSelectReturnsFirstMatch() throws {
        let doc = try CXDocument.parse(fx("api_multi.cx"))
        let first = try doc.select("//service")
        XCTAssertNotNil(first)
        XCTAssertEqual(first?.attr("name") as? String, "auth")
    }

    func testSelectAllReturnsAllMatches() throws {
        let doc = try CXDocument.parse(fx("api_multi.cx"))
        let results = try doc.selectAll("//service")
        XCTAssertEqual(results.count, 3)
    }

    func testSelectAttrExistsPredicate() throws {
        let doc = try CXDocument.parse(fx("api_config.cx"))
        let results = try doc.selectAll("//server[@host]")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].name, "server")
    }

    func testSelectAttrEqualsPredicate() throws {
        let doc = try CXDocument.parse(fx("api_multi.cx"))
        let results = try doc.selectAll("//service[@name=api]")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].attr("name") as? String, "api")
    }

    func testSelectAttrNotEqualPredicate() throws {
        let doc = try CXDocument.parse(fx("api_multi.cx"))
        let results = try doc.selectAll("//service[@name!=auth]")
        XCTAssertEqual(results.count, 2)
    }

    func testSelectAttrNumericComparison() throws {
        let doc = try CXDocument.parse(fx("api_multi.cx"))
        // port >= 8080: api(8080) and worker(9000)
        let results = try doc.selectAll("//service[@port>=8080]")
        XCTAssertEqual(results.count, 2)
    }

    func testSelectPositionPredicate() throws {
        let doc = try CXDocument.parse(fx("api_multi.cx"))
        let second = try doc.select("//service[2]")
        XCTAssertEqual(second?.attr("name") as? String, "api")
    }

    func testSelectLastPredicate() throws {
        let doc = try CXDocument.parse(fx("api_multi.cx"))
        let last = try doc.select("//service[last()]")
        XCTAssertEqual(last?.attr("name") as? String, "worker")
    }

    func testSelectWildcard() throws {
        let doc = try CXDocument.parse(fx("api_config.cx"))
        let results = try doc.selectAll("//*")
        // All descendants: config, server, database, logging
        XCTAssertGreaterThanOrEqual(results.count, 3)
    }

    func testSelectOnElement() throws {
        let doc = try CXDocument.parse(fx("api_article.cx"))
        let body = doc.at("article/body")!
        let results = try body.selectAll("//p")
        XCTAssertEqual(results.count, 3)
    }

    func testSelectBoolAndPredicate() throws {
        let doc = try CXDocument.parse(fx("api_config.cx"))
        // server has both host and port
        let results = try doc.selectAll("//server[@host and @port]")
        XCTAssertEqual(results.count, 1)
    }

    func testSelectNotPredicate() throws {
        let doc = try CXDocument.parse(fx("api_multi.cx"))
        // services without name=auth
        let results = try doc.selectAll("//service[not(@name=auth)]")
        XCTAssertEqual(results.count, 2)
    }

    func testSelectChildPath() throws {
        let doc = try CXDocument.parse(fx("api_config.cx"))
        let results = try doc.selectAll("config/server")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].name, "server")
    }

    // ── transform ────────────────────────────────────────────────────────────

    func testTransformReturnsNewDocument() throws {
        let doc = try CXDocument.parse(fx("api_config.cx"))
        let updated = doc.transform("config/server") { el in
            el.setAttr("host", value: "prod.example.com")
            return el
        }
        XCTAssertFalse(updated === doc)
    }

    func testTransformDoesNotMutateOriginal() throws {
        let doc = try CXDocument.parse(fx("api_config.cx"))
        let _ = doc.transform("config/server") { el in
            el.setAttr("host", value: "prod.example.com")
            return el
        }
        XCTAssertEqual(doc.at("config/server")?.attr("host") as? String, "localhost")
    }

    func testTransformUpdatesTargetElement() throws {
        let doc = try CXDocument.parse(fx("api_config.cx"))
        let updated = doc.transform("config/server") { el in
            el.setAttr("host", value: "prod.example.com")
            return el
        }
        XCTAssertEqual(updated.at("config/server")?.attr("host") as? String, "prod.example.com")
    }

    func testTransformChained() throws {
        let doc = try CXDocument.parse(fx("api_config.cx"))
        let updated = doc
            .transform("config/server") { el in
                el.setAttr("host", value: "web.example.com")
                return el
            }
            .transform("config/database") { el in
                el.setAttr("host", value: "db.example.com")
                return el
            }
        XCTAssertEqual(updated.at("config/server")?.attr("host") as? String, "web.example.com")
        XCTAssertEqual(updated.at("config/database")?.attr("host") as? String, "db.example.com")
    }

    func testTransformMissingPathReturnsOriginal() throws {
        let doc = try CXDocument.parse(fx("api_config.cx"))
        let updated = doc.transform("config/nonexistent") { el in
            el.setAttr("host", value: "x")
            return el
        }
        // Should return self (same or equivalent document)
        XCTAssertNotNil(updated.at("config/server"))
        XCTAssertNil(updated.at("config/nonexistent"))
    }

    // ── transformAll ─────────────────────────────────────────────────────────

    func testTransformAllReturnsNewDocument() throws {
        let doc = try CXDocument.parse(fx("api_multi.cx"))
        let updated = try doc.transformAll("//service") { el in
            el.setAttr("active", value: true)
            return el
        }
        XCTAssertFalse(updated === doc)
    }

    func testTransformAllDoesNotMutateOriginal() throws {
        let doc = try CXDocument.parse(fx("api_multi.cx"))
        let _ = try doc.transformAll("//service") { el in
            el.setAttr("active", value: true)
            return el
        }
        // Original services should not have 'active'
        for svc in doc.findAll("service") {
            XCTAssertNil(svc.attr("active"))
        }
    }

    func testTransformAllUpdatesAllMatches() throws {
        let doc = try CXDocument.parse(fx("api_multi.cx"))
        let updated = try doc.transformAll("//service") { el in
            el.setAttr("active", value: true)
            return el
        }
        let services = updated.findAll("service")
        XCTAssertEqual(services.count, 3)
        for svc in services {
            let active = svc.attr("active")
            XCTAssertNotNil(active)
        }
    }

    func testTransformAllWithPredicate() throws {
        let doc = try CXDocument.parse(fx("api_multi.cx"))
        // Only update api service
        let updated = try doc.transformAll("//service[@name=api]") { el in
            el.setAttr("port", value: 9999, dataType: "int")
            return el
        }
        let api = updated.findAll("service").first { $0.attr("name") as? String == "api" }
        let auth = updated.findAll("service").first { $0.attr("name") as? String == "auth" }
        XCTAssertEqual((api?.attr("port") as? NSNumber)?.intValue, 9999)
        XCTAssertEqual((auth?.attr("port") as? NSNumber)?.intValue, 8001)
    }
}
