package cx.examples

import cx.CXDocument
import cx.CxLib
import java.nio.file.Files
import java.nio.file.Paths

/**
 * CX transform examples — demonstrates the Kotlin CxLib wrapper around libcx.
 *
 * Run: cd kotlin/cxlib && ./gradlew run
 */

private val EXAMPLES = Paths.get("../../../examples")

private fun read(name: String) = Files.readString(EXAMPLES.resolve(name))

private fun section(title: String) {
    println("\n${"─".repeat(60)}")
    println("  $title")
    println("─".repeat(60))
}

fun main() {
    // ── article.cx ───────────────────────────────────────────────────────────
    section("article.cx  (source)")
    println(read("article.cx"))

    section("article.cx  →  CX  (canonical round-trip)")
    println(CxLib.toCx(read("article.cx")))

    section("article.cx  →  XML")
    println(CxLib.toXml(read("article.cx")))

    section("article.cx  →  JSON  (mixed content uses '_' for text runs)")
    println(CxLib.toJson(read("article.cx")))

    section("article.cx  →  YAML")
    println(CxLib.toYaml(read("article.cx")))

    // ── env.cx ───────────────────────────────────────────────────────────────
    section("env.cx  (source)")
    println(read("env.cx"))

    section("env.cx  →  CX  (canonical round-trip)")
    println(CxLib.toCx(read("env.cx")))

    section("env.cx  →  XML  (anchor/merge as cx:anchor / cx:merge attrs)")
    println(CxLib.toXml(read("env.cx")))

    section("env.cx  →  JSON")
    println(CxLib.toJson(read("env.cx")))

    section("env.cx  →  YAML")
    println(CxLib.toYaml(read("env.cx")))

    section("env.cx  →  TOML")
    println(CxLib.toToml(read("env.cx")))

    // ── config.cx ────────────────────────────────────────────────────────────
    section("config.cx  →  JSON")
    println(CxLib.toJson(read("config.cx")))

    section("config.cx  →  YAML")
    println(CxLib.toYaml(read("config.cx")))

    section("config.cx  →  TOML")
    println(CxLib.toToml(read("config.cx")))

    // ── books.cx ─────────────────────────────────────────────────────────────
    section("books.cx  →  XML")
    println(CxLib.toXml(read("books.cx")))

    section("books.cx  →  JSON  (repeated elements auto-collect into arrays)")
    println(CxLib.toJson(read("books.cx")))

    // ── cross-format round-trips ──────────────────────────────────────────────
    section("books.xml   →  CX")
    println(CxLib.xmlToCx(read("books.xml")))

    section("books.json  →  CX")
    println(CxLib.jsonToCx(read("books.json")))

    section("config.yaml  →  CX")
    println(CxLib.yamlToCx(read("config.yaml")))

    section("config.toml  →  CX")
    println(CxLib.tomlToCx(read("config.toml")))

    // ── vcore.cx ─────────────────────────────────────────────────────────────
    section("vcore.cx  (source)")
    println(read("vcore.cx"))

    section("vcore.cx  →  CX  (short aliases expand; auto-array gains explicit :type[])")
    println(CxLib.toCx(read("vcore.cx")))

    section("vcore.cx  →  JSON  (auto-array, :[], triple-quoted, block content)")
    println(CxLib.toJson(read("vcore.cx")))

    section("vcore.cx  →  XML  (cx:type annotations; cx:block for block content)")
    println(CxLib.toXml(read("vcore.cx")))

    // ── doc.cx ───────────────────────────────────────────────────────────────
    section("doc.cx  (source)")
    println(read("doc.cx"))

    section("doc.cx  →  Markdown")
    println(CxLib.toMd(read("doc.cx")))

    section("doc.cx  →  XML")
    println(CxLib.toXml(read("doc.cx")))

    // ── doc.md ───────────────────────────────────────────────────────────────
    section("doc.md  (source)")
    println(read("doc.md"))

    section("doc.md  →  CX")
    println(CxLib.mdToCx(read("doc.md")))

    // ── chapter.cx: XML-style structured document ────────────────────────────
    section("chapter.cx  (source)")
    println(read("chapter.cx"))

    section("chapter.cx  →  CX  (canonical)")
    println(CxLib.toCx(read("chapter.cx")))

    section("chapter.cx  →  XML  (structured document with sections and table)")
    println(CxLib.toXml(read("chapter.cx")))

    section("chapter.cx  →  JSON  (nested sections as nested objects)")
    println(CxLib.toJson(read("chapter.cx")))

    // ── post.cx: Markdown-style blog post ────────────────────────────────────
    section("post.cx  (source)")
    println(read("post.cx"))

    section("post.cx  →  Markdown  (CX markdown dialect → rendered Markdown)")
    println(CxLib.toMd(read("post.cx")))

    section("post.cx  →  CX  (canonical)")
    println(CxLib.toCx(read("post.cx")))

    // ── AST inspection ────────────────────────────────────────────────────────
    section("article.cx  →  AST  →  CX  (round-trip: AST JSON back to canonical CX)")
    println(CxLib.astToCx(CxLib.toAst(read("article.cx"))))

    section("article.cx  →  CX  (compact)")
    println(CxLib.toCxCompact(read("article.cx")))

    // ── Document API ──────────────────────────────────────────────────────────
    section("Document API: CXPath select")
    val svcSrc = """[services
  [service name=auth  port=8080 active=true]
  [service name=api   port=9000 active=false]
  [service name=web   port=80   active=true]
]"""
    val svcDoc = CXDocument.parse(svcSrc)
    val first = svcDoc.select("//service")
    println("first service: ${first?.attr("name")}")
    svcDoc.selectAll("//service[@active=true]").forEach { svc -> println("active: ${svc.attr("name")}") }

    section("Document API: transform (immutable update)")
    val updated = svcDoc.transform("services/service") { el -> el.setAttr("name", "renamed-auth"); el }
    println(updated.toCx())

    section("Document API: transform_all")
    val allActive = svcDoc.transformAll("//service") { el -> el.setAttr("active", true); el }
    println("active services after transform_all: ${allActive.selectAll("//service[@active=true]").size}")
}
