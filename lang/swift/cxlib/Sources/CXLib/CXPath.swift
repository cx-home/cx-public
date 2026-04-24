import Foundation

// ── CXPath AST ────────────────────────────────────────────────────────────────

indirect enum CXPred {
    case attrExists(String)
    case attrCmp(attr: String, op: String, val: Any?)
    case childExists(String)
    case not(CXPred)
    case boolAnd(CXPred, CXPred)
    case boolOr(CXPred, CXPred)
    case position(pos: Int, isLast: Bool)
    case funcContains(attr: String, val: String)
    case funcStartsWith(attr: String, val: String)
}

enum CXAxis { case child, descendant }

struct CXStep {
    var axis: CXAxis
    var name: String   // "" = wildcard
    var preds: [CXPred]
}

struct CXPathExpr {
    var steps: [CXStep]
}

// ── CXPath errors ─────────────────────────────────────────────────────────────

enum CXPathError: Error, CustomStringConvertible {
    case parse(String)
    var description: String {
        if case .parse(let msg) = self { return "CXPath parse error: \(msg)" }
        return "CXPath error"
    }
}

// ── Lexer ─────────────────────────────────────────────────────────────────────

private final class Lexer {
    let src: [Character]
    var pos: Int = 0

    init(_ s: String) { self.src = Array(s) }

    var srcStr: String { String(src) }

    func skipWs() {
        while pos < src.count && src[pos] == " " { pos += 1 }
    }

    func peekStr(_ s: String) -> Bool {
        let chars = Array(s)
        guard pos + chars.count <= src.count else { return false }
        return Array(src[pos..<(pos + chars.count)]) == chars
    }

    @discardableResult
    func eatStr(_ s: String) -> Bool {
        let chars = Array(s)
        if peekStr(s) { pos += chars.count; return true }
        return false
    }

    @discardableResult
    func eatChar(_ c: Character) -> Bool {
        if pos < src.count && src[pos] == c { pos += 1; return true }
        return false
    }

    func readIdent() -> String {
        let start = pos
        while pos < src.count {
            let c = src[pos]
            if c.isLetter || c.isNumber || "_-.:%".contains(c) {
                pos += 1
            } else {
                break
            }
        }
        return String(src[start..<pos])
    }

    func readQuoted() throws -> String {
        if !eatChar("'") {
            throw CXPathError.parse("expected ' at pos \(pos)  expr: \(srcStr)")
        }
        let start = pos
        while pos < src.count && src[pos] != "'" { pos += 1 }
        let s = String(src[start..<pos])
        if !eatChar("'") {
            throw CXPathError.parse("unterminated string at pos \(pos)  expr: \(srcStr)")
        }
        return s
    }
}

// ── Parser ────────────────────────────────────────────────────────────────────

func cxpathParse(_ expr: String) throws -> CXPathExpr {
    let l = Lexer(expr)
    let steps = try parseSteps(l)
    if l.pos != l.src.count {
        throw CXPathError.parse("unexpected characters at pos \(l.pos)  expr: \(expr)")
    }
    if steps.isEmpty {
        throw CXPathError.parse("empty expression  expr: \(expr)")
    }
    return CXPathExpr(steps: steps)
}

private func parseSteps(_ l: Lexer) throws -> [CXStep] {
    var steps: [CXStep] = []
    var axis: CXAxis = .child
    if l.eatStr("//") {
        axis = .descendant
    } else if l.eatStr("/") {
        axis = .child
    }
    steps.append(try parseOneStep(l, axis))
    while true {
        l.skipWs()
        if l.eatStr("//") {
            steps.append(try parseOneStep(l, .descendant))
        } else if l.eatStr("/") {
            steps.append(try parseOneStep(l, .child))
        } else {
            break
        }
    }
    return steps
}

private func parseOneStep(_ l: Lexer, _ axis: CXAxis) throws -> CXStep {
    l.skipWs()
    let name: String
    if l.eatChar("*") {
        name = ""
    } else {
        name = l.readIdent()
        if name.isEmpty {
            throw CXPathError.parse("expected element name at pos \(l.pos)  expr: \(l.srcStr)")
        }
    }
    var preds: [CXPred] = []
    while true {
        l.skipWs()
        if l.peekStr("[") {
            preds.append(try parsePredBracket(l))
        } else {
            break
        }
    }
    return CXStep(axis: axis, name: name, preds: preds)
}

private func parsePredBracket(_ l: Lexer) throws -> CXPred {
    if !l.eatChar("[") {
        throw CXPathError.parse("expected [ at pos \(l.pos)  expr: \(l.srcStr)")
    }
    l.skipWs()
    let pred = try parsePredExpr(l)
    l.skipWs()
    if !l.eatChar("]") {
        throw CXPathError.parse("expected ] at pos \(l.pos)  expr: \(l.srcStr)")
    }
    return pred
}

private func parsePredExpr(_ l: Lexer) throws -> CXPred {
    let left = try parsePredTerm(l)
    l.skipWs()
    let saved = l.pos
    let word = l.readIdent()
    if word == "or" {
        l.skipWs()
        let right = try parsePredTerm(l)
        return .boolOr(left, right)
    }
    l.pos = saved
    return left
}

private func parsePredTerm(_ l: Lexer) throws -> CXPred {
    let left = try parsePredFactor(l)
    l.skipWs()
    let saved = l.pos
    let word = l.readIdent()
    if word == "and" {
        l.skipWs()
        let right = try parsePredFactor(l)
        return .boolAnd(left, right)
    }
    l.pos = saved
    return left
}

private func parsePredFactor(_ l: Lexer) throws -> CXPred {
    l.skipWs()
    // not(...)
    if l.peekStr("not(") || l.peekStr("not (") {
        l.readIdent()  // consume 'not'
        l.skipWs()
        if !l.eatChar("(") {
            throw CXPathError.parse("expected ( after not  expr: \(l.srcStr)")
        }
        l.skipWs()
        let inner = try parsePredExpr(l)
        l.skipWs()
        if !l.eatChar(")") {
            throw CXPathError.parse("expected ) after not(...)  expr: \(l.srcStr)")
        }
        return .not(inner)
    }
    // contains(@attr, val)
    if l.peekStr("contains(") {
        l.readIdent()  // consume 'contains'
        l.skipWs()
        if !l.eatChar("(") {
            throw CXPathError.parse("expected ( after contains  expr: \(l.srcStr)")
        }
        l.skipWs()
        if !l.eatChar("@") {
            throw CXPathError.parse("expected @attr in contains()  expr: \(l.srcStr)")
        }
        let attr = l.readIdent()
        l.skipWs()
        if !l.eatChar(",") {
            throw CXPathError.parse("expected , in contains()  expr: \(l.srcStr)")
        }
        l.skipWs()
        let val = try parseScalarStr(l)
        l.skipWs()
        if !l.eatChar(")") {
            throw CXPathError.parse("expected ) after contains(...)  expr: \(l.srcStr)")
        }
        return .funcContains(attr: attr, val: val)
    }
    // starts-with(@attr, val)
    if l.peekStr("starts-with(") {
        while l.pos < l.src.count && l.src[l.pos] != "(" { l.pos += 1 }
        if !l.eatChar("(") {
            throw CXPathError.parse("expected ( after starts-with  expr: \(l.srcStr)")
        }
        l.skipWs()
        if !l.eatChar("@") {
            throw CXPathError.parse("expected @attr in starts-with()  expr: \(l.srcStr)")
        }
        let attr = l.readIdent()
        l.skipWs()
        if !l.eatChar(",") {
            throw CXPathError.parse("expected , in starts-with()  expr: \(l.srcStr)")
        }
        l.skipWs()
        let val = try parseScalarStr(l)
        l.skipWs()
        if !l.eatChar(")") {
            throw CXPathError.parse("expected ) after starts-with(...)  expr: \(l.srcStr)")
        }
        return .funcStartsWith(attr: attr, val: val)
    }
    // last()
    if l.eatStr("last()") {
        return .position(pos: 0, isLast: true)
    }
    // (grouped expr)
    if l.peekStr("(") {
        l.eatChar("(")
        l.skipWs()
        let inner = try parsePredExpr(l)
        l.skipWs()
        if !l.eatChar(")") {
            throw CXPathError.parse("expected ) at pos \(l.pos)  expr: \(l.srcStr)")
        }
        return inner
    }
    // @attr comparison or existence
    if l.pos < l.src.count && l.src[l.pos] == "@" {
        l.eatChar("@")
        let attr = l.readIdent()
        l.skipWs()
        let op = parseOp(l)
        if op.isEmpty {
            return .attrExists(attr)
        }
        l.skipWs()
        let val = try parseScalarVal(l)
        return .attrCmp(attr: attr, op: op, val: val)
    }
    // integer position predicate
    if l.pos < l.src.count && l.src[l.pos].isNumber {
        let start = l.pos
        while l.pos < l.src.count && l.src[l.pos].isNumber { l.pos += 1 }
        let n = Int(String(l.src[start..<l.pos])) ?? 0
        return .position(pos: n, isLast: false)
    }
    // bare name → child existence
    let name = l.readIdent()
    if !name.isEmpty {
        return .childExists(name)
    }
    throw CXPathError.parse("unexpected character at pos \(l.pos)  expr: \(l.srcStr)")
}

private func parseOp(_ l: Lexer) -> String {
    for op in ["!=", ">=", "<=", "=", ">", "<"] {
        if l.eatStr(op) { return op }
    }
    return ""
}

private func autotypeValue(_ s: String) -> Any? {
    if s == "true"  { return true }
    if s == "false" { return false }
    if s == "null"  { return nil }
    if let n = Int(s) { return n }
    if let f = Double(s) { return f }
    return s
}

private func parseScalarVal(_ l: Lexer) throws -> Any? {
    if l.peekStr("'") { return try l.readQuoted() }
    let s = l.readIdent()
    if s.isEmpty {
        throw CXPathError.parse("expected value at pos \(l.pos)  expr: \(l.srcStr)")
    }
    return autotypeValue(s)
}

private func parseScalarStr(_ l: Lexer) throws -> String {
    if l.peekStr("'") { return try l.readQuoted() }
    return l.readIdent()
}

// ── Evaluator ─────────────────────────────────────────────────────────────────

func collectStep(_ ctx: Element, _ pathExpr: CXPathExpr, _ stepIdx: Int, _ result: inout [Element]) {
    guard stepIdx < pathExpr.steps.count else { return }
    let step = pathExpr.steps[stepIdx]
    if step.axis == .child {
        let candidates: [Element] = ctx.items.compactMap {
            if case .element(let e) = $0 {
                return (step.name.isEmpty || e.name == step.name) ? e : nil
            }
            return nil
        }
        for (i, child) in candidates.enumerated() {
            if predsMatch(child, step.preds, candidates, i) {
                if stepIdx == pathExpr.steps.count - 1 {
                    result.append(child)
                } else {
                    collectStep(child, pathExpr, stepIdx + 1, &result)
                }
            }
        }
    } else {
        collectDescendants(ctx, pathExpr, stepIdx, &result)
    }
}

func collectDescendants(_ ctx: Element, _ pathExpr: CXPathExpr, _ stepIdx: Int, _ result: inout [Element]) {
    let step = pathExpr.steps[stepIdx]
    let isLast = stepIdx == pathExpr.steps.count - 1
    let candidates: [Element] = ctx.items.compactMap {
        if case .element(let e) = $0 {
            return (step.name.isEmpty || e.name == step.name) ? e : nil
        }
        return nil
    }
    for (i, child) in candidates.enumerated() {
        if predsMatch(child, step.preds, candidates, i) {
            if isLast {
                result.append(child)
            } else {
                collectStep(child, pathExpr, stepIdx + 1, &result)
            }
        }
        // Always recurse deeper for descendant axis
        collectDescendants(child, pathExpr, stepIdx, &result)
    }
    // Also descend into non-matching named children
    if !step.name.isEmpty {
        for item in ctx.items {
            if case .element(let child) = item, child.name != step.name {
                collectDescendants(child, pathExpr, stepIdx, &result)
            }
        }
    }
}

// ── Predicate evaluators ──────────────────────────────────────────────────────

func predsMatch(_ el: Element, _ preds: [CXPred], _ siblings: [Element], _ idx: Int) -> Bool {
    return preds.allSatisfy { predEval(el, $0, siblings, idx) }
}

private func predEval(_ el: Element, _ pred: CXPred, _ siblings: [Element], _ idx: Int) -> Bool {
    switch pred {
    case .attrExists(let name):
        return el.attr(name) != nil
    case .attrCmp(let attr, let op, let val):
        guard let v = el.attr(attr) else { return false }
        return cxCompare(v, op, val)
    case .childExists(let name):
        return el.get(name) != nil
    case .not(let inner):
        return !predEval(el, inner, siblings, idx)
    case .boolAnd(let l, let r):
        return predEval(el, l, siblings, idx) && predEval(el, r, siblings, idx)
    case .boolOr(let l, let r):
        return predEval(el, l, siblings, idx) || predEval(el, r, siblings, idx)
    case .position(let pos, let isLast):
        if isLast { return idx == siblings.count - 1 }
        return idx == pos - 1
    case .funcContains(let attr, let val):
        guard let v = el.attr(attr) else { return false }
        return cxValToStr(v).contains(val)
    case .funcStartsWith(let attr, let val):
        guard let v = el.attr(attr) else { return false }
        return cxValToStr(v).hasPrefix(val)
    }
}

private func cxValToStr(_ v: Any?) -> String {
    guard let v = v else { return "null" }
    if let b = v as? Bool { return b ? "true" : "false" }
    return String(describing: v)
}

func cxScalarEq(_ a: Any?, _ b: Any?) -> Bool {
    if a == nil && b == nil { return true }
    guard a != nil && b != nil else { return false }
    // Both are Bool
    if let ab = a as? Bool, let bb = b as? Bool { return ab == bb }
    // One is Bool, other is not
    if a is Bool || b is Bool { return false }
    // Numeric: use NSNumber for cross-type comparison (Int vs Double)
    if let an = (a as? NSNumber)?.doubleValue, let bn = (b as? NSNumber)?.doubleValue {
        return an == bn
    }
    // Int literals from autotype are plain Int, not NSNumber
    if let ai = a as? Int, let bi = b as? Int { return ai == bi }
    if let an = toF64(a), let bn = toF64(b) { return an == bn }
    // String
    if let as_ = a as? String, let bs = b as? String { return as_ == bs }
    return false
}

private func toF64(_ v: Any?) -> Double? {
    guard let v = v else { return nil }
    if v is Bool { return nil }
    if let n = v as? NSNumber { return n.doubleValue }
    if let i = v as? Int { return Double(i) }
    if let d = v as? Double { return d }
    return nil
}

private func cxCompare(_ actual: Any?, _ op: String, _ expected: Any?) -> Bool {
    switch op {
    case "=":  return cxScalarEq(actual, expected)
    case "!=": return !cxScalarEq(actual, expected)
    default:
        guard let a = toF64(actual), let b = toF64(expected) else { return false }
        switch op {
        case ">":  return a > b
        case "<":  return a < b
        case ">=": return a >= b
        case "<=": return a <= b
        default:   return false
        }
    }
}

// ── cxpathElemMatches (for transformAll) ──────────────────────────────────────

func cxpathElemMatches(_ el: Element, _ pathExpr: CXPathExpr) -> Bool {
    guard !pathExpr.steps.isEmpty else { return false }
    let last = pathExpr.steps[pathExpr.steps.count - 1]
    if !last.name.isEmpty && last.name != el.name { return false }
    // Filter out position predicates for matching (same as Python impl)
    let nonPos = last.preds.filter {
        if case .position = $0 { return false }
        return true
    }
    return predsMatch(el, nonPos, [], 0)
}

// ── Transform helpers ─────────────────────────────────────────────────────────

func elemDetached(_ e: Element) -> Element {
    let copy = Element(e.name, attrs: e.attrs, items: e.items)
    copy.anchor = e.anchor
    copy.merge = e.merge
    copy.dataType = e.dataType
    return copy
}

func docReplaceAt(_ d: CXDocument, _ idx: Int, _ el: Element) -> CXDocument {
    var newElements = d.elements
    newElements[idx] = .element(el)
    return CXDocument(elements: newElements, prolog: d.prolog)
}

func elemReplaceItemAt(_ e: Element, _ idx: Int, _ child: Node) -> Element {
    var newItems = e.items
    newItems[idx] = child
    let copy = Element(e.name, attrs: e.attrs, items: newItems)
    copy.anchor = e.anchor
    copy.merge = e.merge
    copy.dataType = e.dataType
    return copy
}

func pathCopyElement(_ e: Element, _ parts: [String], _ f: (Element) -> Element) -> Element? {
    for (i, item) in e.items.enumerated() {
        if case .element(let child) = item, child.name == parts[0] {
            if parts.count == 1 {
                return elemReplaceItemAt(e, i, .element(f(elemDetached(child))))
            }
            if let updated = pathCopyElement(child, Array(parts.dropFirst()), f) {
                return elemReplaceItemAt(e, i, .element(updated))
            }
            return nil
        }
    }
    return nil
}

func rebuildNode(_ node: Node, _ pathExpr: CXPathExpr, _ f: (Element) -> Element) -> Node {
    guard case .element(let el) = node else { return node }
    let newItems = el.items.map { rebuildNode($0, pathExpr, f) }
    let newEl = Element(el.name, attrs: el.attrs, items: newItems)
    newEl.anchor = el.anchor
    newEl.merge = el.merge
    newEl.dataType = el.dataType
    if cxpathElemMatches(newEl, pathExpr) {
        return .element(f(elemDetached(newEl)))
    }
    return .element(newEl)
}
