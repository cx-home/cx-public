import Foundation

// ── Attr ──────────────────────────────────────────────────────────────────────

public struct Attr {
    public var name: String
    public var value: Any?
    public var dataType: String?

    public init(_ name: String, _ value: Any?, dataType: String? = nil) {
        self.name = name
        self.value = value
        self.dataType = dataType
    }
}

// ── Node enum ─────────────────────────────────────────────────────────────────

public indirect enum Node {
    case element(Element)
    case text(String)
    case scalar(dataType: String, value: Any?)
    case comment(String)
    case rawText(String)
    case entityRef(String)
    case alias(String)
    case pi(target: String, data: String?)
    case xmlDecl(version: String, encoding: String?, standalone: String?)
    case cxDirective([Attr])
    case doctype(name: String, externalId: Any?)
    case blockContent([Node])
}

// ── Element ───────────────────────────────────────────────────────────────────

public class Element {
    public var name: String
    public var anchor: String?
    public var merge: String?
    public var dataType: String?
    public var attrs: [Attr]
    public var items: [Node]

    public init(_ name: String, attrs: [Attr] = [], items: [Node] = []) {
        self.name = name
        self.attrs = attrs
        self.items = items
    }

    /// Attribute value by name, or nil.
    public func attr(_ name: String) -> Any? {
        for a in attrs where a.name == name { return a.value }
        return nil
    }

    /// Concatenated Text and Scalar child content.
    public func text() -> String {
        var parts: [String] = []
        for item in items {
            switch item {
            case .text(let s):
                parts.append(s)
            case .scalar(_, let v):
                if let v = v { parts.append(String(describing: v)) }
                else { parts.append("null") }
            default:
                break
            }
        }
        return parts.joined(separator: " ")
    }

    /// Value of first Scalar child, or nil.
    public func scalar() -> Any? {
        for item in items {
            if case .scalar(_, let v) = item { return v }
        }
        return nil
    }

    /// All child Elements (excludes Text, Scalar, and other nodes).
    public func children() -> [Element] {
        return items.compactMap {
            if case .element(let e) = $0 { return e }
            return nil
        }
    }

    /// First child Element with this name.
    public func get(_ name: String) -> Element? {
        for item in items {
            if case .element(let e) = item, e.name == name { return e }
        }
        return nil
    }

    /// All child Elements with this name.
    public func getAll(_ name: String) -> [Element] {
        return items.compactMap {
            if case .element(let e) = $0, e.name == name { return e }
            return nil
        }
    }

    /// All descendant Elements with this name (depth-first).
    public func findAll(_ name: String) -> [Element] {
        var result: [Element] = []
        for item in items {
            if case .element(let e) = item {
                if e.name == name { result.append(e) }
                result.append(contentsOf: e.findAll(name))
            }
        }
        return result
    }

    /// First descendant Element with this name (depth-first).
    public func findFirst(_ name: String) -> Element? {
        for item in items {
            if case .element(let e) = item {
                if e.name == name { return e }
                if let found = e.findFirst(name) { return found }
            }
        }
        return nil
    }

    /// Navigate by slash-separated path.
    public func at(_ path: String) -> Element? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        var cur: Element? = self
        for part in parts {
            cur = cur?.get(part)
        }
        return cur
    }

    /// Set an attribute value, updating if it already exists.
    public func setAttr(_ name: String, value: Any?, dataType: String? = nil) {
        for i in attrs.indices {
            if attrs[i].name == name {
                attrs[i].value = value
                attrs[i].dataType = dataType
                return
            }
        }
        attrs.append(Attr(name, value, dataType: dataType))
    }

    /// Remove an attribute by name.
    public func removeAttr(_ name: String) {
        attrs.removeAll { $0.name == name }
    }

    public func append(_ node: Node) {
        items.append(node)
    }

    public func prepend(_ node: Node) {
        items.insert(node, at: 0)
    }

    public func insert(_ index: Int, _ node: Node) {
        items.insert(node, at: index)
    }

    /// Remove matching element by object identity.
    public func remove(_ node: Node) {
        items.removeAll { item in
            if case .element(let e) = item, case .element(let target) = node {
                return e === target
            }
            return false
        }
    }

    /// Remove all direct child Elements with the given name.
    public func removeChild(_ name: String) {
        items.removeAll { item in
            if case .element(let e) = item { return e.name == name }
            return false
        }
    }

    /// Remove child node at index (no-op if out of bounds).
    public func removeAt(_ index: Int) {
        guard index >= 0 && index < items.count else { return }
        items.remove(at: index)
    }

    /// First Element matching a CXPath expression (searches subtree of this element).
    public func select(_ expr: String) throws -> Element? {
        return try selectAll(expr).first
    }

    /// All Elements matching a CXPath expression (searches subtree of this element).
    public func selectAll(_ expr: String) throws -> [Element] {
        let cx = try cxpathParse(expr)
        var result: [Element] = []
        collectStep(self, cx, 0, &result)
        return result
    }

    /// Emit this element as a CX string.
    public func toCx() -> String {
        return _emitElement(self, depth: 0)
    }
}

// ── CXDocument ────────────────────────────────────────────────────────────────

public class CXDocument {
    public var elements: [Node]
    public var prolog: [Node]

    public init(elements: [Node] = [], prolog: [Node] = []) {
        self.elements = elements
        self.prolog = prolog
    }

    /// First top-level Element.
    public func root() -> Element? {
        for e in elements {
            if case .element(let el) = e { return el }
        }
        return nil
    }

    /// First top-level Element with this name.
    public func get(_ name: String) -> Element? {
        for e in elements {
            if case .element(let el) = e, el.name == name { return el }
        }
        return nil
    }

    /// Navigate by slash-separated path from root.
    public func at(_ path: String) -> Element? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !parts.isEmpty else { return root() }
        guard let cur = get(parts[0]) else { return nil }
        if parts.count == 1 { return cur }
        return cur.at(parts.dropFirst().joined(separator: "/"))
    }

    /// All descendant Elements with this name (depth-first through entire document).
    public func findAll(_ name: String) -> [Element] {
        var result: [Element] = []
        for e in elements {
            if case .element(let el) = e {
                if el.name == name { result.append(el) }
                result.append(contentsOf: el.findAll(name))
            }
        }
        return result
    }

    /// First descendant Element with this name (depth-first through entire document).
    public func findFirst(_ name: String) -> Element? {
        for e in elements {
            if case .element(let el) = e {
                if el.name == name { return el }
                if let found = el.findFirst(name) { return found }
            }
        }
        return nil
    }

    public func append(_ node: Node) {
        elements.append(node)
    }

    public func prepend(_ node: Node) {
        elements.insert(node, at: 0)
    }

    /// First Element matching a CXPath expression.
    public func select(_ expr: String) throws -> Element? {
        return try selectAll(expr).first
    }

    /// All Elements matching a CXPath expression.
    public func selectAll(_ expr: String) throws -> [Element] {
        let cx = try cxpathParse(expr)
        let vroot = Element("#document", items: elements)
        var result: [Element] = []
        collectStep(vroot, cx, 0, &result)
        return result
    }

    /// Return new CXDocument with element at path replaced by f(element).
    @discardableResult
    public func transform(_ path: String, _ f: (Element) -> Element) -> CXDocument {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !parts.isEmpty else { return self }
        for (i, node) in elements.enumerated() {
            if case .element(let el) = node, el.name == parts[0] {
                if parts.count == 1 {
                    return docReplaceAt(self, i, f(elemDetached(el)))
                }
                if let updated = pathCopyElement(el, Array(parts.dropFirst()), f) {
                    return docReplaceAt(self, i, updated)
                }
                return self
            }
        }
        return self
    }

    /// Return new CXDocument with all matching elements replaced by f(element).
    @discardableResult
    public func transformAll(_ expr: String, _ f: (Element) -> Element) throws -> CXDocument {
        let cx = try cxpathParse(expr)
        let newElements = elements.map { rebuildNode($0, cx, f) }
        return CXDocument(elements: newElements, prolog: prolog)
    }

    /// Emit this document as a CX string.
    public func toCx() -> String {
        return _emitDoc(self)
    }

    public func toXml() throws -> String {
        try CXLib.toXml(toCx())
    }

    public func toJson() throws -> String {
        try CXLib.toJson(toCx())
    }

    public func toYaml() throws -> String {
        try CXLib.toYaml(toCx())
    }

    public func toToml() throws -> String {
        try CXLib.toToml(toCx())
    }

    public func toMd() throws -> String {
        try CXLib.toMd(toCx())
    }

    // ── Parse ──────────────────────────────────────────────────────────────────

    /// Parse a CX string into a CXDocument (via binary wire protocol).
    public static func parse(_ cxStr: String) throws -> CXDocument {
        let data = try CXLib.astBin(cxStr)
        return try BinaryDecoder.decodeAST(data)
    }

    /// Parse an XML string into a CXDocument.
    public static func parseXml(_ s: String) throws -> CXDocument {
        let astJson = try CXLib.xmlToAst(s)
        guard let data = astJson.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw CXError.parse("invalid AST JSON") }
        return _docFromDict(obj)
    }

    /// Parse a JSON string into a CXDocument.
    public static func parseJson(_ s: String) throws -> CXDocument {
        let astJson = try CXLib.jsonToAst(s)
        guard let data = astJson.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw CXError.parse("invalid AST JSON") }
        return _docFromDict(obj)
    }

    /// Parse a YAML string into a CXDocument.
    public static func parseYaml(_ s: String) throws -> CXDocument {
        let astJson = try CXLib.yamlToAst(s)
        guard let data = astJson.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw CXError.parse("invalid AST JSON") }
        return _docFromDict(obj)
    }

    /// Parse a TOML string into a CXDocument.
    public static func parseToml(_ s: String) throws -> CXDocument {
        let astJson = try CXLib.tomlToAst(s)
        guard let data = astJson.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw CXError.parse("invalid AST JSON") }
        return _docFromDict(obj)
    }

    /// Parse a Markdown string into a CXDocument.
    public static func parseMd(_ s: String) throws -> CXDocument {
        let astJson = try CXLib.mdToAst(s)
        guard let data = astJson.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw CXError.parse("invalid AST JSON") }
        return _docFromDict(obj)
    }

    /// Stream a CX string as a sequence of StreamEvents.
    public static func stream(_ cxStr: String) throws -> [StreamEvent] {
        let data = try CXLib.eventsBin(cxStr)
        return try BinaryDecoder.decodeEvents(data)
    }

    // ── loads / dumps ──────────────────────────────────────────────────────────

    /// Deserialize a CX data string into native Swift types (dict/array/scalar).
    public static func loads(_ cxStr: String) throws -> Any {
        let jsonStr = try CXLib.toJson(cxStr)
        guard let data = jsonStr.data(using: .utf8) else {
            throw CXError.parse("invalid JSON from toJson")
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    /// Serialize native Swift types to a CX string.
    public static func dumps(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value)
        guard let jsonStr = String(data: data, encoding: .utf8) else {
            throw CXError.parse("JSON serialization failed")
        }
        return try CXLib.jsonToCx(jsonStr)
    }

    /// Deserialize an XML string into native Swift types.
    public static func loadsXml(_ xmlStr: String) throws -> Any {
        let jsonStr = try CXLib.xmlToJson(xmlStr)
        guard let data = jsonStr.data(using: .utf8) else {
            throw CXError.parse("invalid JSON from xmlToJson")
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    /// Deserialize a JSON string via the CX semantic bridge.
    public static func loadsJson(_ jsonStr: String) throws -> Any {
        let outStr = try CXLib.jsonToJson(jsonStr)
        guard let data = outStr.data(using: .utf8) else {
            throw CXError.parse("invalid JSON from jsonToJson")
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    /// Deserialize a YAML string into native Swift types.
    public static func loadsYaml(_ yamlStr: String) throws -> Any {
        let jsonStr = try CXLib.yamlToJson(yamlStr)
        guard let data = jsonStr.data(using: .utf8) else {
            throw CXError.parse("invalid JSON from yamlToJson")
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    /// Deserialize a TOML string into native Swift types.
    public static func loadsToml(_ tomlStr: String) throws -> Any {
        let jsonStr = try CXLib.tomlToJson(tomlStr)
        guard let data = jsonStr.data(using: .utf8) else {
            throw CXError.parse("invalid JSON from tomlToJson")
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    /// Deserialize a Markdown string into native Swift types.
    public static func loadsMd(_ mdStr: String) throws -> Any {
        let jsonStr = try CXLib.mdToJson(mdStr)
        guard let data = jsonStr.data(using: .utf8) else {
            throw CXError.parse("invalid JSON from mdToJson")
        }
        return try JSONSerialization.jsonObject(with: data)
    }
}

// ── Deserialization: AST JSON dict → native types ─────────────────────────────

private func _nodeFromDict(_ d: [String: Any]) -> Node {
    guard let type = d["type"] as? String else { return .text("") }
    switch type {
    case "Element":
        let el = Element(d["name"] as? String ?? "")
        el.anchor = d["anchor"] as? String
        el.merge = d["merge"] as? String
        el.dataType = d["dataType"] as? String
        el.attrs = (d["attrs"] as? [[String: Any]] ?? []).map { a in
            Attr(
                a["name"] as? String ?? "",
                a["value"],
                dataType: a["dataType"] as? String
            )
        }
        el.items = (d["items"] as? [[String: Any]] ?? []).map { _nodeFromDict($0) }
        return .element(el)

    case "Text":
        return .text(d["value"] as? String ?? "")

    case "Scalar":
        return .scalar(
            dataType: d["dataType"] as? String ?? "string",
            value: d["value"]
        )

    case "Comment":
        return .comment(d["value"] as? String ?? "")

    case "RawText":
        return .rawText(d["value"] as? String ?? "")

    case "EntityRef":
        return .entityRef(d["name"] as? String ?? "")

    case "Alias":
        return .alias(d["name"] as? String ?? "")

    case "PI":
        return .pi(
            target: d["target"] as? String ?? "",
            data: d["data"] as? String
        )

    case "XMLDecl":
        return .xmlDecl(
            version: d["version"] as? String ?? "1.0",
            encoding: d["encoding"] as? String,
            standalone: d["standalone"] as? String
        )

    case "CXDirective":
        let dirAttrs = (d["attrs"] as? [[String: Any]] ?? []).map { a in
            Attr(a["name"] as? String ?? "", a["value"])
        }
        return .cxDirective(dirAttrs)

    case "DoctypeDecl":
        return .doctype(
            name: d["name"] as? String ?? "",
            externalId: d["externalID"]
        )

    case "BlockContent":
        let innerItems = (d["items"] as? [[String: Any]] ?? []).map { _nodeFromDict($0) }
        return .blockContent(innerItems)

    default:
        return .text(String(describing: d))
    }
}

private func _docFromDict(_ d: [String: Any]) -> CXDocument {
    let prolog = (d["prolog"] as? [[String: Any]] ?? []).map { _nodeFromDict($0) }
    let elements = (d["elements"] as? [[String: Any]] ?? []).map { _nodeFromDict($0) }
    return CXDocument(elements: elements, prolog: prolog)
}

// ── CX emitter ────────────────────────────────────────────────────────────────

private let _dateRe = try! NSRegularExpression(pattern: #"^\d{4}-\d{2}-\d{2}$"#)
private let _datetimeRe = try! NSRegularExpression(pattern: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}"#)
private let _hexRe = try! NSRegularExpression(pattern: #"^0[xX][0-9a-fA-F]+$"#)

private func _matches(_ re: NSRegularExpression, _ s: String) -> Bool {
    let range = NSRange(s.startIndex..., in: s)
    return re.firstMatch(in: s, range: range) != nil
}

private func _wouldAutotype(_ s: String) -> Bool {
    if s.contains(" ") { return false }
    if _matches(_hexRe, s) { return true }
    if Int(s) != nil { return true }
    if s.contains(".") || s.lowercased().contains("e") {
        if Double(s) != nil { return true }
    }
    if s == "true" || s == "false" || s == "null" { return true }
    if _matches(_datetimeRe, s) { return true }
    if _matches(_dateRe, s) { return true }
    return false
}

private func _cxChooseQuote(_ s: String) -> String {
    if !s.contains("'") { return "'\(s)'" }
    if !s.contains("\"") { return "\"\(s)\"" }
    if !s.contains("'''") { return "'''\(s)'''" }
    return "\"\(s)\""
}

private func _cxQuoteText(_ s: String) -> String {
    let needs = (
        s.hasPrefix(" ") || s.hasSuffix(" ")
        || s.contains("  ") || s.contains("\n") || s.contains("\t")
        || s.contains("[") || s.contains("]") || s.contains("&")
        || s.hasPrefix(":") || s.hasPrefix("'") || s.hasPrefix("\"")
        || _wouldAutotype(s)
    )
    return needs ? _cxChooseQuote(s) : s
}

private func _cxQuoteAttr(_ s: String) -> String {
    if s.isEmpty || s.contains(" ") || s.contains("'") || s.contains("\"") {
        return "'\(s)'"
    }
    return s
}

private func _emitScalarValue(_ dataType: String, _ value: Any?) -> String {
    guard let v = value else { return "null" }
    if let b = v as? Bool { return b ? "true" : "false" }
    if let n = v as? NSNumber {
        // Check if it's a bool stored as NSNumber
        let objcType = String(cString: n.objCType)
        if objcType == "c" || objcType == "B" { return n.boolValue ? "true" : "false" }
        if dataType == "float" || objcType == "d" || objcType == "f" {
            let f = n.doubleValue
            let s = "\(f)"
            return (s.contains(".") || s.lowercased().contains("e")) ? s : s + ".0"
        }
        return n.stringValue
    }
    if let s = v as? String { return s }
    return String(describing: v)
}

private func _emitAttr(_ a: Attr) -> String {
    let dt = a.dataType
    if dt == "int" {
        if let n = a.value as? NSNumber { return "\(a.name)=\(n.intValue)" }
        return "\(a.name)=\(a.value ?? "null")"
    }
    if dt == "float" {
        if let n = a.value as? NSNumber {
            let f = n.doubleValue
            let s = "\(f)"
            let v = (s.contains(".") || s.lowercased().contains("e")) ? s : s + ".0"
            return "\(a.name)=\(v)"
        }
        return "\(a.name)=\(a.value ?? "null")"
    }
    if dt == "bool" {
        if let b = a.value as? Bool { return "\(a.name)=\(b ? "true" : "false")" }
        if let n = a.value as? NSNumber { return "\(a.name)=\(n.boolValue ? "true" : "false")" }
        return "\(a.name)=\(a.value ?? "null")"
    }
    if dt == "null" { return "\(a.name)=null" }
    // string attr
    let s = a.value.map { String(describing: $0) } ?? "null"
    let v = _wouldAutotype(s) ? _cxChooseQuote(s) : _cxQuoteAttr(s)
    return "\(a.name)=\(v)"
}

private func _emitInline(_ node: Node) -> String {
    switch node {
    case .text(let s):
        return s.trimmingCharacters(in: .whitespaces).isEmpty ? "" : _cxQuoteText(s)
    case .scalar(let dt, let v):
        return _emitScalarValue(dt, v)
    case .entityRef(let name):
        return "&\(name);"
    case .rawText(let s):
        return "[#\(s)#]"
    case .element(let e):
        return String(_emitElement(e, depth: 0).dropLast())  // strip trailing \n
    case .blockContent(let nodes):
        let inner = nodes.map { n -> String in
            if case .text(let s) = n { return s }
            if case .element(let e) = n { return String(_emitElement(e, depth: 0).dropLast()) }
            return _emitInline(n)
        }.joined()
        return "[|\(inner)|]"
    default:
        return ""
    }
}

private func _emitElement(_ e: Element, depth: Int) -> String {
    let ind = String(repeating: "  ", count: depth)
    let hasChildElems = e.items.contains { if case .element(_) = $0 { return true }; return false }
    let hasText = e.items.contains {
        switch $0 {
        case .text(_), .scalar(_, _), .entityRef(_), .rawText(_): return true
        default: return false
        }
    }
    let isMultiline = hasChildElems && !hasText

    var metaParts: [String] = []
    if let anchor = e.anchor { metaParts.append("&\(anchor)") }
    if let merge = e.merge { metaParts.append("*\(merge)") }
    if let dt = e.dataType { metaParts.append(":\(dt)") }
    for a in e.attrs { metaParts.append(_emitAttr(a)) }
    let meta = metaParts.isEmpty ? "" : " " + metaParts.joined(separator: " ")

    if isMultiline {
        var lines = ["\(ind)[\(e.name)\(meta)\n"]
        for item in e.items {
            lines.append(_emitNode(item, depth: depth + 1))
        }
        lines.append("\(ind)]\n")
        return lines.joined()
    }

    if e.items.isEmpty && meta.isEmpty {
        return "\(ind)[\(e.name)]\n"
    }

    let bodyParts = e.items.map { _emitInline($0) }.filter { !$0.isEmpty }
    let body = bodyParts.joined(separator: " ")
    let sep = body.isEmpty ? "" : " "
    return "\(ind)[\(e.name)\(meta)\(sep)\(body)]\n"
}

private func _emitNode(_ node: Node, depth: Int) -> String {
    let ind = String(repeating: "  ", count: depth)
    switch node {
    case .element(let e):
        return _emitElement(e, depth: depth)
    case .text(let s):
        return _cxQuoteText(s)
    case .scalar(let dt, let v):
        return _emitScalarValue(dt, v)
    case .comment(let s):
        return "\(ind)[-\(s)]\n"
    case .rawText(let s):
        return "\(ind)[#\(s)#]\n"
    case .entityRef(let name):
        return "&\(name);"
    case .alias(let name):
        return "\(ind)[*\(name)]\n"
    case .blockContent(let nodes):
        let inner = nodes.map { _emitNode($0, depth: 0) }.joined()
        return "\(ind)[|\(inner)|]\n"
    case .pi(let target, let data):
        let d = data.map { " \($0)" } ?? ""
        return "\(ind)[?\(target)\(d)]\n"
    case .xmlDecl(let version, let encoding, let standalone):
        var parts = ["version=\(version)"]
        if let enc = encoding { parts.append("encoding=\(enc)") }
        if let sa = standalone { parts.append("standalone=\(sa)") }
        return "[?xml \(parts.joined(separator: " "))]\n"
    case .cxDirective(let dirAttrs):
        let attrStr = dirAttrs.map { "\($0.name)=\(_cxQuoteAttr(String(describing: $0.value ?? "")))" }.joined(separator: " ")
        return "[?cx \(attrStr)]\n"
    case .doctype(let name, let externalId):
        var ext = ""
        if let extId = externalId as? [String: Any] {
            if let pub = extId["public"] as? String {
                let sys = extId["system"] as? String ?? ""
                ext = " PUBLIC '\(pub)' '\(sys)'"
            } else if let sys = extId["system"] as? String {
                ext = " SYSTEM '\(sys)'"
            }
        }
        return "[!DOCTYPE \(name)\(ext)]\n"
    }
}

private func _emitDoc(_ doc: CXDocument) -> String {
    var parts: [String] = []
    for node in doc.prolog {
        parts.append(_emitNode(node, depth: 0))
    }
    for node in doc.elements {
        parts.append(_emitNode(node, depth: 0))
    }
    var result = parts.joined()
    // Strip trailing newline like the Python emitter does .rstrip('\n')
    while result.hasSuffix("\n") { result.removeLast() }
    return result
}
