# CX — Neovim Setup

Syntax highlighting (tree-sitter) and LSP completions for `.cx` files.

**Requirements:** Neovim ≥ 0.11, Node.js ≥ 18, a C compiler, `tree-sitter` CLI

---

## 1 — Install the parser and queries (one time)

```sh
cd tooling/tree-sitter-cx
make install-nvim
```

This compiles the grammar and copies the parser and query files to
`~/.local/share/nvim/site/`, where Neovim finds them automatically.

Re-run after any grammar change.

---

## 2 — Install the Neovim plugin

Copy `tooling/neovim/cx.lua` into your Neovim plugin directory:

**lazy.nvim / LazyVim:**
```sh
cp tooling/neovim/cx.lua ~/.config/nvim/lua/plugins/cx.lua
```

**Plain init.lua:**
```lua
-- in your init.lua
dofile('/path/to/cx-repo/tooling/neovim/cx.lua')
```

---

## 3 — Build and install the language server

```sh
make build-lsp
mkdir -p ~/.local/share/cx-lsp
cp -r tooling/lsp/out tooling/lsp/node_modules ~/.local/share/cx-lsp/
```

---

## What you get

| Feature | Notes |
|---|---|
| Syntax highlighting | Tree-sitter — element names, attributes, headings H1–H6, bold/italic/etc. |
| Embedded languages | JSON, YAML, Python, Bash, JS/TS, Rust, Go, SQL, CSS, HTML, XML inside `[``` lang=X [| … |] ]` blocks |
| LSP completions | `:type` annotations, element names, `true`/`false`/`null` |
| LSP hover / diagnostics | Via cx-ls language server |

---

## Fallback: Vim-regex highlighting (no tree-sitter)

Works without tree-sitter — no embedded language injection.

```sh
# Manual
cp -r tooling/neovim/syntax   ~/.config/nvim/
cp -r tooling/neovim/ftdetect ~/.config/nvim/

# lazy.nvim local plugin
{ dir = '/path/to/cx-repo/tooling/neovim' }
```

---

## Troubleshooting

**No highlighting after install:**
Restart Neovim. Run `:lua print(vim.treesitter.language.inspect("cx"))` — if it errors, the parser isn't installed. Re-run `make install-nvim`.

**LSP not starting:**
Check the server exists: `ls ~/.local/share/cx-lsp/out/server.js`

**Highlighting broke after grammar change:**
Re-run `make install-nvim` and restart Neovim.
