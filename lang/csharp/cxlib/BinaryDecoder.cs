using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

namespace CX;

/// <summary>
/// Decoder for the compact binary wire format produced by cx_to_ast_bin and
/// cx_to_events_bin.  All integers are little-endian.
/// </summary>
public static class BinaryDecoder
{
    // ── public entry points ───────────────────────────────────────────────────

    /// <summary>Decode a binary AST payload (the bytes AFTER the 4-byte length prefix)
    /// into a <see cref="CXDocument"/>.</summary>
    public static CXDocument DecodeAST(byte[] data)
    {
        var r = new BufReader(data);
        r.U8(); // version byte — currently 1, reserved for future use

        int prologCount = r.U16();
        var prolog = new List<Node>(prologCount);
        for (int i = 0; i < prologCount; i++)
            prolog.Add(ReadNode(r));

        int elemCount = r.U16();
        var elements = new List<Node>(elemCount);
        for (int i = 0; i < elemCount; i++)
            elements.Add(ReadNode(r));

        return new CXDocument { Prolog = prolog, Elements = elements };
    }

    /// <summary>Decode a binary events payload (the bytes AFTER the 4-byte length prefix)
    /// into a list of <see cref="StreamEvent"/>.</summary>
    public static List<StreamEvent> DecodeEvents(byte[] data)
    {
        var r = new BufReader(data);
        uint count = r.U32();
        var events = new List<StreamEvent>((int)count);

        for (uint i = 0; i < count; i++)
        {
            byte tid = r.U8();
            var ev = new StreamEvent { Type = EventTypeName(tid) };

            switch (tid)
            {
                case 0x01: // StartDoc — no payload
                case 0x02: // EndDoc  — no payload
                    break;

                case 0x03: // StartElement
                    ev.Name     = r.Str();
                    ev.Anchor   = r.OptStr();
                    ev.DataType = r.OptStr();
                    ev.Merge    = r.OptStr();
                    ev.Attrs    = ReadAttrs(r, r.U16());
                    break;

                case 0x04: // EndElement
                    ev.Name = r.Str();
                    break;

                case 0x05: // Text
                case 0x07: // Comment
                case 0x0A: // RawText
                    ev.Value = r.Str();
                    break;

                case 0x06: // Scalar
                {
                    string dt = r.Str();
                    ev.DataType = dt;
                    ev.Value = Coerce(dt, r.Str());
                    break;
                }

                case 0x08: // PI
                    ev.Target = r.Str();
                    ev.Data   = r.OptStr();
                    break;

                case 0x09: // EntityRef
                case 0x0B: // Alias
                    ev.Value = r.Str();
                    break;
            }

            events.Add(ev);
        }

        return events;
    }

    // ── AST node reader ───────────────────────────────────────────────────────

    private static Node ReadNode(BufReader r)
    {
        byte tid = r.U8();

        switch (tid)
        {
            case 0x01: // Element
            {
                string name   = r.Str();
                string? anchor = r.OptStr();
                string? dt    = r.OptStr();
                string? merge = r.OptStr();
                var attrs     = ReadAttrs(r, r.U16());
                int childCount = r.U16();
                var items = new List<Node>(childCount);
                for (int i = 0; i < childCount; i++)
                    items.Add(ReadNode(r));
                return new Element(name)
                {
                    Anchor   = anchor,
                    DataType = dt,
                    Merge    = merge,
                    Attrs    = attrs,
                    Items    = items,
                };
            }

            case 0x02: // Text
                return new TextNode(r.Str());

            case 0x03: // Scalar
            {
                string dt = r.Str();
                return new ScalarNode(dt, Coerce(dt, r.Str()));
            }

            case 0x04: // Comment
                return new CommentNode(r.Str());

            case 0x05: // RawText
                return new RawTextNode(r.Str());

            case 0x06: // EntityRef
                return new EntityRefNode(r.Str());

            case 0x07: // Alias
                return new AliasNode(r.Str());

            case 0x08: // PI
            {
                string target = r.Str();
                string? data  = r.OptStr();
                return new PINode(target, data);
            }

            case 0x09: // XMLDecl
            {
                string ver       = r.Str();
                string? encoding = r.OptStr();
                string? sa       = r.OptStr();
                return new XMLDeclNode(ver, encoding, sa);
            }

            case 0x0A: // CXDirective
                return new CXDirectiveNode(ReadAttrs(r, r.U16()));

            case 0x0C: // BlockContent
            {
                int childCount = r.U16();
                var items = new List<Node>(childCount);
                for (int i = 0; i < childCount; i++)
                    items.Add(ReadNode(r));
                return new BlockContentNode(items);
            }

            case 0xFF: // skip / DTD placeholder — no payload
                return new TextNode("");

            default:
                // Unknown type: we cannot safely skip without knowing payload size.
                // Return an empty text node as a best-effort fallback.
                return new TextNode("");
        }
    }

    // ── helpers ───────────────────────────────────────────────────────────────

    private static List<Attr> ReadAttrs(BufReader r, int count)
    {
        var attrs = new List<Attr>(count);
        for (int i = 0; i < count; i++)
        {
            string name     = r.Str();
            string valueStr = r.Str();
            string typeStr  = r.Str();
            string? dt = typeStr == "string" ? null : typeStr;
            attrs.Add(new Attr(name, Coerce(typeStr, valueStr), dt));
        }
        return attrs;
    }

    private static object? Coerce(string typeStr, string valueStr) => typeStr switch
    {
        "int"   => (object?)long.Parse(valueStr,
                        System.Globalization.NumberStyles.Integer,
                        System.Globalization.CultureInfo.InvariantCulture),
        "float" => double.Parse(valueStr,
                        System.Globalization.NumberStyles.Float,
                        System.Globalization.CultureInfo.InvariantCulture),
        "bool"  => valueStr == "true",
        "null"  => null,
        _       => valueStr,
    };

    private static string EventTypeName(byte tid) => tid switch
    {
        0x01 => "StartDoc",
        0x02 => "EndDoc",
        0x03 => "StartElement",
        0x04 => "EndElement",
        0x05 => "Text",
        0x06 => "Scalar",
        0x07 => "Comment",
        0x08 => "PI",
        0x09 => "EntityRef",
        0x0A => "RawText",
        0x0B => "Alias",
        _    => "Unknown",
    };

    // ── BufReader ─────────────────────────────────────────────────────────────

    /// <summary>Cursor-based little-endian reader over a byte array.</summary>
    private sealed class BufReader
    {
        private readonly byte[] _data;
        private int _pos;

        public BufReader(byte[] data) { _data = data; _pos = 0; }

        public byte U8() => _data[_pos++];

        public ushort U16()
        {
            // Use explicit LE decoding to be safe on all platforms.
            ushort v = (ushort)(_data[_pos] | (_data[_pos + 1] << 8));
            _pos += 2;
            return v;
        }

        public uint U32()
        {
            uint v = (uint)(_data[_pos]
                | (_data[_pos + 1] << 8)
                | (_data[_pos + 2] << 16)
                | (_data[_pos + 3] << 24));
            _pos += 4;
            return v;
        }

        public string Str()
        {
            int len = (int)U32();
            string s = Encoding.UTF8.GetString(_data, _pos, len);
            _pos += len;
            return s;
        }

        public string? OptStr()
        {
            byte flag = U8();
            if (flag == 0) return null;
            return Str();
        }
    }
}
