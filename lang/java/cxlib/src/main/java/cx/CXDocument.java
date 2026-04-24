package cx;

import com.google.gson.*;
import java.util.*;
import java.util.function.Function;
import java.util.regex.*;

/**
 * CX Document API — types, parse, query, mutation, CX emitter, loads/dumps.
 *
 * Architecture:
 *   CXDocument.parse(cxStr)  → CxLib.toAst(cxStr) → JSON → native Java objects
 *   CXDocument.loads(cxStr)  → CxLib.toJson(cxStr) → parse JSON → Java Object
 *   CXDocument.dumps(data)   → CxLib.jsonToCx(gson.toJson(data)) → CX string
 *   doc.toCx()               → native CX emitter (StringBuilder)
 *   doc.toXml() etc.         → CxLib.toXml(doc.toCx())
 */

// ── Node marker interface ──────────────────────────────────────────────────────

/**
 * Marker interface for all AST node types.
 */
interface Node {}

// ── Concrete node types ────────────────────────────────────────────────────────

class Attr {
    public String name;
    public Object value;     // String | Long | Double | Boolean | null
    public String dataType;  // null means string (omitted in JSON)

    public Attr(String name, Object value, String dataType) {
        this.name     = name;
        this.value    = value;
        this.dataType = dataType;
    }

    public Attr(String name, Object value) {
        this(name, value, null);
    }
}

class TextNode implements Node {
    public String value;
    public TextNode(String value) { this.value = value; }
}

class ScalarNode implements Node {
    public String dataType;  // int | float | bool | null | string | date | datetime | bytes
    public Object value;     // native Java value

    public ScalarNode(String dataType, Object value) {
        this.dataType = dataType;
        this.value    = value;
    }
}

class CommentNode implements Node {
    public String value;
    public CommentNode(String value) { this.value = value; }
}

class RawTextNode implements Node {
    public String value;
    public RawTextNode(String value) { this.value = value; }
}

class EntityRefNode implements Node {
    public String name;
    public EntityRefNode(String name) { this.name = name; }
}

class AliasNode implements Node {
    public String name;
    public AliasNode(String name) { this.name = name; }
}

class PINode implements Node {
    public String target;
    public String data;  // may be null
    public PINode(String target, String data) {
        this.target = target;
        this.data   = data;
    }
}

class XMLDeclNode implements Node {
    public String version;
    public String encoding;    // may be null
    public String standalone;  // may be null

    public XMLDeclNode(String version, String encoding, String standalone) {
        this.version    = version    != null ? version    : "1.0";
        this.encoding   = encoding;
        this.standalone = standalone;
    }
}

class CXDirectiveNode implements Node {
    public List<Attr> attrs;
    public CXDirectiveNode(List<Attr> attrs) { this.attrs = attrs; }
}

class BlockContentNode implements Node {
    public List<Node> items;
    public BlockContentNode(List<Node> items) { this.items = items; }
}

class DoctypeDeclNode implements Node {
    public String name;
    public Map<String, Object> externalId;  // may be null
    public List<Object> intSubset;

    public DoctypeDeclNode(String name, Map<String, Object> externalId, List<Object> intSubset) {
        this.name       = name;
        this.externalId = externalId;
        this.intSubset  = intSubset != null ? intSubset : new ArrayList<>();
    }
}

// ── Element ────────────────────────────────────────────────────────────────────

class Element implements Node {
    public String     name;
    public String     anchor;    // may be null
    public String     merge;     // may be null
    public String     dataType;  // may be null — TypeAnnotation e.g. "int[]"
    public List<Attr> attrs;
    public List<Node> items;

    public Element(String name) {
        this.name     = name;
        this.anchor   = null;
        this.merge    = null;
        this.dataType = null;
        this.attrs    = new ArrayList<>();
        this.items    = new ArrayList<>();
    }

    /** Attribute value by name, or null. */
    public Object attr(String attrName) {
        for (Attr a : attrs) {
            if (a.name.equals(attrName)) return a.value;
        }
        return null;
    }

    /** Concatenated Text and Scalar child content. */
    public String text() {
        List<String> parts = new ArrayList<>();
        for (Node item : items) {
            if (item instanceof TextNode t) {
                parts.add(t.value);
            } else if (item instanceof ScalarNode s) {
                parts.add(s.value == null ? "null" : String.valueOf(s.value));
            }
        }
        return String.join(" ", parts);
    }

    /** Value of first Scalar child, or null. */
    public Object scalar() {
        for (Node item : items) {
            if (item instanceof ScalarNode s) return s.value;
        }
        return null;
    }

    /** All child Elements (excludes Text, Scalar, and other node types). */
    public List<Element> children() {
        List<Element> result = new ArrayList<>();
        for (Node item : items) {
            if (item instanceof Element e) result.add(e);
        }
        return result;
    }

    /** First child Element with this name. */
    public Element get(String childName) {
        for (Node item : items) {
            if (item instanceof Element e && e.name.equals(childName)) return e;
        }
        return null;
    }

    /** All direct child Elements with this name. */
    public List<Element> getAll(String childName) {
        List<Element> result = new ArrayList<>();
        for (Node item : items) {
            if (item instanceof Element e && e.name.equals(childName)) result.add(e);
        }
        return result;
    }

    /** All descendant Elements with this name (depth-first). */
    public List<Element> findAll(String targetName) {
        List<Element> result = new ArrayList<>();
        for (Node item : items) {
            if (item instanceof Element e) {
                if (e.name.equals(targetName)) result.add(e);
                result.addAll(e.findAll(targetName));
            }
        }
        return result;
    }

    /** First descendant Element with this name (depth-first). */
    public Element findFirst(String targetName) {
        for (Node item : items) {
            if (item instanceof Element e) {
                if (e.name.equals(targetName)) return e;
                Element found = e.findFirst(targetName);
                if (found != null) return found;
            }
        }
        return null;
    }

    /** Navigate by slash-separated path: el.at("server/host"). */
    public Element at(String path) {
        String[] parts = Arrays.stream(path.split("/"))
                               .filter(p -> !p.isEmpty())
                               .toArray(String[]::new);
        Element cur = this;
        for (String part : parts) {
            if (cur == null) return null;
            cur = cur.get(part);
        }
        return cur;
    }

    /** Set an attribute value, updating if it already exists. */
    public void setAttr(String attrName, Object value, String attrDataType) {
        for (Attr a : attrs) {
            if (a.name.equals(attrName)) {
                a.value    = value;
                a.dataType = attrDataType;
                return;
            }
        }
        attrs.add(new Attr(attrName, value, attrDataType));
    }

    /** Set a string attribute value. */
    public void setAttr(String attrName, Object value) {
        setAttr(attrName, value, null);
    }

    /** Remove an attribute by name. */
    public void removeAttr(String attrName) {
        attrs.removeIf(a -> a.name.equals(attrName));
    }

    /** Append a child node. */
    public void append(Node node) {
        items.add(node);
    }

    /** Prepend a child node. */
    public void prepend(Node node) {
        items.add(0, node);
    }

    /** Insert a child node at index. */
    public void insert(int index, Node node) {
        items.add(index, node);
    }

    /** Remove a child node by identity. */
    public void remove(Node node) {
        items.removeIf(i -> i == node);
    }

    /** Remove all direct child Elements with the given name. */
    public void removeChild(String name) {
        items.removeIf(i -> i instanceof Element e && e.name.equals(name));
    }

    /** Remove child node at index (no-op if out of bounds). */
    public void removeAt(int index) {
        if (index >= 0 && index < items.size()) items.remove(index);
    }

    /** First Element matching a CXPath expression. */
    public Element select(String expr) {
        List<Element> results = selectAll(expr);
        return results.isEmpty() ? null : results.get(0);
    }

    /** All Elements matching a CXPath expression (subtree of this element). */
    public List<Element> selectAll(String expr) {
        CXPath.CXPathExpr cx = CXPath.parse(expr);
        List<Element> result = new ArrayList<>();
        CXPath.collectStep(this, cx, 0, result);
        return result;
    }

    /** Emit this element as a CX string (no trailing newline). */
    public String toCx() {
        return CxEmitter.emitElement(this, 0).stripTrailing();
    }
}

// ── CXDocument ─────────────────────────────────────────────────────────────────

/**
 * Top-level document object.
 */
public class CXDocument {
    public List<Node>        elements;
    public List<Node>        prolog;
    public DoctypeDeclNode   doctype;  // may be null

    public CXDocument() {
        this.elements = new ArrayList<>();
        this.prolog   = new ArrayList<>();
        this.doctype  = null;
    }

    /** First top-level Element. */
    public Element root() {
        for (Node e : elements) {
            if (e instanceof Element el) return el;
        }
        return null;
    }

    /** First top-level Element with this name. */
    public Element get(String name) {
        for (Node e : elements) {
            if (e instanceof Element el && el.name.equals(name)) return el;
        }
        return null;
    }

    /** Navigate by slash-separated path from root. */
    public Element at(String path) {
        String[] parts = Arrays.stream(path.split("/"))
                               .filter(p -> !p.isEmpty())
                               .toArray(String[]::new);
        if (parts.length == 0) return root();
        Element cur = get(parts[0]);
        if (cur == null || parts.length == 1) return cur;
        return cur.at(String.join("/", Arrays.copyOfRange(parts, 1, parts.length)));
    }

    /** All descendant Elements with this name (depth-first through entire document). */
    public List<Element> findAll(String name) {
        List<Element> result = new ArrayList<>();
        for (Node e : elements) {
            if (e instanceof Element el) {
                if (el.name.equals(name)) result.add(el);
                result.addAll(el.findAll(name));
            }
        }
        return result;
    }

    /** First descendant Element with this name (depth-first through entire document). */
    public Element findFirst(String name) {
        for (Node e : elements) {
            if (e instanceof Element el) {
                if (el.name.equals(name)) return el;
                Element found = el.findFirst(name);
                if (found != null) return found;
            }
        }
        return null;
    }

    /** Append a top-level node. */
    public void append(Node node) {
        elements.add(node);
    }

    /** Prepend a top-level node. */
    public void prepend(Node node) {
        elements.add(0, node);
    }

    /** First Element matching a CXPath expression. */
    public Element select(String expr) {
        List<Element> results = selectAll(expr);
        return results.isEmpty() ? null : results.get(0);
    }

    /** All Elements matching a CXPath expression. */
    public List<Element> selectAll(String expr) {
        CXPath.CXPathExpr cx = CXPath.parse(expr);
        Element vroot = new Element("#document");
        vroot.items = new ArrayList<>(elements);
        List<Element> result = new ArrayList<>();
        CXPath.collectStep(vroot, cx, 0, result);
        return result;
    }

    /** Return new document with element at path replaced by f(element). */
    public CXDocument transform(String path, Function<Element, Element> f) {
        String[] parts = Arrays.stream(path.split("/"))
                               .filter(p -> !p.isEmpty())
                               .toArray(String[]::new);
        if (parts.length == 0) return this;
        for (int i = 0; i < elements.size(); i++) {
            if (elements.get(i) instanceof Element el && el.name.equals(parts[0])) {
                if (parts.length == 1) {
                    return CXPath.docReplaceAt(this, i, f.apply(CXPath.elemDetached(el)));
                }
                Element updated = CXPath.pathCopyElement(el, Arrays.copyOfRange(parts, 1, parts.length), f);
                if (updated != null) return CXPath.docReplaceAt(this, i, updated);
                return this;
            }
        }
        return this;
    }

    /** Return new document with all matching elements replaced by f(element). */
    public CXDocument transformAll(String expr, Function<Element, Element> f) {
        CXPath.CXPathExpr cx = CXPath.parse(expr);
        List<Node> newElements = elements.stream()
                                         .map(n -> CXPath.rebuildNode(n, cx, f))
                                         .toList();
        CXDocument d = new CXDocument();
        d.elements = new ArrayList<>(newElements);
        d.prolog   = new ArrayList<>(this.prolog);
        d.doctype  = this.doctype;
        return d;
    }

    /** Emit the document as a CX string using the native emitter. */
    public String toCx() {
        return CxEmitter.emitDoc(this);
    }

    public String toXml()  { return CxLib.toXml(toCx());  }
    public String toJson() { return CxLib.toJson(toCx()); }
    public String toYaml() { return CxLib.toYaml(toCx()); }
    public String toToml() { return CxLib.toToml(toCx()); }
    public String toMd()   { return CxLib.toMd(toCx());   }

    // ── Static factory methods ─────────────────────────────────────────────────

    /** Parse a CX string into a CXDocument (uses binary wire protocol). */
    public static CXDocument parse(String cxStr) throws Exception {
        byte[] data = CxLib.astBin(cxStr);
        return BinaryDecoder.decodeAST(data);
    }

    /** Stream a CX string as a list of SAX-like {@link StreamEvent}s. */
    public static List<StreamEvent> stream(String cxStr) throws Exception {
        byte[] data = CxLib.eventsBin(cxStr);
        return BinaryDecoder.decodeEvents(data);
    }

    /** Parse an XML string into a CXDocument. */
    public static CXDocument parseXml(String s) {
        String astJson = CxLib.xmlToAst(s);
        return AstDeserializer.docFromJson(new Gson().fromJson(astJson, JsonObject.class));
    }

    /** Parse a JSON string into a CXDocument. */
    public static CXDocument parseJson(String s) {
        String astJson = CxLib.jsonToAst(s);
        return AstDeserializer.docFromJson(new Gson().fromJson(astJson, JsonObject.class));
    }

    /** Parse a YAML string into a CXDocument. */
    public static CXDocument parseYaml(String s) {
        String astJson = CxLib.yamlToAst(s);
        return AstDeserializer.docFromJson(new Gson().fromJson(astJson, JsonObject.class));
    }

    /** Parse a TOML string into a CXDocument. */
    public static CXDocument parseToml(String s) {
        String astJson = CxLib.tomlToAst(s);
        return AstDeserializer.docFromJson(new Gson().fromJson(astJson, JsonObject.class));
    }

    /** Parse a Markdown string into a CXDocument. */
    public static CXDocument parseMd(String s) {
        String astJson = CxLib.mdToAst(s);
        return AstDeserializer.docFromJson(new Gson().fromJson(astJson, JsonObject.class));
    }

    // ── Data binding ───────────────────────────────────────────────────────────

    /** Deserialize a CX data string into native Java types (Map/List/scalar). */
    public static Object loads(String cxStr) {
        String jsonStr = CxLib.toJson(cxStr);
        return new Gson().fromJson(jsonStr, Object.class);
    }

    /** Deserialize an XML string into native Java types. */
    public static Object loadsXml(String s) {
        return new Gson().fromJson(CxLib.xmlToJson(s), Object.class);
    }

    /** Deserialize a JSON string via the CX semantic bridge. */
    public static Object loadsJson(String s) {
        return new Gson().fromJson(CxLib.jsonToJson(s), Object.class);
    }

    /** Deserialize a YAML string into native Java types. */
    public static Object loadsYaml(String s) {
        return new Gson().fromJson(CxLib.yamlToJson(s), Object.class);
    }

    /** Deserialize a TOML string into native Java types. */
    public static Object loadsToml(String s) {
        return new Gson().fromJson(CxLib.tomlToJson(s), Object.class);
    }

    /** Deserialize a Markdown string into native Java types. */
    public static Object loadsMd(String s) {
        return new Gson().fromJson(CxLib.mdToJson(s), Object.class);
    }

    /** Serialize native Java types (Map/List/scalar) to a CX string. */
    public static String dumps(Object data) {
        return CxLib.jsonToCx(new Gson().toJson(data));
    }
}

// ── AST deserializer ────────────────────────────────────────────────────────────

class AstDeserializer {

    static CXDocument docFromJson(JsonObject d) {
        CXDocument doc = new CXDocument();
        if (d.has("prolog") && !d.get("prolog").isJsonNull()) {
            for (JsonElement n : d.getAsJsonArray("prolog")) {
                doc.prolog.add(nodeFromJson(n.getAsJsonObject()));
            }
        }
        if (d.has("doctype") && !d.get("doctype").isJsonNull()) {
            JsonObject dt = d.getAsJsonObject("doctype");
            doc.doctype = new DoctypeDeclNode(
                dt.get("name").getAsString(),
                null,
                new ArrayList<>()
            );
        }
        if (d.has("elements") && !d.get("elements").isJsonNull()) {
            for (JsonElement n : d.getAsJsonArray("elements")) {
                doc.elements.add(nodeFromJson(n.getAsJsonObject()));
            }
        }
        return doc;
    }

    static Node nodeFromJson(JsonObject o) {
        String type = o.get("type").getAsString();
        return switch (type) {
            case "Element"     -> elementFromJson(o);
            case "Text"        -> new TextNode(o.get("value").getAsString());
            case "Scalar"      -> new ScalarNode(
                                      o.get("dataType").getAsString(),
                                      scalarValue(o));
            case "Comment"     -> new CommentNode(o.get("value").getAsString());
            case "RawText"     -> new RawTextNode(o.get("value").getAsString());
            case "EntityRef"   -> new EntityRefNode(o.get("name").getAsString());
            case "Alias"       -> new AliasNode(o.get("name").getAsString());
            case "PI"          -> new PINode(
                                      o.get("target").getAsString(),
                                      o.has("data") && !o.get("data").isJsonNull()
                                          ? o.get("data").getAsString() : null);
            case "XMLDecl"     -> new XMLDeclNode(
                                      o.has("version")    ? o.get("version").getAsString()    : "1.0",
                                      o.has("encoding")   ? o.get("encoding").getAsString()   : null,
                                      o.has("standalone") ? o.get("standalone").getAsString() : null);
            case "CXDirective" -> {
                List<Attr> attrs = new ArrayList<>();
                if (o.has("attrs")) {
                    for (JsonElement a : o.getAsJsonArray("attrs")) {
                        JsonObject ao = a.getAsJsonObject();
                        attrs.add(new Attr(ao.get("name").getAsString(),
                                           ao.get("value").getAsString(), null));
                    }
                }
                yield new CXDirectiveNode(attrs);
            }
            case "DoctypeDecl" -> new DoctypeDeclNode(
                                      o.get("name").getAsString(), null, new ArrayList<>());
            case "BlockContent" -> {
                List<Node> items = new ArrayList<>();
                if (o.has("items")) {
                    for (JsonElement n : o.getAsJsonArray("items"))
                        items.add(nodeFromJson(n.getAsJsonObject()));
                }
                yield new BlockContentNode(items);
            }
            default -> new TextNode(o.toString());  // unknown — preserve as text
        };
    }

    static Element elementFromJson(JsonObject o) {
        Element e = new Element(o.get("name").getAsString());
        if (o.has("anchor")   && !o.get("anchor").isJsonNull())
            e.anchor   = o.get("anchor").getAsString();
        if (o.has("merge")    && !o.get("merge").isJsonNull())
            e.merge    = o.get("merge").getAsString();
        if (o.has("dataType") && !o.get("dataType").isJsonNull())
            e.dataType = o.get("dataType").getAsString();
        if (o.has("attrs") && !o.get("attrs").isJsonNull()) {
            for (JsonElement a : o.getAsJsonArray("attrs")) {
                JsonObject ao = a.getAsJsonObject();
                Object attrVal = attrValue(ao);
                String attrDt  = ao.has("dataType") && !ao.get("dataType").isJsonNull()
                                  ? ao.get("dataType").getAsString() : null;
                e.attrs.add(new Attr(ao.get("name").getAsString(), attrVal, attrDt));
            }
        }
        if (o.has("items") && !o.get("items").isJsonNull()) {
            for (JsonElement n : o.getAsJsonArray("items"))
                e.items.add(nodeFromJson(n.getAsJsonObject()));
        }
        return e;
    }

    /** Deserialize an attribute value from JSON, preserving native type. */
    static Object attrValue(JsonObject ao) {
        if (!ao.has("value") || ao.get("value").isJsonNull()) return null;
        JsonElement v = ao.get("value");
        String dt = ao.has("dataType") && !ao.get("dataType").isJsonNull()
                    ? ao.get("dataType").getAsString() : null;
        if (v.isJsonPrimitive()) {
            JsonPrimitive p = v.getAsJsonPrimitive();
            if (p.isBoolean()) return p.getAsBoolean();
            if (p.isNumber()) {
                // Use dataType to decide representation
                if ("int".equals(dt))   return p.getAsLong();
                if ("float".equals(dt)) return p.getAsDouble();
                // Infer from JSON number
                double d = p.getAsDouble();
                if (d == Math.floor(d) && !Double.isInfinite(d) && !"float".equals(dt))
                    return p.getAsLong();
                return d;
            }
            return p.getAsString();
        }
        return v.toString();
    }

    /** Deserialize a scalar value from a Scalar node JSON object. */
    static Object scalarValue(JsonObject o) {
        if (!o.has("value") || o.get("value").isJsonNull()) return null;
        JsonElement v  = o.get("value");
        String      dt = o.get("dataType").getAsString();
        if (v.isJsonPrimitive()) {
            JsonPrimitive p = v.getAsJsonPrimitive();
            if (p.isBoolean()) return p.getAsBoolean();
            if (p.isNumber()) {
                if ("int".equals(dt))   return p.getAsLong();
                if ("float".equals(dt)) return p.getAsDouble();
                double d = p.getAsDouble();
                if (d == Math.floor(d) && !Double.isInfinite(d)) return p.getAsLong();
                return d;
            }
            return p.getAsString();
        }
        return null;
    }
}

// ── CX emitter ─────────────────────────────────────────────────────────────────

class CxEmitter {

    private static final Pattern DATE_RE     = Pattern.compile("^\\d{4}-\\d{2}-\\d{2}$");
    private static final Pattern DATETIME_RE = Pattern.compile("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}");
    private static final Pattern HEX_RE      = Pattern.compile("^0[xX][0-9a-fA-F]+$");

    // ── quoting helpers ────────────────────────────────────────────────────────

    static boolean wouldAutotype(String s) {
        if (s.contains(" ")) return false;
        if (HEX_RE.matcher(s).matches()) return true;
        try { Long.parseLong(s); return true; } catch (NumberFormatException ignored) {}
        if (s.contains(".") || s.toLowerCase().contains("e")) {
            try { Double.parseDouble(s); return true; } catch (NumberFormatException ignored) {}
        }
        if (s.equals("true") || s.equals("false") || s.equals("null")) return true;
        if (DATETIME_RE.matcher(s).find()) return true;
        if (DATE_RE.matcher(s).matches())  return true;
        return false;
    }

    static String cxChooseQuote(String s) {
        if (!s.contains("'"))   return "'" + s + "'";
        if (!s.contains("\""))  return "\"" + s + "\"";
        if (!s.contains("'''")) return "'''" + s + "'''";
        return "\"" + s + "\"";  // best effort
    }

    static String cxQuoteText(String s) {
        boolean needs = s.startsWith(" ") || s.endsWith(" ")
                     || s.contains("  ") || s.contains("\n") || s.contains("\t")
                     || s.contains("[")  || s.contains("]")  || s.contains("&")
                     || s.startsWith(":") || s.startsWith("'") || s.startsWith("\"")
                     || wouldAutotype(s);
        return needs ? cxChooseQuote(s) : s;
    }

    static String cxQuoteAttr(String s) {
        if (s.isEmpty() || s.contains(" ") || s.contains("'") || s.contains("\""))
            return "'" + s + "'";
        return s;
    }

    // ── scalar formatting ──────────────────────────────────────────────────────

    static String emitScalarValue(ScalarNode s) {
        Object v = s.value;
        if (v == null)            return "null";
        if (v instanceof Boolean) return (Boolean) v ? "true" : "false";
        if (v instanceof Long   ) return v.toString();
        if (v instanceof Double d) {
            String f = String.valueOf(d);
            return (f.contains(".") || f.toLowerCase().contains("e")) ? f : f + ".0";
        }
        return v.toString();
    }

    // ── attribute formatting ───────────────────────────────────────────────────

    static String emitAttr(Attr a) {
        String dt = a.dataType;
        if ("int".equals(dt)) {
            return a.name + "=" + ((Number) a.value).longValue();
        }
        if ("float".equals(dt)) {
            double d = ((Number) a.value).doubleValue();
            String f = String.valueOf(d);
            String v = (f.contains(".") || f.toLowerCase().contains("e")) ? f : f + ".0";
            return a.name + "=" + v;
        }
        if ("bool".equals(dt)) {
            return a.name + "=" + ((Boolean) a.value ? "true" : "false");
        }
        if ("null".equals(dt)) {
            return a.name + "=null";
        }
        // string attr — quote if would autotype
        String s = a.value == null ? "null" : a.value.toString();
        String v = wouldAutotype(s) ? cxChooseQuote(s) : cxQuoteAttr(s);
        return a.name + "=" + v;
    }

    // ── inline emission ────────────────────────────────────────────────────────

    static String emitInline(Node node) {
        if (node instanceof TextNode t) {
            return t.value.isBlank() ? "" : cxQuoteText(t.value);
        }
        if (node instanceof ScalarNode s) {
            return emitScalarValue(s);
        }
        if (node instanceof EntityRefNode er) {
            return "&" + er.name + ";";
        }
        if (node instanceof RawTextNode rt) {
            return "[#" + rt.value + "#]";
        }
        if (node instanceof Element e) {
            return emitElement(e, 0).stripTrailing();
        }
        if (node instanceof BlockContentNode bc) {
            StringBuilder sb = new StringBuilder("[|");
            for (Node n : bc.items) {
                if (n instanceof TextNode t) {
                    sb.append(t.value);
                } else if (n instanceof Element e) {
                    sb.append(emitElement(e, 0).stripTrailing());
                }
            }
            sb.append("|]");
            return sb.toString();
        }
        return "";
    }

    // ── element emission ───────────────────────────────────────────────────────

    static String emitElement(Element e, int depth) {
        String ind = "  ".repeat(depth);
        boolean hasChildElems = e.items.stream().anyMatch(i -> i instanceof Element);
        boolean hasText       = e.items.stream().anyMatch(
            i -> i instanceof TextNode || i instanceof ScalarNode
              || i instanceof EntityRefNode || i instanceof RawTextNode);
        boolean isMultiline   = hasChildElems && !hasText;

        // Build meta string: &anchor *merge :dataType attr=val ...
        List<String> metaParts = new ArrayList<>();
        if (e.anchor   != null) metaParts.add("&" + e.anchor);
        if (e.merge    != null) metaParts.add("*" + e.merge);
        if (e.dataType != null) metaParts.add(":" + e.dataType);
        for (Attr a : e.attrs) metaParts.add(emitAttr(a));
        String meta = metaParts.isEmpty() ? "" : " " + String.join(" ", metaParts);

        if (isMultiline) {
            StringBuilder sb = new StringBuilder();
            sb.append(ind).append("[").append(e.name).append(meta).append("\n");
            for (Node item : e.items) {
                sb.append(emitNode(item, depth + 1));
            }
            sb.append(ind).append("]\n");
            return sb.toString();
        }

        if (e.items.isEmpty() && meta.isEmpty()) {
            return ind + "[" + e.name + "]\n";
        }

        List<String> bodyParts = new ArrayList<>();
        for (Node item : e.items) {
            String p = emitInline(item);
            if (!p.isEmpty()) bodyParts.add(p);
        }
        String body = String.join(" ", bodyParts);
        String sep  = body.isEmpty() ? "" : " ";
        return ind + "[" + e.name + meta + sep + body + "]\n";
    }

    // ── node emission ──────────────────────────────────────────────────────────

    static String emitNode(Node node, int depth) {
        String ind = "  ".repeat(depth);
        if (node instanceof Element e)        return emitElement(e, depth);
        if (node instanceof TextNode t)       return cxQuoteText(t.value);
        if (node instanceof ScalarNode s)     return emitScalarValue(s);
        if (node instanceof CommentNode c)    return ind + "[-" + c.value + "]\n";
        if (node instanceof RawTextNode rt)   return ind + "[#" + rt.value + "#]\n";
        if (node instanceof EntityRefNode er) return "&" + er.name + ";";
        if (node instanceof AliasNode al)     return ind + "[*" + al.name + "]\n";
        if (node instanceof BlockContentNode bc) {
            StringBuilder sb = new StringBuilder();
            sb.append(ind).append("[|");
            for (Node n : bc.items) sb.append(emitNode(n, 0));
            sb.append("|]\n");
            return sb.toString();
        }
        if (node instanceof PINode pi) {
            String data = pi.data != null ? " " + pi.data : "";
            return ind + "[?" + pi.target + data + "]\n";
        }
        if (node instanceof XMLDeclNode xd) {
            List<String> parts = new ArrayList<>();
            parts.add("version=" + xd.version);
            if (xd.encoding   != null) parts.add("encoding="   + xd.encoding);
            if (xd.standalone != null) parts.add("standalone=" + xd.standalone);
            return "[?xml " + String.join(" ", parts) + "]\n";
        }
        if (node instanceof CXDirectiveNode cd) {
            List<String> parts = new ArrayList<>();
            for (Attr a : cd.attrs)
                parts.add(a.name + "=" + cxQuoteAttr(a.value != null ? a.value.toString() : ""));
            return "[?cx " + String.join(" ", parts) + "]\n";
        }
        if (node instanceof DoctypeDeclNode dt) {
            return "[!DOCTYPE " + dt.name + "]\n";
        }
        return "";
    }

    // ── document emission ──────────────────────────────────────────────────────

    static String emitDoc(CXDocument doc) {
        StringBuilder sb = new StringBuilder();
        for (Node node : doc.prolog)    sb.append(emitNode(node, 0));
        if (doc.doctype != null)        sb.append(emitNode(doc.doctype, 0));
        for (Node node : doc.elements)  sb.append(emitNode(node, 0));
        // Strip trailing newline as in Python
        String s = sb.toString();
        while (s.endsWith("\n")) s = s.substring(0, s.length() - 1);
        return s;
    }
}
