package cx.examples;

import cx.CxLib;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;

/**
 * CX transform examples — demonstrates the Java CxLib wrapper around libcx.
 *
 * Run: mvn -f java/cxlib/pom.xml exec:java -Dexec.mainClass=cx.examples.Transform
 */
public class Transform {

    // examples/ is at ../../examples relative to the java/cxlib project root
    private static final Path EXAMPLES = Paths.get("../../examples");

    static String read(String name) throws IOException {
        return new String(Files.readAllBytes(EXAMPLES.resolve(name)), StandardCharsets.UTF_8);
    }

    static void section(String title) {
        System.out.println("\n" + "─".repeat(60));
        System.out.println("  " + title);
        System.out.println("─".repeat(60));
    }

    public static void main(String[] args) throws IOException {
        // ── article.cx ───────────────────────────────────────────────────────
        section("article.cx  (source)");
        System.out.println(read("article.cx"));

        section("article.cx  →  CX  (canonical round-trip)");
        System.out.println(CxLib.toCx(read("article.cx")));

        section("article.cx  →  XML");
        System.out.println(CxLib.toXml(read("article.cx")));

        section("article.cx  →  JSON  (mixed content uses '_' for text runs)");
        System.out.println(CxLib.toJson(read("article.cx")));

        section("article.cx  →  YAML");
        System.out.println(CxLib.toYaml(read("article.cx")));

        // ── env.cx ───────────────────────────────────────────────────────────
        section("env.cx  (source)");
        System.out.println(read("env.cx"));

        section("env.cx  →  CX  (canonical round-trip)");
        System.out.println(CxLib.toCx(read("env.cx")));

        section("env.cx  →  XML  (anchor/merge as cx:anchor / cx:merge attrs)");
        System.out.println(CxLib.toXml(read("env.cx")));

        section("env.cx  →  JSON");
        System.out.println(CxLib.toJson(read("env.cx")));

        section("env.cx  →  YAML");
        System.out.println(CxLib.toYaml(read("env.cx")));

        section("env.cx  →  TOML");
        System.out.println(CxLib.toToml(read("env.cx")));

        // ── config.cx ────────────────────────────────────────────────────────
        section("config.cx  →  JSON");
        System.out.println(CxLib.toJson(read("config.cx")));

        section("config.cx  →  YAML");
        System.out.println(CxLib.toYaml(read("config.cx")));

        section("config.cx  →  TOML");
        System.out.println(CxLib.toToml(read("config.cx")));

        // ── books.cx ─────────────────────────────────────────────────────────
        section("books.cx  →  XML");
        System.out.println(CxLib.toXml(read("books.cx")));

        section("books.cx  →  JSON  (repeated elements auto-collect into arrays)");
        System.out.println(CxLib.toJson(read("books.cx")));

        // ── cross-format round-trips ──────────────────────────────────────────
        section("books.xml   →  CX");
        System.out.println(CxLib.xmlToCx(read("books.xml")));

        section("books.json  →  CX");
        System.out.println(CxLib.jsonToCx(read("books.json")));

        section("config.yaml  →  CX");
        System.out.println(CxLib.yamlToCx(read("config.yaml")));

        section("config.toml  →  CX");
        System.out.println(CxLib.tomlToCx(read("config.toml")));

        // ── vcore.cx ─────────────────────────────────────────────────────────
        section("vcore.cx  (source)");
        System.out.println(read("vcore.cx"));

        section("vcore.cx  →  CX  (short aliases expand; auto-array gains explicit :type[])");
        System.out.println(CxLib.toCx(read("vcore.cx")));

        section("vcore.cx  →  JSON  (auto-array, :[], triple-quoted, block content)");
        System.out.println(CxLib.toJson(read("vcore.cx")));

        section("vcore.cx  →  XML  (cx:type annotations; cx:block for block content)");
        System.out.println(CxLib.toXml(read("vcore.cx")));

        // ── doc.cx ───────────────────────────────────────────────────────────
        section("doc.cx  (source)");
        System.out.println(read("doc.cx"));

        section("doc.cx  →  Markdown");
        System.out.println(CxLib.toMd(read("doc.cx")));

        section("doc.cx  →  XML");
        System.out.println(CxLib.toXml(read("doc.cx")));

        // ── doc.md ───────────────────────────────────────────────────────────
        section("doc.md  (source)");
        System.out.println(read("doc.md"));

        section("doc.md  →  CX");
        System.out.println(CxLib.mdToCx(read("doc.md")));

        // ── chapter.cx: XML-style structured document ────────────────────────
        section("chapter.cx  (source)");
        System.out.println(read("chapter.cx"));

        section("chapter.cx  →  CX  (canonical)");
        System.out.println(CxLib.toCx(read("chapter.cx")));

        section("chapter.cx  →  XML  (structured document with sections and table)");
        System.out.println(CxLib.toXml(read("chapter.cx")));

        section("chapter.cx  →  JSON  (nested sections as nested objects)");
        System.out.println(CxLib.toJson(read("chapter.cx")));

        // ── post.cx: Markdown-style blog post ────────────────────────────────
        section("post.cx  (source)");
        System.out.println(read("post.cx"));

        section("post.cx  →  Markdown  (CX markdown dialect → rendered Markdown)");
        System.out.println(CxLib.toMd(read("post.cx")));

        section("post.cx  →  CX  (canonical)");
        System.out.println(CxLib.toCx(read("post.cx")));

        // ── AST inspection ────────────────────────────────────────────────────
        section("article.cx  →  AST  →  CX  (round-trip: AST JSON back to canonical CX)");
        System.out.println(CxLib.astToCx(CxLib.toAst(read("article.cx"))));

        section("article.cx  →  CX  (compact)");
        System.out.println(CxLib.toCxCompact(read("article.cx")));
    }
}
