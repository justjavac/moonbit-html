///|
test "detached foreign elements serialize with their own context" {
  let doc = @mutable.parse("<svg><g><path></path></g></svg>")
  let path = doc.find("path").unwrap()
  path.remove()
  assert_eq(path.stringify(), "<path></path>")
  let nested = @mutable.parse("<svg><foreignObject><p>x</p></foreignObject></svg>")
  let p = nested.find("p").unwrap()
  p.remove()
  assert_eq(p.stringify(), "<p>x</p>")
}

///|
test "renaming a detached element reads the foreign context from the tree" {
  let doc = @mutable.parse("<svg><foreignObject><p>x</p></foreignObject></svg>")
  let p = doc.find("p").unwrap()
  p.remove()
  p.set_name("div")
  assert_eq(p.stringify(), "<div>x</div>")
  let svg = @mutable.parse("<svg><g><path></path></g></svg>")
  let path = svg.find("path").unwrap()
  path.remove()
  path.set_name("circle")
  assert_eq(path.stringify(), "<circle></circle>")
}
