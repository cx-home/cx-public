// CX transform examples — demonstrates the C# CxLib wrapper around libcx.
// Run: DOTNET_ROOT=/opt/homebrew/opt/dotnet/libexec dotnet run --project csharp/examples/transform/transform.csproj
using System;
using System.IO;
using CX;

string FindExamples()
{
    var dir = new DirectoryInfo(AppContext.BaseDirectory);
    while (dir != null)
    {
        var candidate = Path.Combine(dir.FullName, "examples");
        if (Directory.Exists(candidate)) return candidate;
        dir = dir.Parent;
    }
    throw new DirectoryNotFoundException("Cannot find examples/ directory");
}

var EXAMPLES = FindExamples();
string Read(string name) => File.ReadAllText(Path.Combine(EXAMPLES, name));

void Section(string title)
{
    Console.WriteLine();
    Console.WriteLine(new string('─', 60));
    Console.WriteLine($"  {title}");
    Console.WriteLine(new string('─', 60));
}

// ── article.cx ───────────────────────────────────────────────────────────────
Section("article.cx  (source)");
Console.WriteLine(Read("article.cx"));

Section("article.cx  →  CX  (canonical round-trip)");
Console.WriteLine(CxLib.ToCx(Read("article.cx")));

Section("article.cx  →  XML");
Console.WriteLine(CxLib.ToXml(Read("article.cx")));

Section("article.cx  →  JSON  (mixed content uses '_' for text runs)");
Console.WriteLine(CxLib.ToJson(Read("article.cx")));

Section("article.cx  →  YAML");
Console.WriteLine(CxLib.ToYaml(Read("article.cx")));

// ── env.cx ───────────────────────────────────────────────────────────────────
Section("env.cx  (source)");
Console.WriteLine(Read("env.cx"));

Section("env.cx  →  CX  (canonical round-trip)");
Console.WriteLine(CxLib.ToCx(Read("env.cx")));

Section("env.cx  →  XML  (anchor/merge as cx:anchor / cx:merge attrs)");
Console.WriteLine(CxLib.ToXml(Read("env.cx")));

Section("env.cx  →  JSON");
Console.WriteLine(CxLib.ToJson(Read("env.cx")));

Section("env.cx  →  YAML");
Console.WriteLine(CxLib.ToYaml(Read("env.cx")));

Section("env.cx  →  TOML");
Console.WriteLine(CxLib.ToToml(Read("env.cx")));

// ── config.cx ─────────────────────────────────────────────────────────────────
Section("config.cx  →  JSON");
Console.WriteLine(CxLib.ToJson(Read("config.cx")));

Section("config.cx  →  YAML");
Console.WriteLine(CxLib.ToYaml(Read("config.cx")));

Section("config.cx  →  TOML");
Console.WriteLine(CxLib.ToToml(Read("config.cx")));

// ── books.cx ──────────────────────────────────────────────────────────────────
Section("books.cx  →  XML");
Console.WriteLine(CxLib.ToXml(Read("books.cx")));

Section("books.cx  →  JSON  (repeated elements auto-collect into arrays)");
Console.WriteLine(CxLib.ToJson(Read("books.cx")));

// ── cross-format round-trips ──────────────────────────────────────────────────
Section("books.xml   →  CX");
Console.WriteLine(CxLib.XmlToCx(Read("books.xml")));

Section("books.json  →  CX");
Console.WriteLine(CxLib.JsonToCx(Read("books.json")));

Section("config.yaml  →  CX");
Console.WriteLine(CxLib.YamlToCx(Read("config.yaml")));

Section("config.toml  →  CX");
Console.WriteLine(CxLib.TomlToCx(Read("config.toml")));

// ── vcore.cx ──────────────────────────────────────────────────────────────────
Section("vcore.cx  (source)");
Console.WriteLine(Read("vcore.cx"));

Section("vcore.cx  →  CX  (short aliases expand; auto-array gains explicit :type[])");
Console.WriteLine(CxLib.ToCx(Read("vcore.cx")));

Section("vcore.cx  →  JSON  (auto-array, :[], triple-quoted, block content)");
Console.WriteLine(CxLib.ToJson(Read("vcore.cx")));

Section("vcore.cx  →  XML  (cx:type annotations; cx:block for block content)");
Console.WriteLine(CxLib.ToXml(Read("vcore.cx")));

// ── doc.cx ────────────────────────────────────────────────────────────────────
Section("doc.cx  (source)");
Console.WriteLine(Read("doc.cx"));

Section("doc.cx  →  Markdown");
Console.WriteLine(CxLib.ToMd(Read("doc.cx")));

Section("doc.cx  →  XML");
Console.WriteLine(CxLib.ToXml(Read("doc.cx")));

// ── doc.md ────────────────────────────────────────────────────────────────────
Section("doc.md  (source)");
Console.WriteLine(Read("doc.md"));

Section("doc.md  →  CX");
Console.WriteLine(CxLib.MdToCx(Read("doc.md")));

// ── chapter.cx: XML-style structured document ────────────────────────────────
Section("chapter.cx  (source)");
Console.WriteLine(Read("chapter.cx"));

Section("chapter.cx  →  CX  (canonical)");
Console.WriteLine(CxLib.ToCx(Read("chapter.cx")));

Section("chapter.cx  →  XML  (structured document with sections and table)");
Console.WriteLine(CxLib.ToXml(Read("chapter.cx")));

Section("chapter.cx  →  JSON  (nested sections as nested objects)");
Console.WriteLine(CxLib.ToJson(Read("chapter.cx")));

// ── post.cx: Markdown-style blog post ────────────────────────────────────────
Section("post.cx  (source)");
Console.WriteLine(Read("post.cx"));

Section("post.cx  →  Markdown  (CX markdown dialect → rendered Markdown)");
Console.WriteLine(CxLib.ToMd(Read("post.cx")));

Section("post.cx  →  CX  (canonical)");
Console.WriteLine(CxLib.ToCx(Read("post.cx")));

// ── AST inspection ────────────────────────────────────────────────────────────
Section("article.cx  →  AST  →  CX  (round-trip: AST JSON back to canonical CX)");
Console.WriteLine(CxLib.AstToCx(CxLib.ToAst(Read("article.cx"))));

Section("article.cx  →  CX  (compact)");
Console.WriteLine(CxLib.ToCxCompact(Read("article.cx")));

// ── Document API ──────────────────────────────────────────────────────────────
Section("Document API: CXPath select");
var svcSrc = "[services\n  [service name=auth  port=8080 active=true]\n  [service name=api   port=9000 active=false]\n  [service name=web   port=80   active=true]\n]";
var svcDoc = CXDocument.Parse(svcSrc);
var first = svcDoc.Select("//service");
Console.WriteLine($"first service: {first?.Attr("name")}");
foreach (var svc in svcDoc.SelectAll("//service[@active=true]"))
    Console.WriteLine($"active: {svc.Attr("name")}");

Section("Document API: transform (immutable update)");
var updated = svcDoc.Transform("services/service", el => { el.SetAttr("name", "renamed-auth"); return el; });
Console.WriteLine(updated.ToCx());

Section("Document API: transform_all");
var allActive = svcDoc.TransformAll("//service", el => { el.SetAttr("active", true); return el; });
Console.WriteLine($"active services after transform_all: {allActive.SelectAll("//service[@active=true]").Count}");
