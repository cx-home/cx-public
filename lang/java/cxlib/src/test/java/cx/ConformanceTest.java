package cx;

import org.junit.jupiter.api.*;
import static org.junit.jupiter.api.Assertions.*;

import java.io.*;
import java.nio.file.*;
import java.util.*;

/**
 * CX Java conformance runner.
 * Parses conformance/*.txt and checks all test cases.
 */
public class ConformanceTest {

    // ── suite parser ───────────────────────────────────────────────────────────

    static class TestCase {
        String name;
        Map<String, String> sections = new LinkedHashMap<>();
        TestCase(String name) { this.name = name; }
    }

    static List<TestCase> parseSuite(Path path) throws IOException {
        List<TestCase> tests = new ArrayList<>();
        TestCase cur = null;
        String section = null;
        List<String> buf = new ArrayList<>();

        for (String raw : Files.readAllLines(path)) {
            String line = raw;
            if (line.startsWith("=== test:")) {
                flush(cur, section, buf);
                if (cur != null) tests.add(cur);
                cur = new TestCase(line.substring(9).trim());
                section = null;
            } else if (line.startsWith("--- ") && cur != null) {
                flush(cur, section, buf);
                section = line.substring(4).trim();
            } else if (section != null && cur != null) {
                buf.add(line);
            }
        }
        flush(cur, section, buf);
        if (cur != null) tests.add(cur);
        return tests;
    }

    static void flush(TestCase cur, String section, List<String> buf) {
        if (cur != null && section != null) {
            List<String> lines = new ArrayList<>(buf);
            while (!lines.isEmpty() && lines.get(0).trim().isEmpty())            lines.remove(0);
            while (!lines.isEmpty() && lines.get(lines.size()-1).trim().isEmpty()) lines.remove(lines.size()-1);
            cur.sections.put(section, String.join("\n", lines));
        }
        buf.clear();
    }

    // ── simple JSON value equality (structural, order-insensitive for objects) ─

    static Object parseJson(String s) {
        return new JsonParser(s.trim()).parse();
    }

    static boolean jsonEqual(Object a, Object b) {
        if (a == null && b == null) return true;
        if (a == null || b == null) return false;
        if (!a.getClass().equals(b.getClass())) {
            // allow int/long comparisons
            if ((a instanceof Number) && (b instanceof Number))
                return ((Number)a).doubleValue() == ((Number)b).doubleValue();
            return false;
        }
        if (a instanceof Map) {
            @SuppressWarnings("unchecked") Map<String,Object> ma = (Map<String,Object>)a;
            @SuppressWarnings("unchecked") Map<String,Object> mb = (Map<String,Object>)b;
            if (!ma.keySet().equals(mb.keySet())) return false;
            for (String k : ma.keySet()) if (!jsonEqual(ma.get(k), mb.get(k))) return false;
            return true;
        }
        if (a instanceof List) {
            @SuppressWarnings("unchecked") List<Object> la = (List<Object>)a;
            @SuppressWarnings("unchecked") List<Object> lb = (List<Object>)b;
            if (la.size() != lb.size()) return false;
            for (int i = 0; i < la.size(); i++) if (!jsonEqual(la.get(i), lb.get(i))) return false;
            return true;
        }
        return a.equals(b);
    }

    // tiny recursive-descent JSON parser
    static class JsonParser {
        final String s;
        int pos;
        JsonParser(String s) { this.s = s; }

        Object parse() {
            skipWs();
            if (pos >= s.length()) return null;
            char c = s.charAt(pos);
            if (c == '{') return parseObject();
            if (c == '[') return parseArray();
            if (c == '"') return parseString();
            if (c == 't') { pos += 4; return Boolean.TRUE; }
            if (c == 'f') { pos += 5; return Boolean.FALSE; }
            if (c == 'n') { pos += 4; return null; }
            return parseNumber();
        }

        void skipWs() { while (pos < s.length() && s.charAt(pos) <= ' ') pos++; }

        Map<String,Object> parseObject() {
            Map<String,Object> m = new LinkedHashMap<>();
            pos++; // {
            skipWs();
            while (pos < s.length() && s.charAt(pos) != '}') {
                String key = parseString();
                skipWs(); pos++; // :
                Object val = parse();
                m.put(key, val);
                skipWs();
                if (pos < s.length() && s.charAt(pos) == ',') { pos++; skipWs(); }
            }
            if (pos < s.length()) pos++; // }
            return m;
        }

        List<Object> parseArray() {
            List<Object> a = new ArrayList<>();
            pos++; // [
            skipWs();
            while (pos < s.length() && s.charAt(pos) != ']') {
                a.add(parse());
                skipWs();
                if (pos < s.length() && s.charAt(pos) == ',') { pos++; skipWs(); }
            }
            if (pos < s.length()) pos++; // ]
            return a;
        }

        String parseString() {
            pos++; // "
            StringBuilder sb = new StringBuilder();
            while (pos < s.length()) {
                char c = s.charAt(pos++);
                if (c == '"') break;
                if (c == '\\') {
                    c = s.charAt(pos++);
                    switch (c) {
                        case '"': sb.append('"'); break;
                        case '\\': sb.append('\\'); break;
                        case '/':  sb.append('/');  break;
                        case 'n':  sb.append('\n'); break;
                        case 'r':  sb.append('\r'); break;
                        case 't':  sb.append('\t'); break;
                        case 'u':
                            int cp = Integer.parseInt(s.substring(pos, pos+4), 16);
                            sb.appendCodePoint(cp); pos += 4; break;
                        default: sb.append(c);
                    }
                } else { sb.append(c); }
            }
            return sb.toString();
        }

        Number parseNumber() {
            int start = pos;
            if (pos < s.length() && s.charAt(pos) == '-') pos++;
            while (pos < s.length() && Character.isDigit(s.charAt(pos))) pos++;
            boolean isFloat = false;
            if (pos < s.length() && s.charAt(pos) == '.') { isFloat = true; pos++; while (pos < s.length() && Character.isDigit(s.charAt(pos))) pos++; }
            if (pos < s.length() && (s.charAt(pos) == 'e' || s.charAt(pos) == 'E')) {
                isFloat = true; pos++;
                if (pos < s.length() && (s.charAt(pos) == '+' || s.charAt(pos) == '-')) pos++;
                while (pos < s.length() && Character.isDigit(s.charAt(pos))) pos++;
            }
            String num = s.substring(start, pos);
            if (isFloat) return Double.parseDouble(num);
            try { return Long.parseLong(num); } catch (NumberFormatException e) { return Double.parseDouble(num); }
        }
    }

    // ── test runner ────────────────────────────────────────────────────────────

    static String dispatch(String inFmt, String outFmt, String input) {
        switch (inFmt + ":" + outFmt) {
            case "cx:cx":     return CxLib.toCx(input);
            case "cx:xml":    return CxLib.toXml(input);
            case "cx:ast":    return CxLib.toAst(input);
            case "cx:json":   return CxLib.toJson(input);
            case "cx:yaml":   return CxLib.toYaml(input);
            case "cx:toml":   return CxLib.toToml(input);
            case "cx:md":     return CxLib.toMd(input);
            case "xml:cx":    return CxLib.xmlToCx(input);
            case "xml:xml":   return CxLib.xmlToXml(input);
            case "xml:ast":   return CxLib.xmlToAst(input);
            case "xml:json":  return CxLib.xmlToJson(input);
            case "xml:yaml":  return CxLib.xmlToYaml(input);
            case "xml:toml":  return CxLib.xmlToToml(input);
            case "xml:md":    return CxLib.xmlToMd(input);
            case "json:cx":   return CxLib.jsonToCx(input);
            case "json:xml":  return CxLib.jsonToXml(input);
            case "json:ast":  return CxLib.jsonToAst(input);
            case "json:json": return CxLib.jsonToJson(input);
            case "json:yaml": return CxLib.jsonToYaml(input);
            case "json:toml": return CxLib.jsonToToml(input);
            case "json:md":   return CxLib.jsonToMd(input);
            case "yaml:cx":   return CxLib.yamlToCx(input);
            case "yaml:xml":  return CxLib.yamlToXml(input);
            case "yaml:ast":  return CxLib.yamlToAst(input);
            case "yaml:json": return CxLib.yamlToJson(input);
            case "yaml:yaml": return CxLib.yamlToYaml(input);
            case "yaml:toml": return CxLib.yamlToToml(input);
            case "yaml:md":   return CxLib.yamlToMd(input);
            case "toml:cx":   return CxLib.tomlToCx(input);
            case "toml:xml":  return CxLib.tomlToXml(input);
            case "toml:ast":  return CxLib.tomlToAst(input);
            case "toml:json": return CxLib.tomlToJson(input);
            case "toml:yaml": return CxLib.tomlToYaml(input);
            case "toml:toml": return CxLib.tomlToToml(input);
            case "toml:md":   return CxLib.tomlToMd(input);
            case "md:cx":     return CxLib.mdToCx(input);
            case "md:xml":    return CxLib.mdToXml(input);
            case "md:ast":    return CxLib.mdToAst(input);
            case "md:json":   return CxLib.mdToJson(input);
            case "md:yaml":   return CxLib.mdToYaml(input);
            case "md:toml":   return CxLib.mdToToml(input);
            case "md:md":     return CxLib.mdToMd(input);
            default: throw new IllegalArgumentException("no dispatch for " + inFmt + ":" + outFmt);
        }
    }

    static List<String> runTest(TestCase t) {
        List<String> failures = new ArrayList<>();
        Map<String, String> s = t.sections;

        String src = null, inFmt = null;
        for (String[] pair : new String[][]{
                {"in_cx","cx"}, {"in_xml","xml"}, {"in_json","json"},
                {"in_yaml","yaml"}, {"in_toml","toml"}, {"in_md","md"}}) {
            if (s.containsKey(pair[0])) { src = s.get(pair[0]); inFmt = pair[1]; break; }
        }
        if (inFmt == null) return failures;

        final String finalSrc = src, finalInFmt = inFmt;

        // helper
        String[] call = new String[2]; // [out, err]
        java.util.function.Consumer<String> doCall = outFmt -> {
            try   { call[0] = dispatch(finalInFmt, outFmt, finalSrc); call[1] = null; }
            catch (Exception e) { call[0] = null; call[1] = e.getMessage(); }
        };

        if (s.containsKey("out_ast")) {
            doCall.accept("ast");
            if (call[1] != null) { failures.add("out_ast parse error: " + call[1]); }
            else {
                Object exp = parseJson(s.get("out_ast")), got = parseJson(call[0]);
                if (!jsonEqual(exp, got)) failures.add("out_ast mismatch\n  expected: " + s.get("out_ast") + "\n  got:      " + call[0]);
            }
        }
        if (s.containsKey("out_xml")) {
            doCall.accept("xml");
            if (call[1] != null) failures.add("out_xml parse error: " + call[1]);
            else if (!s.get("out_xml").trim().equals(call[0].trim())) failures.add("out_xml mismatch\n  expected:\n" + s.get("out_xml") + "\n  got:\n" + call[0]);
        }
        if (s.containsKey("out_cx")) {
            doCall.accept("cx");
            if (call[1] != null) failures.add("out_cx parse error: " + call[1]);
            else if (!s.get("out_cx").trim().equals(call[0].trim())) failures.add("out_cx mismatch\n  expected:\n" + s.get("out_cx") + "\n  got:\n" + call[0]);
        }
        if (s.containsKey("out_json")) {
            doCall.accept("json");
            if (call[1] != null) { failures.add("out_json parse error: " + call[1]); }
            else {
                Object exp = parseJson(s.get("out_json")), got = parseJson(call[0]);
                if (!jsonEqual(exp, got)) failures.add("out_json mismatch\n  expected: " + s.get("out_json") + "\n  got:      " + call[0]);
            }
        }
        if (s.containsKey("out_md")) {
            doCall.accept("md");
            if (call[1] != null) failures.add("out_md parse error: " + call[1]);
            else if (!s.get("out_md").trim().equals(call[0].trim())) failures.add("out_md mismatch\n  expected:\n" + s.get("out_md") + "\n  got:\n" + call[0]);
        }
        return failures;
    }

    static int runSuite(Path path) throws IOException {
        List<TestCase> tests = parseSuite(path);
        int passed = 0, failed = 0;
        for (TestCase t : tests) {
            List<String> failures;
            try   { failures = runTest(t); }
            catch (Exception e) { failures = List.of("runner exception: " + e.getMessage()); }
            if (failures.isEmpty()) { passed++; }
            else {
                failed++;
                System.out.println("FAIL  " + t.name);
                for (String f : failures)
                    for (String line : f.split("\n")) System.out.println("      " + line);
            }
        }
        System.out.println(path + ": " + passed + " passed, " + failed + " failed");
        return failed;
    }

    // ── JUnit 5 test methods ───────────────────────────────────────────────────

    static Path conformanceDir() {
        // tests run from lang/java/cxlib; conformance/ is at ../../../conformance/
        return Paths.get("../../../conformance");
    }

    @Test
    void testCore() throws IOException {
        int f = runSuite(conformanceDir().resolve("core.txt"));
        assertEquals(0, f, "core.txt had failures");
    }

    @Test
    void testExtended() throws IOException {
        int f = runSuite(conformanceDir().resolve("extended.txt"));
        assertEquals(0, f, "extended.txt had failures");
    }

    @Test
    void testXml() throws IOException {
        int f = runSuite(conformanceDir().resolve("xml.txt"));
        assertEquals(0, f, "xml.txt had failures");
    }

    @Test
    void testMd() throws IOException {
        int f = runSuite(conformanceDir().resolve("md.txt"));
        assertEquals(0, f, "md.txt had failures");
    }
}
