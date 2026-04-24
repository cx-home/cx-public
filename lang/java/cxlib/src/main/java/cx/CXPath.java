package cx;

import java.util.*;
import java.util.function.Function;

/**
 * CXPath parser, evaluator, and transform helpers.
 *
 * Port of lang/python/cxlib/cxpath.py.
 */
public class CXPath {

    // ── Predicate hierarchy ───────────────────────────────────────────────────

    interface CXPred {}

    record AttrExists(String attr) implements CXPred {}
    record AttrCmp(String attr, String op, Object val) implements CXPred {}
    record ChildExists(String name) implements CXPred {}
    record Not(CXPred inner) implements CXPred {}
    record BoolAnd(CXPred left, CXPred right) implements CXPred {}
    record BoolOr(CXPred left, CXPred right) implements CXPred {}
    record Position(int pos, boolean isLast) implements CXPred {}
    record FuncContains(String attr, String val) implements CXPred {}
    record FuncStartsWith(String attr, String val) implements CXPred {}

    // ── Step / path AST ───────────────────────────────────────────────────────

    enum Axis { CHILD, DESCENDANT }

    record CXStep(Axis axis, String name, List<CXPred> preds) {}
    record CXPathExpr(List<CXStep> steps) {}

    // ── Tokenizer ─────────────────────────────────────────────────────────────

    private static final class Lexer {
        final String src;
        int pos;

        Lexer(String src) {
            this.src = src;
            this.pos = 0;
        }

        void skipWs() {
            while (pos < src.length() && src.charAt(pos) == ' ') pos++;
        }

        boolean peekStr(String s) {
            return src.startsWith(s, pos);
        }

        boolean eatStr(String s) {
            if (peekStr(s)) { pos += s.length(); return true; }
            return false;
        }

        boolean eatChar(char c) {
            if (pos < src.length() && src.charAt(pos) == c) { pos++; return true; }
            return false;
        }

        String readIdent() {
            int start = pos;
            while (pos < src.length()) {
                char c = src.charAt(pos);
                if (Character.isLetterOrDigit(c) || c == '_' || c == '-' || c == '.' || c == ':' || c == '%') {
                    pos++;
                } else {
                    break;
                }
            }
            return src.substring(start, pos);
        }

        String readQuoted() {
            if (!eatChar('\''))
                throw new IllegalArgumentException("CXPath parse error: expected ' at pos " + pos + "  expr: " + src);
            int start = pos;
            while (pos < src.length() && src.charAt(pos) != '\'') pos++;
            String s = src.substring(start, pos);
            if (!eatChar('\''))
                throw new IllegalArgumentException("CXPath parse error: unterminated string at pos " + pos + "  expr: " + src);
            return s;
        }
    }

    // ── Parser ────────────────────────────────────────────────────────────────

    public static CXPathExpr parse(String expr) {
        Lexer l = new Lexer(expr);
        List<CXStep> steps = parseSteps(l);
        if (l.pos != l.src.length())
            throw new IllegalArgumentException("CXPath parse error: unexpected characters at pos " + l.pos + "  expr: " + expr);
        if (steps.isEmpty())
            throw new IllegalArgumentException("CXPath parse error: empty expression  expr: " + expr);
        return new CXPathExpr(steps);
    }

    private static List<CXStep> parseSteps(Lexer l) {
        List<CXStep> steps = new ArrayList<>();
        Axis axis;
        if (l.peekStr("//")) {
            l.pos += 2;
            axis = Axis.DESCENDANT;
        } else if (l.peekStr("/")) {
            l.pos += 1;
            axis = Axis.CHILD;
        } else {
            axis = Axis.CHILD;
        }
        steps.add(parseOneStep(l, axis));
        while (true) {
            l.skipWs();
            if (l.peekStr("//")) {
                l.pos += 2;
                steps.add(parseOneStep(l, Axis.DESCENDANT));
            } else if (l.peekStr("/")) {
                l.pos += 1;
                steps.add(parseOneStep(l, Axis.CHILD));
            } else {
                break;
            }
        }
        return steps;
    }

    private static CXStep parseOneStep(Lexer l, Axis axis) {
        l.skipWs();
        String name;
        if (l.eatChar('*')) {
            name = "";
        } else {
            name = l.readIdent();
            if (name.isEmpty())
                throw new IllegalArgumentException("CXPath parse error: expected element name at pos " + l.pos + "  expr: " + l.src);
        }
        List<CXPred> preds = new ArrayList<>();
        while (true) {
            l.skipWs();
            if (l.peekStr("[")) {
                preds.add(parsePredBracket(l));
            } else {
                break;
            }
        }
        return new CXStep(axis, name, preds);
    }

    private static CXPred parsePredBracket(Lexer l) {
        if (!l.eatChar('['))
            throw new IllegalArgumentException("CXPath parse error: expected [ at pos " + l.pos + "  expr: " + l.src);
        l.skipWs();
        CXPred pred = parsePredExpr(l);
        l.skipWs();
        if (!l.eatChar(']'))
            throw new IllegalArgumentException("CXPath parse error: expected ] at pos " + l.pos + "  expr: " + l.src);
        return pred;
    }

    private static CXPred parsePredExpr(Lexer l) {
        CXPred left = parsePredTerm(l);
        l.skipWs();
        int saved = l.pos;
        String word = l.readIdent();
        if ("or".equals(word)) {
            l.skipWs();
            CXPred right = parsePredTerm(l);
            return new BoolOr(left, right);
        }
        l.pos = saved;
        return left;
    }

    private static CXPred parsePredTerm(Lexer l) {
        CXPred left = parsePredFactor(l);
        l.skipWs();
        int saved = l.pos;
        String word = l.readIdent();
        if ("and".equals(word)) {
            l.skipWs();
            CXPred right = parsePredFactor(l);
            return new BoolAnd(left, right);
        }
        l.pos = saved;
        return left;
    }

    private static CXPred parsePredFactor(Lexer l) {
        l.skipWs();

        // not(...)
        if (l.peekStr("not(") || l.peekStr("not (")) {
            l.readIdent(); // consume 'not'
            l.skipWs();
            if (!l.eatChar('('))
                throw new IllegalArgumentException("CXPath parse error: expected ( after not  expr: " + l.src);
            l.skipWs();
            CXPred inner = parsePredExpr(l);
            l.skipWs();
            if (!l.eatChar(')'))
                throw new IllegalArgumentException("CXPath parse error: expected ) after not(...)  expr: " + l.src);
            return new Not(inner);
        }

        // contains(@attr, val)
        if (l.peekStr("contains(")) {
            l.readIdent(); // consume 'contains'
            l.skipWs();
            if (!l.eatChar('('))
                throw new IllegalArgumentException("CXPath parse error: expected ( after contains  expr: " + l.src);
            l.skipWs();
            if (!l.eatChar('@'))
                throw new IllegalArgumentException("CXPath parse error: expected @attr in contains()  expr: " + l.src);
            String attr = l.readIdent();
            l.skipWs();
            if (!l.eatChar(','))
                throw new IllegalArgumentException("CXPath parse error: expected , in contains()  expr: " + l.src);
            l.skipWs();
            String val = parseScalarStr(l);
            l.skipWs();
            if (!l.eatChar(')'))
                throw new IllegalArgumentException("CXPath parse error: expected ) after contains(...)  expr: " + l.src);
            return new FuncContains(attr, val);
        }

        // starts-with(@attr, val)
        if (l.peekStr("starts-with(")) {
            // consume up to (
            while (l.pos < l.src.length() && l.src.charAt(l.pos) != '(') l.pos++;
            if (!l.eatChar('('))
                throw new IllegalArgumentException("CXPath parse error: expected ( after starts-with  expr: " + l.src);
            l.skipWs();
            if (!l.eatChar('@'))
                throw new IllegalArgumentException("CXPath parse error: expected @attr in starts-with()  expr: " + l.src);
            String attr = l.readIdent();
            l.skipWs();
            if (!l.eatChar(','))
                throw new IllegalArgumentException("CXPath parse error: expected , in starts-with()  expr: " + l.src);
            l.skipWs();
            String val = parseScalarStr(l);
            l.skipWs();
            if (!l.eatChar(')'))
                throw new IllegalArgumentException("CXPath parse error: expected ) after starts-with(...)  expr: " + l.src);
            return new FuncStartsWith(attr, val);
        }

        // last()
        if (l.peekStr("last()")) {
            l.pos += 6;
            return new Position(0, true);
        }

        // (grouped expr)
        if (l.peekStr("(")) {
            l.eatChar('(');
            l.skipWs();
            CXPred inner = parsePredExpr(l);
            l.skipWs();
            if (!l.eatChar(')'))
                throw new IllegalArgumentException("CXPath parse error: expected ) at pos " + l.pos + "  expr: " + l.src);
            return inner;
        }

        // @attr comparison or existence
        if (l.pos < l.src.length() && l.src.charAt(l.pos) == '@') {
            l.eatChar('@');
            String attr = l.readIdent();
            l.skipWs();
            String op = parseOp(l);
            if (op.isEmpty()) return new AttrExists(attr);
            l.skipWs();
            Object val = parseScalarVal(l);
            return new AttrCmp(attr, op, val);
        }

        // integer position predicate
        if (l.pos < l.src.length() && Character.isDigit(l.src.charAt(l.pos))) {
            int start = l.pos;
            while (l.pos < l.src.length() && Character.isDigit(l.src.charAt(l.pos))) l.pos++;
            int posVal = Integer.parseInt(l.src.substring(start, l.pos));
            return new Position(posVal, false);
        }

        // bare name → child existence
        String name = l.readIdent();
        if (!name.isEmpty()) return new ChildExists(name);

        throw new IllegalArgumentException("CXPath parse error: unexpected character at pos " + l.pos + "  expr: " + l.src);
    }

    private static String parseOp(Lexer l) {
        for (String op : new String[]{"!=", ">=", "<=", "=", ">", "<"}) {
            if (l.eatStr(op)) return op;
        }
        return "";
    }

    private static Object autotypeValue(String s) {
        if ("true".equals(s))  return Boolean.TRUE;
        if ("false".equals(s)) return Boolean.FALSE;
        if ("null".equals(s))  return null;
        try { return Long.parseLong(s); } catch (NumberFormatException ignored) {}
        try { return Double.parseDouble(s); } catch (NumberFormatException ignored) {}
        return s;
    }

    private static Object parseScalarVal(Lexer l) {
        if (l.peekStr("'")) return l.readQuoted();
        String s = l.readIdent();
        if (s.isEmpty())
            throw new IllegalArgumentException("CXPath parse error: expected value at pos " + l.pos + "  expr: " + l.src);
        return autotypeValue(s);
    }

    private static String parseScalarStr(Lexer l) {
        if (l.peekStr("'")) return l.readQuoted();
        return l.readIdent();
    }

    // ── Evaluator ─────────────────────────────────────────────────────────────

    /**
     * Dispatch from context element into its children for the given step.
     */
    public static void collectStep(Element ctx, CXPathExpr expr, int stepIdx, List<Element> result) {
        if (stepIdx >= expr.steps().size()) return;
        CXStep step = expr.steps().get(stepIdx);
        if (step.axis() == Axis.CHILD) {
            List<Element> candidates = new ArrayList<>();
            for (Node item : ctx.items) {
                if (item instanceof Element e && (step.name().isEmpty() || e.name.equals(step.name()))) {
                    candidates.add(e);
                }
            }
            for (int i = 0; i < candidates.size(); i++) {
                Element child = candidates.get(i);
                if (predsMatch(child, step.preds(), candidates, i)) {
                    if (stepIdx == expr.steps().size() - 1) {
                        result.add(child);
                    } else {
                        collectStep(child, expr, stepIdx + 1, result);
                    }
                }
            }
        } else {
            collectDescendants(ctx, expr, stepIdx, result);
        }
    }

    /**
     * Descendant axis: match at every depth with proper sibling context for position preds.
     */
    static void collectDescendants(Element ctx, CXPathExpr expr, int stepIdx, List<Element> result) {
        CXStep step = expr.steps().get(stepIdx);
        boolean isLast = (stepIdx == expr.steps().size() - 1);

        List<Element> candidates = new ArrayList<>();
        for (Node item : ctx.items) {
            if (item instanceof Element e && (step.name().isEmpty() || e.name.equals(step.name()))) {
                candidates.add(e);
            }
        }

        for (int i = 0; i < candidates.size(); i++) {
            Element child = candidates.get(i);
            if (predsMatch(child, step.preds(), candidates, i)) {
                if (isLast) {
                    result.add(child);
                } else {
                    collectStep(child, expr, stepIdx + 1, result);
                }
            }
            // Always recurse deeper for descendant axis
            collectDescendants(child, expr, stepIdx, result);
        }

        // Also descend into non-matching children for named steps
        if (!step.name().isEmpty()) {
            for (Node item : ctx.items) {
                if (item instanceof Element child && !child.name.equals(step.name())) {
                    collectDescendants(child, expr, stepIdx, result);
                }
            }
        }
    }

    // ── Predicate evaluation ──────────────────────────────────────────────────

    static boolean predsMatch(Element el, List<CXPred> preds, List<Element> siblings, int idx) {
        for (CXPred p : preds) {
            if (!predEval(el, p, siblings, idx)) return false;
        }
        return true;
    }

    private static boolean predEval(Element el, CXPred pred, List<Element> siblings, int idx) {
        if (pred instanceof AttrExists p) {
            return el.attr(p.attr()) != null;
        }
        if (pred instanceof AttrCmp p) {
            Object v = el.attr(p.attr());
            if (v == null) return false;
            return compare(v, p.op(), p.val());
        }
        if (pred instanceof ChildExists p) {
            return el.get(p.name()) != null;
        }
        if (pred instanceof Not p) {
            return !predEval(el, p.inner(), siblings, idx);
        }
        if (pred instanceof BoolAnd p) {
            return predEval(el, p.left(), siblings, idx) && predEval(el, p.right(), siblings, idx);
        }
        if (pred instanceof BoolOr p) {
            return predEval(el, p.left(), siblings, idx) || predEval(el, p.right(), siblings, idx);
        }
        if (pred instanceof Position p) {
            if (p.isLast()) return idx == siblings.size() - 1;
            return idx == p.pos() - 1;
        }
        if (pred instanceof FuncContains p) {
            Object v = el.attr(p.attr());
            return v != null && valToStr(v).contains(p.val());
        }
        if (pred instanceof FuncStartsWith p) {
            Object v = el.attr(p.attr());
            return v != null && valToStr(v).startsWith(p.val());
        }
        return false;
    }

    private static String valToStr(Object v) {
        if (v == null)                 return "null";
        if (v instanceof Boolean b)    return b ? "true" : "false";
        return String.valueOf(v);
    }

    private static boolean scalarEq(Object a, Object b) {
        boolean aBool = a instanceof Boolean;
        boolean bBool = b instanceof Boolean;
        // Boolean vs non-Boolean → never equal (guard cross-type matches)
        if (aBool != bBool) return false;
        if ((a instanceof Long || a instanceof Double) && (b instanceof Long || b instanceof Double)) {
            return toF64(a) == toF64(b);
        }
        if (a == null) return b == null;
        return a.equals(b);
    }

    private static boolean compare(Object actual, String op, Object expected) {
        switch (op) {
            case "=":  return scalarEq(actual, expected);
            case "!=": return !scalarEq(actual, expected);
        }
        double a = toF64(actual);
        double b = toF64(expected);
        return switch (op) {
            case ">"  -> a > b;
            case "<"  -> a < b;
            case ">=" -> a >= b;
            case "<=" -> a <= b;
            default   -> false;
        };
    }

    private static double toF64(Object v) {
        if (v instanceof Boolean)
            throw new IllegalArgumentException("CXPath: numeric comparison requires numeric value, got bool: " + v);
        if (v instanceof Long l)   return l.doubleValue();
        if (v instanceof Double d) return d;
        throw new IllegalArgumentException("CXPath: numeric comparison requires numeric attribute value, got: " + v);
    }

    // ── elemMatches (for transformAll) ────────────────────────────────────────

    /**
     * Returns true if el matches the last step of expr (ignoring position predicates).
     */
    public static boolean elemMatches(Element el, CXPathExpr expr) {
        if (expr.steps().isEmpty()) return false;
        CXStep last = expr.steps().get(expr.steps().size() - 1);
        if (!last.name().isEmpty() && !last.name().equals(el.name)) return false;
        List<CXPred> nonPos = new ArrayList<>();
        for (CXPred p : last.preds()) {
            if (!(p instanceof Position)) nonPos.add(p);
        }
        return predsMatch(el, nonPos, List.of(), 0);
    }

    // ── Transform helpers ─────────────────────────────────────────────────────

    /**
     * Return a copy of e with independent attrs/items lists so f cannot mutate the source.
     */
    public static Element elemDetached(Element e) {
        Element copy = new Element(e.name);
        copy.anchor   = e.anchor;
        copy.merge    = e.merge;
        copy.dataType = e.dataType;
        copy.attrs = new ArrayList<>();
        for (Attr a : e.attrs) copy.attrs.add(new Attr(a.name, a.value, a.dataType));
        copy.items = new ArrayList<>(e.items);
        return copy;
    }

    /**
     * Return a new CXDocument with the element at idx replaced by el.
     */
    public static CXDocument docReplaceAt(CXDocument d, int idx, Element el) {
        CXDocument result = new CXDocument();
        result.prolog  = new ArrayList<>(d.prolog);
        result.doctype = d.doctype;
        result.elements = new ArrayList<>(d.elements);
        result.elements.set(idx, el);
        return result;
    }

    /**
     * Return a new Element with child at idx replaced by child node.
     */
    public static Element elemReplaceItemAt(Element e, int idx, Node child) {
        Element copy = new Element(e.name);
        copy.anchor   = e.anchor;
        copy.merge    = e.merge;
        copy.dataType = e.dataType;
        copy.attrs = e.attrs;  // shared (not mutated by callers)
        copy.items = new ArrayList<>(e.items);
        copy.items.set(idx, child);
        return copy;
    }

    /**
     * Return a new Element with f applied at the element named by parts[0..], or null if path not found.
     */
    public static Element pathCopyElement(Element e, String[] parts, Function<Element, Element> f) {
        for (int i = 0; i < e.items.size(); i++) {
            if (e.items.get(i) instanceof Element item && item.name.equals(parts[0])) {
                if (parts.length == 1) {
                    return elemReplaceItemAt(e, i, f.apply(elemDetached(item)));
                }
                Element updated = pathCopyElement(item, Arrays.copyOfRange(parts, 1, parts.length), f);
                if (updated != null) {
                    return elemReplaceItemAt(e, i, updated);
                }
                return null;
            }
        }
        return null;
    }

    /**
     * Recursively rebuild node tree, applying f to every element matching expr.
     */
    public static Node rebuildNode(Node node, CXPathExpr expr, Function<Element, Element> f) {
        if (!(node instanceof Element e)) return node;
        List<Node> newItems = new ArrayList<>();
        for (Node item : e.items) {
            newItems.add(rebuildNode(item, expr, f));
        }
        Element newEl = new Element(e.name);
        newEl.anchor   = e.anchor;
        newEl.merge    = e.merge;
        newEl.dataType = e.dataType;
        newEl.attrs    = e.attrs;  // shared, not mutated
        newEl.items    = newItems;
        if (elemMatches(newEl, expr)) {
            return f.apply(elemDetached(newEl));
        }
        return newEl;
    }
}
