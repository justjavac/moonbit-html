# moonbit-html

[![coverage](https://img.shields.io/codecov/c/github/justjavac/moonbit-html/main?label=coverage)](https://codecov.io/gh/justjavac/moonbit-html)

`justjavac/html` is a fast, lossless HTML parser for MoonBit, migrated from the architecture of [`@lukeed/html`](https://github.com/lukeed/html). It provides immutable and mutable trees, exact source offsets, lazy attributes and entity decoding, CSS selectors, and lossless serialization.

## Why it is fast

- **One source scan:** builds a source-ordered tree with parallel arrays rather than allocating a class instance for every node.
- **Lazy values:** attribute caches, decoded text, and tag indexes are allocated or computed only when first read.
- **Interned tag names:** common ASCII names and their void/raw-text flags are matched in one open-addressed probe, without temporary lowercase strings or `Map` lookups.
- **Targeted selectors:** candidate tag lists are precomputed at compilation; mutable queries visit only elements and skip subtrees that cannot match.
- **Zero-copy reads:** hot loops use unchecked code-unit access where bounds are already guaranteed, and clean text spans are copied with one bounded substring write.

On a 157 KB Wikipedia page, `justjavac/html` parses in about **190 µs natively** — roughly **13× faster** than the next-fastest MoonBit parser in the corpus and over **450× faster** than the WHATWG-conforming ones, while staying the fastest on the JS and Wasm backends too. It is 100% MoonBit with no C code. Detailed numbers, methodology, and the optimization log live in [`benchmark/README.md`](benchmark/README.md).

## Install

```sh
moon add justjavac/html
```

The library supports the `native`, `js`, `wasm`, and `wasm-gc` backends.

## Immutable API

```mbt
let doc = @html.parse(
  "<head><title>Hi &amp; bye</title><link rel=canonical href=\"/\"></head>",
)

let title = doc.find("head > title").unwrap()
title.text() // "Hi & bye"
doc.find("link").unwrap().get_attr("href") // Some("/")
doc.position(title.start()) // { line: 1, column: 7 }
title.html() // "Hi &amp; bye"
title.stringify() // "<title>Hi &amp; bye</title>"
```

`parse` never raises for malformed HTML. `find`, `all`, `matches`, and `closest` raise `SelectorError` for invalid or unsupported selectors. Source offsets are zero-based UTF-16 code-unit offsets; `Position` lines and columns are one-based.

Use pattern matching to inspect child nodes:

```mbt
for node in doc.children() {
  match node {
    @html.Element(element) => println(element.name())
    @html.Text(text) => println(text.value())
    @html.Comment(comment) => println(comment.value())
    @html.Directive(directive) => println(directive.value())
  }
}
```

### Selectors

Supported selectors include type and universal selectors, IDs, classes, attributes (`=`, `~=`, `|=`, `^=`, `$=`, `*=`, with `i`/`s` flags), selector lists, descendant/child/sibling combinators, and these pseudo-classes:

- `:root`, `:empty`
- `:first-child`, `:last-child`, `:only-child`
- `:nth-child()`, `:nth-last-child()`
- `:first-of-type`, `:last-of-type`, `:only-of-type`
- `:nth-of-type()`, `:nth-last-of-type()`
- `:not()`, `:is()`, `:where()`

As with css-select, queries skip the contents of nested `<template>` elements unless the template itself is the query root.

## Mutable API

Import `justjavac/html/mutable` when edits are needed. MoonBit uses explicit setter methods and arrays instead of JavaScript property setters and variadic arguments.

```mbt
let doc = @mutable.parse("<ul><li>a</li></ul>")
let li = doc.find("li").unwrap()
li.set_attr("class", "first")

let more = @mutable.parse("<li>b</li>").children()
doc.find("ul").unwrap().append(
  more.map((node) => @mutable.Content::Node(node)),
)

doc.stringify() // <ul><li class="first">a</li><li>b</li></ul>
```

Elements support `set_name`, `set_attr`, `remove_attr`, `set_text`, `set_html`, `append`, and `prepend`. Every child type supports `before`, `after`, `replace`, `remove`, and `clone`. Text, comments, and directives support `set_value`.

`Content::Text` inserts escaped text, not markup. Use `set_html` or move parsed `Node` values to insert elements. Nodes can move within a document or between documents. Original `start`/`end` offsets become `None` for newly parsed fragments or nodes moved to another document.

## Compatibility and security

Tree recovery follows **htmlparser2**, not the WHATWG browser tree-construction algorithm. Browsers may produce a different tree for malformed markup. This library is **not a sanitizer** and must not be used to decide whether HTML is safe to render.

## Development

```sh
moon check --target all
moon test --target all
moon run --target native examples/basic
```

The test suite includes table-driven htmlparser2 tree oracles and css-select source-offset oracles from the upstream project, plus immutable/mutable compatibility and editing regression tests.

See [`benchmark/README.md`](benchmark/README.md) for the comparison corpus, methodology, results, and commands.

## License

MIT. The packed entity table is derived from `entities` 8.1.0 (BSD-2-Clause); its notice is included in `LICENSE`.
