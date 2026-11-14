///|
const MASK = 511

///|
const IS_VOID = 1

///|
const IS_RAW = 2

///|
const IS_FOREIGN = 4

///|
const IS_INTEGRATION = 8

///|
const HAS_IMPLIES = 16

///|
priv struct NameTable {
  names : Array[String?]
  flags : Array[Int32]
}

///|
fn lower_ascii(code : Int32) -> Int32 {
  if code >= 65 && code <= 90 {
    code + 32
  } else {
    code
  }
}

///|
fn hash_name(source : String, from : Int32, to : Int32) -> Int32 {
  let mut hash = 0
  for i in from..<to {
    hash = (hash * 31 + lower_ascii(unsafe_code_at(source, i))) & 0x7fffffff
  }
  hash
}

///|
fn same_name(source : String, from : Int32, name : String) -> Bool {
  for i in 0..<name.length() {
    if lower_ascii(unsafe_code_at(source, from + i)) !=
      name.unsafe_get(i).to_int() {
      return false
    }
  }
  true
}

///|
fn make_table(names : Array[String]) -> NameTable {
  let slots = Array::make(MASK + 1, None)
  let flags : Array[Int32] = Array::make(MASK + 1, 0)
  for name in names {
    let mut index = hash_name(name, 0, name.length()) & MASK
    while slots[index] is Some(_) {
      index = (index + 1) & MASK
    }
    slots[index] = Some(name)
    flags[index] = compute_flags(name)
  }
  { names: slots, flags, }
}

///|
fn intern(
  table : NameTable,
  source : String,
  from : Int32,
  to : Int32,
) -> (String, Int32) {
  let hash = hash_name(source, from, to)
  let length = to - from
  let mut index = hash & MASK
  while true {
    match table.names[index] {
      None => {
        let name = lower_unicode(slice(source, from, to))
        return (name, compute_flags(name))
      }
      Some(name) => {
        if name.length() == length && same_name(source, from, name) {
          return (name, table.flags[index])
        }
        index = (index + 1) & MASK
      }
    }
  }
  ("", 0)
}

///|
let known : NameTable = make_table([
  "script", "style", "textarea", "title", "xmp", "iframe", "noembed", "noframes",
  "plaintext", "area", "base", "basefont", "br", "col", "command", "embed", "frame",
  "hr", "img", "input", "isindex", "keygen", "link", "meta", "param", "source", "track",
  "wbr", "math", "svg", "mi", "mo", "mn", "ms", "mtext", "annotation-xml", "foreignobject",
  "desc", "tr", "th", "td", "body", "a", "li", "p", "h1", "h2", "h3", "h4", "h5",
  "h6", "select", "output", "button", "datalist", "option", "optgroup", "dd", "dt",
  "rt", "rp", "tbody", "tfoot", "address", "article", "aside", "blockquote", "details",
  "div", "dl", "fieldset", "figcaption", "figure", "footer", "form", "header", "main",
  "nav", "ol", "pre", "section", "table", "ul", "html", "head", "span", "i", "b",
  "em", "strong", "small", "code", "label", "picture", "noscript", "template", "time",
  "sup", "path", "g", "use", "rect", "circle", "image", "video", "thead",
])

///|
fn lower_unicode(input : String) -> String {
  let output = StringBuilder()
  for char in input {
    let code = char.to_int()
    if (code >= 0xc0 && code <= 0xd6) || (code >= 0xd8 && code <= 0xde) {
      match (code + 32).to_char() {
        Some(lower) => output.write_char(lower)
        None => output.write_char(char)
      }
    } else {
      output.write_string(char.to_string().to_lower())
    }
  }
  output.to_string()
}

///|
/// The interned lowercase tag name in `source` from `from` to `to`, with the
/// parser flags of the interned name.
fn tag_info(source : String, from : Int32, to : Int32) -> (String, Int32) {
  intern(known, source, from, to)
}

///|
pub fn tag_name(source : String, from : Int32, to : Int32) -> String {
  let (name, _) = intern(known, source, from, to)
  name
}

///|
fn compute_flags(name : String) -> Int32 {
  let mut result = 0
  if is_void(name) {
    result = result | IS_VOID
  }
  if is_raw(name) {
    result = result | IS_RAW
  }
  if name == "math" || name == "svg" {
    result = result | IS_FOREIGN
  }
  if is_integration(name) {
    result = result | IS_INTEGRATION
  }
  if has_implies(name) {
    result = result | HAS_IMPLIES
  }
  result
}

///|
/// The parser flags of a lowercase tag name, probed in the intern table
/// instead of a separate map.
pub fn flags(name : String) -> Int32 {
  let hash = hash_name(name, 0, name.length())
  let mut index = hash & MASK
  while true {
    match known.names[index] {
      None => return compute_flags(name)
      Some(candidate) => {
        if candidate == name {
          return known.flags[index]
        }
        index = (index + 1) & MASK
      }
    }
  }
  0
}

///|
pub fn is_void(name : String) -> Bool {
  match name {
    "area"
    | "base"
    | "basefont"
    | "br"
    | "col"
    | "command"
    | "embed"
    | "frame"
    | "hr"
    | "img"
    | "input"
    | "isindex"
    | "keygen"
    | "link"
    | "meta"
    | "param"
    | "source"
    | "track"
    | "wbr" => true
    _ => false
  }
}

///|
pub fn is_raw(name : String) -> Bool {
  match name {
    "script"
    | "style"
    | "textarea"
    | "title"
    | "xmp"
    | "iframe"
    | "noembed"
    | "noframes"
    | "plaintext" => true
    _ => false
  }
}

///|
pub fn is_literal(name : String) -> Bool {
  match name {
    "script"
    | "style"
    | "xmp"
    | "iframe"
    | "noembed"
    | "noframes"
    | "plaintext" => true
    _ => false
  }
}

///|
pub fn is_integration(name : String) -> Bool {
  match name {
    "mi"
    | "mo"
    | "mn"
    | "ms"
    | "mtext"
    | "annotation-xml"
    | "foreignObject"
    | "desc"
    | "title" => true
    _ => false
  }
}

///|
fn has_implies(name : String) -> Bool {
  match name {
    "tr"
    | "th"
    | "td"
    | "body"
    | "a"
    | "li"
    | "p"
    | "h1"
    | "h2"
    | "h3"
    | "h4"
    | "h5"
    | "h6"
    | "select"
    | "input"
    | "output"
    | "button"
    | "datalist"
    | "textarea"
    | "option"
    | "optgroup"
    | "dd"
    | "dt"
    | "rt"
    | "rp"
    | "tbody"
    | "tfoot"
    | "address"
    | "article"
    | "aside"
    | "blockquote"
    | "details"
    | "div"
    | "dl"
    | "fieldset"
    | "figcaption"
    | "figure"
    | "footer"
    | "form"
    | "header"
    | "hr"
    | "main"
    | "nav"
    | "ol"
    | "pre"
    | "section"
    | "table"
    | "ul" => true
    _ => false
  }
}

///|
pub fn implies(name : String, open : String) -> Bool {
  match name {
    "tr" => open == "tr" || open == "th" || open == "td"
    "th" => open == "th"
    "td" => open == "thead" || open == "th" || open == "td"
    "body" => open == "head" || open == "link" || open == "script"
    "a" => open == "a"
    "li" => open == "li"
    "p" => open == "p"
    "h1" | "h2" | "h3" | "h4" | "h5" | "h6" =>
      match open {
        "h1" | "h2" | "h3" | "h4" | "h5" | "h6" | "p" => true
        _ => false
      }
    "select" | "input" | "output" | "button" | "datalist" | "textarea" =>
      match open {
        "input"
        | "option"
        | "optgroup"
        | "select"
        | "button"
        | "datalist"
        | "textarea" => true
        _ => false
      }
    "option" => open == "option"
    "optgroup" => open == "optgroup" || open == "option"
    "dd" | "dt" => open == "dd" || open == "dt"
    "rt" | "rp" => open == "rt" || open == "rp"
    "tbody" | "tfoot" => open == "thead" || open == "tbody"
    _ => open == "p"
  }
}

///|
pub fn svg_name(name : String) -> String {
  match name {
    "altglyph" => "altGlyph"
    "altglyphdef" => "altGlyphDef"
    "altglyphitem" => "altGlyphItem"
    "animatecolor" => "animateColor"
    "animatemotion" => "animateMotion"
    "animatetransform" => "animateTransform"
    "clippath" => "clipPath"
    "feblend" => "feBlend"
    "fecolormatrix" => "feColorMatrix"
    "fecomponenttransfer" => "feComponentTransfer"
    "fecomposite" => "feComposite"
    "feconvolvematrix" => "feConvolveMatrix"
    "fediffuselighting" => "feDiffuseLighting"
    "fedisplacementmap" => "feDisplacementMap"
    "fedistantlight" => "feDistantLight"
    "fedropshadow" => "feDropShadow"
    "feflood" => "feFlood"
    "fefunca" => "feFuncA"
    "fefuncb" => "feFuncB"
    "fefuncg" => "feFuncG"
    "fefuncr" => "feFuncR"
    "fegaussianblur" => "feGaussianBlur"
    "feimage" => "feImage"
    "femerge" => "feMerge"
    "femergenode" => "feMergeNode"
    "femorphology" => "feMorphology"
    "feoffset" => "feOffset"
    "fepointlight" => "fePointLight"
    "fespecularlighting" => "feSpecularLighting"
    "fespotlight" => "feSpotLight"
    "fetile" => "feTile"
    "feturbulence" => "feTurbulence"
    "foreignobject" => "foreignObject"
    "glyphref" => "glyphRef"
    "lineargradient" => "linearGradient"
    "radialgradient" => "radialGradient"
    "textpath" => "textPath"
    _ => name
  }
}
