// CX transform examples — demonstrates the Swift CXLib wrapper around libcx.
//
// Run: swift run --package-path swift/cxlib transform
import CXLib
import Foundation

// Locate examples/ relative to the repo root (Package.swift is at swift/cxlib/)
let repoRoot: URL = {
    var url = URL(fileURLWithPath: #file)  // Examples/transform/main.swift
    // Go up: transform -> Examples -> swift/cxlib -> swift -> repo root
    for _ in 0..<4 { url.deleteLastPathComponent() }
    return url
}()

let examplesDir = repoRoot.appendingPathComponent("examples")

func read(_ name: String) -> String {
    let url = examplesDir.appendingPathComponent(name)
    return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
}

func section(_ title: String) {
    print("\n" + String(repeating: "─", count: 60))
    print("  \(title)")
    print(String(repeating: "─", count: 60))
}

func must<T>(_ fn: () throws -> T) -> T {
    do { return try fn() }
    catch { fatalError("\(error)") }
}

// ── article.cx ───────────────────────────────────────────────────────────────
section("article.cx  (source)")
print(read("article.cx"))

section("article.cx  →  CX  (canonical round-trip)")
print(must { try toCx(read("article.cx")) })

section("article.cx  →  XML")
print(must { try toXml(read("article.cx")) })

section("article.cx  →  JSON  (mixed content uses '_' for text runs)")
print(must { try toJson(read("article.cx")) })

section("article.cx  →  YAML")
print(must { try toYaml(read("article.cx")) })

// ── env.cx ───────────────────────────────────────────────────────────────────
section("env.cx  (source)")
print(read("env.cx"))

section("env.cx  →  CX  (canonical round-trip)")
print(must { try toCx(read("env.cx")) })

section("env.cx  →  XML  (anchor/merge as cx:anchor / cx:merge attrs)")
print(must { try toXml(read("env.cx")) })

section("env.cx  →  JSON")
print(must { try toJson(read("env.cx")) })

section("env.cx  →  YAML")
print(must { try toYaml(read("env.cx")) })

section("env.cx  →  TOML")
print(must { try toToml(read("env.cx")) })

// ── config.cx ─────────────────────────────────────────────────────────────────
section("config.cx  →  JSON")
print(must { try toJson(read("config.cx")) })

section("config.cx  →  YAML")
print(must { try toYaml(read("config.cx")) })

section("config.cx  →  TOML")
print(must { try toToml(read("config.cx")) })

// ── books.cx ──────────────────────────────────────────────────────────────────
section("books.cx  →  XML")
print(must { try toXml(read("books.cx")) })

section("books.cx  →  JSON  (repeated elements auto-collect into arrays)")
print(must { try toJson(read("books.cx")) })

// ── cross-format round-trips ──────────────────────────────────────────────────
section("books.xml   →  CX")
print(must { try xmlToCx(read("books.xml")) })

section("books.json  →  CX")
print(must { try jsonToCx(read("books.json")) })

section("config.yaml  →  CX")
print(must { try yamlToCx(read("config.yaml")) })

section("config.toml  →  CX")
print(must { try tomlToCx(read("config.toml")) })

// ── vcore.cx ──────────────────────────────────────────────────────────────────
section("vcore.cx  (source)")
print(read("vcore.cx"))

section("vcore.cx  →  CX  (short aliases expand; auto-array gains explicit :type[])")
print(must { try toCx(read("vcore.cx")) })

section("vcore.cx  →  JSON  (auto-array, :[], triple-quoted, block content)")
print(must { try toJson(read("vcore.cx")) })

section("vcore.cx  →  XML  (cx:type annotations; cx:block for block content)")
print(must { try toXml(read("vcore.cx")) })

// ── doc.cx ────────────────────────────────────────────────────────────────────
section("doc.cx  (source)")
print(read("doc.cx"))

section("doc.cx  →  Markdown")
print(must { try toMd(read("doc.cx")) })

section("doc.cx  →  XML")
print(must { try toXml(read("doc.cx")) })

// ── doc.md ────────────────────────────────────────────────────────────────────
section("doc.md  (source)")
print(read("doc.md"))

section("doc.md  →  CX")
print(must { try mdToCx(read("doc.md")) })

// ── chapter.cx: XML-style structured document ────────────────────────────────
section("chapter.cx  (source)")
print(read("chapter.cx"))

section("chapter.cx  →  CX  (canonical)")
print(try! CXLib.toCx(read("chapter.cx")))

section("chapter.cx  →  XML  (structured document with sections and table)")
print(try! CXLib.toXml(read("chapter.cx")))

section("chapter.cx  →  JSON  (nested sections as nested objects)")
print(try! CXLib.toJson(read("chapter.cx")))

// ── post.cx: Markdown-style blog post ────────────────────────────────────────
section("post.cx  (source)")
print(read("post.cx"))

section("post.cx  →  Markdown  (CX markdown dialect → rendered Markdown)")
print(try! CXLib.toMd(read("post.cx")))

section("post.cx  →  CX  (canonical)")
print(try! CXLib.toCx(read("post.cx")))

// ── AST inspection ────────────────────────────────────────────────────────────
section("article.cx  →  AST  →  CX  (round-trip: AST JSON back to canonical CX)")
print(must { try astToCx(toAst(read("article.cx"))) })

section("article.cx  →  CX  (compact)")
print(must { try toCxCompact(read("article.cx")) })
