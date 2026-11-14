///|
test "attribute edits preserve slashes and unquoted values" {
  let doc = @mutable.parse(
    "<img alt=x src=a.png /><svg><path d=\"M0\" fill=red /><path/></svg>",
  )
  doc.find("img").unwrap().set_attr("alt", "y")
  doc.find("path").unwrap().set_attr("d", "M9")
  let output = doc.stringify()
  assert_eq(
    output, "<img alt=\"y\" src=a.png /><svg><path d=\"M9\" fill=red /><path/></svg>",
  )
  let again = @mutable.parse(output)
  assert_eq(again.find("img").unwrap().get_attr("src"), Some("a.png"))
  assert_eq(again.all("svg > path").length(), 2)
}

///|
test "renames follow the current parser context" {
  let doc = @mutable.parse("<div></div><p></p><svg><g></g><image/></svg>")
  let div = doc.find("div").unwrap()
  let p = doc.find("p").unwrap()
  let g = doc.find("g").unwrap()
  let image = doc.find("image").unwrap()
  div.set_name("clipPath")
  p.set_name("image")
  g.set_name("clippath")
  image.set_name("IMAGE")
  assert_eq([div.name(), p.name(), g.name(), image.name()], [
    "clippath", "img", "clipPath", "image",
  ])
  assert_eq(
    document_shape(@mutable.parse(doc.stringify())),
    document_shape(doc),
  )
}

///|
test "moved text is escaped according to its new parent" {
  let doc = @mutable.parse(
    "<script>a<b</script><div>x &lt; y</div><title>c<d</title><p></p>",
  )
  let script = doc.find("script").unwrap()
  let div = doc.find("div").unwrap()
  let title = doc.find("title").unwrap()
  let p = doc.find("p").unwrap()
  let a = script.children()[0]
  let x = div.children()[0]
  let c = title.children()[0]
  div.append([@mutable.Content::Node(a)])
  script.append([@mutable.Content::Node(x)])
  p.append([@mutable.Content::Node(c)])
  assert_eq(
    doc.stringify(),
    "<script>x < y</script><div>a&lt;b</div><title></title><p>c&lt;d</p>",
  )
  assert_eq(a.stringify(), "a&lt;b")
  a.remove()
  assert_eq(a.stringify(), "a<b")
}

///|
test "CDATA remains literal until moved into HTML" {
  let doc = @mutable.parse(
    "<svg><style><![CDATA[a{b:c}&amp;]]></style></svg><div></div>",
  )
  let style = doc.find("style").unwrap()
  assert_eq(style.text(), "a{b:c}&amp;")
  style.set_attr("id", "s")
  assert_eq(
    doc.stringify(),
    "<svg><style id=\"s\"><![CDATA[a{b:c}&amp;]]></style></svg><div></div>",
  )
  let cdata = style.children()[0]
  doc.find("div").unwrap().append([@mutable.Content::Node(cdata)])
  let output = doc.stringify()
  assert_eq(
    output, "<svg><style id=\"s\"></style></svg><div>a{b:c}&amp;amp;</div>",
  )
  assert_eq(@mutable.parse(output).find("div").unwrap().text(), "a{b:c}&amp;")
}

///|
test "remaining implied-close cases preserve the edited tree" {
  let cloned = @mutable.parse("<p>a<p>b")
  let p = cloned.find("p").unwrap()
  cloned.append([
    @mutable.Content::Node(@mutable.Node::Element(p.clone())),
    @mutable.Content::Text("c"),
  ])
  assert_eq(cloned.stringify(), "<p>a<p>b</p><p>a</p>c")
  assert_eq(
    document_shape(@mutable.parse(cloned.stringify())),
    document_shape(cloned),
  )

  let stray = @mutable.parse("</p><p>a")
  stray.prepend([@mutable.Content::Text("x")])
  assert_eq(stray.stringify(), "x</p><p>a")
  assert_eq(
    document_shape(@mutable.parse(stray.stringify())),
    document_shape(stray),
  )

  let list = @mutable.parse("<ul><li>a<li>b</ul>")
  list.find("li").unwrap().append(contents(@mutable.parse("<p>x").children()))
  assert_eq(list.stringify(), "<ul><li>a<p>x</p><li>b</ul>")
  assert_eq(
    document_shape(@mutable.parse(list.stringify())),
    document_shape(list),
  )
}

///|
test "HTML self-closing syntax and new elements stay valid" {
  let doc = @mutable.parse("<br/><a href=/x/>")
  doc.find("br").unwrap().set_attr("class", "y")
  doc.find("a").unwrap().append([@mutable.Content::Text("z")])
  assert_eq(doc.stringify(), "<br class=\"y\"/><a href=/x/>z")
  assert_eq(
    document_shape(@mutable.parse(doc.stringify())),
    document_shape(doc),
  )

  let created = @mutable.parse("<div></div>")
  created.find("div").unwrap().set_html("<span>a</span><br>")
  created.find("span").unwrap().set_attr("class", "x")
  assert_eq(created.stringify(), "<div><span class=\"x\">a</span><br></div>")
}
