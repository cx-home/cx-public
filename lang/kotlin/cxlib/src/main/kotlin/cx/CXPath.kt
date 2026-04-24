package cx

// ── Predicates ────────────────────────────────────────────────────────────────

sealed class CXPred
data class CXPredAttrExists(val attr: String) : CXPred()
data class CXPredAttrCmp(val attr: String, val op: String, val `val`: Any?) : CXPred()
data class CXPredChildExists(val name: String) : CXPred()
data class CXPredNot(val inner: CXPred) : CXPred()
data class CXPredBoolAnd(val left: CXPred, val right: CXPred) : CXPred()
data class CXPredBoolOr(val left: CXPred, val right: CXPred) : CXPred()
data class CXPredPosition(val pos: Int = 0, val isLast: Boolean = false) : CXPred()
data class CXPredFuncContains(val attr: String, val `val`: String) : CXPred()
data class CXPredFuncStartsWith(val attr: String, val `val`: String) : CXPred()

enum class CXAxis { CHILD, DESCENDANT }

data class CXStep(val axis: CXAxis, val name: String, val preds: List<CXPred>)
data class CXPathExpr(val steps: List<CXStep>)


// ── Lexer ─────────────────────────────────────────────────────────────────────

private class Lexer(val src: String) {
    var pos: Int = 0

    fun skipWs() {
        while (pos < src.length && src[pos] == ' ') pos++
    }

    fun peekStr(s: String): Boolean = src.startsWith(s, pos)

    fun eatStr(s: String): Boolean {
        if (peekStr(s)) { pos += s.length; return true }
        return false
    }

    fun eatChar(c: Char): Boolean {
        if (pos < src.length && src[pos] == c) { pos++; return true }
        return false
    }

    fun readIdent(): String {
        val start = pos
        while (pos < src.length) {
            val c = src[pos]
            if (c.isLetterOrDigit() || c in "_-.:%") pos++ else break
        }
        return src.substring(start, pos)
    }

    fun readQuoted(): String {
        if (!eatChar('\'')) throw IllegalArgumentException("CXPath parse error: expected ' at pos $pos  expr: $src")
        val start = pos
        while (pos < src.length && src[pos] != '\'') pos++
        val s = src.substring(start, pos)
        if (!eatChar('\'')) throw IllegalArgumentException("CXPath parse error: unterminated string at pos $pos  expr: $src")
        return s
    }
}


// ── Parser ────────────────────────────────────────────────────────────────────

fun cxpathParse(expr: String): CXPathExpr {
    val l = Lexer(expr)
    val steps = parseSteps(l)
    if (l.pos != l.src.length)
        throw IllegalArgumentException("CXPath parse error: unexpected characters at pos ${l.pos}  expr: $expr")
    if (steps.isEmpty())
        throw IllegalArgumentException("CXPath parse error: empty expression  expr: $expr")
    return CXPathExpr(steps)
}

private fun parseSteps(l: Lexer): List<CXStep> {
    val steps = mutableListOf<CXStep>()
    val axis = when {
        l.peekStr("//") -> { l.pos += 2; CXAxis.DESCENDANT }
        l.peekStr("/")  -> { l.pos += 1; CXAxis.CHILD }
        else -> CXAxis.CHILD
    }
    steps.add(parseOneStep(l, axis))
    while (true) {
        l.skipWs()
        when {
            l.peekStr("//") -> { l.pos += 2; steps.add(parseOneStep(l, CXAxis.DESCENDANT)) }
            l.peekStr("/")  -> { l.pos += 1; steps.add(parseOneStep(l, CXAxis.CHILD)) }
            else -> break
        }
    }
    return steps
}

private fun parseOneStep(l: Lexer, axis: CXAxis): CXStep {
    l.skipWs()
    val name = if (l.eatChar('*')) {
        ""
    } else {
        val n = l.readIdent()
        if (n.isEmpty()) throw IllegalArgumentException("CXPath parse error: expected element name at pos ${l.pos}  expr: ${l.src}")
        n
    }
    val preds = mutableListOf<CXPred>()
    while (true) {
        l.skipWs()
        if (l.peekStr("[")) preds.add(parsePredBracket(l))
        else break
    }
    return CXStep(axis, name, preds)
}

private fun parsePredBracket(l: Lexer): CXPred {
    if (!l.eatChar('[')) throw IllegalArgumentException("CXPath parse error: expected [ at pos ${l.pos}  expr: ${l.src}")
    l.skipWs()
    val pred = parsePredExpr(l)
    l.skipWs()
    if (!l.eatChar(']')) throw IllegalArgumentException("CXPath parse error: expected ] at pos ${l.pos}  expr: ${l.src}")
    return pred
}

private fun parsePredExpr(l: Lexer): CXPred {
    val left = parsePredTerm(l)
    l.skipWs()
    val saved = l.pos
    val word = l.readIdent()
    if (word == "or") {
        l.skipWs()
        val right = parsePredTerm(l)
        return CXPredBoolOr(left, right)
    }
    l.pos = saved
    return left
}

private fun parsePredTerm(l: Lexer): CXPred {
    val left = parsePredFactor(l)
    l.skipWs()
    val saved = l.pos
    val word = l.readIdent()
    if (word == "and") {
        l.skipWs()
        val right = parsePredFactor(l)
        return CXPredBoolAnd(left, right)
    }
    l.pos = saved
    return left
}

private fun parsePredFactor(l: Lexer): CXPred {
    l.skipWs()
    // not(...)
    if (l.peekStr("not(") || l.peekStr("not (")) {
        l.readIdent()  // consume 'not'
        l.skipWs()
        if (!l.eatChar('(')) throw IllegalArgumentException("CXPath parse error: expected ( after not  expr: ${l.src}")
        l.skipWs()
        val inner = parsePredExpr(l)
        l.skipWs()
        if (!l.eatChar(')')) throw IllegalArgumentException("CXPath parse error: expected ) after not(...)  expr: ${l.src}")
        return CXPredNot(inner)
    }
    // contains(@attr, val)
    if (l.peekStr("contains(")) {
        l.readIdent()  // consume 'contains'
        l.skipWs()
        if (!l.eatChar('(')) throw IllegalArgumentException("CXPath parse error: expected ( after contains  expr: ${l.src}")
        l.skipWs()
        if (!l.eatChar('@')) throw IllegalArgumentException("CXPath parse error: expected @attr in contains()  expr: ${l.src}")
        val attr = l.readIdent()
        l.skipWs()
        if (!l.eatChar(',')) throw IllegalArgumentException("CXPath parse error: expected , in contains()  expr: ${l.src}")
        l.skipWs()
        val `val` = parseScalarStr(l)
        l.skipWs()
        if (!l.eatChar(')')) throw IllegalArgumentException("CXPath parse error: expected ) after contains(...)  expr: ${l.src}")
        return CXPredFuncContains(attr, `val`)
    }
    // starts-with(@attr, val)
    if (l.peekStr("starts-with(")) {
        while (l.pos < l.src.length && l.src[l.pos] != '(') l.pos++
        if (!l.eatChar('(')) throw IllegalArgumentException("CXPath parse error: expected ( after starts-with  expr: ${l.src}")
        l.skipWs()
        if (!l.eatChar('@')) throw IllegalArgumentException("CXPath parse error: expected @attr in starts-with()  expr: ${l.src}")
        val attr = l.readIdent()
        l.skipWs()
        if (!l.eatChar(',')) throw IllegalArgumentException("CXPath parse error: expected , in starts-with()  expr: ${l.src}")
        l.skipWs()
        val `val` = parseScalarStr(l)
        l.skipWs()
        if (!l.eatChar(')')) throw IllegalArgumentException("CXPath parse error: expected ) after starts-with(...)  expr: ${l.src}")
        return CXPredFuncStartsWith(attr, `val`)
    }
    // last()
    if (l.peekStr("last()")) {
        l.pos += 6
        return CXPredPosition(isLast = true)
    }
    // (grouped expr)
    if (l.peekStr("(")) {
        l.eatChar('(')
        l.skipWs()
        val inner = parsePredExpr(l)
        l.skipWs()
        if (!l.eatChar(')')) throw IllegalArgumentException("CXPath parse error: expected ) at pos ${l.pos}  expr: ${l.src}")
        return inner
    }
    // @attr comparison or existence
    if (l.pos < l.src.length && l.src[l.pos] == '@') {
        l.eatChar('@')
        val attr = l.readIdent()
        l.skipWs()
        val op = parseOp(l)
        if (op.isEmpty()) return CXPredAttrExists(attr)
        l.skipWs()
        val `val` = parseScalarVal(l)
        return CXPredAttrCmp(attr, op, `val`)
    }
    // integer position predicate
    if (l.pos < l.src.length && l.src[l.pos].isDigit()) {
        val start = l.pos
        while (l.pos < l.src.length && l.src[l.pos].isDigit()) l.pos++
        return CXPredPosition(pos = l.src.substring(start, l.pos).toInt())
    }
    // bare name → child existence
    val name = l.readIdent()
    if (name.isNotEmpty()) return CXPredChildExists(name)
    throw IllegalArgumentException("CXPath parse error: unexpected character at pos ${l.pos}  expr: ${l.src}")
}

private fun parseOp(l: Lexer): String {
    for (op in listOf("!=", ">=", "<=", "=", ">", "<")) {
        if (l.eatStr(op)) return op
    }
    return ""
}

private fun autotypeValue(s: String): Any? {
    if (s == "true")  return true
    if (s == "false") return false
    if (s == "null")  return null
    s.toLongOrNull()?.let { return it }
    s.toDoubleOrNull()?.let { return it }
    return s
}

private fun parseScalarVal(l: Lexer): Any? {
    if (l.peekStr("'")) return l.readQuoted()
    val s = l.readIdent()
    if (s.isEmpty()) throw IllegalArgumentException("CXPath parse error: expected value at pos ${l.pos}  expr: ${l.src}")
    return autotypeValue(s)
}

private fun parseScalarStr(l: Lexer): String {
    if (l.peekStr("'")) return l.readQuoted()
    return l.readIdent()
}


// ── Evaluator ─────────────────────────────────────────────────────────────────

fun collectStep(ctx: Element, expr: CXPathExpr, stepIdx: Int, result: MutableList<Element>) {
    if (stepIdx >= expr.steps.size) return
    val step = expr.steps[stepIdx]
    if (step.axis == CXAxis.CHILD) {
        val candidates = ctx.items.filterIsInstance<Element>()
            .filter { step.name.isEmpty() || it.name == step.name }
        for ((i, child) in candidates.withIndex()) {
            if (predsMatch(child, step.preds, candidates, i)) {
                if (stepIdx == expr.steps.size - 1) {
                    result.add(child)
                } else {
                    collectStep(child, expr, stepIdx + 1, result)
                }
            }
        }
    } else {
        collectDescendants(ctx, expr, stepIdx, result)
    }
}

private fun collectDescendants(ctx: Element, expr: CXPathExpr, stepIdx: Int, result: MutableList<Element>) {
    val step = expr.steps[stepIdx]
    val isLast = stepIdx == expr.steps.size - 1
    val candidates = ctx.items.filterIsInstance<Element>()
        .filter { step.name.isEmpty() || it.name == step.name }
    for ((i, child) in candidates.withIndex()) {
        if (predsMatch(child, step.preds, candidates, i)) {
            if (isLast) {
                result.add(child)
            } else {
                collectStep(child, expr, stepIdx + 1, result)
            }
        }
        // Always recurse deeper for descendant axis
        collectDescendants(child, expr, stepIdx, result)
    }
    // Also descend into non-matching children for named steps
    if (step.name.isNotEmpty()) {
        for (child in ctx.items) {
            if (child is Element && child.name != step.name) {
                collectDescendants(child, expr, stepIdx, result)
            }
        }
    }
}


// ── Predicate evaluators ──────────────────────────────────────────────────────

private fun predsMatch(el: Element, preds: List<CXPred>, siblings: List<Element>, idx: Int): Boolean =
    preds.all { predEval(el, it, siblings, idx) }

private fun predEval(el: Element, pred: CXPred, siblings: List<Element>, idx: Int): Boolean = when (pred) {
    is CXPredAttrExists -> el.attr(pred.attr) != null
    is CXPredAttrCmp -> {
        val v = el.attr(pred.attr)
        if (v == null) false else compare(v, pred.op, pred.`val`)
    }
    is CXPredChildExists -> el.get(pred.name) != null
    is CXPredNot -> !predEval(el, pred.inner, siblings, idx)
    is CXPredBoolAnd -> predEval(el, pred.left, siblings, idx) && predEval(el, pred.right, siblings, idx)
    is CXPredBoolOr  -> predEval(el, pred.left, siblings, idx) || predEval(el, pred.right, siblings, idx)
    is CXPredPosition -> if (pred.isLast) idx == siblings.size - 1 else idx == pred.pos - 1
    is CXPredFuncContains -> {
        val v = el.attr(pred.attr)
        v != null && pred.`val` in valToStr(v)
    }
    is CXPredFuncStartsWith -> {
        val v = el.attr(pred.attr)
        v != null && valToStr(v).startsWith(pred.`val`)
    }
}

private fun valToStr(v: Any?): String = when {
    v == null -> "null"
    v is Boolean -> if (v) "true" else "false"
    else -> v.toString()
}

private fun scalarEq(a: Any?, b: Any?): Boolean {
    // Guard: bool vs non-bool cross-type must never match (unlike Python where bool < int)
    val aBool = a is Boolean
    val bBool = b is Boolean
    if (aBool != bBool) return false
    // Numeric equality via Double (handles Long vs Double comparisons)
    if (a is Number && b is Number)
        return a.toDouble() == b.toDouble()
    return a == b
}

private fun compare(actual: Any?, op: String, expected: Any?): Boolean = when (op) {
    "="  -> scalarEq(actual, expected)
    "!=" -> !scalarEq(actual, expected)
    else -> {
        val a = toF64(actual)
        val b = toF64(expected)
        when (op) {
            ">"  -> a > b
            "<"  -> a < b
            ">=" -> a >= b
            "<=" -> a <= b
            else -> false
        }
    }
}

private fun toF64(v: Any?): Double {
    if (v is Boolean) throw IllegalArgumentException("CXPath: numeric comparison requires numeric value, got bool: $v")
    if (v is Number) return v.toDouble()
    throw IllegalArgumentException("CXPath: numeric comparison requires numeric attribute value, got: $v")
}


// ── cxpathElemMatches (for transformAll) ──────────────────────────────────────

fun cxpathElemMatches(el: Element, expr: CXPathExpr): Boolean {
    if (expr.steps.isEmpty()) return false
    val last = expr.steps.last()
    if (last.name.isNotEmpty() && last.name != el.name) return false
    val nonPos = last.preds.filter { it !is CXPredPosition }
    return predsMatch(el, nonPos, emptyList(), 0)
}


// ── Transform helpers ─────────────────────────────────────────────────────────

fun elemDetached(e: Element): Element =
    Element(
        name = e.name,
        anchor = e.anchor,
        merge = e.merge,
        dataType = e.dataType,
        attrs = e.attrs.map { Attr(it.name, it.value, it.dataType) }.toMutableList(),
        items = e.items.toMutableList(),
    )

fun docReplaceAt(d: CXDocument, idx: Int, el: Element): CXDocument {
    val newElements = d.elements.mapIndexed { i, n -> if (i == idx) el else n }.toMutableList()
    return CXDocument(newElements, d.prolog.toMutableList(), d.doctype)
}

fun elemReplaceItemAt(e: Element, idx: Int, child: Node): Element =
    Element(
        name = e.name,
        anchor = e.anchor,
        merge = e.merge,
        dataType = e.dataType,
        attrs = e.attrs,
        items = e.items.mapIndexed { i, n -> if (i == idx) child else n }.toMutableList(),
    )

fun pathCopyElement(e: Element, parts: List<String>, f: (Element) -> Element): Element? {
    for ((i, item) in e.items.withIndex()) {
        if (item is Element && item.name == parts[0]) {
            return if (parts.size == 1) {
                elemReplaceItemAt(e, i, f(elemDetached(item)))
            } else {
                val updated = pathCopyElement(item, parts.drop(1), f)
                if (updated != null) elemReplaceItemAt(e, i, updated) else null
            }
        }
    }
    return null
}

fun rebuildNode(node: Node, expr: CXPathExpr, f: (Element) -> Element): Node {
    if (node !is Element) return node
    val newItems = node.items.map { rebuildNode(it, expr, f) }.toMutableList()
    val newEl = Element(
        name = node.name,
        anchor = node.anchor,
        merge = node.merge,
        dataType = node.dataType,
        attrs = node.attrs,
        items = newItems,
    )
    return if (cxpathElemMatches(newEl, expr)) f(elemDetached(newEl)) else newEl
}
