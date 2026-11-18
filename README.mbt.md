# `justjavac/html`

[![coverage](https://img.shields.io/codecov/c/github/justjavac/moonbit-html/main?label=coverage)](https://codecov.io/gh/justjavac/moonbit-html)

Fast, lossless HTML parsing with UTF-16 source offsets, lazy entity decoding, CSS selectors, and an optional mutable tree. Supports `native`, `js`, `wasm`, and `wasm-gc`.

## Performance

The fastest MoonBit HTML parser on every backend: parsing a 157 KB Wikipedia page takes **~190 µs on native** — 19× faster than the next-fastest MoonBit parser and 460×+ faster than the WHATWG-conforming one — with precompiled selector queries in ~10 µs. Numbers and methodology: [`benchmark/README.md`](benchmark/README.md).

## Install

```bash
moon add justjavac/html
```

## Quick Start

```mbt check
///|
test "parse and query HTML" {
  let doc = @html.parse(
    "<head><title>Hi &amp; bye</title><link rel=canonical href=\"/\"></head>",
  )
  inspect(doc.find("head > title").unwrap().text(), content="Hi & bye")
  assert_eq(
    doc.find("link[rel=canonical]").unwrap().get_attr("href"),
    Some("/"),
  )
  let title = doc.find("title").unwrap()
  assert_eq(doc.position(title.start()), { line: 1, column: 7, })
  inspect(title.stringify(), content="<title>Hi &amp; bye</title>")
}
```

## Mutable Trees

Import `justjavac/html/mutable` for attribute, text, and child edits. Mutable nodes preserve untouched source and rebuild only edited branches.

This package follows htmlparser2-style recovery, not the WHATWG tree-construction algorithm. Do not use it as an HTML sanitizer.
