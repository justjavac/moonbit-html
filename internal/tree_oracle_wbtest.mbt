///|
fn attribute_detail(tree : Tree, id : Int32) -> String {
  let entries = attributes(tree, id).to_array()
  let fields = entries.map(entry => {
    let (name, value) = entry
    name.escape() + ":" + value.escape()
  })
  "{" + fields.join(",") + "}"
}

///|
fn oracle_lines(html : String) -> Array[String] {
  let tree = build(html)
  let depths = [-1]
  let output : Array[String] = []
  for id in 1..<tree.size {
    let depth = depths[tree.parent[id]] + 1
    depths.push(depth)
    let (kind, detail) = match tree.kind[id] {
      Element => ("element", tree.name[id] + " " + attribute_detail(tree, id))
      Text => ("text", value(tree, id))
      Comment => ("comment", "")
      Directive => ("directive", "")
      Document => abort("unreachable")
    }
    if kind == "text" && output.length() > 0 {
      let last = output.length() - 1
      let previous = output[last]
      let split = previous.split("|")
      let prefix = match (split.next(), split.next()) {
        (Some(previous_depth), Some("text")) if previous_depth ==
          depth.to_string() => Some(previous_depth + "|text|")
        _ => None
      }
      if prefix is Some(value) {
        let start = value.length()
        output[last] = value.to_owned() +
          previous.unsafe_view(start~, end=previous.length()).to_owned() +
          detail
        continue
      }
    }
    output.push("\{depth}|\{kind}|\{detail}")
  }
  output
}

///|
test "all upstream tree cases match htmlparser2 oracle lines" {
  for case in tree_oracles {
    let (name, input, expected) = case
    let actual = oracle_lines(input)
    if actual != expected {
      println("oracle mismatch: " + name)
    }
    assert_eq(actual, expected)
  }
}
