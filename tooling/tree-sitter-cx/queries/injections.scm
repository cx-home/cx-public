; Inject embedded language parsers into [``` lang=X [| … |] ] blocks.
; The lang_name node carries the language identifier.
; The block_content inside the code_block carries the actual code.

((code_block
   (lang_attr lang: (lang_name) @_lang)
   (block_content) @injection.content)
 (#match? @_lang "^(json|JSON)$")
 (#set! injection.language "json"))

((code_block
   (lang_attr lang: (lang_name) @_lang)
   (block_content) @injection.content)
 (#match? @_lang "^(xml|XML)$")
 (#set! injection.language "xml"))

((code_block
   (lang_attr lang: (lang_name) @_lang)
   (block_content) @injection.content)
 (#match? @_lang "^(html|HTML)$")
 (#set! injection.language "html"))

((code_block
   (lang_attr lang: (lang_name) @_lang)
   (block_content) @injection.content)
 (#match? @_lang "^(css|CSS)$")
 (#set! injection.language "css"))

((code_block
   (lang_attr lang: (lang_name) @_lang)
   (block_content) @injection.content)
 (#match? @_lang "^(js|javascript|JavaScript|JS)$")
 (#set! injection.language "javascript"))

((code_block
   (lang_attr lang: (lang_name) @_lang)
   (block_content) @injection.content)
 (#match? @_lang "^(ts|typescript|TypeScript|TS)$")
 (#set! injection.language "typescript"))

((code_block
   (lang_attr lang: (lang_name) @_lang)
   (block_content) @injection.content)
 (#match? @_lang "^(py|python|Python)$")
 (#set! injection.language "python"))

((code_block
   (lang_attr lang: (lang_name) @_lang)
   (block_content) @injection.content)
 (#match? @_lang "^(sh|bash|shell|Bash|Shell)$")
 (#set! injection.language "bash"))

((code_block
   (lang_attr lang: (lang_name) @_lang)
   (block_content) @injection.content)
 (#match? @_lang "^(sql|SQL)$")
 (#set! injection.language "sql"))

((code_block
   (lang_attr lang: (lang_name) @_lang)
   (block_content) @injection.content)
 (#match? @_lang "^(yaml|yml|YAML)$")
 (#set! injection.language "yaml"))

((code_block
   (lang_attr lang: (lang_name) @_lang)
   (block_content) @injection.content)
 (#match? @_lang "^(toml|TOML)$")
 (#set! injection.language "toml"))

((code_block
   (lang_attr lang: (lang_name) @_lang)
   (block_content) @injection.content)
 (#match? @_lang "^(rust|Rust|rs)$")
 (#set! injection.language "rust"))

((code_block
   (lang_attr lang: (lang_name) @_lang)
   (block_content) @injection.content)
 (#match? @_lang "^(go|Go)$")
 (#set! injection.language "go"))

((code_block
   (lang_attr lang: (lang_name) @_lang)
   (block_content) @injection.content)
 (#match? @_lang "^(cx|CX)$")
 (#set! injection.language "cx"))
