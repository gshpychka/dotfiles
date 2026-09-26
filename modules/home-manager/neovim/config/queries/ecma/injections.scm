; Subset of nvim-treesitter's ecma injections that target installed parsers.
; Every pattern adds to the query compile time paid on the first JS/TS buffer.

((comment) @injection.content
  (#set! injection.language "comment"))
; html(`...`), html`...`, sql(`...`), etc.
(call_expression
  function: (identifier) @injection.language
  arguments: [
    (arguments
      (template_string) @injection.content)
    (template_string) @injection.content
  ]
  (#lua-match? @injection.language "^[a-zA-Z][a-zA-Z0-9]*$")
  (#offset! @injection.content 0 1 0 -1)
  (#set! injection.include-children)
  ; Languages excluded from auto-injection due to special rules
  ; - svg uses the html parser
  ; - css uses the styled parser
  (#not-any-of? @injection.language "svg" "css"))

; Vercel PostgreSQL
; foo.sql`...` or foo.sql(`...`)
(call_expression
  function: (member_expression
    property: (property_identifier) @injection.language)
  arguments: [
    (arguments
      (template_string) @injection.content)
    (template_string) @injection.content
  ]
  (#eq? @injection.language "sql")
  (#offset! @injection.content 0 1 0 -1)
  (#set! injection.include-children))

((regex_pattern) @injection.content
  (#set! injection.language "regex"))
