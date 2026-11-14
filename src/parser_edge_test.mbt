///|
test "implied end tags for table cells and ruby annotations" {
  let table = @html.parse("<table><tr><th>a<th>b</tr></table>")
  let ths = table.all("th")
  assert_eq(ths.length(), 2)
  assert_eq(ths[0].text(), "a")
  assert_eq(ths[1].text(), "b")
  let ruby = @html.parse("<ruby><rt>a<rt>b<rp>(</ruby>")
  assert_eq(ruby.all("rt").length(), 2)
  assert_eq(ruby.all("rp").length(), 1)
}

///|
test "svg tag names keep their camelCase forms" {
  let doc = @html.parse(
    "<svg><altglyph></altglyph><feblend></feblend><glyphref></glyphref><radialgradient></radialgradient></svg>",
  )
  let names = doc.all("*").map(element => element.name())
  assert_true(names.contains("altGlyph"))
  assert_true(names.contains("feBlend"))
  assert_true(names.contains("glyphRef"))
  assert_true(names.contains("radialGradient"))
}

///|
test "a greater-than sign inside a quoted value does not end the tag" {
  let doc = @html.parse("<a href=\"x>y\">link</a>")
  let a = doc.find("a").unwrap()
  assert_eq(a.get_attr("href"), Some("x>y"))
  assert_eq(a.text(), "link")
  // Without the closing quote there is no tag at all.
  assert_eq(@html.parse("<a href=\"x>").find("a"), None)
}

///|
test "large documents pre-size the tree" {
  let source = "<p>" + "x".repeat(2000) + "</p>"
  let doc = @html.parse(source)
  assert_eq(doc.find("p").unwrap().text().length(), 2000)
  assert_eq(doc.stringify(), source)
}

///|
test "unterminated raw text runs to the end of input" {
  let doc = @html.parse("<script>var x = 1")
  assert_eq(doc.find("script").unwrap().text(), "var x = 1")
}

///|
test "comments ending in dashes at EOF" {
  let doc = @html.parse("<!--x--")
  guard doc.children() is [@html.Node::Comment(comment)] else {
    abort("expected a comment")
  }
  assert_eq(comment.value(), "x")
}

///|
test "empty raw text elements stay empty" {
  let doc = @html.parse("<script></script><textarea></textarea><title></title>")
  assert_eq(doc.find("script").unwrap().text(), "")
  assert_eq(doc.find("textarea").unwrap().text(), "")
  assert_eq(doc.find("title").unwrap().text(), "")
}
