///|
let mutable_source : String = "<!doctype html>\n<html>\n<head>\n\t<title>Hi &amp; bye</title>\n\t<link rel=\"canonical\" href=\"https://example.com/?a=1&amp;b=2\">\n</head>\n<body>\n\t<!-- note -->\n\t<nav><a href=\"/\" CLASS=x>Home</a><a href=\"/about/\">About</a></nav>\n\t<p>One <b>two</b> &lt;three&gt;<p>implied\n\t<ul><li>1<li>2</ul>\n\t<img src=a.png>\n\t<script>if (a < b) \"&amp;\"</script>\n</body>\n</html>"

///|
fn contents(nodes : Array[@mutable.Node]) -> Array[@mutable.Content] {
  nodes.map(node => @mutable.Content::Node(node))
}

///|
fn shape(node : @mutable.Node) -> String {
  match node {
    Text(text) => text.value()
    Comment(_) => "comment"
    Directive(_) => "directive"
    Element(element) =>
      element.name() + "(" + element.children().map(shape).join(",") + ")"
  }
}

///|
fn document_shape(doc : @mutable.Document) -> String {
  "#document(" + doc.children().map(shape).join(",") + ")"
}

///|
test "parse round trips exactly and reads values" {
  for
    source in [
      mutable_source, "", "text", "<p>a<p>b", "<a href=x/>", "<!--x", "<svg><path/></svg>",
    ] {
    let doc = @mutable.parse(source)
    assert_eq(doc.stringify(), source)
    for element in doc.all("*") {
      assert_eq(
        element.stringify(),
        source[element.start().unwrap():element.end().unwrap()].to_owned(),
      )
    }
  }
  let doc = @mutable.parse(mutable_source)
  assert_eq(doc.find("title").unwrap().text(), "Hi & bye")
  assert_eq(
    doc.find("link").unwrap().get_attr("href"),
    Some("https://example.com/?a=1&b=2"),
  )
  assert_eq(doc.find("script").unwrap().text(), "if (a < b) \"&amp;\"")
  assert_eq(doc.find("a"), Some(doc.all("a")[0]))
  assert_eq(
    doc.find("a").unwrap().parent(),
    Some(@mutable.Parent::Element(doc.find("nav").unwrap())),
  )
  assert_eq(
    doc.find("html").unwrap().parent(),
    Some(@mutable.Parent::Document(doc)),
  )
}

///|
test "attributes add, replace, remove, escape, and retain snapshots" {
  let doc = @mutable.parse("<a href=\"/\">x</a>")
  let a = doc.find("a").unwrap()
  a.set_attr("HREF", "/next?a=1&b=2")
  a.set_attr("title", "say \"hi\" > bye")
  assert_eq(a.get_attr("href"), Some("/next?a=1&b=2"))
  assert_eq(a.get_attr("title"), Some("say \"hi\" > bye"))
  assert_eq(
    doc.stringify(),
    "<a href=\"/next?a=1&amp;b=2\" title=\"say &quot;hi&quot; > bye\">x</a>",
  )
  assert_eq(
    @mutable.parse(doc.stringify()).find("a").unwrap().attributes(),
    a.attributes(),
  )
  let before = a.attributes()
  a.set_attr("id", "y")
  assert_eq(before.get("id"), None)
  assert_eq(a.get_attr("id"), Some("y"))
  for bad in ["", "a b", "a\"", "a>", "a=b", "a/"] {
    let result = Ok(a.set_attr(bad, "x")) catch { e => Err(e) }
    assert_true(result is Err(@mutable.HtmlError::InvalidName(_)))
  }
  let input_doc = @mutable.parse("<input type=\"checkbox\" disabled checked>")
  let input = input_doc.find("input").unwrap()
  input.remove_attr("CHECKED")
  input.remove_attr("missing")
  assert_false(input.has_attr("checked"))
  assert_eq(input_doc.stringify(), "<input type=\"checkbox\" disabled>")
}

///|
test "tag rebuilding preserves unedited source spelling" {
  let doc = @mutable.parse(
    "<svg viewBox=\"0 0 24 24\"><linearGradient gradientUnits='userSpaceOnUse' title=&copy; hidden></linearGradient></svg>",
  )
  doc.find("svg").unwrap().set_attr("class", "icon")
  doc.find("linearGradient").unwrap().set_attr("id", "g")
  assert_eq(
    doc.stringify(),
    "<svg viewBox=\"0 0 24 24\" class=\"icon\"><linearGradient gradientUnits='userSpaceOnUse' title=&copy; hidden id=\"g\"></linearGradient></svg>",
  )
  let other = @mutable.parse(
    "<P CLASS=a>x</P><img src=a.png  alt='x' /><a href= >y</a>",
  )
  other.find("p").unwrap().set_attr("id", "b")
  other.find("img").unwrap().set_attr("loading", "lazy")
  other.find("a").unwrap().set_attr("rel", "n")
  assert_eq(
    other.stringify(),
    "<P CLASS=a id=\"b\">x</P><img src=a.png  alt='x' loading=\"lazy\"/><a href=\"\" rel=\"n\">y</a>",
  )
  let nested = @mutable.parse("<div  class='a'><p  id=x>t</p></div>")
  nested.find("p").unwrap().set_attr("id", "y")
  assert_eq(nested.stringify(), "<div  class='a'><p id=\"y\">t</p></div>")
}

///|
test "attribute spelling and selectors follow edits" {
  let doc = @mutable.parse("<svg viewBox=\"0 0 1 1\" refX=1></svg>")
  let svg = doc.find("svg").unwrap()
  svg.set_attr("VIEWBOX", "0 0 2 2")
  svg.set_attr("preserveAspectRatio", "none")
  svg.set_attr("focusable", "")
  svg.remove_attr("refx")
  svg.set_attr("refx", "2")
  assert_eq(
    doc.stringify(),
    "<svg viewBox=\"0 0 2 2\" preserveAspectRatio=\"none\" focusable=\"\" refX=\"2\"></svg>",
  )
  svg.remove_attr("preserveaspectratio")
  svg.set_attr("preserveaspectratio", "none")
  assert_eq(
    doc.stringify(),
    "<svg viewBox=\"0 0 2 2\" focusable=\"\" refX=\"2\" preserveaspectratio=\"none\"></svg>",
  )
  let links = @mutable.parse("<a></a><a></a>")
  links.all("a")[1].set_attr("data-x", "1")
  assert_eq(links.all("[data-x=\"1\"]"), [links.all("a")[1]])
  assert_false(links.find("a").unwrap().matches("[data-x]"))
}

///|
test "element renaming follows HTML and SVG rules" {
  let doc = @mutable.parse("<h2 id=a>T <b>x</b></h2><ul><li>a<li>b</ul>")
  let h2 = doc.find("h2").unwrap()
  h2.set_name("H5")
  doc.find("li").unwrap().set_name("p")
  assert_eq(h2.name(), "h5")
  assert_eq(doc.find("h5"), Some(h2))
  assert_eq(doc.find("h2"), None)
  assert_eq(doc.stringify(), "<h5 id=a>T <b>x</b></h5><ul><p>a</p><li>b</ul>")
  let svg = @mutable.parse("<svg><path d=\"M0\"/></svg>")
  svg.find("path").unwrap().set_name("LINEARGRADIENT")
  assert_eq(svg.find("path"), None)
  assert_eq(
    svg.stringify(),
    "<svg><linearGradient d=\"M0\"></linearGradient></svg>",
  )
  let voids = @mutable.parse("<br/><img src=a><div>x</div>")
  voids.find("br").unwrap().set_name("hr")
  voids.find("img").unwrap().set_name("span")
  let invalid = Ok(voids.find("div").unwrap().set_name("img")) catch {
    e => Err(e)
  }
  assert_true(invalid is Err(@mutable.HtmlError::InvalidName(_)))
  assert_eq(voids.stringify(), "<hr><span src=a></span><div>x</div>")
  let raw = @mutable.parse("<div>a &lt; b</div>")
  raw.find("div").unwrap().set_name("script")
  assert_eq(raw.stringify(), "<script>a < b</script>")
}

///|
test "invalid element names and raw-text child rules raise" {
  let div = @mutable.parse("<div>").find("div").unwrap()
  for bad in ["", "1a", "a b", "a>", "a/b", "a\""] {
    let result = Ok(div.set_name(bad)) catch { e => Err(e) }
    assert_true(result is Err(@mutable.HtmlError::InvalidName(_)))
  }
  let doc = @mutable.parse("<div><b>x</b></div><p>y</p><svg><g><b/></g></svg>")
  let result = Ok(doc.find("div").unwrap().set_name("script")) catch {
    e => Err(e)
  }
  assert_true(result is Err(@mutable.HtmlError::InvalidName(_)))
  doc.find("p").unwrap().set_name("title")
  doc.find("g").unwrap().set_name("title")
  assert_eq(
    doc.stringify(),
    "<div><b>x</b></div><title>y</title><svg><title><b/></title></svg>",
  )
}

///|
test "text and HTML setters replace children with contextual parsing" {
  let doc = @mutable.parse("<p>a <b>b</b></p>")
  let p = doc.find("p").unwrap()
  p.set_text("<c> & d")
  assert_eq(p.text(), "<c> & d")
  assert_eq(p.children().length(), 1)
  assert_eq(doc.stringify(), "<p>&lt;c&gt; &amp; d</p>")
  assert_eq(
    @mutable.parse(doc.stringify()).find("p").unwrap().text(),
    "<c> & d",
  )
  let script = @mutable.parse("<script>x</script>")
  script.find("script").unwrap().set_text("a < b && c")
  assert_eq(script.stringify(), "<script>a < b && c</script>")
  let list = @mutable.parse("<ul><li>a</li></ul>")
  let ul = list.find("ul").unwrap()
  ul.set_html("<li>b<li>c")
  assert_eq(ul.all("li").map(x => x.text()), ["b", "c"])
  assert_eq(ul.html(), "<li>b<li>c")
  assert_eq(list.stringify(), "<ul><li>b<li>c</ul>")
  assert_eq(list.find("li").unwrap().document(), list)
  assert_eq(list.find("li").unwrap().start(), None)
}

///|
test "HTML setter respects SVG integration and raw text contexts" {
  let doc = @mutable.parse(
    "<svg><g></g><foreignObject></foreignObject></svg><div></div>",
  )
  doc.find("g").unwrap().set_html("<path/><lineargradient/>")
  doc.find("foreignObject").unwrap().set_html("<p/>x")
  doc.find("div").unwrap().set_html("<path/>x")
  assert_eq(
    doc
    .find("g")
    .unwrap()
    .children()
    .map(node => {
      match node {
        Element(e) => e.name()
        _ => ""
      }
    }),
    ["path", "linearGradient"],
  )
  assert_eq(doc.find("foreignObject").unwrap().find("p").unwrap().text(), "x")
  assert_eq(doc.find("div").unwrap().find("path").unwrap().text(), "x")
  let raw = @mutable.parse("<title>a</title><style>x</style>")
  raw.find("title").unwrap().set_html("b &amp; <i>c</i>")
  raw.find("style").unwrap().set_html("a > b {}")
  assert_eq(raw.find("title").unwrap().text(), "b & <i>c</i>")
  assert_eq(raw.find("style").unwrap().text(), "a > b {}")
  let foreign = @mutable.parse("<svg><style>a</style></svg>")
  let style = foreign.find("style").unwrap()
  style.set_html("<b>&amp;")
  assert_eq(style.children().length(), 1)
  style.set_text("<&>")
  assert_eq(foreign.stringify(), "<svg><style>&lt;&amp;&gt;</style></svg>")
}

///|
test "leaf setters escape and validate values" {
  let doc = @mutable.parse("<p>a</p>")
  guard doc.find("p").unwrap().children()[0] is Text(text) else {
    fail("expected text")
  }
  text.set_value("<b>")
  assert_eq(doc.stringify(), "<p>&lt;b&gt;</p>")
  let leaves = @mutable.parse("<!doctype html><!-- a -->")
  guard leaves.children()[0] is Directive(directive) else {
    fail("expected directive")
  }
  guard leaves.children()[1] is Comment(comment) else {
    fail("expected comment")
  }
  directive.set_value("DOCTYPE html")
  comment.set_value(" b ")
  for bad in ["-->", "a--!>b", ">a", "->a"] {
    let result = Ok(comment.set_value(bad)) catch { e => Err(e) }
    assert_true(result is Err(@mutable.HtmlError::InvalidValue(_)))
  }
  comment.set_value("a-")
  let invalid = Ok(directive.set_value("x")) catch { e => Err(e) }
  assert_true(invalid is Err(@mutable.HtmlError::InvalidValue(_)))
  assert_eq(leaves.stringify(), "<!DOCTYPE html><!--a--->")
}

///|
test "append prepend before after replace and remove" {
  let doc = @mutable.parse("<ul><li>b</li></ul>")
  let ul = doc.find("ul").unwrap()
  let li = doc.find("li").unwrap()
  ul.append(contents(@mutable.parse("<li>d</li>").children()))
  ul.prepend([@mutable.Content::Text("a")])
  li.after([@mutable.Content::Text("c")])
  li.before([@mutable.Content::Text("x")])
  assert_eq(doc.stringify(), "<ul>ax<li>b</li>c<li>d</li></ul>")
  assert_eq(ul.all("li").map(x => x.text()), ["b", "d"])
  let top = @mutable.parse("<p>a</p>")
  top.append([@mutable.Content::Text("z")])
  top.prepend(contents(@mutable.parse("<!doctype html>").children()))
  assert_eq(top.stringify(), "<!doctype html><p>a</p>z")
  let replace = @mutable.parse("<p>a<b>b</b><i>c</i></p>")
  let b = replace.find("b").unwrap()
  let replacements : Array[@mutable.Content] = [@mutable.Content::Text("C")]
  for item in contents(@mutable.parse("<em>!</em>").children()) {
    replacements.push(item)
  }
  replace.find("i").unwrap().replace(replacements)
  b.remove()
  assert_eq(b.parent(), None)
  assert_eq(b.stringify(), "<b>b</b>")
  assert_eq(replace.stringify(), "<p>aC<em>!</em></p>")
}

///|
test "moving nodes within and between documents" {
  let doc = @mutable.parse("<a>1</a><b>2</b><c>3</c>")
  let a = doc.find("a").unwrap()
  doc
  .find("c")
  .unwrap()
  .after([@mutable.Content::Node(@mutable.Node::Element(a))])
  doc
  .find("b")
  .unwrap()
  .prepend([
    @mutable.Content::Node(@mutable.Node::Element(doc.find("c").unwrap())),
  ])
  assert_eq(doc.stringify(), "<b><c>3</c>2</b><a>1</a>")
  assert_eq(a.start(), Some(0))
  let from = @mutable.parse("<p>x</p>")
  let to = @mutable.parse("<div></div>")
  let p = from.find("p").unwrap()
  to
  .find("div")
  .unwrap()
  .append([@mutable.Content::Node(@mutable.Node::Element(p))])
  assert_eq(p.document(), to)
  assert_eq(p.start(), None)
  assert_eq(from.stringify(), "")
  assert_eq(to.stringify(), "<div><p>x</p></div>")
}

///|
test "clone creates independent detached deep copies" {
  let doc = @mutable.parse("<svg><g id=a><path d=\"M0\"/><!--c--></g></svg>")
  let g = doc.find("g").unwrap()
  g.set_attr("class", "x")
  let copy = g.clone()
  assert_true(copy != g)
  assert_eq(copy.parent(), None)
  assert_eq(copy.document(), doc)
  assert_eq(
    copy.stringify(),
    "<g id=a class=\"x\"><path d=\"M0\"/><!--c--></g>",
  )
  copy.set_attr("id", "b")
  copy.find("path").unwrap().set_attr("d", "M1")
  doc
  .find("svg")
  .unwrap()
  .append([@mutable.Content::Node(@mutable.Node::Element(copy))])
  assert_eq(
    doc.stringify(),
    "<svg><g id=a class=\"x\"><path d=\"M0\"/><!--c--></g><g id=\"b\" class=\"x\"><path d=\"M1\"/><!--c--></g></svg>",
  )
  assert_eq(doc.all("path").map(x => x.get_attr("d")), [Some("M0"), Some("M1")])
  let svg_doc = @mutable.parse("<svg></svg>")
  let svg = svg_doc.find("svg").unwrap()
  svg.set_attr("viewBox", "0 0 1 1")
  let svg_copy = svg.clone()
  svg.remove_attr("viewbox")
  assert_eq(svg_copy.stringify(), "<svg viewBox=\"0 0 1 1\"></svg>")
  let leaves = @mutable.parse("<!doctype html><!--c-->t")
  let copies = leaves
    .children()
    .map(node => @mutable.Content::Node(node.clone()))
  leaves.append(copies)
  assert_eq(
    leaves.stringify(),
    "<!doctype html><!--c-->t<!doctype html><!--c-->t",
  )
}

///|
test "invalid inserts raise without corrupting the tree" {
  let doc = @mutable.parse("<div><p>x</p></div><img>")
  let div = doc.find("div").unwrap()
  let p = doc.find("p").unwrap()
  let cycle = Ok(
    p.append([@mutable.Content::Node(@mutable.Node::Element(div))]),
  ) catch {
    e => Err(e)
  }
  assert_true(cycle is Err(@mutable.HtmlError::InvalidInsertion(_)))
  let self_insert = Ok(
    div.append([@mutable.Content::Node(@mutable.Node::Element(div))]),
  ) catch {
    e => Err(e)
  }
  assert_true(self_insert is Err(@mutable.HtmlError::InvalidInsertion(_)))
  let void_insert = Ok(
    doc.find("img").unwrap().append([@mutable.Content::Text("x")]),
  ) catch {
    e => Err(e)
  }
  assert_true(void_insert is Err(@mutable.HtmlError::InvalidInsertion(_)))
  p.remove()
  let detached = Ok(p.before([@mutable.Content::Text("x")])) catch {
    e => Err(e)
  }
  assert_true(detached is Err(@mutable.HtmlError::NoParent))
}

///|
test "implied close serialization stays equivalent after edits" {
  let first = @mutable.parse("<p>a<p>b")
  first.find("p").unwrap().append([@mutable.Content::Text("!")])
  assert_eq(first.stringify(), "<p>a!<p>b")
  let cases = ["<p>a<p>b", "<ul><li>a<li>b</ul>", "<div><p>a</div>"]
  for source in cases {
    let doc = @mutable.parse(source)
    match doc.all("*")[0].name() {
      "p" =>
        doc
        .find("p")
        .unwrap()
        .after(contents(@mutable.parse("<span>s</span>").children()))
      "ul" =>
        doc
        .find("li")
        .unwrap()
        .after(contents(@mutable.parse("<span>s</span>").children()))
      _ =>
        doc
        .find("div")
        .unwrap()
        .append(contents(@mutable.parse("<span>s</span>").children()))
    }
    let expected = match source {
      "<p>a<p>b" => "<p>a</p><span>s</span><p>b"
      "<ul><li>a<li>b</ul>" => "<ul><li>a</li><span>s</span><li>b</ul>"
      _ => "<div><p>a</p><span>s</span></div>"
    }
    assert_eq(doc.stringify(), expected)
    assert_eq(document_shape(@mutable.parse(expected)), document_shape(doc))
  }
  let open = @mutable.parse("<div>x")
  open.append([@mutable.Content::Text("y")])
  assert_eq(open.stringify(), "<div>x</div>y")
  let renamed = @mutable.parse("<p>a<p>b")
  renamed.all("p")[1].set_name("span")
  assert_eq(renamed.stringify(), "<p>a</p><span>b</span>")
}

///|
test "self closing tags remain valid after edits" {
  let doc = @mutable.parse("<svg><path d=\"M0\"/><path d=\"M1\"/></svg>")
  doc.find("path").unwrap().set_attr("fill", "red")
  assert_eq(
    doc.stringify(),
    "<svg><path d=\"M0\" fill=\"red\"/><path d=\"M1\"/></svg>",
  )
  let nested = @mutable.parse("<svg><g/></svg>")
  let path = @mutable.parse("<svg><path d=\"M2\"/></svg>").find("path").unwrap()
  nested
  .find("g")
  .unwrap()
  .append([@mutable.Content::Node(@mutable.Node::Element(path))])
  assert_eq(nested.stringify(), "<svg><g><path d=\"M2\"/></g></svg>")
  let title = @mutable.parse("<svg><title/></svg>")
  title.find("title").unwrap().set_text("Hi")
  assert_eq(title.stringify(), "<svg><title>Hi</title></svg>")
  let cleared = @mutable.parse("<svg><g/></svg>")
  let g = cleared.find("g").unwrap()
  g.append([@mutable.Content::Text("x")])
  g.set_html("")
  assert_eq(cleared.stringify(), "<svg><g/></svg>")
  let unquoted = @mutable.parse("<svg><path d=M0/><path d=M1 / ></svg>")
  for path in unquoted.all("path") {
    path.set_attr("fill", "red")
  }
  assert_eq(
    unquoted.stringify(),
    "<svg><path d=M0/ fill=\"red\"><path d=M1 fill=\"red\"/></svg>",
  )
}

///|
test "document reads, positions, templates, and empty see edits" {
  let doc = @mutable.parse("a &amp; <p>b<!--c--></p>")
  doc.append([@mutable.Content::Text("d")])
  assert_eq(doc.text(), "a & bd")
  let positions = @mutable.parse("<p>\n<img>")
  let start = positions.find("img").unwrap().start().unwrap()
  positions.prepend([@mutable.Content::Text("lots\nof\ntext")])
  assert_eq(positions.position(start), { line: 2, column: 1, })
  assert_eq(positions.source(), "<p>\n<img>")
  let templates = @mutable.parse(
    "<template><p class=\"x\">a</p></template><p class=\"x\">b</p>",
  )
  assert_eq(templates.all(".x").map(x => x.text()), ["b"])
  assert_eq(templates.find("template").unwrap().all(".x").map(x => x.text()), [
    "a",
  ])
  let p = @mutable.parse("<p></p>")
  assert_eq(p.find("p:empty").unwrap().name(), "p")
  p.find("p").unwrap().append([@mutable.Content::Text("x")])
  assert_eq(p.find("p:empty"), None)
  assert_eq(p.start(), 0)
  assert_eq(p.end(), p.source().length())
}
