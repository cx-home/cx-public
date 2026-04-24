using System;
using System.Collections.Generic;
using System.Linq;

namespace CX;

// ── CXPath predicate types ────────────────────────────────────────────────────

public abstract class CXPred { }
public sealed class CXPredAttrExists(string attr) : CXPred { public string Attr { get; } = attr; }
public sealed class CXPredAttrCmp(string attr, string op, object? val) : CXPred
{
    public string Attr { get; } = attr;
    public string Op { get; } = op;
    public object? Val { get; } = val;
}
public sealed class CXPredChildExists(string name) : CXPred { public string Name { get; } = name; }
public sealed class CXPredNot(CXPred inner) : CXPred { public CXPred Inner { get; } = inner; }
public sealed class CXPredBoolAnd(CXPred left, CXPred right) : CXPred
{
    public CXPred Left { get; } = left;
    public CXPred Right { get; } = right;
}
public sealed class CXPredBoolOr(CXPred left, CXPred right) : CXPred
{
    public CXPred Left { get; } = left;
    public CXPred Right { get; } = right;
}
public sealed class CXPredPosition(int pos, bool isLast) : CXPred
{
    public int Pos { get; } = pos;
    public bool IsLast { get; } = isLast;
}
public sealed class CXPredFuncContains(string attr, string val) : CXPred
{
    public string Attr { get; } = attr;
    public string Val { get; } = val;
}
public sealed class CXPredFuncStartsWith(string attr, string val) : CXPred
{
    public string Attr { get; } = attr;
    public string Val { get; } = val;
}

public enum CXAxis { Child, Descendant }

public class CXStep(CXAxis axis, string name, List<CXPred> preds)
{
    public CXAxis Axis { get; } = axis;
    public string Name { get; } = name;  // "" = wildcard
    public List<CXPred> Preds { get; } = preds;
}

public class CXPathExpr(List<CXStep> steps)
{
    public List<CXStep> Steps { get; } = steps;
}

// ── Lexer ─────────────────────────────────────────────────────────────────────

sealed class Lexer(string src)
{
    public string Src { get; } = src;
    public int Pos { get; set; } = 0;

    public void SkipWs()
    {
        while (Pos < Src.Length && Src[Pos] == ' ')
            Pos++;
    }

    public bool PeekStr(string s) => Src.AsSpan(Pos).StartsWith(s.AsSpan());

    public bool EatStr(string s)
    {
        if (PeekStr(s)) { Pos += s.Length; return true; }
        return false;
    }

    public bool EatChar(char c)
    {
        if (Pos < Src.Length && Src[Pos] == c) { Pos++; return true; }
        return false;
    }

    public string ReadIdent()
    {
        int start = Pos;
        while (Pos < Src.Length)
        {
            char c = Src[Pos];
            if (char.IsLetterOrDigit(c) || c == '_' || c == '-' || c == '.' || c == ':' || c == '%')
                Pos++;
            else
                break;
        }
        return Src[start..Pos];
    }

    public string ReadQuoted()
    {
        if (!EatChar('\''))
            throw new ArgumentException($"CXPath parse error: expected ' at pos {Pos}  expr: {Src}");
        int start = Pos;
        while (Pos < Src.Length && Src[Pos] != '\'')
            Pos++;
        string s = Src[start..Pos];
        if (!EatChar('\''))
            throw new ArgumentException($"CXPath parse error: unterminated string at pos {Pos}  expr: {Src}");
        return s;
    }
}

// ── Parser ────────────────────────────────────────────────────────────────────

public static class CXPath
{
    public static CXPathExpr Parse(string expr)
    {
        var l = new Lexer(expr);
        var steps = ParseSteps(l);
        if (l.Pos != l.Src.Length)
            throw new ArgumentException($"CXPath parse error: unexpected characters at pos {l.Pos}  expr: {expr}");
        if (steps.Count == 0)
            throw new ArgumentException($"CXPath parse error: empty expression  expr: {expr}");
        return new CXPathExpr(steps);
    }

    static List<CXStep> ParseSteps(Lexer l)
    {
        var steps = new List<CXStep>();
        CXAxis axis = CXAxis.Child;
        if (l.PeekStr("//"))
        {
            l.Pos += 2;
            axis = CXAxis.Descendant;
        }
        else if (l.PeekStr("/"))
        {
            l.Pos += 1;
            axis = CXAxis.Child;
        }
        steps.Add(ParseOneStep(l, axis));
        while (true)
        {
            l.SkipWs();
            if (l.PeekStr("//"))
            {
                l.Pos += 2;
                steps.Add(ParseOneStep(l, CXAxis.Descendant));
            }
            else if (l.PeekStr("/"))
            {
                l.Pos += 1;
                steps.Add(ParseOneStep(l, CXAxis.Child));
            }
            else
                break;
        }
        return steps;
    }

    static CXStep ParseOneStep(Lexer l, CXAxis axis)
    {
        l.SkipWs();
        string name;
        if (l.EatChar('*'))
            name = "";
        else
        {
            name = l.ReadIdent();
            if (name.Length == 0)
                throw new ArgumentException($"CXPath parse error: expected element name at pos {l.Pos}  expr: {l.Src}");
        }
        var preds = new List<CXPred>();
        while (true)
        {
            l.SkipWs();
            if (l.PeekStr("["))
                preds.Add(ParsePredBracket(l));
            else
                break;
        }
        return new CXStep(axis, name, preds);
    }

    static CXPred ParsePredBracket(Lexer l)
    {
        if (!l.EatChar('['))
            throw new ArgumentException($"CXPath parse error: expected [ at pos {l.Pos}  expr: {l.Src}");
        l.SkipWs();
        var pred = ParsePredExpr(l);
        l.SkipWs();
        if (!l.EatChar(']'))
            throw new ArgumentException($"CXPath parse error: expected ] at pos {l.Pos}  expr: {l.Src}");
        return pred;
    }

    static CXPred ParsePredExpr(Lexer l)
    {
        var left = ParsePredTerm(l);
        l.SkipWs();
        int saved = l.Pos;
        string word = l.ReadIdent();
        if (word == "or")
        {
            l.SkipWs();
            var right = ParsePredTerm(l);
            return new CXPredBoolOr(left, right);
        }
        l.Pos = saved;
        return left;
    }

    static CXPred ParsePredTerm(Lexer l)
    {
        var left = ParsePredFactor(l);
        l.SkipWs();
        int saved = l.Pos;
        string word = l.ReadIdent();
        if (word == "and")
        {
            l.SkipWs();
            var right = ParsePredFactor(l);
            return new CXPredBoolAnd(left, right);
        }
        l.Pos = saved;
        return left;
    }

    static CXPred ParsePredFactor(Lexer l)
    {
        l.SkipWs();

        // not(...)
        if (l.PeekStr("not(") || l.PeekStr("not ("))
        {
            l.ReadIdent();  // consume 'not'
            l.SkipWs();
            if (!l.EatChar('('))
                throw new ArgumentException($"CXPath parse error: expected ( after not  expr: {l.Src}");
            l.SkipWs();
            var inner = ParsePredExpr(l);
            l.SkipWs();
            if (!l.EatChar(')'))
                throw new ArgumentException($"CXPath parse error: expected ) after not(...)  expr: {l.Src}");
            return new CXPredNot(inner);
        }

        // contains(@attr, val)
        if (l.PeekStr("contains("))
        {
            l.ReadIdent();  // consume 'contains'
            l.SkipWs();
            if (!l.EatChar('('))
                throw new ArgumentException($"CXPath parse error: expected ( after contains  expr: {l.Src}");
            l.SkipWs();
            if (!l.EatChar('@'))
                throw new ArgumentException($"CXPath parse error: expected @attr in contains()  expr: {l.Src}");
            string attr = l.ReadIdent();
            l.SkipWs();
            if (!l.EatChar(','))
                throw new ArgumentException($"CXPath parse error: expected , in contains()  expr: {l.Src}");
            l.SkipWs();
            string val = ParseScalarStr(l);
            l.SkipWs();
            if (!l.EatChar(')'))
                throw new ArgumentException($"CXPath parse error: expected ) after contains(...)  expr: {l.Src}");
            return new CXPredFuncContains(attr, val);
        }

        // starts-with(@attr, val)
        if (l.PeekStr("starts-with("))
        {
            while (l.Pos < l.Src.Length && l.Src[l.Pos] != '(')
                l.Pos++;
            if (!l.EatChar('('))
                throw new ArgumentException($"CXPath parse error: expected ( after starts-with  expr: {l.Src}");
            l.SkipWs();
            if (!l.EatChar('@'))
                throw new ArgumentException($"CXPath parse error: expected @attr in starts-with()  expr: {l.Src}");
            string attr = l.ReadIdent();
            l.SkipWs();
            if (!l.EatChar(','))
                throw new ArgumentException($"CXPath parse error: expected , in starts-with()  expr: {l.Src}");
            l.SkipWs();
            string val = ParseScalarStr(l);
            l.SkipWs();
            if (!l.EatChar(')'))
                throw new ArgumentException($"CXPath parse error: expected ) after starts-with(...)  expr: {l.Src}");
            return new CXPredFuncStartsWith(attr, val);
        }

        // last()
        if (l.PeekStr("last()"))
        {
            l.Pos += 6;
            return new CXPredPosition(0, true);
        }

        // (grouped expr)
        if (l.PeekStr("("))
        {
            l.EatChar('(');
            l.SkipWs();
            var inner = ParsePredExpr(l);
            l.SkipWs();
            if (!l.EatChar(')'))
                throw new ArgumentException($"CXPath parse error: expected ) at pos {l.Pos}  expr: {l.Src}");
            return inner;
        }

        // @attr comparison or existence
        if (l.Pos < l.Src.Length && l.Src[l.Pos] == '@')
        {
            l.EatChar('@');
            string attr = l.ReadIdent();
            l.SkipWs();
            string op = ParseOp(l);
            if (op.Length == 0)
                return new CXPredAttrExists(attr);
            l.SkipWs();
            object? val = ParseScalarVal(l);
            return new CXPredAttrCmp(attr, op, val);
        }

        // integer position predicate
        if (l.Pos < l.Src.Length && char.IsDigit(l.Src[l.Pos]))
        {
            int start = l.Pos;
            while (l.Pos < l.Src.Length && char.IsDigit(l.Src[l.Pos]))
                l.Pos++;
            return new CXPredPosition(int.Parse(l.Src[start..l.Pos]), false);
        }

        // bare name → child existence
        string name = l.ReadIdent();
        if (name.Length > 0)
            return new CXPredChildExists(name);

        throw new ArgumentException($"CXPath parse error: unexpected character at pos {l.Pos}  expr: {l.Src}");
    }

    static string ParseOp(Lexer l)
    {
        foreach (string op in new[] { "!=", ">=", "<=", "=", ">", "<" })
            if (l.EatStr(op)) return op;
        return "";
    }

    static object? AutotypeValue(string s)
    {
        if (s == "true")  return true;
        if (s == "false") return false;
        if (s == "null")  return null;
        if (long.TryParse(s, out long l)) return l;
        if (double.TryParse(s, System.Globalization.NumberStyles.Float,
            System.Globalization.CultureInfo.InvariantCulture, out double d)) return d;
        return s;
    }

    static object? ParseScalarVal(Lexer l)
    {
        if (l.PeekStr("'"))
            return l.ReadQuoted();
        string s = l.ReadIdent();
        if (s.Length == 0)
            throw new ArgumentException($"CXPath parse error: expected value at pos {l.Pos}  expr: {l.Src}");
        return AutotypeValue(s);
    }

    static string ParseScalarStr(Lexer l)
    {
        if (l.PeekStr("'"))
            return l.ReadQuoted();
        return l.ReadIdent();
    }

    // ── Evaluator ─────────────────────────────────────────────────────────────

    public static void CollectStep(Element ctx, CXPathExpr expr, int stepIdx, List<Element> result)
    {
        if (stepIdx >= expr.Steps.Count) return;
        var step = expr.Steps[stepIdx];
        if (step.Axis == CXAxis.Child)
        {
            var candidates = ctx.Items
                .OfType<Element>()
                .Where(e => step.Name == "" || e.Name == step.Name)
                .ToList();
            for (int i = 0; i < candidates.Count; i++)
            {
                var child = candidates[i];
                if (PredsMatch(child, step.Preds, candidates, i))
                {
                    if (stepIdx == expr.Steps.Count - 1)
                        result.Add(child);
                    else
                        CollectStep(child, expr, stepIdx + 1, result);
                }
            }
        }
        else
        {
            CollectDescendants(ctx, expr, stepIdx, result);
        }
    }

    static void CollectDescendants(Element ctx, CXPathExpr expr, int stepIdx, List<Element> result)
    {
        var step = expr.Steps[stepIdx];
        bool isLast = stepIdx == expr.Steps.Count - 1;
        var candidates = ctx.Items
            .OfType<Element>()
            .Where(e => step.Name == "" || e.Name == step.Name)
            .ToList();
        for (int i = 0; i < candidates.Count; i++)
        {
            var child = candidates[i];
            if (PredsMatch(child, step.Preds, candidates, i))
            {
                if (isLast)
                    result.Add(child);
                else
                    CollectStep(child, expr, stepIdx + 1, result);
            }
            // Always recurse deeper for descendant axis
            CollectDescendants(child, expr, stepIdx, result);
        }
        // Also descend into non-matching children for named steps
        if (step.Name.Length > 0)
        {
            foreach (var child in ctx.Items.OfType<Element>())
            {
                if (child.Name != step.Name)
                    CollectDescendants(child, expr, stepIdx, result);
            }
        }
    }

    // ── Predicate evaluators ──────────────────────────────────────────────────

    static bool PredsMatch(Element el, List<CXPred> preds, List<Element> siblings, int idx)
        => preds.All(p => PredEval(el, p, siblings, idx));

    static bool PredEval(Element el, CXPred pred, List<Element> siblings, int idx)
    {
        switch (pred)
        {
            case CXPredAttrExists p:
                return el.Attr(p.Attr) is not null;

            case CXPredAttrCmp p:
                var v = el.Attr(p.Attr);
                if (v is null) return false;
                return Compare(v, p.Op, p.Val);

            case CXPredChildExists p:
                return el.Get(p.Name) is not null;

            case CXPredNot p:
                return !PredEval(el, p.Inner, siblings, idx);

            case CXPredBoolAnd p:
                return PredEval(el, p.Left, siblings, idx) && PredEval(el, p.Right, siblings, idx);

            case CXPredBoolOr p:
                return PredEval(el, p.Left, siblings, idx) || PredEval(el, p.Right, siblings, idx);

            case CXPredPosition p:
                if (p.IsLast) return idx == siblings.Count - 1;
                return idx == p.Pos - 1;

            case CXPredFuncContains p:
                var cv = el.Attr(p.Attr);
                return cv is not null && ValToStr(cv).Contains(p.Val);

            case CXPredFuncStartsWith p:
                var sv = el.Attr(p.Attr);
                return sv is not null && ValToStr(sv).StartsWith(p.Val);

            default:
                return false;
        }
    }

    static string ValToStr(object? v)
    {
        if (v is null)  return "null";
        if (v is bool b) return b ? "true" : "false";
        return v.ToString()!;
    }

    static bool ScalarEq(object? a, object? b)
    {
        bool aBool = a is bool;
        bool bBool = b is bool;
        // bool must not match numeric
        if (aBool != bBool) return false;
        if (aBool) return (bool)a! == (bool)b!;
        // numeric comparison
        bool aNum = a is long or double or int or float;
        bool bNum = b is long or double or int or float;
        if (aNum && bNum)
            return Convert.ToDouble(a) == Convert.ToDouble(b);
        return Equals(a, b);
    }

    static bool Compare(object? actual, string op, object? expected)
    {
        if (op == "=")  return ScalarEq(actual, expected);
        if (op == "!=") return !ScalarEq(actual, expected);
        double a = ToF64(actual);
        double b = ToF64(expected);
        return op switch
        {
            ">"  => a > b,
            "<"  => a < b,
            ">=" => a >= b,
            "<=" => a <= b,
            _    => false,
        };
    }

    static double ToF64(object? v)
    {
        if (v is bool)
            throw new InvalidOperationException($"CXPath: numeric comparison requires numeric value, got bool: {v}");
        if (v is long or double or int or float)
            return Convert.ToDouble(v);
        throw new InvalidOperationException($"CXPath: numeric comparison requires numeric attribute value, got: {v}");
    }

    // ── ElemMatches (for TransformAll) ────────────────────────────────────────

    public static bool ElemMatches(Element el, CXPathExpr expr)
    {
        if (expr.Steps.Count == 0) return false;
        var last = expr.Steps[^1];
        if (last.Name.Length > 0 && last.Name != el.Name) return false;
        var nonPos = last.Preds.Where(p => p is not CXPredPosition).ToList();
        return PredsMatch(el, nonPos, new List<Element>(), 0);
    }

    // ── Transform helpers ─────────────────────────────────────────────────────

    public static Element ElemDetached(Element e)
    {
        var copy = new Element(e.Name)
        {
            Anchor = e.Anchor,
            Merge = e.Merge,
            DataType = e.DataType,
        };
        copy.Attrs = new List<Attr>(e.Attrs);
        copy.Items = new List<Node>(e.Items);
        return copy;
    }

    public static CXDocument DocReplaceAt(CXDocument d, int idx, Element el)
    {
        var newElements = new List<Node>(d.Elements);
        newElements[idx] = el;
        return new CXDocument { Elements = newElements, Prolog = d.Prolog, Doctype = d.Doctype };
    }

    public static Element ElemReplaceItemAt(Element e, int idx, Node child)
    {
        var newItems = new List<Node>(e.Items);
        newItems[idx] = child;
        return new Element(e.Name)
        {
            Anchor = e.Anchor,
            Merge = e.Merge,
            DataType = e.DataType,
            Attrs = e.Attrs,
            Items = newItems,
        };
    }

    public static Element? PathCopyElement(Element e, string[] parts, Func<Element, Element> f)
    {
        for (int i = 0; i < e.Items.Count; i++)
        {
            if (e.Items[i] is Element item && item.Name == parts[0])
            {
                if (parts.Length == 1)
                    return ElemReplaceItemAt(e, i, f(ElemDetached(item)));
                var updated = PathCopyElement(item, parts[1..], f);
                if (updated is not null)
                    return ElemReplaceItemAt(e, i, updated);
                return null;
            }
        }
        return null;
    }

    public static Node RebuildNode(Node node, CXPathExpr expr, Func<Element, Element> f)
    {
        if (node is not Element el) return node;
        var newItems = el.Items.Select(item => RebuildNode(item, expr, f)).ToList();
        var newEl = new Element(el.Name)
        {
            Anchor = el.Anchor,
            Merge = el.Merge,
            DataType = el.DataType,
            Attrs = el.Attrs,
            Items = newItems,
        };
        if (ElemMatches(newEl, expr))
            return f(ElemDetached(newEl));
        return newEl;
    }
}
