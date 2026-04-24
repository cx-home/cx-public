# CX Editor Tooling

Syntax highlighting and completions for `.cx` files in VS Code and Neovim.

```
tooling/
  lsp/          TypeScript language server (completions)
  vscode/       VS Code extension (grammar + LSP client)
  neovim/       Neovim setup (cx.lua + README)
```

## Quick start

### Build

```sh
make build-lsp       # compile the language server
make build-vscode    # package the VS Code extension (.vsix)
make build-editors   # both
```

### VS Code

**Build and install:**

```sh
make build-vscode
code --install-extension tooling/vscode/cx-language-0.1.0.vsix
```

Reload VS Code when prompted, then open any `.cx` file — syntax highlighting and completions activate automatically.

**Manual install (UI):** Extensions sidebar → `⋯` menu (top-right) → *Install from VSIX…* → pick `tooling/vscode/cx-language-0.1.0.vsix`.

**Optional — point at a custom server binary** (only needed if running the server from a non-default location):

```json
// settings.json
"cx.languageServerPath": "/absolute/path/to/tooling/lsp/out/server.js"
```

### Neovim

See [neovim/README.md](neovim/README.md) for full setup instructions.

Short version:

```sh
make build-lsp
mkdir -p ~/.local/share/cx-lsp
cp -r tooling/lsp/out tooling/lsp/node_modules ~/.local/share/cx-lsp/
```

Then paste the setup block from [neovim/README.md](neovim/README.md) into your `init.lua`.

## Completions provided

| Trigger | Completions |
|---|---|
| `:` | `:int` `:float` `:bool` `:string` `:null` `:int[]` `:float[]` `:bool[]` `:string[]` `:[]` |
| `[` | element names found in the current document |
| `=` | `true` `false` `null` |
