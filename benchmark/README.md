# HTML parser benchmarks

## Method

All implementations parse the same 157,021-byte Wikipedia page from `bobzhang/html_parser`'s JustHTML fixture corpus. The generated MoonBit string is shared before timing starts. `it.keep` consumes every result.

Measurements use `moon bench --release`, with mean times from the runner. Each timing is one complete operation on the page, not an amortized batch time.

Compared versions:

- `justjavac/html` 0.1.0 (this module)
- `moonbit-community/html` 0.2.4
- `marianoguerra/html` 0.1.2
- `Milky2018/html` 0.1.2
- `bobzhang/html_parser` 0.2.3

Environment: MoonBit nightly toolchain, Node.js 22 for the JS backend, measured in GitHub Actions on ubuntu-latest, windows-latest, and macos-latest.

These libraries do not implement identical tree-construction semantics. community and Milky2018 perform WHATWG document construction; bobzhang provides a larger parser/sanitizer toolkit; marianoguerra builds a semantic markup tree. The results compare the same input operation, not feature-equivalent implementations.

## Parse

Mean time to parse the page and keep a result derived from its tree.

| Implementation | native | JS | Wasm |
| --- | ---: | ---: | ---: |
| **justjavac/html** | **1.06 ms** | **0.381 ms** | **0.434 ms** |
| justjavac/html mutable | 1.36 ms | 0.488 ms | 0.791 ms |
| moonbit-community/html | 97.03 ms | 12.34 ms | 95.23 ms |
| marianoguerra/html | 5.47 ms | 2.38 ms | 6.47 ms |
| Milky2018/html | 96.63 ms | 6.18 ms | 92.47 ms |
| bobzhang/html_parser | 6.26 ms | 4.58 ms | 47.17 ms |

## Parse and stringify

Mean time to parse and serialize the complete document without edits.

| Implementation | native | JS | Wasm |
| --- | ---: | ---: | ---: |
| **justjavac/html** | **1.10 ms** | **0.373 ms** | **0.432 ms** |
| justjavac/html mutable | 1.46 ms | 0.506 ms | 0.755 ms |
| moonbit-community/html | 98.39 ms | 13.33 ms | 97.16 ms |
| marianoguerra/html | 7.54 ms | 4.33 ms | 7.62 ms |
| Milky2018/html | 97.56 ms | 8.69 ms | 93.48 ms |
| bobzhang/html_parser | 11.75 ms | 15.44 ms | 78.78 ms |

The immutable serializer is an original-source operation. Mutable mode materializes node states and therefore has different tradeoffs.

## Optimization comparison

The following are same-session native results before and after the first MoonBit-specific optimization pass. The input and benchmark runner are unchanged.

| Workload | Before | After | Change |
| --- | ---: | ---: | ---: |
| parse, immutable | 1.83 ms | 1.04 ms | 43.2% faster |
| parse, mutable | 2.09 ms | 1.37 ms | 34.4% faster |
| parse and read all attributes/text | 4.20 ms | 2.74 ms | 34.8% faster |
| precompiled ordinary selectors | 22.00 µs | 16.85 µs | 23.4% faster |
| structural selectors, immutable, 10 queries | 3.43 ms | 1.71 ms | 50.1% faster |
| structural selectors, mutable, 10 queries | 3.37 ms | 1.06 ms | 68.5% faster |

The second pass was measured by A/B alternation in a single session: baseline and optimized sources were swapped in place for three rounds per target, on workloads amplified 10–100× to stay above machine noise. Each entry is the median of the per-round optimized/baseline ratios; "within noise" means the rounds disagreed in direction.

| Workload | native | JS | Wasm |
| --- | ---: | ---: | ---: |
| parse | within noise | within noise | within noise |
| parse, mutable | within noise | 19% faster | 10% faster |
| parse and read all attributes/text | 23% faster | 20% faster¹ | 23% faster |
| precompiled ordinary selectors | 12% faster | within noise | within noise |
| structural selectors | 15% faster | within noise | 8% faster |
| mutable ordinary selectors | 41% faster | 13% faster | 32% faster |
| mutable structural selectors | 25% faster | 29% faster | within noise |

¹ The first A/B round exposed a JS-only regression: the bounded search called `String::indexOf` without an end, so entity checks on short text nodes scanned far into the rest of the document. It was replaced with a bounded `charCodeAt` scan; the 20% figure is from a focused four-round re-measurement after the fix.

The retained optimizations are:

- Attribute pair and `Map` caches are allocated only on their first use, rather than for every potential node during parsing.
- Raw-text and doctype names are compared through `StringView` without temporary lowercase strings.
- Tag flags (void, raw text, foreign content) live in parallel slots of the intern table, so the parser reads name and flags in a single probe with no `Map` lookup.
- Source reads in hot loops use unchecked `unsafe_get` code-unit access where the surrounding loop already guarantees the bounds.
- `~=` and `|=` attribute selectors compare in place with `unsafe_range_equal` instead of allocating substrings and concatenated prefixes.
- `text()` performs a bounded entity precheck and copies clean spans with one `write_substring`, using the core library's bounded search on every target.
- Mutable queries push only element nodes on the DFS stack, build attribute maps on first use, and skip subtrees when the selector's candidate tags cannot match.
- Candidate tag lists are computed when a selector is compiled, not on every query.
- `:nth-*` and sibling combinators scan the parent's children directly without allocating and filtering sibling arrays.
- Single-code-unit searches delegate to the core library's `StringView::find` on every target; see "Search implementation" below.

Two experiments without stable gains were reverted: replacing checked array writes with `unsafe_set`, and replacing the foreign-content `Bool?` with an integer state.

The final run also includes these immutable workloads:

| Workload | native | JS | Wasm |
| --- | ---: | ---: | ---: |
| parse and read all attributes/text | 2.47 ms | 0.981 ms | 1.64 ms |
| precompiled ordinary selectors | 18.61 µs | 10.32 µs | 24.91 µs |
| structural selectors, 10 queries | 1.75 ms | 2.58 ms | 3.29 ms |

## Search implementation

The parser used to ship a C stub (`find_native.c`) that searched single code units with runtime-detected AVX2, SSE2, and scalar fallbacks. It was added because the stable toolchain's Windows MSVC build of the core library's `StringView::find` was ~100× slower than its Linux build (505 µs vs 3.0 µs for a 64 Ki scan, measured in [mbt-indexof-bench](https://github.com/justjavac/mbt-indexof-bench)).

The nightly toolchain fixed that regression, and its core find is SIMD-accelerated on both the native and wasm targets (2–7 µs per 64 Ki scan on all three operating systems). The C stub and all per-target search code were therefore removed: every backend now uses the same pure-MoonBit call to the core library. The full cross-backend, cross-platform evidence lives in [mbt-indexof-bench](https://github.com/justjavac/mbt-indexof-bench).

## Reproduce

From the repository root, with Node.js on `PATH` for JS:

```sh
moon bench --target native --release -p justjavac/html-benchmark
moon bench --target js --release -p justjavac/html-benchmark
moon bench --target wasm --release -p justjavac/html-benchmark
```

`Milky2018/html@0.1.2` still publishes legacy JSON manifests. With the 2026-11 toolchain, after MoonBit downloads it, run `moon fmt` in `.mooncakes/Milky2018/html` once, then use `--frozen` for subsequent commands. This is a dependency packaging issue, not a benchmark workaround.

`wikipedia.html` is the readable fixture; `fixture.mbt` is generated from it by `scripts/generate_benchmark_fixture.mbtx` so every backend receives identical input without file I/O in the timed region.

The tree and selector oracle fixtures under `scripts/oracles/` come from the upstream htmlparser2/css-select tests. `scripts/generate_tree_oracle_tests.mbtx` converts them into table-driven MoonBit assertions; the test suite itself does not need Bun or network access.
