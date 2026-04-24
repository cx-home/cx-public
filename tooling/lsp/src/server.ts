#!/usr/bin/env node
import {
  createConnection,
  TextDocuments,
  ProposedFeatures,
  InitializeParams,
  CompletionItem,
  CompletionItemKind,
  TextDocumentPositionParams,
  TextDocumentSyncKind,
  InitializeResult,
} from 'vscode-languageserver/node';
import { TextDocument } from 'vscode-languageserver-textdocument';

const connection = createConnection(ProposedFeatures.all);
const documents = new TextDocuments(TextDocument);

// ── Type annotation suffixes ────────────────────────────────────────────────

const TYPE_COMPLETIONS: CompletionItem[] = [
  { label: ':int',      kind: CompletionItemKind.TypeParameter, detail: 'integer scalar' },
  { label: ':float',    kind: CompletionItemKind.TypeParameter, detail: 'float scalar' },
  { label: ':bool',     kind: CompletionItemKind.TypeParameter, detail: 'boolean scalar' },
  { label: ':string',   kind: CompletionItemKind.TypeParameter, detail: 'string scalar' },
  { label: ':null',     kind: CompletionItemKind.TypeParameter, detail: 'null scalar' },
  { label: ':int[]',    kind: CompletionItemKind.TypeParameter, detail: 'array of integers' },
  { label: ':float[]',  kind: CompletionItemKind.TypeParameter, detail: 'array of floats' },
  { label: ':bool[]',   kind: CompletionItemKind.TypeParameter, detail: 'array of booleans' },
  { label: ':string[]', kind: CompletionItemKind.TypeParameter, detail: 'array of strings' },
  { label: ':[]',       kind: CompletionItemKind.TypeParameter, detail: 'untyped array' },
].map((item, i) => ({ ...item, sortText: String(i).padStart(3, '0') }));

// ── Attribute value keywords ────────────────────────────────────────────────

const BOOL_COMPLETIONS: CompletionItem[] = [
  { label: 'true',  kind: CompletionItemKind.Value },
  { label: 'false', kind: CompletionItemKind.Value },
  { label: 'null',  kind: CompletionItemKind.Value },
];

// ── Extract element names from document text ────────────────────────────────

function extractElementNames(text: string): string[] {
  const seen = new Set<string>();
  // Match [name  or [name:type  at start of element
  const re = /\[([a-zA-Z_][\w.-]*)/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(text)) !== null) {
    seen.add(m[1]);
  }
  return Array.from(seen).sort();
}

// ── Determine trigger context at cursor ─────────────────────────────────────

interface Context {
  kind: 'type' | 'element' | 'value' | 'none';
  prefix: string;
}

function getContext(doc: TextDocument, pos: TextDocumentPositionParams['position']): Context {
  const text = doc.getText();
  const offset = doc.offsetAt(pos);
  const before = text.slice(0, offset);

  // After : — type annotation
  const typeMatch = before.match(/:([a-z\[\]]*)$/);
  if (typeMatch) {
    return { kind: 'type', prefix: typeMatch[1] };
  }

  // After [ — element name
  const elemMatch = before.match(/\[([a-zA-Z_][\w.-]*)$/);
  if (elemMatch) {
    return { kind: 'element', prefix: elemMatch[1] };
  }

  // Start of element (just after '[')
  if (before.match(/\[$/)) {
    return { kind: 'element', prefix: '' };
  }

  // After = — attribute value
  if (before.match(/=\s*$/)) {
    return { kind: 'value', prefix: '' };
  }

  return { kind: 'none', prefix: '' };
}

// ── LSP lifecycle ────────────────────────────────────────────────────────────

connection.onInitialize((_params: InitializeParams): InitializeResult => {
  return {
    capabilities: {
      textDocumentSync: TextDocumentSyncKind.Incremental,
      completionProvider: {
        triggerCharacters: [':', '[', '='],
        resolveProvider: false,
      },
    },
    serverInfo: { name: 'cx-language-server', version: '0.1.0' },
  };
});

connection.onCompletion((params: TextDocumentPositionParams): CompletionItem[] => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return [];

  const ctx = getContext(doc, params.position);

  if (ctx.kind === 'type') {
    return TYPE_COMPLETIONS.filter(c => c.label.startsWith(':' + ctx.prefix));
  }

  if (ctx.kind === 'element') {
    const names = extractElementNames(doc.getText());
    return names
      .filter(n => n.startsWith(ctx.prefix))
      .map(n => ({
        label: n,
        kind: CompletionItemKind.Field,
      }));
  }

  if (ctx.kind === 'value') {
    return BOOL_COMPLETIONS;
  }

  return [];
});

documents.listen(connection);
connection.listen();
