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

version = "0.1.1"

source = "src"

readme = "README.mbt.md"

repository = "https://github.com/justjavac/moonbit-html"

license = "MIT"

keywords = [ "html", "parser", "dom", "css", "selector" ]

preferred_target = "native"

supported_targets = "+all"

description = "A fast, lossless HTML parser with source offsets, CSS selectors, and an optional mutable tree"
