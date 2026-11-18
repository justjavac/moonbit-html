// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "justjavac/html"

version = "0.1.3"

source = "src"

readme = "README.mbt.md"

repository = "https://github.com/justjavac/moonbit-html"

license = "MIT"

keywords = [ "html", "parser", "dom", "css", "selector" ]

preferred_target = "native"

supported_targets = "+all"

description = "The fastest MoonBit HTML parser: ~240 µs for a 157 KB page on native, 20–440x faster than other MoonBit parsers. Lossless, with source offsets, CSS selectors, and an optional mutable tree"
