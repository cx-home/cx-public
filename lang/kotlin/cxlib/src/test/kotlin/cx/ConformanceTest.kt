package cx

import org.junit.jupiter.api.Test
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths
import kotlin.test.assertEquals

/**
 * CX Kotlin conformance runner.
 */
class ConformanceTest {

    // ── suite parser ───────────────────────────────────────────────────────────

    data class TestCase(val name: String, val sections: MutableMap<String, String> = mutableMapOf())

    fun parseSuite(path: Path): List<TestCase> {
        val tests = mutableListOf<TestCase>()
        var cur: TestCase? = null
        var section: String? = null
        val buf = mutableListOf<String>()

        fun flush() {
            val c = cur ?: return
            val s = section ?: return
            val lines = buf.toMutableList()
            while (lines.isNotEmpty() && lines.first().isBlank()) lines.removeFirst()
            while (lines.isNotEmpty() && lines.last().isBlank()) lines.removeLast()
            c.sections[s] = lines.joinToString("\n")
            buf.clear()
        }

        for (line in Files.readAllLines(path)) {
            when {
                line.startsWith("=== test:") -> {
                    flush()
                    cur?.let { tests.add(it) }
                    cur = TestCase(line.substring(9).trim())
                    section = null
                }
                line.startsWith("--- ") && cur != null -> {
                    flush()
                    section = line.substring(4).trim()
                }
                section != null && cur != null -> buf.add(line)
            }
        }
        flush()
        cur?.let { tests.add(it) }
        return tests
    }

    // ── tiny JSON parser + deep equality ──────────────────────────────────────

    private fun parseJson(s: String): Any? = JsonParser(s.trim()).parse()

    private fun jsonEqual(a: Any?, b: Any?): Boolean {
        if (a === b) return true
        if (a == null || b == null) return false
        if (a is Map<*,*> && b is Map<*,*>) {
            if (a.keys != b.keys) return false
            return a.keys.all { jsonEqual(a[it], b[it]) }
        }
        if (a is List<*> && b is List<*>) {
            if (a.size != b.size) return false
            return a.indices.all { jsonEqual(a[it], b[it]) }
        }
        if (a is Number && b is Number) return a.toDouble() == b.toDouble()
        return a == b
    }

    inner class JsonParser(val s: String) {
        var pos = 0
        fun parse(): Any? {
            skipWs()
            if (pos >= s.length) return null
            return when (s[pos]) {
                '{' -> parseObject()
                '[' -> parseArray()
                '"' -> parseString()
                't' -> { pos += 4; true }
                'f' -> { pos += 5; false }
                'n' -> { pos += 4; null }
                else -> parseNumber()
            }
        }
        fun skipWs() { while (pos < s.length && s[pos] <= ' ') pos++ }
        fun parseObject(): Map<String, Any?> {
            pos++; skipWs()
            val m = mutableMapOf<String, Any?>()
            while (pos < s.length && s[pos] != '}') {
                val k = parseString(); skipWs(); pos++ // :
                m[k] = parse(); skipWs()
                if (pos < s.length && s[pos] == ',') { pos++; skipWs() }
            }
            if (pos < s.length) pos++; return m
        }
        fun parseArray(): List<Any?> {
            pos++; skipWs()
            val a = mutableListOf<Any?>()
            while (pos < s.length && s[pos] != ']') {
                a.add(parse()); skipWs()
                if (pos < s.length && s[pos] == ',') { pos++; skipWs() }
            }
            if (pos < s.length) pos++; return a
        }
        fun parseString(): String {
            pos++
            val sb = StringBuilder()
            while (pos < s.length) {
                val c = s[pos++]
                if (c == '"') break
                if (c == '\\') {
                    when (val e = s[pos++]) {
                        '"'  -> sb.append('"')
                        '\\' -> sb.append('\\')
                        '/'  -> sb.append('/')
                        'n'  -> sb.append('\n')
                        'r'  -> sb.append('\r')
                        't'  -> sb.append('\t')
                        'u'  -> { sb.appendCodePoint(s.substring(pos, pos+4).toInt(16)); pos += 4 }
                        else -> sb.append(e)
                    }
                } else sb.append(c)
            }
            return sb.toString()
        }
        fun parseNumber(): Number {
            val start = pos
            if (pos < s.length && s[pos] == '-') pos++
            while (pos < s.length && s[pos].isDigit()) pos++
            var isFloat = false
            if (pos < s.length && s[pos] == '.') { isFloat = true; pos++; while (pos < s.length && s[pos].isDigit()) pos++ }
            if (pos < s.length && (s[pos] == 'e' || s[pos] == 'E')) {
                isFloat = true; pos++
                if (pos < s.length && (s[pos] == '+' || s[pos] == '-')) pos++
                while (pos < s.length && s[pos].isDigit()) pos++
            }
            val num = s.substring(start, pos)
            return if (isFloat) num.toDouble() else num.toLong()
        }
    }

    // ── dispatch ───────────────────────────────────────────────────────────────

    fun dispatch(inFmt: String, outFmt: String, input: String): String = when ("$inFmt:$outFmt") {
        "cx:cx"     -> CxLib.toCx(input);     "cx:xml"    -> CxLib.toXml(input)
        "cx:ast"    -> CxLib.toAst(input);    "cx:json"   -> CxLib.toJson(input)
        "cx:yaml"   -> CxLib.toYaml(input);   "cx:toml"   -> CxLib.toToml(input)
        "cx:md"     -> CxLib.toMd(input)
        "xml:cx"    -> CxLib.xmlToCx(input);  "xml:xml"   -> CxLib.xmlToXml(input)
        "xml:ast"   -> CxLib.xmlToAst(input); "xml:json"  -> CxLib.xmlToJson(input)
        "xml:yaml"  -> CxLib.xmlToYaml(input);"xml:toml"  -> CxLib.xmlToToml(input)
        "xml:md"    -> CxLib.xmlToMd(input)
        "json:cx"   -> CxLib.jsonToCx(input); "json:xml"  -> CxLib.jsonToXml(input)
        "json:ast"  -> CxLib.jsonToAst(input);"json:json" -> CxLib.jsonToJson(input)
        "json:yaml" -> CxLib.jsonToYaml(input);"json:toml"-> CxLib.jsonToToml(input)
        "json:md"   -> CxLib.jsonToMd(input)
        "yaml:cx"   -> CxLib.yamlToCx(input); "yaml:xml"  -> CxLib.yamlToXml(input)
        "yaml:ast"  -> CxLib.yamlToAst(input);"yaml:json" -> CxLib.yamlToJson(input)
        "yaml:yaml" -> CxLib.yamlToYaml(input);"yaml:toml"-> CxLib.yamlToToml(input)
        "yaml:md"   -> CxLib.yamlToMd(input)
        "toml:cx"   -> CxLib.tomlToCx(input); "toml:xml"  -> CxLib.tomlToXml(input)
        "toml:ast"  -> CxLib.tomlToAst(input);"toml:json" -> CxLib.tomlToJson(input)
        "toml:yaml" -> CxLib.tomlToYaml(input);"toml:toml"-> CxLib.tomlToToml(input)
        "toml:md"   -> CxLib.tomlToMd(input)
        "md:cx"     -> CxLib.mdToCx(input);   "md:xml"    -> CxLib.mdToXml(input)
        "md:ast"    -> CxLib.mdToAst(input);  "md:json"   -> CxLib.mdToJson(input)
        "md:yaml"   -> CxLib.mdToYaml(input); "md:toml"   -> CxLib.mdToToml(input)
        "md:md"     -> CxLib.mdToMd(input)
        else -> throw IllegalArgumentException("no dispatch for $inFmt:$outFmt")
    }

    // ── test runner ────────────────────────────────────────────────────────────

    fun runTest(t: TestCase): List<String> {
        val failures = mutableListOf<String>()
        val s = t.sections

        val (src, inFmt) = listOf(
            "in_cx" to "cx", "in_xml" to "xml", "in_json" to "json",
            "in_yaml" to "yaml", "in_toml" to "toml", "in_md" to "md"
        ).firstOrNull { (k, _) -> k in s }
            ?.let { (k, fmt) -> s[k]!! to fmt } ?: return failures

        fun call(outFmt: String): Pair<String?, String?> = try {
            dispatch(inFmt, outFmt, src) to null
        } catch (e: Exception) { null to e.message }

        if ("out_ast" in s) {
            val (out, err) = call("ast")
            if (err != null) failures.add("out_ast parse error: $err")
            else if (!jsonEqual(parseJson(s["out_ast"]!!), parseJson(out!!)))
                failures.add("out_ast mismatch\n  expected: ${s["out_ast"]}\n  got:      $out")
        }
        if ("out_xml" in s) {
            val (out, err) = call("xml")
            if (err != null) failures.add("out_xml parse error: $err")
            else if (s["out_xml"]!!.trim() != out!!.trim())
                failures.add("out_xml mismatch\n  expected:\n${s["out_xml"]}\n  got:\n$out")
        }
        if ("out_cx" in s) {
            val (out, err) = call("cx")
            if (err != null) failures.add("out_cx parse error: $err")
            else if (s["out_cx"]!!.trim() != out!!.trim())
                failures.add("out_cx mismatch\n  expected:\n${s["out_cx"]}\n  got:\n$out")
        }
        if ("out_json" in s) {
            val (out, err) = call("json")
            if (err != null) failures.add("out_json parse error: $err")
            else if (!jsonEqual(parseJson(s["out_json"]!!), parseJson(out!!)))
                failures.add("out_json mismatch\n  expected: ${s["out_json"]}\n  got:      $out")
        }
        if ("out_md" in s) {
            val (out, err) = call("md")
            if (err != null) failures.add("out_md parse error: $err")
            else if (s["out_md"]!!.trim() != out!!.trim())
                failures.add("out_md mismatch\n  expected:\n${s["out_md"]}\n  got:\n$out")
        }
        return failures
    }

    fun runSuite(path: Path): Int {
        val tests = parseSuite(path)
        var passed = 0; var failed = 0
        for (t in tests) {
            val failures = try { runTest(t) } catch (e: Exception) { listOf("runner exception: ${e.message}") }
            if (failures.isEmpty()) passed++
            else {
                failed++
                println("FAIL  ${t.name}")
                failures.forEach { f -> f.split("\n").forEach { println("      $it") } }
            }
        }
        println("$path: $passed passed, $failed failed")
        return failed
    }

    private fun conformanceDir(): Path = Paths.get("../../../conformance")

    @Test fun testCore()     { assertEquals(0, runSuite(conformanceDir().resolve("core.txt")), "core.txt") }
    @Test fun testExtended() { assertEquals(0, runSuite(conformanceDir().resolve("extended.txt")), "extended.txt") }
    @Test fun testXml()      { assertEquals(0, runSuite(conformanceDir().resolve("xml.txt")), "xml.txt") }
    @Test fun testMd()       { assertEquals(0, runSuite(conformanceDir().resolve("md.txt")), "md.txt") }
}
