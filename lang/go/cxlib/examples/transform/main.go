// CX transform examples — demonstrates the Go cxlib wrapper around libcx.
//
// Run from repo root:
//
//	cd lang/go/cxlib && go run ./examples/transform/
package main

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"

	cxlib "github.com/ardec/cx/lang/go"
)

var examplesDir string

func init() {
	_, file, _, _ := runtime.Caller(0)
	// file is lang/go/cxlib/examples/transform/main.go; repo root is ../../../../../
	examplesDir = filepath.Join(filepath.Dir(file), "..", "..", "..", "..", "..", "examples")
}

func read(name string) string {
	data, err := os.ReadFile(filepath.Join(examplesDir, name))
	if err != nil {
		panic(err)
	}
	return string(data)
}

func section(title string) {
	fmt.Printf("\n%s\n  %s\n%s\n", strings.Repeat("─", 60), title, strings.Repeat("─", 60))
}

func must(s string, err error) string {
	if err != nil {
		panic(err)
	}
	return s
}

func main() {
	// ── article.cx ───────────────────────────────────────────────────────────
	section("article.cx  (source)")
	fmt.Println(read("article.cx"))

	section("article.cx  →  CX  (canonical round-trip)")
	fmt.Println(must(cxlib.ToCx(read("article.cx"))))

	section("article.cx  →  XML")
	fmt.Println(must(cxlib.ToXml(read("article.cx"))))

	section("article.cx  →  JSON  (mixed content uses '_' for text runs)")
	fmt.Println(must(cxlib.ToJson(read("article.cx"))))

	section("article.cx  →  YAML")
	fmt.Println(must(cxlib.ToYaml(read("article.cx"))))

	// ── env.cx ───────────────────────────────────────────────────────────────
	section("env.cx  (source)")
	fmt.Println(read("env.cx"))

	section("env.cx  →  CX  (canonical round-trip)")
	fmt.Println(must(cxlib.ToCx(read("env.cx"))))

	section("env.cx  →  XML  (anchor/merge as cx:anchor / cx:merge attrs)")
	fmt.Println(must(cxlib.ToXml(read("env.cx"))))

	section("env.cx  →  JSON")
	fmt.Println(must(cxlib.ToJson(read("env.cx"))))

	section("env.cx  →  YAML")
	fmt.Println(must(cxlib.ToYaml(read("env.cx"))))

	section("env.cx  →  TOML")
	fmt.Println(must(cxlib.ToToml(read("env.cx"))))

	// ── config.cx ────────────────────────────────────────────────────────────
	section("config.cx  →  JSON")
	fmt.Println(must(cxlib.ToJson(read("config.cx"))))

	section("config.cx  →  YAML")
	fmt.Println(must(cxlib.ToYaml(read("config.cx"))))

	section("config.cx  →  TOML")
	fmt.Println(must(cxlib.ToToml(read("config.cx"))))

	// ── books.cx ─────────────────────────────────────────────────────────────
	section("books.cx  →  XML")
	fmt.Println(must(cxlib.ToXml(read("books.cx"))))

	section("books.cx  →  JSON  (repeated elements auto-collect into arrays)")
	fmt.Println(must(cxlib.ToJson(read("books.cx"))))

	// ── cross-format round-trips ──────────────────────────────────────────────
	section("books.xml   →  CX")
	fmt.Println(must(cxlib.XmlToCx(read("books.xml"))))

	section("books.json  →  CX")
	fmt.Println(must(cxlib.JsonToCx(read("books.json"))))

	section("config.yaml  →  CX")
	fmt.Println(must(cxlib.YamlToCx(read("config.yaml"))))

	section("config.toml  →  CX")
	fmt.Println(must(cxlib.TomlToCx(read("config.toml"))))

	// ── vcore.cx ─────────────────────────────────────────────────────────────
	section("vcore.cx  (source)")
	fmt.Println(read("vcore.cx"))

	section("vcore.cx  →  CX  (short aliases expand; auto-array gains explicit :type[])")
	fmt.Println(must(cxlib.ToCx(read("vcore.cx"))))

	section("vcore.cx  →  JSON  (auto-array, :[], triple-quoted, block content)")
	fmt.Println(must(cxlib.ToJson(read("vcore.cx"))))

	section("vcore.cx  →  XML  (cx:type annotations; cx:block for block content)")
	fmt.Println(must(cxlib.ToXml(read("vcore.cx"))))

	// ── doc.cx ───────────────────────────────────────────────────────────────
	section("doc.cx  (source)")
	fmt.Println(read("doc.cx"))

	section("doc.cx  →  Markdown")
	fmt.Println(must(cxlib.ToMd(read("doc.cx"))))

	section("doc.cx  →  XML")
	fmt.Println(must(cxlib.ToXml(read("doc.cx"))))

	// ── doc.md ───────────────────────────────────────────────────────────────
	section("doc.md  (source)")
	fmt.Println(read("doc.md"))

	section("doc.md  →  CX")
	fmt.Println(must(cxlib.MdToCx(read("doc.md"))))

	// ── chapter.cx: XML-style structured document ────────────────────────────
	section("chapter.cx  (source)")
	fmt.Println(read("chapter.cx"))

	section("chapter.cx  →  CX  (canonical)")
	fmt.Println(must(cxlib.ToCx(read("chapter.cx"))))

	section("chapter.cx  →  XML  (structured document with sections and table)")
	fmt.Println(must(cxlib.ToXml(read("chapter.cx"))))

	section("chapter.cx  →  JSON  (nested sections as nested objects)")
	fmt.Println(must(cxlib.ToJson(read("chapter.cx"))))

	// ── post.cx: Markdown-style blog post ────────────────────────────────────
	section("post.cx  (source)")
	fmt.Println(read("post.cx"))

	section("post.cx  →  Markdown  (CX markdown dialect → rendered Markdown)")
	fmt.Println(must(cxlib.ToMd(read("post.cx"))))

	section("post.cx  →  CX  (canonical)")
	fmt.Println(must(cxlib.ToCx(read("post.cx"))))

	// ── AST inspection ────────────────────────────────────────────────────────
	section("article.cx  →  AST  →  CX  (round-trip: AST JSON back to canonical CX)")
	fmt.Println(must(cxlib.AstToCx(must(cxlib.ToAst(read("article.cx"))))))

	section("article.cx  →  CX  (compact)")
	fmt.Println(must(cxlib.ToCxCompact(read("article.cx"))))

	// ── Document API ──────────────────────────────────────────────────────────
	const servicesSrc = `[services
  [service name=auth  port=8080 active=true]
  [service name=api   port=9000 active=false]
  [service name=web   port=80   active=true]
]`

	section("Document API: CXPath select")
	doc, err := cxlib.Parse(servicesSrc)
	if err != nil {
		panic(err)
	}
	first, err := doc.Select("//service")
	if err != nil {
		panic(err)
	}
	fmt.Printf("first service: %v\n", first.Attr("name"))
	actives, err := doc.SelectAll("//service[@active=true]")
	if err != nil {
		panic(err)
	}
	for _, svc := range actives {
		fmt.Printf("active service: %v\n", svc.Attr("name"))
	}

	section("Document API: transform (immutable update)")
	updated := doc.Transform("services/service", func(el *cxlib.Element) *cxlib.Element {
		el.SetAttr("name", "renamed-auth", "")
		return el
	})
	fmt.Println(updated.ToCx())

	section("Document API: transform_all")
	allActive, err := doc.TransformAll("//service", func(el *cxlib.Element) *cxlib.Element {
		el.SetAttr("active", true, "")
		return el
	})
	if err != nil {
		panic(err)
	}
	allServices, err := allActive.SelectAll("//service[@active=true]")
	if err != nil {
		panic(err)
	}
	fmt.Printf("active services after transform_all: %d\n", len(allServices))
}
