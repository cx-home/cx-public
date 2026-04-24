" cx.vim — Vim/Neovim syntax for CX markup/configuration
if exists("b:current_syntax") | finish | endif

syn case match

" ── Comments  [- … ] ──────────────────────────────────────────────────────────
syn match cxComment /\[-[^\]]*\]/

" ── Headings  [# …] through [###### …]  (must come before raw-text) ──────────
" Most-specific patterns first so [######] doesn't match as [#].
syn region cxH6 matchgroup=cxH6Mark start=/\[######\(\s\|\]\)/  end=/\]/ contains=cxBold,cxItalic,cxInlineCode,cxElement,cxString
syn region cxH5 matchgroup=cxH5Mark start=/\[#####\(\s\|\]\)/   end=/\]/ contains=cxBold,cxItalic,cxInlineCode,cxElement,cxString
syn region cxH4 matchgroup=cxH4Mark start=/\[####\(\s\|\]\)/    end=/\]/ contains=cxBold,cxItalic,cxInlineCode,cxElement,cxString
syn region cxH3 matchgroup=cxH3Mark start=/\[###\(\s\|\]\)/     end=/\]/ contains=cxBold,cxItalic,cxInlineCode,cxElement,cxString
syn region cxH2 matchgroup=cxH2Mark start=/\[##\(\s\|\]\)/      end=/\]/ contains=cxBold,cxItalic,cxInlineCode,cxElement,cxString
syn region cxH1 matchgroup=cxH1Mark start=/\[#\(\s\|\]\)/       end=/\]/ contains=cxBold,cxItalic,cxInlineCode,cxElement,cxString
" Alias for contains= lists
syn cluster cxHeadings contains=cxH1,cxH2,cxH3,cxH4,cxH5,cxH6

" ── Raw text  [# … #] ─────────────────────────────────────────────────────────
syn region cxRawText start=/\[#/ end=/#\]/

" ── Block content  [| … |] ────────────────────────────────────────────────────
syn region cxBlockContent start=/\[|/ end=/|\]/

" ── Triple-quoted  ''' … ''' ──────────────────────────────────────────────────
syn region cxTripleQuoted start=/'''/ end=/'''/

" ── Inline markup ─────────────────────────────────────────────────────────────
" bold must come before italic; strikethrough before subscript
syn region cxBold        matchgroup=cxMarkupTag start=/\[\*\*/             end=/\]/ contains=cxBold,cxItalic,cxInlineCode,cxElement
syn region cxItalic      matchgroup=cxMarkupTag start=/\[\*\ze[^a-zA-Z_*]/ end=/\]/ contains=cxBold,cxItalic,cxInlineCode,cxElement
syn region cxStrike      matchgroup=cxMarkupTag start=/\[~~/               end=/\]/ contains=cxBold,cxItalic
syn region cxSubscript   matchgroup=cxMarkupTag start=/\[~\ze[^~]/         end=/\]/ contains=cxBold,cxItalic
syn region cxSuperscript matchgroup=cxMarkupTag start=/\[\^/               end=/\]/ contains=cxBold,cxItalic
syn region cxUnderline   matchgroup=cxMarkupTag start=/\[__/               end=/\]/ contains=cxBold,cxItalic
syn region cxInlineCode  matchgroup=cxMarkupTag start=/\[`\ze[^`]/         end=/\]/

" ── Blockquote  [> …] ─────────────────────────────────────────────────────────
syn region cxBlockquote matchgroup=cxMarkupTag start=/\[>/ end=/\]/
  \ contains=cxBold,cxItalic,cxInlineCode,cxElement

" ── PI  [? … ] ────────────────────────────────────────────────────────────────
syn match cxPI /\[\?[^\]]*\]/

" ── Alias  [*name] ────────────────────────────────────────────────────────────
syn match cxAlias /\[\*[a-zA-Z_][a-zA-Z0-9._-]*\]/

" ── Type annotations  :int  :string[]  :[] ───────────────────────────────────
syn match cxTypeAnnotation /:\(int\|float\|bool\|string\|null\)\(\[\]\)\?/
syn match cxTypeAnnotation /:\(\[\]\)/

" ── Scalar values ─────────────────────────────────────────────────────────────
syn match   cxFloat   /-\?\b[0-9]\+\.[0-9]\+\([eE][+-]\?[0-9]\+\)\?\b/
syn match   cxInteger /-\?\b[0-9]\+\b/
syn keyword cxBoolean true false
syn keyword cxNull    null
syn region  cxString  start=/"/ skip=/\\./ end=/"/ contains=cxEscape
syn region  cxString  start=/'/ skip=/\\./ end=/'/ contains=cxEscape
syn match   cxEscape  /\\./ contained

" ── Entity references ─────────────────────────────────────────────────────────
syn match cxEntityRef /&[a-zA-Z][a-zA-Z0-9]*;\|&#[0-9]\+;\|&#x[0-9a-fA-F]\+;/

" ── Attributes  name=value  name="quoted value" ───────────────────────────────
syn match cxAttrName  /[a-zA-Z_][a-zA-Z0-9._-]*\ze\s*=/ contained
syn match cxAttrEq    /=/ contained
syn match cxAttrValue /\("[^"]*"\|'[^']*'\|[^\s\]]\+\)/ contained
syn match cxAttribute
  \ /[a-zA-Z_][a-zA-Z0-9._-]*\s*=\s*\("[^"]*"\|'[^']*'\|[^\s\]]*\)/
  \ contains=cxAttrName,cxAttrEq,cxAttrValue

" ── Embedded-language code blocks  [``` lang=LANG [| … |] ] ──────────────────
" Helper: load a runtime syntax file into a cluster, then define the two regions.
" Usage: call s:EmbedLang('JSON', 'json', 'json')
"        call s:EmbedLang('Bash', '\(bash\|sh\|shell\)', 'sh')
function! s:EmbedLang(tag, lang_re, runtime) abort
  let save = get(b:, 'current_syntax', '')
  unlet! b:current_syntax
  try | exe 'syn include @cx' . a:tag . 'Syn syntax/' . a:runtime . '.vim' | catch | endtry
  if save != '' | let b:current_syntax = save | endif

  exe 'syn region cxCode' . a:tag
    \ . ' matchgroup=cxCodeFence'
    \ . ' start=/\[```[^\]]*lang[=:]' . a:lang_re . '/'
    \ . ' end=/\]/'
    \ . ' contains=cxEmbed' . a:tag . ',cxAttribute'
  exe 'syn region cxEmbed' . a:tag
    \ . ' start=/\[|/ end=/|\]/ contained'
    \ . ' contains=@cx' . a:tag . 'Syn'
endfunction

call s:EmbedLang('JSON',   'json',                      'json')
call s:EmbedLang('XML',    'xml',                        'xml')
call s:EmbedLang('CSS',    'css',                        'css')
call s:EmbedLang('HTML',   'html',                       'html')
call s:EmbedLang('JS',     '\(js\|javascript\)',          'javascript')
call s:EmbedLang('Python', '\(python\|py\)',              'python')
call s:EmbedLang('Bash',   '\(bash\|sh\|shell\)',         'sh')
call s:EmbedLang('SQL',    'sql',                        'sql')
call s:EmbedLang('YAML',   '\(yaml\|yml\)',               'yaml')

" Generic code block (no embedded highlighting)
syn region cxCodeBlock matchgroup=cxCodeFence start=/\[```/ end=/\]/
  \ contains=cxBlockContent,cxAttribute

" Nested CX inside [``` lang=cx [| … |] ]
syn region cxCodeCX matchgroup=cxCodeFence
  \ start=/\[```[^\]]*lang[=:]cx/ end=/\]/
  \ contains=cxEmbedCX,cxAttribute
syn region cxEmbedCX start=/\[|/ end=/|\]/ contained contains=TOP

" ── Element regions ───────────────────────────────────────────────────────────
" matchgroup highlights [tagname … and … ] with cxTag; content is transparent.
" Listed order of contains determines priority at the same start position.
syn region cxElement matchgroup=cxTag
  \ start=/\[[a-zA-Z_][a-zA-Z0-9._-]*/ end=/\]/
  \ transparent
  \ contains=cxComment,@cxHeadings,cxRawText,cxBlockContent,cxTripleQuoted,
  \   cxCodeJSON,cxCodeXML,cxCodeCSS,cxCodeHTML,cxCodeJS,cxCodePython,
  \   cxCodeBash,cxCodeSQL,cxCodeYAML,cxCodeCX,cxCodeBlock,
  \   cxBold,cxItalic,cxStrike,cxSubscript,cxSuperscript,cxUnderline,
  \   cxInlineCode,cxBlockquote,cxPI,cxAlias,cxElement,
  \   cxAttribute,cxTypeAnnotation,cxFloat,cxInteger,cxBoolean,cxNull,
  \   cxString,cxEntityRef

" ── Highlight links ───────────────────────────────────────────────────────────
" Use treesitter @markup.* groups on Neovim (picked up by modern colorschemes);
" fall back to classic Vim groups elsewhere.
" tokyonight palette notes (storm/night):
"   @function → Function → c.blue      (#7aa2f7)  — used for element names
"   @property → c.green1  (#73daca)               — used for attr names
"   @type     → Type      → c.blue1    (#2ac3de)  — used for type annotations
"   @operator → c.blue5                            — used for =
"   @markup.* → structural markup (bold/italic/etc)
"   @tag      → Label → Statement → c.magenta     — AVOID (pink-purple)
"   @keyword  → c.purple                           — AVOID (purple)

if has('nvim')
  " comments, strings, scalars
  hi def link cxComment        @comment
  hi def link cxString         @string
  hi def link cxTripleQuoted   @string
  hi def link cxEscape         @character.special
  hi def link cxFloat          @number.float
  hi def link cxInteger        @number
  hi def link cxBoolean        @boolean
  hi def link cxNull           @constant.builtin
  hi def link cxEntityRef      @string.special

  " headings — @markup.heading.N gives rainbow levels in tokyonight
  hi def link cxH1Mark         @markup.heading.1
  hi def link cxH1             @markup.heading.1
  hi def link cxH2Mark         @markup.heading.2
  hi def link cxH2             @markup.heading.2
  hi def link cxH3Mark         @markup.heading.3
  hi def link cxH3             @markup.heading.3
  hi def link cxH4Mark         @markup.heading.4
  hi def link cxH4             @markup.heading.4
  hi def link cxH5Mark         @markup.heading.5
  hi def link cxH5             @markup.heading.5
  hi def link cxH6Mark         @markup.heading.6
  hi def link cxH6             @markup.heading.6

  " inline markup — delimiters are dimmed so styled content stands out
  hi def link cxMarkupTag      @comment
  hi def link cxBold           @markup.strong
  hi def link cxItalic         @markup.italic
  hi def link cxStrike         @markup.strikethrough
  hi def link cxSubscript      @markup.italic
  hi def link cxSuperscript    @markup.italic
  hi def link cxUnderline      @markup.underline
  hi def link cxInlineCode     @markup.raw
  hi def link cxBlockquote     @markup.quote
  hi def link cxRawText        @markup.raw
  hi def link cxBlockContent   @markup.raw

  " elements — @function (blue) not @tag (magenta/pink-purple)
  hi def link cxTag            @function
  hi def link cxCodeFence      @punctuation.special
  hi def link cxPI             @keyword.directive
  hi def link cxAlias          @variable.member

  " attributes
  hi def link cxAttrName       @property
  hi def link cxAttrEq         @operator
  hi def link cxAttrValue      @string

  " type annotations
  hi def link cxTypeAnnotation @type
else
  hi def link cxComment        Comment
  hi def link cxString         String
  hi def link cxTripleQuoted   String
  hi def link cxEscape         SpecialChar
  hi def link cxFloat          Float
  hi def link cxInteger        Number
  hi def link cxBoolean        Boolean
  hi def link cxNull           Constant
  hi def link cxEntityRef      Special
  hi def link cxH1Mark         Title
  hi def link cxH1             Title
  hi def link cxH2Mark         Title
  hi def link cxH2             Title
  hi def link cxH3Mark         Title
  hi def link cxH3             Title
  hi def link cxH4Mark         Title
  hi def link cxH4             Title
  hi def link cxH5Mark         Title
  hi def link cxH5             Title
  hi def link cxH6Mark         Title
  hi def link cxH6             Title
  hi def link cxMarkupTag      Comment
  hi def link cxBold           Bold
  hi def link cxItalic         Italic
  hi def link cxStrike         Comment
  hi def link cxSubscript      Special
  hi def link cxSuperscript    Special
  hi def link cxUnderline      Underlined
  hi def link cxInlineCode     Constant
  hi def link cxBlockquote     String
  hi def link cxRawText        String
  hi def link cxBlockContent   String
  hi def link cxTag            Function
  hi def link cxCodeFence      Special
  hi def link cxPI             PreProc
  hi def link cxAlias          Identifier
  hi def link cxAttrName       Identifier
  hi def link cxAttrEq         Operator
  hi def link cxAttrValue      String
  hi def link cxTypeAnnotation Type
endif

let b:current_syntax = "cx"
