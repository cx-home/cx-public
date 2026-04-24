package cx;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

/**
 * Decoder for the compact binary wire format produced by cx_to_ast_bin and
 * cx_to_events_bin.
 *
 * All integers are little-endian.
 *
 * String encoding:   u32(byte_len) + raw UTF-8 bytes (no null terminator)
 * OptStr encoding:   u8(0=absent | 1=present) + str if present
 * Attr encoding:     str:name + str:value_str + str:inferred_type
 */
public class BinaryDecoder {

    // ── Buffer reader ─────────────────────────────────────────────────────────

    static final class BufReader {
        private final ByteBuffer buf;

        BufReader(byte[] data) {
            this.buf = ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN);
        }

        int u8() {
            return buf.get() & 0xFF;
        }

        int u16() {
            return buf.getShort() & 0xFFFF;
        }

        long u32() {
            return buf.getInt() & 0xFFFFFFFFL;
        }

        String str() {
            int len = (int) u32();
            byte[] bytes = new byte[len];
            buf.get(bytes);
            return new String(bytes, StandardCharsets.UTF_8);
        }

        String optStr() {
            int flag = u8();
            if (flag == 0) return null;
            return str();
        }
    }

    // ── Scalar coercion ───────────────────────────────────────────────────────

    static Object coerce(String inferredType, String valueStr) {
        return switch (inferredType) {
            case "int"    -> Long.parseLong(valueStr);
            case "float"  -> Double.parseDouble(valueStr);
            case "bool"   -> "true".equals(valueStr);
            case "null"   -> null;
            default       -> valueStr;  // string / date / datetime / bytes
        };
    }

    // ── Attr reader ───────────────────────────────────────────────────────────

    static Attr readAttr(BufReader b) {
        String name      = b.str();
        String valueStr  = b.str();
        String inferType = b.str();
        Object value     = coerce(inferType, valueStr);
        // Only carry dataType forward when it's not plain "string"
        String dataType  = "string".equals(inferType) ? null : inferType;
        return new Attr(name, value, dataType);
    }

    // ── AST node reader ───────────────────────────────────────────────────────

    static Node readNode(BufReader b) {
        int tid = b.u8();
        return switch (tid) {
            case 0x01 -> {
                String     name     = b.str();
                String     anchor   = b.optStr();
                String     dataType = b.optStr();
                String     merge    = b.optStr();
                int        nAttrs   = b.u16();
                List<Attr> attrs = new ArrayList<>(nAttrs);
                for (int i = 0; i < nAttrs; i++) attrs.add(readAttr(b));
                int        nItems   = b.u16();
                List<Node> items    = new ArrayList<>(nItems);
                for (int i = 0; i < nItems; i++) items.add(readNode(b));
                Element e = new Element(name);
                e.anchor   = anchor;
                e.dataType = dataType;
                e.merge    = merge;
                e.attrs    = attrs;
                e.items    = items;
                yield e;
            }
            case 0x02 -> new TextNode(b.str());
            case 0x03 -> {
                String dt  = b.str();
                String val = b.str();
                yield new ScalarNode(dt, coerce(dt, val));
            }
            case 0x04 -> new CommentNode(b.str());
            case 0x05 -> new RawTextNode(b.str());
            case 0x06 -> new EntityRefNode(b.str());
            case 0x07 -> new AliasNode(b.str());
            case 0x08 -> {
                String target = b.str();
                String data   = b.optStr();
                yield new PINode(target, data);
            }
            case 0x09 -> {
                String version    = b.str();
                String encoding   = b.optStr();
                String standalone = b.optStr();
                yield new XMLDeclNode(version, encoding, standalone);
            }
            case 0x0A -> {
                int nAttrs = b.u16();
                List<Attr> attrs = new ArrayList<>(nAttrs);
                for (int i = 0; i < nAttrs; i++) attrs.add(readAttr(b));
                yield new CXDirectiveNode(attrs);
            }
            case 0x0C -> {
                int        nItems = b.u16();
                List<Node> items  = new ArrayList<>(nItems);
                for (int i = 0; i < nItems; i++) items.add(readNode(b));
                yield new BlockContentNode(items);
            }
            // 0xFF = skip/DTD, no payload
            default -> new TextNode("");
        };
    }

    // ── Public: decode AST ────────────────────────────────────────────────────

    /**
     * Decode a binary AST payload (the bytes after the 4-byte length prefix)
     * into a {@link CXDocument}.
     *
     * Format:
     *   u8:  version (=1)
     *   u16: prolog_count  + prolog nodes
     *   u16: element_count + element nodes
     */
    public static CXDocument decodeAST(byte[] data) {
        BufReader b = new BufReader(data);
        /* int version = */ b.u8();  // currently unused

        int nProlog = b.u16();
        List<Node> prolog = new ArrayList<>(nProlog);
        for (int i = 0; i < nProlog; i++) prolog.add(readNode(b));

        int nElements = b.u16();
        List<Node> elements = new ArrayList<>(nElements);
        for (int i = 0; i < nElements; i++) elements.add(readNode(b));

        CXDocument doc = new CXDocument();
        doc.prolog   = prolog;
        doc.elements = elements;
        return doc;
    }

    // ── Public: decode Events ─────────────────────────────────────────────────

    /**
     * Decode a binary events payload (the bytes after the 4-byte length prefix)
     * into a list of {@link StreamEvent}s.
     *
     * Format:
     *   u32: event_count
     *   For each event:
     *     u8: type_id  (see binary.py / task spec for mapping)
     */
    public static List<StreamEvent> decodeEvents(byte[] data) {
        BufReader b = new BufReader(data);
        long n = b.u32();
        List<StreamEvent> events = new ArrayList<>((int) n);

        for (long i = 0; i < n; i++) {
            int tid = b.u8();
            StreamEvent e = switch (tid) {
                case 0x01 -> new StreamEvent("StartDoc");
                case 0x02 -> new StreamEvent("EndDoc");
                case 0x03 -> {
                    StreamEvent se = new StreamEvent("StartElement");
                    se.name     = b.str();
                    se.anchor   = b.optStr();
                    se.dataType = b.optStr();
                    se.merge    = b.optStr();
                    int nAttrs  = b.u16();
                    se.attrs    = new ArrayList<>(nAttrs);
                    for (int j = 0; j < nAttrs; j++) {
                        String aName    = b.str();
                        String aValStr  = b.str();
                        String aType    = b.str();
                        Object aVal     = coerce(aType, aValStr);
                        String aDt      = "string".equals(aType) ? null : aType;
                        se.attrs.add(new Attr(aName, aVal, aDt));
                    }
                    yield se;
                }
                case 0x04 -> {
                    StreamEvent se = new StreamEvent("EndElement");
                    se.name = b.str();
                    yield se;
                }
                case 0x05 -> {
                    StreamEvent se = new StreamEvent("Text");
                    se.value = b.str();
                    yield se;
                }
                case 0x06 -> {
                    StreamEvent se = new StreamEvent("Scalar");
                    String dt  = b.str();
                    se.dataType = dt;
                    se.value    = coerce(dt, b.str());
                    yield se;
                }
                case 0x07 -> {
                    StreamEvent se = new StreamEvent("Comment");
                    se.value = b.str();
                    yield se;
                }
                case 0x08 -> {
                    StreamEvent se = new StreamEvent("PI");
                    se.target = b.str();
                    se.data   = b.optStr();
                    yield se;
                }
                case 0x09 -> {
                    StreamEvent se = new StreamEvent("EntityRef");
                    se.value = b.str();
                    yield se;
                }
                case 0x0A -> {
                    StreamEvent se = new StreamEvent("RawText");
                    se.value = b.str();
                    yield se;
                }
                case 0x0B -> {
                    StreamEvent se = new StreamEvent("Alias");
                    se.value = b.str();
                    yield se;
                }
                default -> new StreamEvent("Unknown");
            };
            events.add(e);
        }
        return events;
    }
}
