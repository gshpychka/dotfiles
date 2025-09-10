; extends

; Magic string based language detection
; Use comments like # lang:bash or -- lang:lua at the start of multiline strings

; Bash/Shell with magic comment
((indented_string_expression (string_fragment) @injection.content)
 (#match? @injection.content "^[ \t]*#[ \t]*lang:bash")
 (#set! injection.language "bash"))

((string_expression (string_fragment) @injection.content)
 (#match? @injection.content "^[ \t]*#[ \t]*lang:bash")
 (#set! injection.language "bash"))

; Lua with magic comment
((indented_string_expression (string_fragment) @injection.content)
 (#match? @injection.content "^[ \t]*--[ \t]*lang:lua")
 (#set! injection.language "lua"))

((string_expression (string_fragment) @injection.content)
 (#match? @injection.content "^[ \t]*--[ \t]*lang:lua")
 (#set! injection.language "lua"))

; Python with magic comment
((indented_string_expression (string_fragment) @injection.content)
 (#match? @injection.content "^[ \t]*#[ \t]*lang:python")
 (#set! injection.language "python"))

((string_expression (string_fragment) @injection.content)
 (#match? @injection.content "^[ \t]*#[ \t]*lang:python")
 (#set! injection.language "python"))

; JavaScript with magic comment
((indented_string_expression (string_fragment) @injection.content)
 (#match? @injection.content "^[ \t]*//[ \t]*lang:javascript")
 (#set! injection.language "javascript"))

((string_expression (string_fragment) @injection.content)
 (#match? @injection.content "^[ \t]*//[ \t]*lang:javascript")
 (#set! injection.language "javascript"))

; Lua in multiline strings
((indented_string_expression) @injection.content
 (#lua-match? @injection.content "^%s*%-%-")
 (#set! injection.language "lua"))

; Bash/Shell in multiline strings
((indented_string_expression) @injection.content
 (#lua-match? @injection.content "^%s*#!/bin/bash")
 (#set! injection.language "bash"))

((indented_string_expression) @injection.content
 (#lua-match? @injection.content "^%s*#!/bin/sh")
 (#set! injection.language "bash"))

; Python in multiline strings
((indented_string_expression) @injection.content
 (#lua-match? @injection.content "^%s*#!/usr/bin/env python")
 (#set! injection.language "python"))

((indented_string_expression) @injection.content
 (#lua-match? @injection.content "^%s*import ")
 (#set! injection.language "python"))

((indented_string_expression) @injection.content
 (#lua-match? @injection.content "^%s*def ")
 (#set! injection.language "python"))

; JavaScript/TypeScript in multiline strings
((indented_string_expression) @injection.content
 (#lua-match? @injection.content "^%s*const ")
 (#set! injection.language "javascript"))

((indented_string_expression) @injection.content
 (#lua-match? @injection.content "^%s*let ")
 (#set! injection.language "javascript"))

((indented_string_expression) @injection.content
 (#lua-match? @injection.content "^%s*var ")
 (#set! injection.language "javascript"))

((indented_string_expression) @injection.content
 (#lua-match? @injection.content "^%s*function ")
 (#set! injection.language "javascript"))

; YAML in multiline strings
((indented_string_expression) @injection.content
 (#lua-match? @injection.content "^%s*%w+:")
 (#set! injection.language "yaml"))

; JSON in multiline strings
((indented_string_expression) @injection.content
 (#lua-match? @injection.content "^%s*{")
 (#set! injection.language "json"))

((indented_string_expression) @injection.content
 (#lua-match? @injection.content "^%s*%[")
 (#set! injection.language "json"))