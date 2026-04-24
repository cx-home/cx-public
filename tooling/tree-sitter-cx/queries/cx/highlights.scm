; ── Element tags ─────────────────────────────────────────────────────────────
(element name: (tag_name) @function)

; ── Attributes ────────────────────────────────────────────────────────────────
(attribute name: (attr_name) @property)
(attribute "=" @operator)
(attribute value: (attr_value (quoted_string) @string))
(attribute value: (attr_value (unquoted_value) @string))
(attribute value: (attr_value (boolean) @boolean))
(attribute value: (attr_value (null_value) @constant.builtin))
(attribute value: (attr_value (number) @number))

; ── Type annotations ──────────────────────────────────────────────────────────
(type_annotation) @type

; ── Headings ──────────────────────────────────────────────────────────────────
((heading (heading_marker) @_m) @markup.heading.1
 (#eq? @_m "#"))

((heading (heading_marker) @_m) @markup.heading.2
 (#eq? @_m "##"))

((heading (heading_marker) @_m) @markup.heading.3
 (#eq? @_m "###"))

((heading (heading_marker) @_m) @markup.heading.4
 (#eq? @_m "####"))

((heading (heading_marker) @_m) @markup.heading.5
 (#eq? @_m "#####"))

((heading (heading_marker) @_m) @markup.heading.6
 (#eq? @_m "######"))

; The heading_marker punctuation itself
(heading (heading_marker) @punctuation.special)
(heading "[" @punctuation.special)
(heading "]" @punctuation.special)

; ── Inline markup ─────────────────────────────────────────────────────────────
(bold) @markup.strong
(bold "[" @punctuation.delimiter)
(bold "]" @punctuation.delimiter)

(italic) @markup.italic
(italic "[" @punctuation.delimiter)
(italic "]" @punctuation.delimiter)

(strike) @markup.strikethrough
(strike "[" @punctuation.delimiter)
(strike "]" @punctuation.delimiter)

(underline) @markup.underline
(underline "[" @punctuation.delimiter)
(underline "]" @punctuation.delimiter)

(subscript) @markup.italic
(subscript "[" @punctuation.delimiter)
(subscript "]" @punctuation.delimiter)

(superscript) @markup.italic
(superscript "[" @punctuation.delimiter)
(superscript "]" @punctuation.delimiter)

(inline_code) @markup.raw
(inline_code "[" @punctuation.delimiter)
(inline_code "]" @punctuation.delimiter)

(blockquote) @markup.quote
(blockquote "[" @punctuation.delimiter)
(blockquote "]" @punctuation.delimiter)

; ── Code blocks ───────────────────────────────────────────────────────────────
(code_block "[" @punctuation.special)
(code_block "```" @punctuation.special)
(code_block "]" @punctuation.special)
(lang_attr "lang" @keyword.directive)
(lang_attr ["=" ":"] @operator)
(lang_attr lang: (lang_name) @string.special)

; ── Block content and raw text ────────────────────────────────────────────────
; Highlight only the delimiters — injected language highlights the body.
(block_content "[" @punctuation.special)
(block_content "|]" @punctuation.special)
(raw_text) @markup.raw

; ── Comments ──────────────────────────────────────────────────────────────────
(comment) @comment

; ── PI ────────────────────────────────────────────────────────────────────────
(pi) @keyword.directive

; ── Alias ─────────────────────────────────────────────────────────────────────
(alias) @variable.member

; ── Scalars ───────────────────────────────────────────────────────────────────
(number) @number
(boolean) @boolean
(null_value) @constant.builtin
(quoted_string) @string
(triple_quoted) @string
(entity_ref) @string.special

; ── Element bracket punctuation ───────────────────────────────────────────────
(element "[" @punctuation.bracket)
(element "]" @punctuation.bracket)
