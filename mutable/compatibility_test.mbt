///|
test "mutable selectors and reads agree with immutable handles" {
  let immutable = @html.parse(mutable_source)
  let mutable = @mutable.parse(mutable_source)
  let selectors = [
    "*", "a", "nav > a + a", "head title", "link[rel=canonical]", "a.x", "p:first-of-type",
    "li:nth-child(2)", ":root", "img:not([alt])", "[constructor]",
  ]
  for selector in selectors {
    let expected = immutable.all(selector).map(element => element.start())
    let actual = mutable.all(selector).map(element => element.start().unwrap())
    assert_eq(actual, expected)
  }
  let left = immutable.all("*")
  let right = mutable.all("*")
  assert_eq(left.length(), right.length())
  for i in 0..<left.length() {
    assert_eq(right[i].name(), left[i].name())
    assert_eq(right[i].attributes(), left[i].attributes())
    assert_eq(right[i].text(), left[i].text())
    assert_eq(right[i].html(), left[i].html())
  }
}
