///|
fn invalid(selector : String) -> Bool {
  let failed : Result[Array[@html.Element], @html.SelectorError] = Ok(
    @html.parse("<p></p>").all(selector),
  ) catch {
    e => Err(e)
  }
  failed is Err(@html.SelectorError::InvalidSelector(_))
}

///|
test "class selectors accept CSS escapes" {
  let doc = @html.parse("<p class=\"\u{e9}\">x</p><a class=\"\u{fffd}\">y</a>")
  // "\e9" decodes to é and exercises the a-f hex branch.
  assert_eq(doc.all(".\\e9").length(), 1)
  // A code point beyond U+10FFFF decodes to U+FFFD.
  assert_eq(doc.all(".\\110000").length(), 1)
}

///|
test "nth expressions cover signs and keywords" {
  let doc = @html.parse("<ul><li>a</li><li>b</li><li>c</li><li>d</li></ul>")
  assert_eq(doc.all("li:nth-child(n)").length(), 4)
  assert_eq(doc.all("li:nth-child(+n)").length(), 4)
  assert_eq(doc.all("li:nth-child(-n+2)").length(), 2)
  assert_eq(doc.all("li:nth-child(-3)").length(), 0)
  assert_eq(doc.all("li:nth-child(2n+1)").length(), 2)
  assert_eq(doc.find("li:nth-last-of-type(2)").unwrap().text(), "c")
  assert_eq(doc.all("li:nth-child(odd)").length(), 2)
}

///|
test "only-of-type and nested pseudo arguments" {
  let doc = @html.parse(
    "<div><p>a</p><p>a2</p><span><p>b</p></span></div><p>c</p>",
  )
  assert_eq(doc.find("p:only-of-type").unwrap().text(), "b")
  // Nested parentheses inside :not(:is(...)) are tracked by depth.
  assert_eq(doc.all("div:not(:is(section))").length(), 1)
  assert_eq(doc.all("p:not(:is(.lead))").length(), 4)
}

///|
test "invalid selectors raise SelectorError" {
  assert_true(invalid(":nth-child()"))
  assert_true(invalid(":nth-child(-)"))
  assert_true(invalid(":nth-child(n+x)"))
  assert_true(invalid(":nth-child(2n"))
  assert_true(invalid(":foo(1)"))
  assert_true(invalid("p=q"))
}

///|
test "attribute operators compare in place" {
  let doc = @html.parse(
    "<a href=\"/x\" data-id=\"7\">a</a><p class=\"one two\">b</p>",
  )
  assert_eq(doc.all("[href]").length(), 1)
  assert_eq(doc.all("[class~=two]").length(), 1)
  assert_eq(doc.all("[class~=nope]").length(), 0)
  assert_eq(doc.find("[data-id=\"7\"]").unwrap().name(), "a")
}

///|
test "queries without candidate tags walk the tree" {
  let doc = @html.parse("<p class=lead>a</p><p>b</p>")
  // A class-only selector has no candidate tags, so matching walks the
  // tree and stops at the limit.
  assert_eq(doc.find(".lead").unwrap().text(), "a")
  // A document without elements has no tag index at all.
  assert_eq(@html.parse("plain text").all("p"), [])
}

///|
test "the selector cache evicts when full" {
  let doc = @html.parse("<p class=c0>a</p>")
  for i in 0..<520 {
    let _ = doc.all(".c\{i}")
  }
  assert_eq(doc.all(".c0").length(), 1)
}
