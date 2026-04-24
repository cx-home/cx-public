package cx

import java.nio.ByteBuffer
import java.nio.ByteOrder

// ── StreamEvent ───────────────────────────────────────────────────────────────

data class StreamEvent(
    val type: String,
    val name: String? = null,
    val anchor: String? = null,
    val dataType: String? = null,
    val merge: String? = null,
    val attrs: List<Attr> = emptyList(),
    val value: Any? = null,
    val target: String? = null,
    val data: String? = null,
)

// ── BufReader ─────────────────────────────────────────────────────────────────

private class BufReader(data: ByteArray) {
    private val buf: ByteBuffer = ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN)

    fun u8(): Int = buf.get().toInt() and 0xFF

    fun u16(): Int = buf.short.toInt() and 0xFFFF

    fun u32(): Int = buf.int   // still LE; we treat as unsigned via toLong() where needed

    fun str(): String {
        val len = u32()
        val bytes = ByteArray(len)
        buf.get(bytes)
        return String(bytes, Charsets.UTF_8)
    }

    fun optStr(): String? {
        val flag = u8()
        return if (flag == 0) null else str()
    }
}

// ── scalar coercion ───────────────────────────────────────────────────────────

private fun coerce(typeStr: String, valueStr: String): Any? = when (typeStr) {
    "int"   -> valueStr.toLong()
    "float" -> valueStr.toDouble()
    "bool"  -> valueStr == "true"
    "null"  -> null
    else    -> valueStr
}

// ── BinaryDecoder ─────────────────────────────────────────────────────────────

object BinaryDecoder {

    // ── AST ───────────────────────────────────────────────────────────────────

    fun decodeAST(data: ByteArray): CXDocument {
        val buf = BufReader(data)
        @Suppress("UNUSED_VARIABLE")
        val version = buf.u8()          // currently always 1
        val prologCount = buf.u16()
        val prolog = (0 until prologCount).map { readNode(buf) }.toMutableList()
        val elemCount = buf.u16()
        val elements = (0 until elemCount).map { readNode(buf) }.toMutableList()
        return CXDocument(elements = elements, prolog = prolog)
    }

    private fun readAttr(buf: BufReader): Attr {
        val name     = buf.str()
        val valueStr = buf.str()
        val typeStr  = buf.str()
        val dt = if (typeStr == "string") null else typeStr
        return Attr(name = name, value = coerce(typeStr, valueStr), dataType = dt)
    }

    private fun readNode(buf: BufReader): Node {
        return when (val tid = buf.u8()) {
            0x01 -> {
                val name      = buf.str()
                val anchor    = buf.optStr()
                val dataType  = buf.optStr()
                val merge     = buf.optStr()
                val attrCount = buf.u16()
                val attrs     = (0 until attrCount).map { readAttr(buf) }.toMutableList()
                val childCount = buf.u16()
                val items     = (0 until childCount).map { readNode(buf) }.toMutableList()
                Element(name = name, anchor = anchor, merge = merge, dataType = dataType,
                        attrs = attrs, items = items)
            }
            0x02 -> TextNode(buf.str())
            0x03 -> {
                val typeStr  = buf.str()
                val valueStr = buf.str()
                ScalarNode(dataType = typeStr, value = coerce(typeStr, valueStr))
            }
            0x04 -> CommentNode(buf.str())
            0x05 -> RawTextNode(buf.str())
            0x06 -> EntityRefNode(buf.str())
            0x07 -> AliasNode(buf.str())
            0x08 -> {
                val target = buf.str()
                val data   = buf.optStr()
                PINode(target = target, data = data)
            }
            0x09 -> {
                val version    = buf.str()
                val encoding   = buf.optStr()
                val standalone = buf.optStr()
                XMLDeclNode(version = version, encoding = encoding, standalone = standalone)
            }
            0x0A -> {
                val attrCount = buf.u16()
                val attrs = (0 until attrCount).map { readAttr(buf) }
                CXDirectiveNode(attrs = attrs)
            }
            0x0C -> {
                val childCount = buf.u16()
                val items = (0 until childCount).map { readNode(buf) }
                BlockContentNode(items = items)
            }
            0xFF -> TextNode("")   // skip marker — no payload
            else  -> TextNode("")  // unknown type — no payload assumed
        }
    }

    // ── Events ────────────────────────────────────────────────────────────────

    fun decodeEvents(data: ByteArray): List<StreamEvent> {
        val buf = BufReader(data)
        val count = buf.u32()   // event_count is u32
        val events = ArrayList<StreamEvent>(count)
        repeat(count) {
            val tid = buf.u8()
            val evt = when (tid) {
                0x01 -> StreamEvent(type = "StartDoc")
                0x02 -> StreamEvent(type = "EndDoc")
                0x03 -> {
                    val name     = buf.str()
                    val anchor   = buf.optStr()
                    val dataType = buf.optStr()
                    val merge    = buf.optStr()
                    val attrCount = buf.u16()
                    val attrs = (0 until attrCount).map {
                        val n  = buf.str()
                        val vs = buf.str()
                        val t  = buf.str()
                        val dt = if (t == "string") null else t
                        Attr(name = n, value = coerce(t, vs), dataType = dt)
                    }
                    StreamEvent(type = "StartElement", name = name, anchor = anchor,
                                dataType = dataType, merge = merge, attrs = attrs)
                }
                0x04 -> StreamEvent(type = "EndElement",  name = buf.str())
                0x05 -> StreamEvent(type = "Text",        value = buf.str())
                0x06 -> {
                    val typeStr  = buf.str()
                    val valueStr = buf.str()
                    StreamEvent(type = "Scalar", dataType = typeStr,
                                value = coerce(typeStr, valueStr))
                }
                0x07 -> StreamEvent(type = "Comment",   value = buf.str())
                0x08 -> {
                    val target = buf.str()
                    val data   = buf.optStr()
                    StreamEvent(type = "PI", target = target, data = data)
                }
                0x09 -> StreamEvent(type = "EntityRef", value = buf.str())
                0x0A -> StreamEvent(type = "RawText",   value = buf.str())
                0x0B -> StreamEvent(type = "Alias",     value = buf.str())
                else  -> StreamEvent(type = "Unknown")
            }
            events.add(evt)
        }
        return events
    }
}
