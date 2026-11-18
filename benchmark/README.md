# HTML parser benchmarks

## Method

All implementations parse the same 157,021-byte Wikipedia page from `bobzhang/html_parser`'s JustHTML fixture corpus. The generated MoonBit string is shared before timing starts. `it.keep` consumes every result.

Measurements use `moon bench --release`; each reported time is the runner's mean for one complete operation on the page, not an amortized batch time. Parenthesized multipliers are relative to `justjavac/html` on the same backend.

Compared versions:

- `justjavac/html` 0.1.1 (this module)
- `moonbit-community/html` 0.2.4
- `bobzhang/html_parser` 0.2.3

`marianoguerra/html` and `Milky2018/html` were part of the comparison until their published releases were left behind by the toolchain: nightly no longer accepts their legacy JSON manifests. Their upstream repositories have already migrated, so they return as soon as new versions are published.

Environment: MoonBit nightly toolchain (0.1.20261118), Node.js 22 for the JS backend, measured in GitHub Actions on ubuntu-latest, windows-latest, and macos-latest. The tables below are from the ubuntu-latest run; all three platforms are published as CI artifacts.

These libraries do not implement identical tree-construction semantics: `moonbit-community/html` performs WHATWG document construction and `bobzhang/html_parser` is a larger parser/sanitizer toolkit. The tables compare the same input operation, not feature-equivalent implementations.

## Parse

Mean time to parse the page and keep a result derived from its tree.

| Implementation | native | JS | Wasm |
| --- | ---: | ---: | ---: |
| **justjavac/html** | **236.17 µs** | **614.22 µs** | **636.16 µs** |
| justjavac/html mutable | 707.37 µs (3.0×) | 765.52 µs (1.2×) | 1.30 ms (2.0×) |
| moonbit-community/html | 104.39 ms (442×) | 32.01 ms (52×) | 139.58 ms (219×) |
| bobzhang/html_parser | 4.67 ms (20×) | 24.18 ms (39×) | 26.25 ms (41×) |

## Parse and stringify

Mean time to parse and serialize the complete document without edits.

| Implementation | native | JS | Wasm |
| --- | ---: | ---: | ---: |
| **justjavac/html** | **237.46 µs** | **612.13 µs** | **664.31 µs** |
| justjavac/html mutable | 702.64 µs (3.0×) | 772.80 µs (1.3×) | 1.30 ms (2.0×) |
| moonbit-community/html | 105.26 ms (443×) | 32.60 ms (53×) | 139.94 ms (211×) |
| bobzhang/html_parser | 8.21 ms (35×) | 37.57 ms (61×) | 30.48 ms (46×) |

The immutable serializer copies directly from the original source, while mutable mode materializes node states — the two modes have different tradeoffs.

## Read and query workloads

Additional `justjavac/html` workloads from the same run:

| Workload | native | JS | Wasm |
| --- | ---: | ---: | ---: |
| parse and read all attributes/text | 938.36 µs | 1.62 ms | 2.46 ms |
| precompiled ordinary selectors | 12.99 µs | 16.91 µs | 38.51 µs |
| structural selectors, 10 queries | 1.71 ms | 3.82 ms | 5.59 ms |
| ordinary selectors, mutable | 75.00 µs | 191.38 µs | 188.84 µs |
| structural selectors, mutable, 10 queries | 1.42 ms | 2.75 ms | 6.87 ms |

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

## Search implementation

The parser used to ship a C stub (`find_native.c`) that searched single code units with runtime-detected AVX2, SSE2, and scalar fallbacks. It was added because the stable toolchain's Windows MSVC build of the core library's `StringView::find` was ~100× slower than its Linux build (505 µs vs 3.0 µs for a 64 Ki scan, measured in [mbt-indexof-bench](https://github.com/justjavac/mbt-indexof-bench)).

The nightly toolchain fixed that regression, and its core find is SIMD-accelerated on both the native and wasm targets (2–7 µs per 64 Ki scan on all three operating systems). The C stub and all per-target search code were therefore removed: every backend now uses the same pure-MoonBit call to the core library. The full cross-backend, cross-platform evidence lives in [mbt-indexof-bench](https://github.com/justjavac/mbt-indexof-bench).

The results above were measured after the removal: on the same Windows machine, native parse of this page dropped from 1.06 ms (stable toolchain with the C stub) to ~320 µs (nightly, pure MoonBit), and the ubuntu CI run above measures 236.17 µs — native is the fastest backend again.

## Reproduce

From the repository root, with Node.js on `PATH` for JS:

```sh
moon bench --target native --release -p justjavac/html-benchmark
moon bench --target js --release -p justjavac/html-benchmark
moon bench --target wasm --release -p justjavac/html-benchmark
```

`wikipedia.html` is the readable fixture; `fixture.mbt` is generated from it by `scripts/generate_benchmark_fixture.mbtx` so every backend receives identical input without file I/O in the timed region.

The tree and selector oracle fixtures under `scripts/oracles/` come from the upstream htmlparser2/css-select tests. `scripts/generate_tree_oracle_tests.mbtx` converts them into table-driven MoonBit assertions; the test suite itself does not need Bun or network access.
