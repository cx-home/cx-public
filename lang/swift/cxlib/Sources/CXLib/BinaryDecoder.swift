import Foundation

// ── StreamEvent ───────────────────────────────────────────────────────────────

/// A single event from the CX streaming parser.
public struct StreamEvent {
    public var type: String
    // StartElement / EndElement
    public var name: String?
    public var anchor: String?
    public var dataType: String?
    public var merge: String?
    public var attrs: [Attr] = []
    // Text / Comment / RawText / EntityRef / Alias / Scalar value
    public var value: Any?
    // PI
    public var target: String?
    public var data: String?

    public init(type: String) { self.type = type }

    public func isStartElement(_ named: String? = nil) -> Bool {
        type == "StartElement" && (named == nil || name == named)
    }
    public func isEndElement(_ named: String? = nil) -> Bool {
        type == "EndElement" && (named == nil || name == named)
    }
}

// ── BufReader ─────────────────────────────────────────────────────────────────

private struct BufReader {
    let bytes: [UInt8]
    var pos: Int = 0

    init(_ data: Data) {
        self.bytes = Array(data)
    }

    mutating func u8() throws -> UInt8 {
        guard pos < bytes.count else { throw CXError.parse("binary: unexpected end of buffer (u8)") }
        let v = bytes[pos]; pos += 1; return v
    }

    mutating func u16() throws -> UInt16 {
        guard pos + 1 < bytes.count else { throw CXError.parse("binary: unexpected end of buffer (u16)") }
        let lo = UInt16(bytes[pos])
        let hi = UInt16(bytes[pos + 1])
        pos += 2
        return lo | (hi << 8)
    }

    mutating func u32() throws -> UInt32 {
        guard pos + 3 < bytes.count else { throw CXError.parse("binary: unexpected end of buffer (u32)") }
        let a = UInt32(bytes[pos])
        let b = UInt32(bytes[pos + 1])
        let c = UInt32(bytes[pos + 2])
        let d = UInt32(bytes[pos + 3])
        pos += 4
        return a | (b << 8) | (c << 16) | (d << 24)
    }

    mutating func str() throws -> String {
        let len = Int(try u32())
        guard pos + len <= bytes.count else { throw CXError.parse("binary: string overflows buffer") }
        let slice = bytes[pos ..< pos + len]
        pos += len
        guard let s = String(bytes: slice, encoding: .utf8) else {
            throw CXError.parse("binary: invalid UTF-8 in string")
        }
        return s
    }

    mutating func optStr() throws -> String? {
        let flag = try u8()
        guard flag != 0 else { return nil }
        return try str()
    }
}

// ── coercion ──────────────────────────────────────────────────────────────────

private func _coerce(_ typeStr: String, _ valueStr: String) -> Any? {
    switch typeStr {
    case "int":    return Int(valueStr) as Any?
    case "float":  return Double(valueStr) as Any?
    case "bool":   return (valueStr == "true") as Any?
    case "null":   return nil
    default:       return valueStr as Any?   // string / date / datetime / etc.
    }
}

// ── AST decoder ───────────────────────────────────────────────────────────────

private func _readAttr(_ b: inout BufReader) throws -> Attr {
    let name     = try b.str()
    let valueStr = try b.str()
    let typeStr  = try b.str()
    let dt: String? = typeStr == "string" ? nil : typeStr
    return Attr(name, _coerce(typeStr, valueStr), dataType: dt)
}

private func _readNode(_ b: inout BufReader) throws -> Node {
    let tid = try b.u8()
    switch tid {
    case 0x01:  // Element
        let name   = try b.str()
        let anchor = try b.optStr()
        let dt     = try b.optStr()
        let merge  = try b.optStr()
        let attrCount = Int(try b.u16())
        var attrs: [Attr] = []
        attrs.reserveCapacity(attrCount)
        for _ in 0 ..< attrCount { attrs.append(try _readAttr(&b)) }
        let childCount = Int(try b.u16())
        var items: [Node] = []
        items.reserveCapacity(childCount)
        for _ in 0 ..< childCount { items.append(try _readNode(&b)) }
        let el = Element(name, attrs: attrs, items: items)
        el.anchor   = anchor
        el.dataType = dt
        el.merge    = merge
        return .element(el)

    case 0x02:  // Text
        return .text(try b.str())

    case 0x03:  // Scalar
        let typeStr  = try b.str()
        let valueStr = try b.str()
        return .scalar(dataType: typeStr, value: _coerce(typeStr, valueStr))

    case 0x04:  // Comment
        return .comment(try b.str())

    case 0x05:  // RawText
        return .rawText(try b.str())

    case 0x06:  // EntityRef
        return .entityRef(try b.str())

    case 0x07:  // Alias
        return .alias(try b.str())

    case 0x08:  // PI
        let target = try b.str()
        let data   = try b.optStr()
        return .pi(target: target, data: data)

    case 0x09:  // XMLDecl
        let version    = try b.str()
        let encoding   = try b.optStr()
        let standalone = try b.optStr()
        return .xmlDecl(version: version, encoding: encoding, standalone: standalone)

    case 0x0A:  // CXDirective
        let count = Int(try b.u16())
        var attrs: [Attr] = []
        attrs.reserveCapacity(count)
        for _ in 0 ..< count { attrs.append(try _readAttr(&b)) }
        return .cxDirective(attrs)

    case 0x0C:  // BlockContent
        let count = Int(try b.u16())
        var items: [Node] = []
        items.reserveCapacity(count)
        for _ in 0 ..< count { items.append(try _readNode(&b)) }
        return .blockContent(items)

    case 0xFF:  // skip (DTD etc.) — no payload
        return .text("")

    default:
        throw CXError.parse("binary: unknown node type 0x\(String(tid, radix: 16))")
    }
}

// ── Events decoder ────────────────────────────────────────────────────────────

private func _decodeEvents(_ b: inout BufReader) throws -> [StreamEvent] {
    let count = Int(try b.u32())
    var events: [StreamEvent] = []
    events.reserveCapacity(count)

    for _ in 0 ..< count {
        let tid = try b.u8()
        switch tid {
        case 0x01:  // StartDoc
            events.append(StreamEvent(type: "StartDoc"))

        case 0x02:  // EndDoc
            events.append(StreamEvent(type: "EndDoc"))

        case 0x03:  // StartElement
            var e = StreamEvent(type: "StartElement")
            e.name     = try b.str()
            e.anchor   = try b.optStr()
            e.dataType = try b.optStr()
            e.merge    = try b.optStr()
            let attrCount = Int(try b.u16())
            var attrs: [Attr] = []
            attrs.reserveCapacity(attrCount)
            for _ in 0 ..< attrCount {
                let aName    = try b.str()
                let aValStr  = try b.str()
                let aTypeStr = try b.str()
                let dt: String? = aTypeStr == "string" ? nil : aTypeStr
                attrs.append(Attr(aName, _coerce(aTypeStr, aValStr), dataType: dt))
            }
            e.attrs = attrs
            events.append(e)

        case 0x04:  // EndElement
            var e = StreamEvent(type: "EndElement")
            e.name = try b.str()
            events.append(e)

        case 0x05:  // Text
            var e = StreamEvent(type: "Text")
            e.value = try b.str()
            events.append(e)

        case 0x06:  // Scalar
            var e = StreamEvent(type: "Scalar")
            let typeStr  = try b.str()
            let valueStr = try b.str()
            e.dataType = typeStr
            e.value    = _coerce(typeStr, valueStr)
            events.append(e)

        case 0x07:  // Comment
            var e = StreamEvent(type: "Comment")
            e.value = try b.str()
            events.append(e)

        case 0x08:  // PI
            var e = StreamEvent(type: "PI")
            e.target = try b.str()
            e.data   = try b.optStr()
            events.append(e)

        case 0x09:  // EntityRef
            var e = StreamEvent(type: "EntityRef")
            e.value = try b.str()
            events.append(e)

        case 0x0A:  // RawText
            var e = StreamEvent(type: "RawText")
            e.value = try b.str()
            events.append(e)

        case 0x0B:  // Alias
            var e = StreamEvent(type: "Alias")
            e.value = try b.str()
            events.append(e)

        default:
            throw CXError.parse("binary: unknown event type 0x\(String(tid, radix: 16))")
        }
    }
    return events
}

// ── Public API ────────────────────────────────────────────────────────────────

public enum BinaryDecoder {

    /// Decode a binary AST payload (without the 4-byte size prefix) into a CXDocument.
    public static func decodeAST(_ data: Data) throws -> CXDocument {
        var b = BufReader(data)
        _ = try b.u8()  // version byte (currently 1)
        let prologCount = Int(try b.u16())
        var prolog: [Node] = []
        prolog.reserveCapacity(prologCount)
        for _ in 0 ..< prologCount { prolog.append(try _readNode(&b)) }
        let elemCount = Int(try b.u16())
        var elements: [Node] = []
        elements.reserveCapacity(elemCount)
        for _ in 0 ..< elemCount { elements.append(try _readNode(&b)) }
        return CXDocument(elements: elements, prolog: prolog)
    }

    /// Decode a binary events payload (without the 4-byte size prefix) into [StreamEvent].
    public static func decodeEvents(_ data: Data) throws -> [StreamEvent] {
        var b = BufReader(data)
        return try _decodeEvents(&b)
    }
}
