///|
/// The kind of a tree node.
#derive(Eq, Debug)
pub(all) enum Kind {
  Document
  Element
  Text
  Comment
  Directive
}

///|
/// The compact parse tree: parallel arrays indexed by node id.
pub struct Tree {
  source : String
  mut size : Int32
  kind : Array[Kind]
  name : Array[String]
  parent : Array[Int32]
  stop : Array[Int32]
  start : Array[Int32]
  end : Array[Int32]
  from : Array[Int32]
  to : Array[Int32]
  head : Array[Int32]
  mut pairs : Array[Array[String]?]?
  mut attrs : Array[Map[String, String]?]?
  mut tags : Map[String, Array[Int32]]?
  foreign : Bool
}

///|
/// Incremental tree construction state.
priv struct Builder {
  tree : Tree
  stack : Array[Int32]
  contexts : Array[Bool]
  owners : Array[Int32]
  base : Bool
  mut alien : Bool
  mut text : Int32
}

///|
/// Create a builder for one source document.
fn Builder::new(source : String, foreign : Bool) -> Builder {
  let capacity = if source.length() / 16 > 64 {
    source.length() / 16
  } else {
    64
  }
  let tree : Tree = {
    source,
    size: 1,
    kind: Array::make(capacity, Kind::Document),
    name: Array::make(capacity, ""),
    parent: Array::make(capacity, 0),
    stop: Array::make(capacity, 0),
    start: Array::make(capacity, 0),
    end: Array::make(capacity, 0),
    from: Array::make(capacity, 0),
    to: Array::make(capacity, 0),
    head: Array::make(capacity, 0),
    pairs: None,
    attrs: None,
    tags: None,
    foreign,
  }
  tree.parent[0] = -1
  tree.end[0] = source.length()
  tree.to[0] = source.length()
  {
    tree,
    stack: [0],
    contexts: [],
    owners: [],
    base: foreign,
    alien: foreign,
    text: 0,
  }
}

///|
fn[T] put(items : Array[T], index : Int32, value : T) -> Unit {
  if index < items.length() {
    items[index] = value
  } else {
    items.push(value)
  }
}

///|
/// Append a node and return its id.
fn Builder::add(
  self : Builder,
  kind : Kind,
  name : String,
  outer : Int32,
  close : Int32,
  inner : Int32,
  until : Int32,
  attrs : Int32,
) -> Int32 {
  let id = self.tree.size
  self.tree.size += 1
  put(self.tree.kind, id, kind)
  put(self.tree.name, id, name)
  put(self.tree.parent, id, self.stack[self.stack.length() - 1])
  put(self.tree.stop, id, id + 1)
  put(self.tree.start, id, outer)
  put(self.tree.end, id, close)
  put(self.tree.from, id, inner)
  put(self.tree.to, id, until)
  put(self.tree.head, id, attrs)
  id
}

///|
/// Attach pending text up to `until`.
fn Builder::flush(self : Builder, until : Int32) -> Unit {
  if until > self.text {
    let _ = self.add(
      Kind::Text,
      "",
      self.text,
      until,
      self.text,
      until,
      self.text,
    )
  }
}

///|
/// Close the innermost open element.
fn Builder::pop(self : Builder, at : Int32, inner : Int32) -> Unit {
  let id = self.stack.unsafe_pop()
  self.tree.end[id] = at
  self.tree.to[id] = inner
  self.tree.stop[id] = self.tree.size
  if self.owners.length() > 0 && self.owners[self.owners.length() - 1] == id {
    let _ = self.owners.unsafe_pop()
    let _ = self.contexts.unsafe_pop()
    self.alien = if self.contexts.length() > 0 {
      self.contexts[self.contexts.length() - 1]
    } else {
      self.base
    }
  }
}

///|
/// The offset just past an open tag and whether it self-closes, or -1.
fn tag_end(source : String, from : Int32) -> (Int32, Bool) {
  let length = source.length()
  let mut i = from
  let mut slash = false
  while i < length {
    let mut code = unsafe_code_at(source, i)
    if code == 32 {
      i += 1
      continue
    }
    if code == 62 {
      return (i + 1, slash)
    }
    if code == 47 {
      i += 1
      while i < length && is_space(unsafe_code_at(source, i)) {
        i += 1
      }
      if code_at(source, i) != 62 {
        continue
      }
      slash = true
      return (i + 1, slash)
    }
    if is_space(code) {
      i += 1
      continue
    }
    i += 1
    while i < length {
      code = unsafe_code_at(source, i)
      if code > 62 {
        i += 1
        continue
      }
      if code == 61 || code == 47 || code == 62 || is_space(code) {
        break
      }
      i += 1
    }
    if code != 61 {
      while i < length && is_space(unsafe_code_at(source, i)) {
        i += 1
      }
      if code_at(source, i) != 61 {
        continue
      }
    }
    i += 1
    code = code_at(source, i)
    while i < length && is_space(code) {
      i += 1
      code = code_at(source, i)
    }
    if code == 34 || code == 39 {
      let quote = if code == 34 { "\"" } else { "'" }
      let close = find_from(source, quote, i + 1)
      if close == -1 {
        return (-1, slash)
      }
      i = close + 1
      continue
    }
    while i < length {
      code = unsafe_code_at(source, i)
      if code > 62 {
        i += 1
        continue
      }
      if code == 62 || is_space(code) {
        break
      }
      i += 1
    }
  }
  (-1, slash)
}

///|
/// Whether the open tag starting at `head` is self-closing.
pub fn self_closing(source : String, head : Int32) -> Bool {
  let (end, slash) = tag_end(source, head)
  end != -1 && slash
}

///|
/// The end offsets of a comment or bogus comment starting at `from`.
fn comment_end(source : String, from : Int32) -> (Int32, Int32) {
  if code_at(source, from) == 62 {
    return (from, from + 1)
  }
  if starts_at(source, "->", from) {
    return (from, from + 2)
  }
  let mut at = from
  while true {
    at = find_from(source, "--", at)
    if at == -1 {
      break
    }
    let code = code_at(source, at + 2)
    if code == 62 {
      return (at, at + 3)
    }
    if code == 33 && code_at(source, at + 3) == 62 {
      return (at, at + 4)
    }
    at += 1
  }
  let length = source.length()
  let mut to = length
  while to > from && to > length - 2 && code_at(source, to - 1) == 45 {
    to -= 1
  }
  (to, length)
}

///|
/// The offset of the matching close tag for a raw-text element, or the source length.
fn closing(source : String, name : String, from : Int32) -> Int32 {
  let mut at = from
  while true {
    at = find_from(source, "</", at)
    if at == -1 {
      return source.length()
    }
    let tail = at + 2 + name.length()
    if tail <= source.length() &&
      source.unsafe_view(start=at + 2, end=tail).equal_ignore_ascii_case(name) {
      let next = code_at(source, tail)
      if is_space(next) || next == 62 || next == 47 {
        return at
      }
    }
    at += 2
  }
  source.length()
}

///|
/// Whether the node is in foreign (SVG/MathML) content.
pub fn foreign(tree : Tree, id : Int32) -> Bool {
  let mut current = id
  while current > 0 {
    if tree.name[current] == "svg" || tree.name[current] == "math" {
      return true
    }
    if is_integration(tree.name[current]) {
      return false
    }
    current = tree.parent[current]
  }
  tree.foreign
}

///|
/// Parse `source` into a compact tree.
pub fn build(source : String, foreign~ : Bool = false) -> Tree {
  let builder = Builder::new(source, foreign)
  let length = source.length()
  let mut i = 0
  while i < length {
    let lt = find_from(source, "<", i)
    if lt == -1 {
      break
    }
    let code = code_at(source, lt + 1)
    if code == 33 {
      builder.flush(lt)
      if starts_at(source, "--", lt + 2) {
        let (to, stop) = comment_end(source, lt + 4)
        let _ = builder.add(Kind::Comment, "", lt, stop, lt + 4, to, lt)
        i = stop
        builder.text = stop
        continue
      }
      if builder.alien && starts_at(source, "[CDATA[", lt + 2) {
        let end = find_from(source, "]]>", lt + 9)
        let stop = if end == -1 { length } else { end + 3 }
        let to = if end == -1 { length } else { end }
        let _ = builder.add(Kind::Text, "", lt, stop, lt + 9, to, lt)
        i = stop
        builder.text = stop
        continue
      }
      let end = find_from(source, ">", lt + 2)
      let stop = if end == -1 { length } else { end + 1 }
      let doctype = lt + 9 <= length &&
        source
        .unsafe_view(start=lt + 2, end=lt + 9)
        .equal_ignore_ascii_case("doctype")
      let kind = if doctype { Kind::Directive } else { Kind::Comment }
      let to = if end == -1 { length } else { end }
      let _ = builder.add(kind, "", lt, stop, lt + 2, to, lt)
      i = stop
      builder.text = stop
      continue
    }
    if code == 63 {
      builder.flush(lt)
      let end = find_from(source, ">", lt + 2)
      let stop = if end == -1 { length } else { end + 1 }
      let to = if end == -1 { length } else { end }
      let _ = builder.add(Kind::Comment, "", lt, stop, lt + 1, to, lt)
      i = stop
      builder.text = stop
      continue
    }
    if code == 47 {
      let end = find_from(source, ">", lt + 2)
      if end == -1 {
        if lt + 2 >= length {
          break
        }
        builder.flush(lt)
        if !is_alpha(code_at(source, lt + 2)) {
          let _ = builder.add(Kind::Comment, "", lt, length, lt + 2, length, lt)
        }
        i = length
        builder.text = length
        break
      }
      builder.flush(lt)
      i = end + 1
      builder.text = end + 1
      if end == lt + 2 {
        continue
      }
      if !is_alpha(code_at(source, lt + 2)) {
        let _ = builder.add(Kind::Comment, "", lt, end + 1, lt + 2, end, lt)
        continue
      }
      let mut j = lt + 2
      while j < end &&
            !is_space(unsafe_code_at(source, j)) &&
            unsafe_code_at(source, j) != 47 {
        j += 1
      }
      let (interned, interned_flags) = tag_info(source, lt + 2, j)
      let mut name = interned
      if builder.alien {
        name = svg_name(name)
      }
      if (interned_flags & IS_VOID) != 0 {
        if name == "br" {
          let _ = builder.add(
            Kind::Element,
            "br",
            lt,
            end + 1,
            end + 1,
            end + 1,
            end,
          )
        }
        continue
      }
      let mut pos = builder.stack.length() - 1
      while pos > 0 && builder.tree.name[builder.stack[pos]] != name {
        pos -= 1
      }
      if pos > 0 {
        while builder.stack.length() - 1 > pos {
          builder.pop(lt, lt)
        }
        builder.pop(end + 1, lt)
      } else if name == "p" {
        let _ = builder.add(
          Kind::Element,
          "p",
          lt,
          end + 1,
          end + 1,
          end + 1,
          end,
        )
      }
      continue
    }
    if !is_alpha(code) {
      i = lt + 1
      continue
    }
    let mut j = lt + 2
    while j < length {
      let next = unsafe_code_at(source, j)
      if is_space(next) || next == 62 || next == 47 {
        break
      }
      j += 1
    }
    let (close, slash) = tag_end(source, j)
    if close == -1 {
      builder.flush(lt)
      i = length
      builder.text = length
      break
    }
    builder.flush(lt)
    i = close
    builder.text = close
    let (interned, interned_flags) = tag_info(source, lt + 1, j)
    let mut name = interned
    let mut flag = interned_flags
    if builder.alien {
      let renamed = svg_name(name)
      if renamed != name {
        flag = flags(renamed)
        name = renamed
      }
    } else if name == "image" {
      name = "img"
      flag = IS_VOID
    }
    if name == "form" {
      let mut found = false
      for id in builder.stack {
        if builder.tree.name[id] == "form" {
          found = true
          break
        }
      }
      if found {
        continue
      }
    }
    if (flag & HAS_IMPLIES) != 0 {
      while builder.stack.length() > 1 &&
            implies(
              name,
              builder.tree.name[builder.stack[builder.stack.length() - 1]],
            ) {
        builder.pop(lt, lt)
      }
    }
    let id = builder.add(Kind::Element, name, lt, close, close, close, j)
    if (flag & IS_VOID) != 0 {
      continue
    }
    let outer = builder.alien
    let context = if (flag & IS_FOREIGN) != 0 {
      Some(true)
    } else if (flag & IS_INTEGRATION) != 0 {
      Some(false)
    } else {
      None
    }
    if context.unwrap_or(outer) && slash {
      continue
    }
    builder.stack.push(id)
    match context {
      Some(value) => {
        builder.contexts.push(value)
        builder.owners.push(id)
        builder.alien = value
      }
      None => ()
    }
    if outer || (flag & IS_RAW) == 0 {
      continue
    }
    let close_at = if name == "plaintext" {
      length
    } else {
      closing(source, name, close)
    }
    builder.flush(close_at)
    i = close_at
    builder.text = close_at
  }
  builder.flush(length)
  while builder.stack.length() > 1 {
    builder.pop(length, length)
  }
  builder.tree.stop[0] = builder.tree.size
  builder.tree
}
