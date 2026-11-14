///|
let tree_cases : Array[(String, String)] = [
  ("empty", ""),
  ("text only", "hello &amp; world"),
  (
    "basic document", "<!doctype html><html><head><title>Hi</title></head><body><p>x</p></body></html>",
  ),
  ("uppercase tags", "<DIV ID=a><SPAN>x</SPAN></DIV>"),
  ("attributes, quoted", "<a href=\"x\" title='y' data-z=z>t</a>"),
  ("attributes, no value", "<input disabled checked>"),
  ("attributes, duplicates", "<a href=\"first\" href=\"second\">t</a>"),
  ("attributes, mixed case", "<meta charSet=\"utf-8\" ConTent=x>"),
  (
    "attributes, entities", "<a href=\"?a=1&amp;b=2&lt;\" title=\"&quot;q&quot;\">t</a>",
  ),
  ("attributes, '>' in quotes", "<div title=\"a>b\" data-x='c>d'>x</div>"),
  ("attributes, unquoted slash", "<a href=/x/>t</a>"),
  ("attributes, newlines", "<a\n  href=\"x\"\n  class=\"y\"\n>t</a>"),
  ("attributes, doubled quote", "<a href=\"/x\"\">link</a><p>Hello</p>"),
  ("attributes, doubled single quote", "<a b='c''>x</a><p>y</p>"),
  (
    "attributes, quote in name", "<div data-x\"y>one</div><p>Hello</p><span z\">two</span>",
  ),
  (
    "attributes, quote in unquoted value", "<div class=a\"b>one</div><p>Hello</p><span title=\"t\">two</span>",
  ),
  ("attributes, apostrophe in unquoted value", "<a b=c'd e=f>x</a>"),
  ("attributes, leading equals", "<a =b c>x</a>"),
  ("attributes, slash between", "<a b = \"c\" / d>x</a>"),
  ("attributes, quote after value", "<a b=\"c\"d e>x</a>"),
  ("attributes, empty unquoted", "<a b= >x</a><a c=>y</a>"),
  ("self-closing svg, unquoted slash", "<svg><path d=M0/><path d=M1/></svg>"),
  ("self-closing svg, spaced slash", "<svg><path d=M0 / ><path/></svg>"),
  ("self-closing svg, quoted slash", "<svg><path d=\"M0/\"/><path/></svg>"),
  ("self-closing html", "<div/><span>x</span>"),
  ("void elements", "<p>a<br>b<img src=x>c<hr>d</p>"),
  ("implied p close", "<p>one<p>two<div>three</div>"),
  ("implied li close", "<ul><li>a<li>b</ul>"),
  ("implied table", "<table><tr><td>a<td>b<tr><td>c</table>"),
  ("implied option", "<select><option>a<option>b<optgroup><option>c</select>"),
  ("implied dd/dt", "<dl><dt>a<dd>b<dt>c</dl>"),
  ("implied heading", "<h1>a<h2>b</h2>"),
  ("implied a", "<a href=1>one<a href=2>two</a>"),
  ("body closes head", "<html><head><link rel=x><body>y</body>"),
  ("stray close p", "<div></p></div>"),
  ("stray close br", "<div></br></div>"),
  ("stray close tag", "<div></span>x</div>"),
  ("unclosed elements", "<div><span>x"),
  ("misnested", "<b><i>x</b>y</i>"),
  ("nested form", "<form><form><input></form></form>"),
  ("comment", "<!-- hi --><p>x</p>"),
  ("comment, unclosed", "<p>x<!-- never"),
  ("bogus comment", "<p>x</ 3>y</p>"),
  ("processing instruction", "<?xml version=1?><p>x</p>"),
  ("directive", "<!DOCTYPE html><p>x</p>"),
  (
    "script, raw", "<script>if (a < b && c > d) document.write(\"<p>x</p>\")</script>",
  ),
  ("script, uppercase close", "<script>x</SCRIPT>y"),
  ("script, unclosed", "<script>x<p>y"),
  ("style, raw", "<style>a > b { content: '&amp;' }</style>"),
  ("title, entities", "<title>a &amp; b <i>c</i></title>"),
  ("textarea", "<textarea><b>&lt;x&gt;</b></textarea>"),
  ("plaintext", "<plaintext><b>x</b></plaintext>"),
  ("noscript", "<noscript><img src=x></noscript>"),
  ("lone <", "<p>a < b and c <3 d</p>"),
  ("text entities", "<p>&copy; &#169; &#xA9; &nbsp;&notanentity; &amp</p>"),
  (
    "svg names", "<svg viewBox='0 0 1 1'><clipPath id=c><rect/></clipPath><foreignObject><div>x</div></foreignObject></svg>",
  ),
  ("svg self-closing", "<svg/><p>x</p>"),
  ("svg title", "<svg><title><b>x</b></title></svg>"),
  ("math", "<math><mi>x</mi><mo>+</mo></math>"),
  ("image alias", "<image src=x>"),
  ("whitespace", "\n  <div>\n\t<span> x </span>\n  </div>\n"),
  ("bogus comments", "<!x><!><!-x><![CDATA[x]]><?x?></ x>"),
  ("doctypes", "<!doctype html><!DOCTYPE html><!DocType x>"),
  ("empty end tag", "<p>a</>b</p>"),
  ("cdata in svg", "<svg><style><![CDATA[a&amp;<b>]]></style></svg>"),
  ("eof in start tag", "<p>a<a href=\"x"),
  ("eof in unquoted value", "<p>a<a b=c"),
  ("eof in attribute name", "<p>a<a b"),
  ("eof in end tag", "<p>a</p"),
  ("eof after end tag open", "<p>a</"),
  ("eof after lone <", "<p>a<"),
  ("eof in bogus comment", "<p>a</ x"),
  ("eof in declaration", "<p>a<!x"),
  ("eof in raw text end tag", "<script>a</script"),
  ("eof in rcdata end tag", "<title>a</title"),
]

///|
test "all upstream tree cases have valid ranges and contiguous subtrees" {
  for pair in tree_cases {
    let (name, html) = pair
    let tree = build(html)
    assert_eq(tree.source, html)
    assert_eq(tree.stop[0], tree.size)
    for id in 1..<tree.size {
      let outer = slice(html, tree.start[id], tree.end[id])
      if tree.kind[id] == Kind::Element {
        assert_true(outer.has_prefix("<"))
        assert_true(tree.start[id] <= tree.from[id])
        assert_true(tree.from[id] <= tree.to[id])
        assert_true(tree.to[id] <= tree.end[id])
      }
      if tree.kind[id] == Kind::Text {
        let inner = slice(html, tree.from[id], tree.to[id])
        if outer != inner {
          assert_eq(outer, "<![CDATA[" + inner + "]]>")
        }
      }
      for child in (id + 1)..<tree.stop[id] {
        let mut parent = tree.parent[child]
        while parent > id {
          parent = tree.parent[parent]
        }
        assert_eq(parent, id)
      }
    }
    let _ = attributes(tree, if tree.size > 1 { 1 } else { 0 })
    let _ = text(tree, 0)
    let _ = name
  }
}

///|
fn shape(tree : Tree, id : Int32) -> String {
  if tree.kind[id] == Kind::Text {
    return value(tree, id)
  }
  if tree.kind[id] == Kind::Comment {
    return "<!--" + value(tree, id) + "-->"
  }
  if tree.kind[id] == Kind::Directive {
    return "<!" + value(tree, id) + ">"
  }
  if is_void(tree.name[id]) {
    return tree.name[id]
  }
  let output = StringBuilder()
  output.write_string(tree.name[id])
  output.write_char('(')
  let mut child = id + 1
  let mut first = true
  while child < tree.stop[id] {
    if !first {
      output.write_char(',')
    }
    output.write_string(shape(tree, child))
    first = false
    child = tree.stop[child]
  }
  output.write_char(')')
  output.to_string()
}

///|
fn document_shape(html : String) -> String {
  let tree = build(html)
  let output : Array[String] = []
  let mut id = 1
  while id < tree.size {
    output.push(shape(tree, id))
    id = tree.stop[id]
  }
  output.join(",")
}

///|
test "implied end tags and misnested markup match upstream shapes" {
  assert_eq(
    document_shape("<p>one<p>two<div>three</div>"),
    "p(one),p(two),div(three)",
  )
  assert_eq(document_shape("<ul><li>a<li>b</ul>"), "ul(li(a),li(b))")
  assert_eq(
    document_shape("<table><tr><td>a<td>b<tr><td>c</table>"),
    "table(tr(td(a),td(b)),tr(td(c)))",
  )
  assert_eq(
    document_shape("<select><option>a<option>b<optgroup><option>c</select>"),
    "select(option(a),option(b),optgroup(option(c)))",
  )
  assert_eq(document_shape("<dl><dt>a<dd>b<dt>c</dl>"), "dl(dt(a),dd(b),dt(c))")
  assert_eq(document_shape("<h1>a<h2>b</h2>"), "h1(a),h2(b)")
  assert_eq(document_shape("<a href=1>one<a href=2>two</a>"), "a(one),a(two)")
  assert_eq(document_shape("<b><i>x</b>y</i>"), "b(i(x)),y")
  assert_eq(document_shape("<form><form><input></form></form>"), "form(input)")
}

///|
test "void, raw, foreign, and malformed nodes match upstream shapes" {
  assert_eq(
    document_shape("<p>a<br>b<img src=x>c<hr>d</p>"),
    "p(a,br,b,img,c),hr,d,p()",
  )
  assert_eq(document_shape("<div></p></div>"), "div(p())")
  assert_eq(document_shape("<div></br></div>"), "div(br)")
  assert_eq(document_shape("<div></span>x</div>"), "div(x)")
  assert_eq(document_shape("<div><span>x"), "div(span(x))")
  assert_eq(document_shape("<script>x</SCRIPT>y"), "script(x),y")
  assert_eq(document_shape("<script>x<p>y"), "script(x<p>y)")
  assert_eq(
    document_shape("<title>a &amp; b <i>c</i></title>"),
    "title(a & b <i>c</i>)",
  )
  assert_eq(
    document_shape("<textarea><b>&lt;x&gt;</b></textarea>"),
    "textarea(<b><x></b>)",
  )
  assert_eq(
    document_shape("<plaintext><b>x</b></plaintext>"),
    "plaintext(<b>x</b></plaintext>)",
  )
  assert_eq(
    document_shape("<svg><title><b>x</b></title></svg>"),
    "svg(title(b(x)))",
  )
  assert_eq(document_shape("<image src=x>"), "img")
  assert_eq(
    document_shape("<svg><style><![CDATA[a&amp;<b>]]></style></svg>"),
    "svg(style(a&amp;<b>))",
  )
}

///|
test "unfinished tags are dropped like browsers" {
  let cases = [
    ("<p>a<a/", "p(a)"),
    ("<p>a</p x", "p(a)"),
    ("<p>a</p ", "p(a)"),
    ("<script>a</script x", "script(a)"),
    ("<script>a</script/", "script(a)"),
    ("<textarea>a</textarea ", "textarea(a)"),
  ]
  for pair in cases {
    assert_eq(document_shape(pair.0), pair.1)
  }
}

///|
test "comment, directive, and CDATA values follow browsers" {
  let tree = build(
    "<!x><?x?><!DOCTYPE html><![CDATA[c]]><svg><![CDATA[a&amp;<b>]]></svg>",
  )
  let actual : Array[(Kind, String)] = []
  for id in 1..<tree.size {
    if tree.kind[id] != Kind::Element {
      actual.push((tree.kind[id], value(tree, id)))
    }
  }
  assert_eq(actual, [
    (Kind::Comment, "x"),
    (Kind::Comment, "?x?"),
    (Kind::Directive, "DOCTYPE html"),
    (Kind::Comment, "[CDATA[c]]"),
    (Kind::Text, "a&amp;<b>"),
  ])
}
