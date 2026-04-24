package cx

import com.google.gson.JsonArray
import com.google.gson.JsonElement
import com.google.gson.JsonNull
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import com.google.gson.JsonPrimitive

// ── Node hierarchy ─────────────────────────────────────────────────────────────

sealed class Node

data class Attr(val name: String, var value: Any?, var dataType: String? = null)

class Element(
    val name: String,
    var anchor: String? = null,
    var merge: String? = null,
    var dataType: String? = null,
    val attrs: MutableList<Attr> = mutableListOf(),
    val items: MutableList<Node> = mutableListOf(),
) : Node() {

    fun attr(name: String): Any? = attrs.find { it.name == name }?.value

    fun text(): String {
        val parts = mutableListOf<String>()
        for (item in items) {
            when (item) {
                is TextNode -> parts.add(item.value)
                is ScalarNode -> parts.add(if (item.value == null) "null" else item.value.toString())
                else -> {}
            }
        }
        return parts.joinToString(" ")
    }

    fun scalar(): Any? = items.filterIsInstance<ScalarNode>().firstOrNull()?.value

    fun children(): List<Element> = items.filterIsInstance<Element>()

    fun get(name: String): Element? =
        items.filterIsInstance<Element>().firstOrNull { it.name == name }

    fun getAll(name: String): List<Element> =
        items.filterIsInstance<Element>().filter { it.name == name }

    fun findAll(name: String): List<Element> {
        val result = mutableListOf<Element>()
        for (item in items) {
            if (item is Element) {
                if (item.name == name) result.add(item)
                result.addAll(item.findAll(name))
            }
        }
        return result
    }

    fun findFirst(name: String): Element? {
        for (item in items) {
            if (item is Element) {
                if (item.name == name) return item
                val found = item.findFirst(name)
                if (found != null) return found
            }
        }
        return null
    }

    fun at(path: String): Element? {
        val parts = path.split('/').filter { it.isNotEmpty() }
        var cur: Element? = this
        for (part in parts) {
            cur = cur?.get(part)
        }
        return cur
    }

    fun setAttr(name: String, value: Any?, dataType: String? = null) {
        val existing = attrs.find { it.name == name }
        if (existing != null) {
            existing.value = value
            existing.dataType = dataType
        } else {
            attrs.add(Attr(name, value, dataType))
        }
    }

    fun removeAttr(name: String) {
        attrs.removeIf { it.name == name }
    }

    fun append(node: Node) { items.add(node) }
    fun prepend(node: Node) { items.add(0, node) }
    fun insert(index: Int, node: Node) { items.add(index, node) }
    fun remove(node: Node) { items.removeIf { it === node } }

    fun toCx(): String = emitElement(this, 0)

    fun removeChild(name: String) {
        items.removeIf { it is Element && it.name == name }
    }

    fun removeAt(index: Int) {
        if (index in items.indices) items.removeAt(index)
    }

    fun select(expr: String): Element? = selectAll(expr).firstOrNull()

    fun selectAll(expr: String): List<Element> {
        val cx = cxpathParse(expr)
        val result = mutableListOf<Element>()
        collectStep(this, cx, 0, result)
        return result
    }
}

data class TextNode(val value: String) : Node()
data class ScalarNode(val dataType: String, val value: Any?) : Node()
data class CommentNode(val value: String) : Node()
data class RawTextNode(val value: String) : Node()
data class EntityRefNode(val name: String) : Node()
data class AliasNode(val name: String) : Node()
data class PINode(val target: String, val data: String? = null) : Node()
data class XMLDeclNode(
    val version: String = "1.0",
    val encoding: String? = null,
    val standalone: String? = null,
) : Node()
data class CXDirectiveNode(val attrs: List<Attr>) : Node()
data class DoctypeDeclNode(
    val name: String,
    val externalId: Any? = null,
    val intSubset: List<Any> = emptyList(),
) : Node()
data class BlockContentNode(val items: List<Node>) : Node()


// ── Document ───────────────────────────────────────────────────────────────────

class CXDocument(
    val elements: MutableList<Node> = mutableListOf(),
    val prolog: MutableList<Node> = mutableListOf(),
    var doctype: DoctypeDeclNode? = null,
) {
    fun root(): Element? = elements.filterIsInstance<Element>().firstOrNull()

    fun get(name: String): Element? =
        elements.filterIsInstance<Element>().firstOrNull { it.name == name }

    fun at(path: String): Element? {
        val parts = path.split('/').filter { it.isNotEmpty() }
        if (parts.isEmpty()) return root()
        val first = get(parts[0]) ?: return null
        if (parts.size == 1) return first
        return first.at(parts.drop(1).joinToString("/"))
    }

    fun findAll(name: String): List<Element> {
        val result = mutableListOf<Element>()
        for (e in elements) {
            if (e is Element) {
                if (e.name == name) result.add(e)
                result.addAll(e.findAll(name))
            }
        }
        return result
    }

    fun findFirst(name: String): Element? {
        for (e in elements) {
            if (e is Element) {
                if (e.name == name) return e
                val found = e.findFirst(name)
                if (found != null) return found
            }
        }
        return null
    }

    fun append(node: Node) { elements.add(node) }
    fun prepend(node: Node) { elements.add(0, node) }

    fun select(expr: String): Element? = selectAll(expr).firstOrNull()

    fun selectAll(expr: String): List<Element> {
        val cx = cxpathParse(expr)
        val vroot = Element("#document", items = elements.toMutableList())
        val result = mutableListOf<Element>()
        collectStep(vroot, cx, 0, result)
        return result
    }

    fun transform(path: String, f: (Element) -> Element): CXDocument {
        val parts = path.split("/").filter { it.isNotEmpty() }
        if (parts.isEmpty()) return this
        for ((i, node) in elements.withIndex()) {
            if (node is Element && node.name == parts[0]) {
                if (parts.size == 1) {
                    return docReplaceAt(this, i, f(elemDetached(node)))
                }
                val updated = pathCopyElement(node, parts.drop(1), f)
                if (updated != null) return docReplaceAt(this, i, updated)
                return this
            }
        }
        return this
    }

    fun transformAll(expr: String, f: (Element) -> Element): CXDocument {
        val cx = cxpathParse(expr)
        val newElements = elements.map { rebuildNode(it, cx, f) }.toMutableList()
        return CXDocument(newElements, prolog.toMutableList(), doctype)
    }

    fun toCx(): String = emitDoc(this)
    fun toXml(): String = CxLib.toXml(toCx())
    fun toJson(): String = CxLib.toJson(toCx())
    fun toYaml(): String = CxLib.toYaml(toCx())
    fun toToml(): String = CxLib.toToml(toCx())
    fun toMd(): String = CxLib.toMd(toCx())

    companion object {
        fun parse(cxStr: String): CXDocument {
            val data = CxLib.astBin(cxStr)
            return BinaryDecoder.decodeAST(data)
        }

        fun stream(cxStr: String): List<StreamEvent> {
            val data = CxLib.eventsBin(cxStr)
            return BinaryDecoder.decodeEvents(data)
        }

        fun parseXml(s: String): CXDocument {
            val astJson = CxLib.xmlToAst(s)
            val root = JsonParser.parseString(astJson).asJsonObject
            return docFromJson(root)
        }

        fun parseJson(s: String): CXDocument {
            val astJson = CxLib.jsonToAst(s)
            val root = JsonParser.parseString(astJson).asJsonObject
            return docFromJson(root)
        }

        fun parseYaml(s: String): CXDocument {
            val astJson = CxLib.yamlToAst(s)
            val root = JsonParser.parseString(astJson).asJsonObject
            return docFromJson(root)
        }

        fun parseToml(s: String): CXDocument {
            val astJson = CxLib.tomlToAst(s)
            val root = JsonParser.parseString(astJson).asJsonObject
            return docFromJson(root)
        }

        fun parseMd(s: String): CXDocument {
            val astJson = CxLib.mdToAst(s)
            val root = JsonParser.parseString(astJson).asJsonObject
            return docFromJson(root)
        }

        fun loads(cxStr: String): Any? {
            val jsonStr = CxLib.toJson(cxStr)
            return parseJsonValue(JsonParser.parseString(jsonStr))
        }

        fun loadsXml(s: String): Any? {
            val jsonStr = CxLib.xmlToJson(s)
            return parseJsonValue(JsonParser.parseString(jsonStr))
        }

        fun loadsJson(s: String): Any? {
            val jsonStr = CxLib.jsonToJson(s)
            return parseJsonValue(JsonParser.parseString(jsonStr))
        }

        fun loadsYaml(s: String): Any? {
            val jsonStr = CxLib.yamlToJson(s)
            return parseJsonValue(JsonParser.parseString(jsonStr))
        }

        fun loadsToml(s: String): Any? {
            val jsonStr = CxLib.tomlToJson(s)
            return parseJsonValue(JsonParser.parseString(jsonStr))
        }

        fun loadsMd(s: String): Any? {
            val jsonStr = CxLib.mdToJson(s)
            return parseJsonValue(JsonParser.parseString(jsonStr))
        }

        fun dumps(data: Any?): String {
            val jsonStr = nativeToJsonString(data)
            return CxLib.jsonToCx(jsonStr)
        }

        // ── JSON value parsing ─────────────────────────────────────────────────

        private fun parseJsonValue(el: JsonElement): Any? = when {
            el is JsonNull -> null
            el is JsonPrimitive && el.isBoolean -> el.asBoolean
            el is JsonPrimitive && el.isNumber -> {
                val n = el.asNumber
                val d = n.toDouble()
                val l = n.toLong()
                if (d == l.toDouble()) l else d
            }
            el is JsonPrimitive -> el.asString
            el is JsonObject -> {
                val map = mutableMapOf<String, Any?>()
                for ((k, v) in el.entrySet()) map[k] = parseJsonValue(v)
                map
            }
            el is JsonArray -> {
                el.map { parseJsonValue(it) }
            }
            else -> null
        }

        // ── Serialize native Kotlin values to JSON string ──────────────────────

        private fun nativeToJsonString(data: Any?): String = when (data) {
            null -> "null"
            is Boolean -> if (data) "true" else "false"
            is Int -> data.toString()
            is Long -> data.toString()
            is Double -> {
                val s = data.toString()
                if ('.' in s || 'e' in s.lowercase()) s else "$s.0"
            }
            is Float -> {
                val s = data.toDouble().toString()
                if ('.' in s || 'e' in s.lowercase()) s else "$s.0"
            }
            is Number -> data.toString()
            is String -> buildString {
                append('"')
                for (c in data) when (c) {
                    '"'  -> append("\\\"")
                    '\\' -> append("\\\\")
                    '\n' -> append("\\n")
                    '\r' -> append("\\r")
                    '\t' -> append("\\t")
                    else -> append(c)
                }
                append('"')
            }
            is Map<*, *> -> {
                data.entries.joinToString(",", "{", "}") { (k, v) ->
                    "${nativeToJsonString(k.toString())}:${nativeToJsonString(v)}"
                }
            }
            is List<*> -> data.joinToString(",", "[", "]") { nativeToJsonString(it) }
            is Array<*> -> data.joinToString(",", "[", "]") { nativeToJsonString(it) }
            else -> nativeToJsonString(data.toString())
        }

        // ── AST JSON → Document ────────────────────────────────────────────────

        internal fun docFromJson(d: JsonObject): CXDocument {
            val prolog = d.getAsJsonArray("prolog")
                ?.map { nodeFromJson(it.asJsonObject) }?.toMutableList()
                ?: mutableListOf()
            val elements = d.getAsJsonArray("elements")
                ?.map { nodeFromJson(it.asJsonObject) }?.toMutableList()
                ?: mutableListOf()
            val doctype: DoctypeDeclNode? = d.getAsJsonObject("doctype")?.let {
                DoctypeDeclNode(
                    name = it.get("name").asString,
                    externalId = it.get("externalID")?.takeUnless { e -> e is JsonNull },
                    intSubset = it.getAsJsonArray("intSubset")?.map { e -> e.toString() } ?: emptyList(),
                )
            }
            return CXDocument(elements = elements, prolog = prolog, doctype = doctype)
        }

        internal fun nodeFromJson(d: JsonObject): Node {
            return when (val t = d.get("type")?.asString ?: "") {
                "Element" -> Element(
                    name = d.get("name").asString,
                    anchor = d.get("anchor")?.takeUnless { it is JsonNull }?.asString,
                    merge = d.get("merge")?.takeUnless { it is JsonNull }?.asString,
                    dataType = d.get("dataType")?.takeUnless { it is JsonNull }?.asString,
                    attrs = d.getAsJsonArray("attrs")
                        ?.map { attrFromJson(it.asJsonObject) }?.toMutableList()
                        ?: mutableListOf(),
                    items = d.getAsJsonArray("items")
                        ?.map { nodeFromJson(it.asJsonObject) }?.toMutableList()
                        ?: mutableListOf(),
                )
                "Text" -> TextNode(d.get("value").asString)
                "Scalar" -> ScalarNode(
                    dataType = d.get("dataType").asString,
                    value = jsonScalarValue(d.get("value"), d.get("dataType").asString),
                )
                "Comment" -> CommentNode(d.get("value").asString)
                "RawText" -> RawTextNode(d.get("value").asString)
                "EntityRef" -> EntityRefNode(d.get("name").asString)
                "Alias" -> AliasNode(d.get("name").asString)
                "PI" -> PINode(
                    target = d.get("target").asString,
                    data = d.get("data")?.takeUnless { it is JsonNull }?.asString,
                )
                "XMLDecl" -> XMLDeclNode(
                    version = d.get("version")?.asString ?: "1.0",
                    encoding = d.get("encoding")?.takeUnless { it is JsonNull }?.asString,
                    standalone = d.get("standalone")?.takeUnless { it is JsonNull }?.asString,
                )
                "CXDirective" -> CXDirectiveNode(
                    attrs = d.getAsJsonArray("attrs")
                        ?.map { attrFromJson(it.asJsonObject) }
                        ?: emptyList(),
                )
                "DoctypeDecl" -> DoctypeDeclNode(
                    name = d.get("name").asString,
                    externalId = d.get("externalID")?.takeUnless { it is JsonNull },
                    intSubset = d.getAsJsonArray("intSubset")
                        ?.map { it.toString() } ?: emptyList(),
                )
                "BlockContent" -> BlockContentNode(
                    items = d.getAsJsonArray("items")
                        ?.map { nodeFromJson(it.asJsonObject) } ?: emptyList(),
                )
                else -> TextNode(d.toString())  // unknown — preserve as text
            }
        }

        private fun attrFromJson(a: JsonObject): Attr {
            val dt = a.get("dataType")?.takeUnless { it is JsonNull }?.asString
            val raw = a.get("value")
            val value = if (dt != null) jsonScalarValue(raw, dt) else {
                raw?.takeUnless { it is JsonNull }?.asString
            }
            return Attr(
                name = a.get("name").asString,
                value = value,
                dataType = dt,
            )
        }

        private fun jsonScalarValue(el: JsonElement?, dataType: String): Any? {
            if (el == null || el is JsonNull) return null
            if (el !is JsonPrimitive) return el.toString()
            return when (dataType) {
                "bool"     -> el.asBoolean
                "int"      -> el.asLong
                "float"    -> el.asDouble
                "null"     -> null
                else       -> el.asString
            }
        }
    }
}


// ── CX emitter ─────────────────────────────────────────────────────────────────

private val DATE_RE = Regex("""^\d{4}-\d{2}-\d{2}$""")
private val DATETIME_RE = Regex("""^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}""")
private val HEX_RE = Regex("""^0[xX][0-9a-fA-F]+$""")

private fun wouldAutotype(s: String): Boolean {
    if (' ' in s) return false
    if (HEX_RE.matches(s)) return true
    s.toLongOrNull()?.let { return true }
    if ('.' in s || 'e' in s.lowercase()) {
        s.toDoubleOrNull()?.let { return true }
    }
    if (s == "true" || s == "false" || s == "null") return true
    if (DATETIME_RE.containsMatchIn(s)) return true
    if (DATE_RE.matches(s)) return true
    return false
}

private fun cxChooseQuote(s: String): String = when {
    '\'' !in s -> "'$s'"
    '"' !in s  -> "\"$s\""
    "'''" !in s -> "'''$s'''"
    else -> "\"$s\""
}

private fun cxQuoteText(s: String): String {
    val needs = s.startsWith(' ') || s.endsWith(' ')
        || "  " in s || '\n' in s || '\t' in s
        || '[' in s || ']' in s || '&' in s
        || s.startsWith(':') || s.startsWith('\'') || s.startsWith('"')
        || wouldAutotype(s)
    return if (needs) cxChooseQuote(s) else s
}

private fun cxQuoteAttr(s: String): String {
    if (s.isEmpty() || ' ' in s || '\'' in s || '"' in s) return "'$s'"
    return s
}

private fun emitScalar(s: ScalarNode): String {
    val v = s.value ?: return "null"
    return when (v) {
        is Boolean -> if (v) "true" else "false"
        is Long    -> v.toString()
        is Int     -> v.toString()
        is Double  -> {
            val f = v.toString()
            if ('.' in f || 'e' in f.lowercase()) f else "$f.0"
        }
        is Float  -> {
            val f = v.toDouble().toString()
            if ('.' in f || 'e' in f.lowercase()) f else "$f.0"
        }
        else -> v.toString()
    }
}

private fun emitAttr(a: Attr): String {
    return when (a.dataType) {
        "int"  -> "${a.name}=${(a.value as? Number)?.toLong() ?: a.value}"
        "float" -> {
            val d = (a.value as? Number)?.toDouble() ?: 0.0
            val f = d.toString()
            val v = if ('.' in f || 'e' in f.lowercase()) f else "$f.0"
            "${a.name}=$v"
        }
        "bool" -> "${a.name}=${if (a.value == true) "true" else "false"}"
        "null" -> "${a.name}=null"
        else -> {
            val s = a.value?.toString() ?: ""
            val v = if (wouldAutotype(s)) cxChooseQuote(s) else cxQuoteAttr(s)
            "${a.name}=$v"
        }
    }
}

private fun emitInline(node: Node): String = when (node) {
    is TextNode -> if (node.value.isNotBlank()) cxQuoteText(node.value) else ""
    is ScalarNode -> emitScalar(node)
    is EntityRefNode -> "&${node.name};"
    is RawTextNode -> "[#${node.value}#]"
    is Element -> emitElement(node, 0).trimEnd('\n')
    is BlockContentNode -> {
        val inner = node.items.joinToString("") { n ->
            when (n) {
                is TextNode -> n.value
                is Element -> emitElement(n, 0).trimEnd('\n')
                else -> ""
            }
        }
        "[|$inner|]"
    }
    else -> ""
}

internal fun emitElement(e: Element, depth: Int): String {
    val ind = "  ".repeat(depth)
    val hasChildElems = e.items.any { it is Element }
    val hasText = e.items.any { it is TextNode || it is ScalarNode || it is EntityRefNode || it is RawTextNode }
    val isMultiline = hasChildElems && !hasText

    val metaParts = mutableListOf<String>()
    e.anchor?.let { metaParts.add("&$it") }
    e.merge?.let { metaParts.add("*$it") }
    e.dataType?.let { metaParts.add(":$it") }
    e.attrs.forEach { metaParts.add(emitAttr(it)) }
    val meta = if (metaParts.isNotEmpty()) " " + metaParts.joinToString(" ") else ""

    if (isMultiline) {
        val sb = StringBuilder()
        sb.append("$ind[${e.name}$meta\n")
        for (item in e.items) sb.append(emitNode(item, depth + 1))
        sb.append("$ind]\n")
        return sb.toString()
    }

    if (e.items.isEmpty() && meta.isEmpty()) {
        return "$ind[${e.name}]\n"
    }

    val bodyParts = e.items.map { emitInline(it) }.filter { it.isNotEmpty() }
    val body = bodyParts.joinToString(" ")
    val sep = if (body.isNotEmpty()) " " else ""
    return "$ind[${e.name}$meta$sep$body]\n"
}

internal fun emitNode(node: Node, depth: Int): String {
    val ind = "  ".repeat(depth)
    return when (node) {
        is Element -> emitElement(node, depth)
        is TextNode -> cxQuoteText(node.value)
        is ScalarNode -> emitScalar(node)
        is CommentNode -> "$ind[-${node.value}]\n"
        is RawTextNode -> "$ind[#${node.value}#]\n"
        is EntityRefNode -> "&${node.name};"
        is AliasNode -> "$ind[*${node.name}]\n"
        is BlockContentNode -> {
            val inner = node.items.joinToString("") { emitNode(it, 0) }
            "$ind[|$inner|]\n"
        }
        is PINode -> {
            val data = if (node.data != null) " ${node.data}" else ""
            "$ind[?${node.target}$data]\n"
        }
        is XMLDeclNode -> {
            val parts = mutableListOf("version=${node.version}")
            node.encoding?.let { parts.add("encoding=$it") }
            node.standalone?.let { parts.add("standalone=$it") }
            "[?xml ${parts.joinToString(" ")}]\n"
        }
        is CXDirectiveNode -> {
            val attrs = node.attrs.joinToString(" ") { "${it.name}=${cxQuoteAttr(it.value?.toString() ?: "")}" }
            "[?cx $attrs]\n"
        }
        is DoctypeDeclNode -> {
            val ext = buildString {
                val eid = node.externalId
                if (eid is Map<*, *>) {
                    val pub = eid["public"]
                    val sys = eid["system"]
                    if (pub != null) append(" PUBLIC '$pub' '${sys ?: ""}'")
                    else if (sys != null) append(" SYSTEM '$sys'")
                }
            }
            "[!DOCTYPE ${node.name}$ext]\n"
        }
    }
}

internal fun emitDoc(doc: CXDocument): String {
    val sb = StringBuilder()
    for (node in doc.prolog) sb.append(emitNode(node, 0))
    doc.doctype?.let { sb.append(emitNode(it, 0)) }
    for (node in doc.elements) sb.append(emitNode(node, 0))
    return sb.toString().trimEnd('\n')
}
