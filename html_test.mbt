///|
let source : String = "<!doctype html>\n<html>\n<head>\n\t<title>Hi &amp; bye</title>\n\t<link rel=\"canonical\" href=\"https://example.com/?a=1&amp;b=2\">\n</head>\n<body>\n\t<!-- note -->\n\t<nav><a href=\"/\" CLASS=\"x\">Home</a></nav>\n\t<p>One <b>two</b> &lt;three&gt;</p>\n\t<script>if (a < b) \"&amp;\"</script>\n</body>\n</html>"

///|
test "parse returns a lossless document" {
  let doc = @html.parse(source)
  assert_eq(doc.source(), source)
  assert_eq(doc.start(), 0)
  assert_eq(doc.end(), source.length())
  assert_eq(doc.stringify(), source)
  assert_eq(doc.children().length(), 3)
  assert_true(doc.children()[0] is Directive(_))
  assert_true(doc.children()[1] is Text(_))
  assert_true(doc.children()[2] is Element(_))
}

///|
test "handles refer to the same parsed nodes" {
  let doc = @html.parse(source)
  assert_eq(doc.find("a"), Some(doc.all("a")[0]))
  assert_eq(
    doc.find("a").unwrap().parent(),
    @html.Parent::Element(doc.find("nav").unwrap()),
  )
  assert_eq(doc.find("a").unwrap().document(), doc)
}

///|
test "precompiled selectors can be reused" {
  let doc = @html.parse(source)
  let selector = @html.Selector::parse("nav > a.x")
  assert_eq(doc.find_with(selector), doc.find("a"))
  assert_eq(doc.all_with(selector).length(), 1)
  let a = doc.find("a").unwrap()
  assert_true(a.matches_with(selector))
  assert_eq(a.closest_with(selector), Some(a))
  assert_eq(doc.find("nav").unwrap().find_with(selector), Some(a))
  assert_eq(doc.find("nav").unwrap().all_with(selector), [a])
}

///|
test "malformed HTML never raises" {
  for bad in ["<", "<a", "</", "<!--", "<a href='x", "<<<>>>", "\u{0}"] {
    let _ = @html.parse(bad).all("*")
  }
}

///|
test "document text, missing queries, and invalid selectors" {
  let doc = @html.parse("a &amp; <p>b<!--c--></p><script>&amp;</script>")
  assert_eq(doc.text(), "a & b&amp;")
  assert_eq(doc.find("video"), None)
  let failed : Result[Array[@html.Element], @html.SelectorError] = Ok(
    doc.all("a["),
  ) catch {
    e => Err(e)
  }
  assert_true(failed is Err(@html.SelectorError::InvalidSelector(_)))
}

///|
test "position maps UTF-16 offsets to one-based lines and columns" {
  let doc = @html.parse(source)
  assert_eq(doc.position(0), { line: 1, column: 1, })
  assert_eq(doc.position(doc.find("link").unwrap().start()), {
    line: 5,
    column: 2,
  })
  assert_eq(doc.position(source.length()), { line: 13, column: 8, })
}

///|
test "element names, ranges, and attributes" {
  let doc = @html.parse(source)
  let a = doc.find("a").unwrap()
  assert_eq(a.name(), "a")
  assert_eq(source[a.start():a.end()], "<a href=\"/\" CLASS=\"x\">Home</a>")
  assert_eq(a.get_attr("class"), Some("x"))
  assert_eq(a.get_attr("Class"), Some("x"))
  assert_eq(a.get_attr("id"), None)
  assert_true(a.has_attr("CLASS"))
  assert_false(a.has_attr("constructor"))
  let link = doc.find("link").unwrap()
  let attrs = link.attributes()
  assert_eq(attrs.get("rel"), Some("canonical"))
  assert_eq(attrs.get("href"), Some("https://example.com/?a=1&b=2"))
  attrs["rel"] = "changed"
  assert_eq(link.get_attr("rel"), Some("canonical"))
}

///|
test "element text and inner HTML" {
  let doc = @html.parse(source)
  assert_eq(doc.find("title").unwrap().text(), "Hi & bye")
  assert_eq(doc.find("p").unwrap().text(), "One two <three>")
  assert_eq(doc.find("script").unwrap().text(), "if (a < b) \"&amp;\"")
  assert_eq(doc.find("p").unwrap().html(), "One <b>two</b> &lt;three&gt;")
  let svg = @html.parse("<svg><style>a&amp;b</style></svg><style>&amp;</style>")
  assert_eq(svg.find("svg style").unwrap().text(), "a&b")
  assert_eq(svg.find("style:not(svg style)").unwrap().text(), "&amp;")
}

///|
test "children include text and comments" {
  let body = @html.parse(source).find("body").unwrap()
  let kinds = body
    .children()
    .map(node => {
      match node {
        Element(_) => "element"
        Text(_) => "text"
        Comment(_) => "comment"
        Directive(_) => "directive"
      }
    })
  assert_eq(kinds, [
    "text", "comment", "text", "element", "text", "element", "text", "element", "text",
  ])
}

///|
test "element queries are scoped" {
  let doc = @html.parse(source)
  let nav = doc.find("nav").unwrap()
  assert_eq(nav.find("a").unwrap().text(), "Home")
  assert_eq(nav.all("p"), [])
}

///|
test "matches and closest" {
  let doc = @html.parse(source)
  let a = doc.find("a").unwrap()
  assert_true(a.matches("nav > a.x"))
  assert_false(a.matches("p a"))
  assert_eq(a.closest("a"), Some(a))
  assert_eq(a.closest("body").unwrap().name(), "body")
  assert_eq(a.closest("p"), None)
}

///|
test "leaf values, parents, and source ranges" {
  let doc = @html.parse(source)
  guard doc.children()[0] is Directive(directive) else {
    fail("expected directive")
  }
  guard doc.find("body").unwrap().children()[1] is Comment(comment) else {
    fail("expected comment")
  }
  guard doc.find("title").unwrap().children()[0] is Text(text) else {
    fail("expected text")
  }
  assert_eq(directive.value(), "doctype html")
  assert_eq(comment.value(), " note ")
  assert_eq(text.value(), "Hi & bye")
  assert_eq(text.parent(), @html.Parent::Element(doc.find("title").unwrap()))
  assert_eq(directive.parent(), @html.Parent::Document(doc))
  for
    node in [
      @html.Node::Directive(directive),
      @html.Node::Comment(comment),
      @html.Node::Text(text),
    ] {
    assert_eq(node.stringify(), source[node.start():node.end()].to_owned())
    assert_eq(node.document(), doc)
  }
}

///|
test "stringify round trips every node" {
  let doc = @html.parse(source)
  for element in doc.all("*") {
    assert_eq(
      @html.stringify(element),
      source[element.start():element.end()].to_owned(),
    )
  }
  assert_eq(@html.stringify(doc), source)
}
