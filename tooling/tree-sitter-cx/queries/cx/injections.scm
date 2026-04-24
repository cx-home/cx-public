; Use @injection.language to capture the lang name directly from the tree.
; Neovim maps the node text (e.g. "json", "bash") to the parser language.
((code_block
   (lang_attr lang: (lang_name) @injection.language)
   (block_content (block_body) @injection.content))
 (#set! injection.include-children))
