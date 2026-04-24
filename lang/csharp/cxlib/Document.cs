using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace CX;

// ── Node types ────────────────────────────────────────────────────────────────

public abstract class Node { }

public sealed class TextNode(string value) : Node { public string Value { get; } = value; }
public sealed class ScalarNode(string dataType, object? value) : Node { public string DataType { get; } = dataType; public object? Value { get; } = value; }
public sealed class CommentNode(string value) : Node { public string Value { get; } = value; }
public sealed class RawTextNode(string value) : Node { public string Value { get; } = value; }
public sealed class EntityRefNode(string name) : Node { public string Name { get; } = name; }
public sealed class AliasNode(string name) : Node { public string Name { get; } = name; }
public sealed class PINode(string target, string? data = null) : Node { public string Target { get; } = target; public string? Data { get; } = data; }
public sealed class XMLDeclNode(string version = "1.0", string? encoding = null, string? standalone = null) : Node { public string Version { get; } = version; public string? Encoding { get; } = encoding; public string? Standalone { get; } = standalone; }
public sealed class CXDirectiveNode(List<Attr> attrs) : Node { public List<Attr> Attrs { get; } = attrs; }
public sealed class DoctypeDeclNode(string name, object? externalId = null, List<object>? intSubset = null) : Node { public string Name { get; } = name; public object? ExternalId { get; } = externalId; public List<object>? IntSubset { get; } = intSubset; }
public sealed class BlockContentNode(List<Node> items) : Node { public List<Node> Items { get; } = items; }

public record Attr(string Name, object? Value, string? DataType = null)
{
    public Attr WithValue(object? v, string? dt = null) => new(Name, v, dt);
}

public class Element : Node
{
    public string Name { get; set; }
    public string? Anchor { get; set; }
    public string? Merge { get; set; }
    public string? DataType { get; set; }
    public List<Attr> Attrs { get; set; } = new();
    public List<Node> Items { get; set; } = new();

    public Element(string name) { Name = name; }

    /// <summary>Attribute value by name, or null.</summary>
    public object? Attr(string name) => Attrs.FirstOrDefault(a => a.Name == name)?.Value;

    /// <summary>Concatenated Text and Scalar child content.</summary>
    public string Text()
    {
        var parts = new List<string>();
        foreach (var item in Items)
        {
            if (item is TextNode t) parts.Add(t.Value);
            else if (item is ScalarNode s) parts.Add(s.Value is null ? "null" : s.Value.ToString()!);
        }
        return string.Join(" ", parts);
    }

    /// <summary>Value of first Scalar child, or null.</summary>
    public object? Scalar()
    {
        foreach (var item in Items)
            if (item is ScalarNode s) return s.Value;
        return null;
    }

    /// <summary>All child Elements (excludes Text, Scalar, and other nodes).</summary>
    public IEnumerable<Element> Children() => Items.OfType<Element>();

    /// <summary>First child Element with this name.</summary>
    public Element? Get(string name) =>
        Items.OfType<Element>().FirstOrDefault(e => e.Name == name);

    /// <summary>All child Elements with this name.</summary>
    public IEnumerable<Element> GetAll(string name) =>
        Items.OfType<Element>().Where(e => e.Name == name);

    /// <summary>All descendant Elements with this name (depth-first).</summary>
    public IEnumerable<Element> FindAll(string name)
    {
        var result = new List<Element>();
        foreach (var item in Items.OfType<Element>())
        {
            if (item.Name == name) result.Add(item);
            result.AddRange(item.FindAll(name));
        }
        return result;
    }

    /// <summary>First descendant Element with this name (depth-first).</summary>
    public Element? FindFirst(string name)
    {
        foreach (var item in Items.OfType<Element>())
        {
            if (item.Name == name) return item;
            var found = item.FindFirst(name);
            if (found is not null) return found;
        }
        return null;
    }

    /// <summary>Navigate by slash-separated path: el.At("server/host").</summary>
    public Element? At(string path)
    {
        var parts = path.Split('/').Where(p => p.Length > 0).ToArray();
        Element? cur = this;
        foreach (var part in parts)
        {
            if (cur is null) return null;
            cur = cur.Get(part);
        }
        return cur;
    }

    /// <summary>Set an attribute value, updating if it already exists.</summary>
    public void SetAttr(string name, object? value, string? dataType = null)
    {
        for (int i = 0; i < Attrs.Count; i++)
        {
            if (Attrs[i].Name == name)
            {
                Attrs[i] = new Attr(name, value, dataType);
                return;
            }
        }
        Attrs.Add(new Attr(name, value, dataType));
    }

    /// <summary>Remove an attribute by name.</summary>
    public void RemoveAttr(string name) => Attrs.RemoveAll(a => a.Name == name);

    /// <summary>Append a child node.</summary>
    public void Append(Node node) => Items.Add(node);

    /// <summary>Prepend a child node.</summary>
    public void Prepend(Node node) => Items.Insert(0, node);

    /// <summary>Insert a child node at index.</summary>
    public void Insert(int index, Node node) => Items.Insert(index, node);

    /// <summary>Remove a child node by identity.</summary>
    public void Remove(Node node) => Items.Remove(node);

    /// <summary>Remove all direct child Elements with the given name.</summary>
    public void RemoveChild(string name) => Items.RemoveAll(i => i is Element e && e.Name == name);

    /// <summary>Remove child node at index (no-op if out of bounds).</summary>
    public void RemoveAt(int index)
    {
        if (index >= 0 && index < Items.Count) Items.RemoveAt(index);
    }

    /// <summary>First Element matching a CXPath expression.</summary>
    public Element? Select(string expr) => SelectAll(expr).FirstOrDefault();

    /// <summary>All Elements matching a CXPath expression (subtree of this element).</summary>
    public IEnumerable<Element> SelectAll(string expr)
    {
        var cx = CXPath.Parse(expr);
        var result = new List<Element>();
        CXPath.CollectStep(this, cx, 0, result);
        return result;
    }

    /// <summary>Emit this element as a CX string.</summary>
    public string ToCx() => CXEmitter.EmitElement(this, 0);
}

// ── Document ──────────────────────────────────────────────────────────────────

public class CXDocument
{
    public List<Node> Elements { get; set; } = new();
    public List<Node> Prolog { get; set; } = new();
    public DoctypeDeclNode? Doctype { get; set; }

    /// <summary>First top-level Element.</summary>
    public Element? Root() => Elements.OfType<Element>().FirstOrDefault();

    /// <summary>First top-level Element with this name.</summary>
    public Element? Get(string name) =>
        Elements.OfType<Element>().FirstOrDefault(e => e.Name == name);

    /// <summary>Navigate by slash-separated path from root: doc.At("article/body/p").</summary>
    public Element? At(string path)
    {
        var parts = path.Split('/').Where(p => p.Length > 0).ToArray();
        if (parts.Length == 0) return Root();
        var cur = Get(parts[0]);
        if (cur is null || parts.Length == 1) return cur;
        return cur.At(string.Join("/", parts[1..]));
    }

    /// <summary>All descendant Elements with this name (depth-first through entire document).</summary>
    public IEnumerable<Element> FindAll(string name)
    {
        var result = new List<Element>();
        foreach (var e in Elements.OfType<Element>())
        {
            if (e.Name == name) result.Add(e);
            result.AddRange(e.FindAll(name));
        }
        return result;
    }

    /// <summary>First descendant Element with this name (depth-first through entire document).</summary>
    public Element? FindFirst(string name)
    {
        foreach (var e in Elements.OfType<Element>())
        {
            if (e.Name == name) return e;
            var found = e.FindFirst(name);
            if (found is not null) return found;
        }
        return null;
    }

    /// <summary>First Element matching a CXPath expression.</summary>
    public Element? Select(string expr) => SelectAll(expr).FirstOrDefault();

    /// <summary>All Elements matching a CXPath expression.</summary>
    public IEnumerable<Element> SelectAll(string expr)
    {
        var cx = CXPath.Parse(expr);
        var vroot = new Element("#document") { Items = Elements.ToList() };
        var result = new List<Element>();
        CXPath.CollectStep(vroot, cx, 0, result);
        return result;
    }

    /// <summary>Return new document with element at path replaced by f(element).</summary>
    public CXDocument Transform(string path, Func<Element, Element> f)
    {
        var parts = path.Split('/').Where(p => p.Length > 0).ToArray();
        if (parts.Length == 0) return this;
        for (int i = 0; i < Elements.Count; i++)
        {
            if (Elements[i] is Element el && el.Name == parts[0])
            {
                if (parts.Length == 1)
                    return CXPath.DocReplaceAt(this, i, f(CXPath.ElemDetached(el)));
                var updated = CXPath.PathCopyElement(el, parts[1..], f);
                if (updated is not null)
                    return CXPath.DocReplaceAt(this, i, updated);
                return this;
            }
        }
        return this;
    }

    /// <summary>Return new document with all matching elements replaced by f(element).</summary>
    public CXDocument TransformAll(string expr, Func<Element, Element> f)
    {
        var cx = CXPath.Parse(expr);
        var newElements = Elements.Select(n => CXPath.RebuildNode(n, cx, f)).ToList();
        return new CXDocument { Elements = newElements, Prolog = Prolog, Doctype = Doctype };
    }

    /// <summary>Append a top-level node.</summary>
    public void Append(Node node) => Elements.Add(node);

    /// <summary>Prepend a top-level node.</summary>
    public void Prepend(Node node) => Elements.Insert(0, node);

    // ── Serialization ──────────────────────────────────────────────────────────

    public string ToCx() => CXEmitter.EmitDoc(this);
    public string ToXml() => CxLib.ToXml(ToCx());
    public string ToJson() => CxLib.ToJson(ToCx());
    public string ToYaml() => CxLib.ToYaml(ToCx());
    public string ToToml() => CxLib.ToToml(ToCx());
    public string ToMd() => CxLib.ToMd(ToCx());

    // ── Parse (CX and other formats) ───────────────────────────────────────────

    /// <summary>Parse a CX string into a CXDocument (uses binary wire protocol).</summary>
    public static CXDocument Parse(string cxStr)
    {
        var data = CxLib.AstBin(cxStr);
        return BinaryDecoder.DecodeAST(data);
    }

    /// <summary>Stream a CX string as a list of <see cref="StreamEvent"/> objects.</summary>
    public static List<StreamEvent> Stream(string cxStr)
    {
        var data = CxLib.EventsBin(cxStr);
        return BinaryDecoder.DecodeEvents(data);
    }

    /// <summary>Parse an XML string into a CXDocument.</summary>
    public static CXDocument ParseXml(string s)
    {
        string astJson = CxLib.XmlToAst(s);
        return DocFromJson(JsonDocument.Parse(astJson).RootElement);
    }

    /// <summary>Parse a JSON string into a CXDocument.</summary>
    public static CXDocument ParseJson(string s)
    {
        string astJson = CxLib.JsonToAst(s);
        return DocFromJson(JsonDocument.Parse(astJson).RootElement);
    }

    /// <summary>Parse a YAML string into a CXDocument.</summary>
    public static CXDocument ParseYaml(string s)
    {
        string astJson = CxLib.YamlToAst(s);
        return DocFromJson(JsonDocument.Parse(astJson).RootElement);
    }

    /// <summary>Parse a TOML string into a CXDocument.</summary>
    public static CXDocument ParseToml(string s)
    {
        string astJson = CxLib.TomlToAst(s);
        return DocFromJson(JsonDocument.Parse(astJson).RootElement);
    }

    /// <summary>Parse a Markdown string into a CXDocument.</summary>
    public static CXDocument ParseMd(string s)
    {
        string astJson = CxLib.MdToAst(s);
        return DocFromJson(JsonDocument.Parse(astJson).RootElement);
    }

    // ── Loads / Dumps ──────────────────────────────────────────────────────────

    /// <summary>Deserialize CX data string into native .NET types (Dictionary/List/scalar).</summary>
    public static object? Loads(string cxStr)
    {
        string jsonStr = CxLib.ToJson(cxStr);
        return JsonElementToObject(JsonDocument.Parse(jsonStr).RootElement);
    }

    /// <summary>Deserialize XML string into native .NET types.</summary>
    public static object? LoadsXml(string s)
    {
        string jsonStr = CxLib.XmlToJson(s);
        return JsonElementToObject(JsonDocument.Parse(jsonStr).RootElement);
    }

    /// <summary>Deserialize JSON string via the CX semantic bridge.</summary>
    public static object? LoadsJson(string s)
    {
        string jsonStr = CxLib.JsonToJson(s);
        return JsonElementToObject(JsonDocument.Parse(jsonStr).RootElement);
    }

    /// <summary>Deserialize YAML string into native .NET types.</summary>
    public static object? LoadsYaml(string s)
    {
        string jsonStr = CxLib.YamlToJson(s);
        return JsonElementToObject(JsonDocument.Parse(jsonStr).RootElement);
    }

    /// <summary>Deserialize TOML string into native .NET types.</summary>
    public static object? LoadsToml(string s)
    {
        string jsonStr = CxLib.TomlToJson(s);
        return JsonElementToObject(JsonDocument.Parse(jsonStr).RootElement);
    }

    /// <summary>Serialize native .NET types (Dictionary/List/scalar) to a CX string.</summary>
    public static string Dumps(object? data)
    {
        string jsonStr = JsonSerializer.Serialize(data);
        return CxLib.JsonToCx(jsonStr);
    }

    // ── JSON deserialization helpers ───────────────────────────────────────────

    private static CXDocument DocFromJson(JsonElement root)
    {
        var doc = new CXDocument();

        if (root.TryGetProperty("prolog", out var prologEl))
            foreach (var n in prologEl.EnumerateArray())
                doc.Prolog.Add(NodeFromJson(n));

        if (root.TryGetProperty("doctype", out var dtEl))
            doc.Doctype = DoctypeFromJson(dtEl);

        if (root.TryGetProperty("elements", out var elemsEl))
            foreach (var n in elemsEl.EnumerateArray())
                doc.Elements.Add(NodeFromJson(n));

        return doc;
    }

    private static DoctypeDeclNode DoctypeFromJson(JsonElement e)
    {
        string name = e.TryGetProperty("name", out var np) ? np.GetString()! : "";
        object? extId = e.TryGetProperty("externalID", out var ext) ? JsonElementToObject(ext) : null;
        return new DoctypeDeclNode(name, extId);
    }

    private static Node NodeFromJson(JsonElement e)
    {
        string type = e.TryGetProperty("type", out var tp) ? (tp.GetString() ?? "") : "";
        return type switch
        {
            "Element" => ElementFromJson(e),
            "Text" => new TextNode(e.GetProperty("value").GetString()!),
            "Scalar" => new ScalarNode(
                e.GetProperty("dataType").GetString()!,
                JsonElementToObject(e.GetProperty("value"))
            ),
            "Comment" => new CommentNode(e.GetProperty("value").GetString()!),
            "RawText" => new RawTextNode(e.GetProperty("value").GetString()!),
            "EntityRef" => new EntityRefNode(e.GetProperty("name").GetString()!),
            "Alias" => new AliasNode(e.GetProperty("name").GetString()!),
            "PI" => new PINode(
                e.GetProperty("target").GetString()!,
                e.TryGetProperty("data", out var pd) ? pd.GetString() : null
            ),
            "XMLDecl" => new XMLDeclNode(
                e.TryGetProperty("version", out var ver) ? (ver.GetString() ?? "1.0") : "1.0",
                e.TryGetProperty("encoding", out var enc) ? enc.GetString() : null,
                e.TryGetProperty("standalone", out var sa) ? sa.GetString() : null
            ),
            "CXDirective" => new CXDirectiveNode(
                e.TryGetProperty("attrs", out var catts)
                    ? catts.EnumerateArray().Select(AttrFromJson).ToList()
                    : new List<Attr>()
            ),
            "DoctypeDecl" => new DoctypeDeclNode(
                e.TryGetProperty("name", out var dtn) ? (dtn.GetString() ?? "") : "",
                e.TryGetProperty("externalID", out var dtext) ? JsonElementToObject(dtext) : null
            ),
            "BlockContent" => new BlockContentNode(
                e.TryGetProperty("items", out var bitems)
                    ? bitems.EnumerateArray().Select(NodeFromJson).ToList()
                    : new List<Node>()
            ),
            _ => new TextNode(e.ToString())
        };
    }

    private static Element ElementFromJson(JsonElement e)
    {
        var el = new Element(e.GetProperty("name").GetString()!)
        {
            Anchor = e.TryGetProperty("anchor", out var anc) ? anc.GetString() : null,
            Merge = e.TryGetProperty("merge", out var mrg) ? mrg.GetString() : null,
            DataType = e.TryGetProperty("dataType", out var dt) ? dt.GetString() : null,
        };

        if (e.TryGetProperty("attrs", out var attrs))
            el.Attrs = attrs.EnumerateArray().Select(AttrFromJson).ToList();

        if (e.TryGetProperty("items", out var items))
            el.Items = items.EnumerateArray().Select(NodeFromJson).ToList();

        return el;
    }

    private static Attr AttrFromJson(JsonElement e)
    {
        string name = e.GetProperty("name").GetString()!;
        object? value = JsonElementToObject(e.GetProperty("value"));
        string? dataType = e.TryGetProperty("dataType", out var dt) ? dt.GetString() : null;
        return new Attr(name, value, dataType);
    }

    internal static object? JsonElementToObject(JsonElement e) => e.ValueKind switch
    {
        JsonValueKind.Null => null,
        JsonValueKind.True => (object?)true,
        JsonValueKind.False => false,
        JsonValueKind.Number =>
            e.TryGetInt64(out long l) ? (object?)l :
            e.TryGetDouble(out double d) ? d : (object?)e.GetDecimal(),
        JsonValueKind.String => e.GetString(),
        JsonValueKind.Array =>
            e.EnumerateArray().Select(JsonElementToObject).ToList(),
        JsonValueKind.Object =>
            e.EnumerateObject().ToDictionary(p => p.Name, p => JsonElementToObject(p.Value)),
        _ => e.ToString()
    };
}

// ── CX Emitter ────────────────────────────────────────────────────────────────

internal static class CXEmitter
{
    private static readonly Regex DateRe = new(@"^\d{4}-\d{2}-\d{2}$", RegexOptions.Compiled);
    private static readonly Regex DateTimeRe = new(@"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}", RegexOptions.Compiled);
    private static readonly Regex HexRe = new(@"^0[xX][0-9a-fA-F]+$", RegexOptions.Compiled);

    private static bool WouldAutotype(string s)
    {
        if (s.Contains(' ')) return false;
        if (HexRe.IsMatch(s)) return true;
        if (long.TryParse(s, out _)) return true;
        if (s.Contains('.') || s.ToLower().Contains('e'))
            if (double.TryParse(s, System.Globalization.NumberStyles.Float,
                System.Globalization.CultureInfo.InvariantCulture, out _)) return true;
        if (s == "true" || s == "false" || s == "null") return true;
        if (DateTimeRe.IsMatch(s)) return true;
        if (DateRe.IsMatch(s)) return true;
        return false;
    }

    private static string ChooseQuote(string s)
    {
        if (!s.Contains('\'')) return $"'{s}'";
        if (!s.Contains('"')) return $"\"{s}\"";
        if (!s.Contains("'''")) return $"'''{s}'''";
        return $"\"{s}\"";
    }

    private static string QuoteText(string s)
    {
        bool needs = s.StartsWith(' ') || s.EndsWith(' ')
            || s.Contains("  ") || s.Contains('\n') || s.Contains('\t')
            || s.Contains('[') || s.Contains(']') || s.Contains('&')
            || s.StartsWith(':') || s.StartsWith('\'') || s.StartsWith('"')
            || WouldAutotype(s);
        return needs ? ChooseQuote(s) : s;
    }

    private static string QuoteAttr(string s)
    {
        if (s.Length == 0 || s.Contains(' ') || s.Contains('\'') || s.Contains('"'))
            return $"'{s}'";
        return s;
    }

    private static string EmitScalar(ScalarNode s)
    {
        if (s.Value is null) return "null";
        if (s.Value is bool b) return b ? "true" : "false";
        if (s.Value is long li) return li.ToString();
        if (s.Value is int i) return i.ToString();
        if (s.Value is double d)
        {
            string f = d.ToString("G", System.Globalization.CultureInfo.InvariantCulture);
            return (f.Contains('.') || f.ToLower().Contains('e')) ? f : f + ".0";
        }
        if (s.Value is float fl)
        {
            string f = fl.ToString("G", System.Globalization.CultureInfo.InvariantCulture);
            return (f.Contains('.') || f.ToLower().Contains('e')) ? f : f + ".0";
        }
        return s.Value.ToString()!;
    }

    private static string EmitAttr(Attr a)
    {
        string dt = a.DataType ?? "";
        if (dt == "int") return $"{a.Name}={Convert.ToInt64(a.Value)}";
        if (dt == "float")
        {
            double d = Convert.ToDouble(a.Value);
            string f = d.ToString("G", System.Globalization.CultureInfo.InvariantCulture);
            string v = (f.Contains('.') || f.ToLower().Contains('e')) ? f : f + ".0";
            return $"{a.Name}={v}";
        }
        if (dt == "bool") return $"{a.Name}={(Convert.ToBoolean(a.Value) ? "true" : "false")}";
        if (dt == "null") return $"{a.Name}=null";
        // string attr — quote if would autotype
        string sv = a.Value?.ToString() ?? "";
        string qv = WouldAutotype(sv) ? ChooseQuote(sv) : QuoteAttr(sv);
        return $"{a.Name}={qv}";
    }

    private static string EmitInline(Node node)
    {
        if (node is TextNode t) return t.Value.Trim().Length == 0 ? "" : QuoteText(t.Value);
        if (node is ScalarNode s) return EmitScalar(s);
        if (node is EntityRefNode er) return $"&{er.Name};";
        if (node is RawTextNode rt) return $"[#{rt.Value}#]";
        if (node is Element el) return EmitElement(el, 0).TrimEnd('\n');
        if (node is BlockContentNode bc)
        {
            var inner = new StringBuilder();
            foreach (var n in bc.Items)
            {
                if (n is TextNode tn) inner.Append(tn.Value);
                else if (n is Element be) inner.Append(EmitElement(be, 0).TrimEnd('\n'));
            }
            return $"[|{inner}|]";
        }
        return "";
    }

    public static string EmitElement(Element e, int depth)
    {
        string ind = new string(' ', depth * 2);
        bool hasChildElems = e.Items.Any(i => i is Element);
        bool hasText = e.Items.Any(i => i is TextNode or ScalarNode or EntityRefNode or RawTextNode);
        bool isMultiline = hasChildElems && !hasText;

        var metaParts = new List<string>();
        if (e.Anchor is not null) metaParts.Add($"&{e.Anchor}");
        if (e.Merge is not null) metaParts.Add($"*{e.Merge}");
        if (e.DataType is not null) metaParts.Add($":{e.DataType}");
        foreach (var a in e.Attrs) metaParts.Add(EmitAttr(a));
        string meta = metaParts.Count > 0 ? " " + string.Join(" ", metaParts) : "";

        if (isMultiline)
        {
            var sb = new StringBuilder();
            sb.Append($"{ind}[{e.Name}{meta}\n");
            foreach (var item in e.Items)
                sb.Append(EmitNode(item, depth + 1));
            sb.Append($"{ind}]\n");
            return sb.ToString();
        }

        if (e.Items.Count == 0 && meta.Length == 0)
            return $"{ind}[{e.Name}]\n";

        var bodyParts = e.Items.Select(EmitInline).Where(p => p.Length > 0).ToList();
        string body = string.Join(" ", bodyParts);
        string sep = body.Length > 0 ? " " : "";
        return $"{ind}[{e.Name}{meta}{sep}{body}]\n";
    }

    private static string EmitNode(Node node, int depth)
    {
        string ind = new string(' ', depth * 2);
        if (node is Element el) return EmitElement(el, depth);
        if (node is TextNode t) return QuoteText(t.Value);
        if (node is ScalarNode s) return EmitScalar(s);
        if (node is CommentNode c) return $"{ind}[-{c.Value}]\n";
        if (node is RawTextNode rt) return $"{ind}[#{rt.Value}#]\n";
        if (node is EntityRefNode er) return $"&{er.Name};";
        if (node is AliasNode al) return $"{ind}[*{al.Name}]\n";
        if (node is BlockContentNode bc)
        {
            var inner = new StringBuilder();
            foreach (var n in bc.Items) inner.Append(EmitNode(n, 0));
            return $"{ind}[|{inner}|]\n";
        }
        if (node is PINode pi)
        {
            string data = pi.Data is not null ? $" {pi.Data}" : "";
            return $"{ind}[?{pi.Target}{data}]\n";
        }
        if (node is XMLDeclNode xd)
        {
            var parts = new List<string> { $"version={xd.Version}" };
            if (xd.Encoding is not null) parts.Add($"encoding={xd.Encoding}");
            if (xd.Standalone is not null) parts.Add($"standalone={xd.Standalone}");
            return $"[?xml {string.Join(" ", parts)}]\n";
        }
        if (node is CXDirectiveNode cxd)
        {
            string attrs = string.Join(" ", cxd.Attrs.Select(a => $"{a.Name}={QuoteAttr(a.Value?.ToString() ?? "")}"));
            return $"[?cx {attrs}]\n";
        }
        if (node is DoctypeDeclNode dt)
        {
            string ext = "";
            if (dt.ExternalId is Dictionary<string, object?> extDict)
            {
                if (extDict.TryGetValue("public", out var pub) && pub is not null)
                {
                    string sys = extDict.TryGetValue("system", out var s2) && s2 is not null ? s2.ToString()! : "";
                    ext = $" PUBLIC '{pub}' '{sys}'";
                }
                else if (extDict.TryGetValue("system", out var sys2) && sys2 is not null)
                    ext = $" SYSTEM '{sys2}'";
            }
            return $"[!DOCTYPE {dt.Name}{ext}]\n";
        }
        return "";
    }

    public static string EmitDoc(CXDocument doc)
    {
        var sb = new StringBuilder();
        foreach (var node in doc.Prolog) sb.Append(EmitNode(node, 0));
        if (doc.Doctype is not null) sb.Append(EmitNode(doc.Doctype, 0));
        foreach (var node in doc.Elements) sb.Append(EmitNode(node, 0));
        string result = sb.ToString().TrimEnd('\n');
        return result;
    }
}
