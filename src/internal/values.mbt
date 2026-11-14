///|
fn is_attribute_name(code : Int32) -> Bool {
  !(is_space(code) || code == 47 || code == 61 || code == 62)
}

///|
pub fn find_pair(
  list : Array[String],
  key : String,
  stride~ : Int32 = 2,
) -> Int32 {
  let mut i = 0
  while i < list.length() {
    if list[i] == key {
      return i
    }
    i += stride
  }
  -1
}

///|
pub fn pairs(tree : Tree, id : Int32) -> Array[String] {
  if tree.pairs is Some(cache) && cache[id] is Some(cached) {
    return cached
  }
  let output : Array[String] = []
  let source = tree.source
  let end = tree.from[id] - 1
  let mut i = tree.head[id]
  while i < end {
    let code = code_at(source, i)
    if code == 47 || is_space(code) {
      i += 1
      continue
    }
    let from = i
    i += 1
    while i < end && is_attribute_name(unsafe_code_at(source, i)) {
      i += 1
    }
    let key = slice(source, from, i).to_lower()
    let mut at = i
    while at < end && is_space(unsafe_code_at(source, at)) {
      at += 1
    }
    let mut value = ""
    if code_at(source, at) == 61 {
      i = at + 1
      while i < end && is_space(unsafe_code_at(source, i)) {
        i += 1
      }
      let quote = code_at(source, i)
      if quote == 34 || quote == 39 {
        let token = if quote == 34 { "\"" } else { "'" }
        let mut close = find_from(source, token, i + 1)
        if close == -1 || close > end {
          close = end
        }
        value = slice(source, i + 1, close)
        i = close + 1
      } else {
        let start = i
        while i < end && !is_space(unsafe_code_at(source, i)) {
          i += 1
        }
        value = slice(source, start, i)
      }
    }
    if find_pair(output, key) != -1 {
      continue
    }
    output.push(key)
    output.push(
      if value.contains("&") {
        decode_html(value, attribute=true)
      } else {
        value
      },
    )
  }
  if tree.pairs is None {
    tree.pairs = Some(Array::make(tree.size, None))
  }
  tree.pairs.unwrap()[id] = Some(output)
  output
}

///|
pub fn spans(tree : Tree, id : Int32) -> Array[String] {
  let output : Array[String] = []
  let source = tree.source
  let end = tree.from[id] - 1
  let mut i = tree.head[id]
  while i < end {
    while i < end &&
          (
            unsafe_code_at(source, i) == 47 ||
            is_space(unsafe_code_at(source, i))
          ) {
      i += 1
    }
    if i >= end {
      break
    }
    let name_start = i
    i += 1
    while i < end && is_attribute_name(unsafe_code_at(source, i)) {
      i += 1
    }
    let name_end = i
    let mut at = i
    while at < end && is_space(unsafe_code_at(source, at)) {
      at += 1
    }
    if code_at(source, at) == 61 {
      i = at + 1
      while i < end && is_space(unsafe_code_at(source, i)) {
        i += 1
      }
      let quote = code_at(source, i)
      if quote == 34 || quote == 39 {
        let token = if quote == 34 { "\"" } else { "'" }
        let mut close = find_from(source, token, i + 1)
        if close == -1 || close > end {
          close = end
        }
        i = close + 1
      } else {
        while i < end && !is_space(unsafe_code_at(source, i)) {
          i += 1
        }
      }
    }
    let name = slice(source, name_start, name_end)
    let key = name.to_lower()
    if find_pair(output, key, stride=3) != -1 {
      continue
    }
    output.push(key)
    output.push(name)
    output.push(slice(source, name_start, if i < end { i } else { end }))
  }
  output
}

///|
pub fn attribute(tree : Tree, id : Int32, key : String) -> String? {
  let list = pairs(tree, id)
  let at = find_pair(list, key)
  if at == -1 {
    None
  } else {
    Some(list[at + 1])
  }
}

///|
pub fn attributes(tree : Tree, id : Int32) -> Map[String, String] {
  if tree.attrs is Some(cache) && cache[id] is Some(cached) {
    return cached
  }
  let output : Map[String, String] = Map([])
  let list = pairs(tree, id)
  let mut i = 0
  while i < list.length() {
    output[list[i]] = list[i + 1]
    i += 2
  }
  if tree.attrs is None {
    tree.attrs = Some(Array::make(tree.size, None))
  }
  tree.attrs.unwrap()[id] = Some(output)
  output
}

///|
/// Whether the text node `id` holds an entity that `decode_html` expands:
/// its range contains `&`, it is not CDATA, and its parent is not a literal
/// raw-text element like `<script>`.
fn decodable(tree : Tree, id : Int32) -> Bool {
  if tree.start[id] != tree.from[id] {
    return false
  }
  let parent = tree.parent[id]
  if is_literal(tree.name[parent]) && !foreign(tree, tree.parent[parent]) {
    return false
  }
  find_in(tree.source, "&", tree.from[id], tree.to[id]) != -1
}

///|
pub fn value(tree : Tree, id : Int32) -> String {
  let raw = slice(tree.source, tree.from[id], tree.to[id])
  if tree.kind[id] != Kind::Text || !decodable(tree, id) {
    return raw
  }
  decode_html(raw)
}

///|
pub fn text(tree : Tree, id : Int32) -> String {
  if tree.kind[id] == Kind::Text {
    return value(tree, id)
  }
  let output = StringBuilder()
  let source = tree.source
  for current in (id + 1)..<tree.stop[id] {
    if tree.kind[current] == Kind::Text {
      if decodable(tree, current) {
        output.write_string(
          decode_html(slice(source, tree.from[current], tree.to[current])),
        )
      } else {
        output.write_substring(
          source,
          tree.from[current],
          tree.to[current] - tree.from[current],
        )
      }
    }
  }
  output.to_string()
}
