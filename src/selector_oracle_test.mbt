///|
test "all upstream selectors match css-select offsets and source order" {
  let doc = @html.parse(selector_html)
  for case in selector_oracles {
    let (selector, expected) = case
    let actual = doc.all(selector).map(element => element.start())
    if actual != expected {
      println("selector oracle mismatch: " + selector)
    }
    assert_eq(actual, expected)
  }
}
