use std::path::{Path, PathBuf};

fn examples_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent().unwrap()   // rustlang
        .parent().unwrap()   // repo root
        .join("examples")
}

fn read(name: &str) -> String {
    std::fs::read_to_string(examples_dir().join(name))
        .unwrap_or_else(|e| panic!("could not read {name}: {e}"))
}

fn section(title: &str) {
    println!("\n{}", "─".repeat(60));
    println!("  {title}");
    println!("{}", "─".repeat(60));
}

fn main() {
    println!("libcx {}", cxlib::version());

    // ── article.cx: comments, mixed content, raw text, entity refs ──────────
    section("article.cx  (source)");
    println!("{}", read("article.cx"));

    section("article.cx  →  CX  (canonical round-trip)");
    println!("{}", cxlib::to_cx(&read("article.cx")).unwrap());

    section("article.cx  →  XML");
    println!("{}", cxlib::to_xml(&read("article.cx")).unwrap());

    section("article.cx  →  JSON  (mixed content uses '_' for text runs)");
    println!("{}", cxlib::to_json(&read("article.cx")).unwrap());

    section("article.cx  →  YAML");
    println!("{}", cxlib::to_yaml(&read("article.cx")).unwrap());

    // ── env.cx: anchors, merges, comments ────────────────────────────────────
    section("env.cx  (source)");
    println!("{}", read("env.cx"));

    section("env.cx  →  CX  (canonical round-trip)");
    println!("{}", cxlib::to_cx(&read("env.cx")).unwrap());

    section("env.cx  →  XML  (anchor/merge as cx:anchor / cx:merge attrs)");
    println!("{}", cxlib::to_xml(&read("env.cx")).unwrap());

    section("env.cx  →  JSON");
    println!("{}", cxlib::to_json(&read("env.cx")).unwrap());

    section("env.cx  →  YAML");
    println!("{}", cxlib::to_yaml(&read("env.cx")).unwrap());

    section("env.cx  →  TOML");
    println!("{}", cxlib::to_toml(&read("env.cx")).unwrap());

    // ── config.cx: typed scalars, arrays ─────────────────────────────────────
    section("config.cx  →  JSON");
    println!("{}", cxlib::to_json(&read("config.cx")).unwrap());

    section("config.cx  →  YAML");
    println!("{}", cxlib::to_yaml(&read("config.cx")).unwrap());

    section("config.cx  →  TOML");
    println!("{}", cxlib::to_toml(&read("config.cx")).unwrap());

    // ── books.cx: repeated elements become arrays ─────────────────────────────
    section("books.cx  →  XML");
    println!("{}", cxlib::to_xml(&read("books.cx")).unwrap());

    section("books.cx  →  JSON  (repeated elements auto-collect into arrays)");
    println!("{}", cxlib::to_json(&read("books.cx")).unwrap());

    // ── cross-format round-trips ──────────────────────────────────────────────
    section("books.xml   →  CX");
    println!("{}", cxlib::xml_to_cx(&read("books.xml")).unwrap());

    section("books.json  →  CX");
    println!("{}", cxlib::json_to_cx(&read("books.json")).unwrap());

    section("config.yaml  →  CX");
    println!("{}", cxlib::yaml_to_cx(&read("config.yaml")).unwrap());

    section("config.toml  →  CX");
    println!("{}", cxlib::toml_to_cx(&read("config.toml")).unwrap());

    // ── vcore.cx: v3.3 features ───────────────────────────────────────────────
    section("vcore.cx  (source)");
    println!("{}", read("vcore.cx"));

    section("vcore.cx  →  CX  (short aliases expand; auto-array gains explicit :type[])");
    println!("{}", cxlib::to_cx(&read("vcore.cx")).unwrap());

    section("vcore.cx  →  JSON  (auto-array, :[], triple-quoted, block content)");
    println!("{}", cxlib::to_json(&read("vcore.cx")).unwrap());

    section("vcore.cx  →  XML  (cx:type annotations; cx:block for block content)");
    println!("{}", cxlib::to_xml(&read("vcore.cx")).unwrap());

    // ── doc.cx: MD dialect document ───────────────────────────────────────────
    section("doc.cx  (source)");
    println!("{}", read("doc.cx"));

    section("doc.cx  →  Markdown");
    println!("{}", cxlib::to_md(&read("doc.cx")).unwrap());

    section("doc.cx  →  XML");
    println!("{}", cxlib::to_xml(&read("doc.cx")).unwrap());

    // ── doc.md: Markdown → CX ─────────────────────────────────────────────────
    section("doc.md  (source)");
    println!("{}", read("doc.md"));

    section("doc.md  →  CX");
    println!("{}", cxlib::md_to_cx(&read("doc.md")).unwrap());

    // ── chapter.cx: XML-style structured document ────────────────────────────
    section("chapter.cx  (source)");
    println!("{}", read("chapter.cx"));

    section("chapter.cx  →  CX  (canonical)");
    println!("{}", cxlib::to_cx(&read("chapter.cx")).unwrap());

    section("chapter.cx  →  XML  (structured document with sections and table)");
    println!("{}", cxlib::to_xml(&read("chapter.cx")).unwrap());

    section("chapter.cx  →  JSON  (nested sections as nested objects)");
    println!("{}", cxlib::to_json(&read("chapter.cx")).unwrap());

    // ── post.cx: Markdown-style blog post ────────────────────────────────────
    section("post.cx  (source)");
    println!("{}", read("post.cx"));

    section("post.cx  →  Markdown  (CX markdown dialect → rendered Markdown)");
    println!("{}", cxlib::to_md(&read("post.cx")).unwrap());

    section("post.cx  →  CX  (canonical)");
    println!("{}", cxlib::to_cx(&read("post.cx")).unwrap());

    // ── AST inspection ────────────────────────────────────────────────────────
    section("article.cx  →  AST  →  CX  (round-trip: AST JSON back to canonical CX)");
    println!("{}", cxlib::ast_to_cx(&cxlib::to_ast(&read("article.cx")).unwrap()).unwrap());

    section("article.cx  →  CX  (compact)");
    println!("{}", cxlib::to_cx_compact(&read("article.cx")).unwrap());

    // ── error handling ────────────────────────────────────────────────────────
    section("error handling");
    match cxlib::to_json("[unclosed") {
        Ok(_)    => unreachable!(),
        Err(msg) => println!("parse error: {msg}"),
    }

    // ── Document API ──────────────────────────────────────────────────────────
    let src = r#"[services
  [service name=auth  port=8080 active=true]
  [service name=api   port=9000 active=false]
  [service name=web   port=80   active=true]
]"#;

    section("Document API: CXPath select");
    let doc = cxlib::parse(src).unwrap();
    let first = doc.select("//service").unwrap().unwrap();
    println!("first service: {:?}", first.attr("name"));
    let active = doc.select_all("//service[@active=true]").unwrap();
    for el in &active {
        println!("active service: {:?}", el.attr("name"));
    }

    section("Document API: transform (immutable update)");
    let doc = cxlib::parse(src).unwrap();
    let updated = doc.transform("services/service", |mut el| {
        el.set_attr("name", serde_json::Value::String("renamed-auth".to_string()), None);
        el
    });
    println!("{}", updated.to_cx());

    section("Document API: transform_all");
    let doc = cxlib::parse(src).unwrap();
    let result = doc.transform_all("//service", |mut el| {
        el.set_attr("active", serde_json::Value::Bool(true), None);
        el
    }).unwrap();
    let all_active = result.select_all("//service[@active=true]").unwrap();
    println!("active service count: {}", all_active.len());
}
