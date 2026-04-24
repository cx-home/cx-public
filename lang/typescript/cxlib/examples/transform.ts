/**
 * CX transform examples — demonstrates the TypeScript cxlib wrapper around libcx.
 *
 * Run from repo root:
 *   cd typescript/cxlib && npm run example
 */
import * as cx from '../src/index';
import * as fs from 'fs';
import * as path from 'path';

const EXAMPLES = path.resolve(__dirname, '..', '..', '..', '..', 'examples');

function read(name: string): string {
  return fs.readFileSync(path.join(EXAMPLES, name), 'utf8');
}

function section(title: string): void {
  console.log(`\n${'─'.repeat(60)}`);
  console.log(`  ${title}`);
  console.log('─'.repeat(60));
}

// ── article.cx ────────────────────────────────────────────────────────────────

section('article.cx  (source)');
console.log(read('article.cx'));

section('article.cx  →  CX  (canonical round-trip)');
console.log(cx.toCx(read('article.cx')));

section('article.cx  →  XML');
console.log(cx.toXml(read('article.cx')));

section("article.cx  →  JSON  (mixed content uses '_' for text runs)");
console.log(cx.toJson(read('article.cx')));

section('article.cx  →  YAML');
console.log(cx.toYaml(read('article.cx')));

// ── env.cx ────────────────────────────────────────────────────────────────────

section('env.cx  (source)');
console.log(read('env.cx'));

section('env.cx  →  CX  (canonical round-trip)');
console.log(cx.toCx(read('env.cx')));

section('env.cx  →  XML  (anchor/merge as cx:anchor / cx:merge attrs)');
console.log(cx.toXml(read('env.cx')));

section('env.cx  →  JSON');
console.log(cx.toJson(read('env.cx')));

section('env.cx  →  YAML');
console.log(cx.toYaml(read('env.cx')));

section('env.cx  →  TOML');
console.log(cx.toToml(read('env.cx')));

// ── config.cx ─────────────────────────────────────────────────────────────────

section('config.cx  →  JSON');
console.log(cx.toJson(read('config.cx')));

section('config.cx  →  YAML');
console.log(cx.toYaml(read('config.cx')));

section('config.cx  →  TOML');
console.log(cx.toToml(read('config.cx')));

// ── books.cx ──────────────────────────────────────────────────────────────────

section('books.cx  →  XML');
console.log(cx.toXml(read('books.cx')));

section('books.cx  →  JSON  (repeated elements auto-collect into arrays)');
console.log(cx.toJson(read('books.cx')));

// ── cross-format round-trips ──────────────────────────────────────────────────

section('books.xml   →  CX');
console.log(cx.xmlToCx(read('books.xml')));

section('books.json  →  CX');
console.log(cx.jsonToCx(read('books.json')));

section('config.yaml  →  CX');
console.log(cx.yamlToCx(read('config.yaml')));

section('config.toml  →  CX');
console.log(cx.tomlToCx(read('config.toml')));

// ── vcore.cx ──────────────────────────────────────────────────────────────────

section('vcore.cx  (source)');
console.log(read('vcore.cx'));

section('vcore.cx  →  CX  (short aliases expand; auto-array gains explicit :type[])');
console.log(cx.toCx(read('vcore.cx')));

section('vcore.cx  →  JSON  (auto-array, :[], triple-quoted, block content)');
console.log(cx.toJson(read('vcore.cx')));

section('vcore.cx  →  XML  (cx:type annotations; cx:block for block content)');
console.log(cx.toXml(read('vcore.cx')));

// ── doc.cx ────────────────────────────────────────────────────────────────────

section('doc.cx  (source)');
console.log(read('doc.cx'));

section('doc.cx  →  Markdown');
console.log(cx.toMd(read('doc.cx')));

section('doc.cx  →  XML');
console.log(cx.toXml(read('doc.cx')));

// ── doc.md ────────────────────────────────────────────────────────────────────

section('doc.md  (source)');
console.log(read('doc.md'));

section('doc.md  →  CX');
console.log(cx.mdToCx(read('doc.md')));

// ── AST inspection ────────────────────────────────────────────────────────────

// ── chapter.cx: XML-style structured document ────────────────────────────────

section('chapter.cx  (source)');
console.log(read('chapter.cx'));

section('chapter.cx  →  CX  (canonical)');
console.log(cx.toCx(read('chapter.cx')));

section('chapter.cx  →  XML  (structured document with sections and table)');
console.log(cx.toXml(read('chapter.cx')));

section('chapter.cx  →  JSON  (nested sections as nested objects)');
console.log(cx.toJson(read('chapter.cx')));

// ── post.cx: Markdown-style blog post ────────────────────────────────────────

section('post.cx  (source)');
console.log(read('post.cx'));

section('post.cx  →  Markdown  (CX markdown dialect → rendered Markdown)');
console.log(cx.toMd(read('post.cx')));

section('post.cx  →  CX  (canonical)');
console.log(cx.toCx(read('post.cx')));

section("article.cx  →  AST  →  CX  (round-trip: AST JSON back to canonical CX)");
console.log(cx.astToCx(cx.toAst(read('article.cx'))));

section("article.cx  →  CX  (compact)");
console.log(cx.toCxCompact(read('article.cx')));

// ── Document API ──────────────────────────────────────────────────────────────

const svcSrc = `[services
  [service name=auth  port=8080 active=true]
  [service name=api   port=9000 active=false]
  [service name=web   port=80   active=true]
]`;

section('Document API: CXPath select');
const svcDoc = cx.parse(svcSrc);
const first = svcDoc.select('//service');
console.log(`first service: ${first?.attr('name')}`);
for (const svc of svcDoc.selectAll('//service[@active=true]')) {
  console.log(`active: ${svc.attr('name')}`);
}

section('Document API: transform (immutable update)');
const updated = svcDoc.transform('services/service', el => { el.setAttr('name', 'renamed-auth'); return el; });
console.log(updated.toCx());

section('Document API: transform_all');
const allActive = svcDoc.transformAll('//service', el => { el.setAttr('active', true); return el; });
console.log(`active services after transform_all: ${allActive.selectAll('//service[@active=true]').length}`);
