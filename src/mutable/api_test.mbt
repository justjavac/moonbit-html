///|
test "generic stringify works on every node kind" {
  let doc = @mutable.parse("<!doctype html>\n<p>a<!--x--></p>")
  assert_eq(@mutable.stringify(doc), "<!doctype html>\n<p>a<!--x--></p>")
  let p = doc.find("p").unwrap()
  assert_eq(@mutable.stringify(p), "<p>a<!--x--></p>")
  guard p.children() is [@mutable.Node::Text(text), @mutable.Node::Comment(comment)] else {
    abort("unexpected children")
  }
  assert_eq(@mutable.stringify(text), "a")
  assert_eq(@mutable.stringify(comment), "<!--x-->")
  guard doc.children() is [@mutable.Node::Directive(directive), ..] else {
    abort("unexpected children")
  }
  assert_eq(@mutable.stringify(directive), "<!doctype html>")
}

///|
test "leaf handles compare by identity" {
  let doc = @mutable.parse("a<!--x--><!doctype html><p>b</p>")
  let other = @mutable.parse("a<!--x--><!doctype html><p>b</p>")
  guard doc.children()
    is [@mutable.Node::Text(text_a), @mutable.Node::Comment(comment), @mutable.Node::Directive(directive), @mutable.Node::Element(p)] else {
    abort("unexpected children")
  }
  guard p.children() is [@mutable.Node::Text(text_b)] else {
    abort("unexpected <p> children")
  }
  assert_eq(text_a, text_a)
  assert_eq(comment, comment)
  assert_eq(directive, directive)
  assert_false(text_a == text_b)
  guard other.children()
    is [@mutable.Node::Text(other_text), @mutable.Node::Comment(other_comment), @mutable.Node::Directive(other_directive), ..] else {
    abort("unexpected children")
  }
  assert_false(text_a == other_text)
  assert_false(comment == other_comment)
  assert_false(directive == other_directive)
}

///|
test "debug representations name every node kind" {
  let doc = @mutable.parse("<!doctype html><p>a<!--x--></p>")
  debug_inspect(doc, content=(
    #|"Document"
  ))
  guard doc.children() is [@mutable.Node::Directive(directive), @mutable.Node::Element(p)] else {
    abort("unexpected children")
  }
  debug_inspect(directive, content=(
    #|"Directive(doctype html)"
  ))
  debug_inspect(p, content=(
    #|"Element(p)"
  ))
  guard p.children() is [@mutable.Node::Text(text), @mutable.Node::Comment(comment)] else {
    abort("unexpected children")
  }
  debug_inspect(text, content=(
    #|"Text(a)"
  ))
  debug_inspect(comment, content=(
    #|"Comment(x)"
  ))
}

///|
test "closest walks up to the nearest matching ancestor" {
  let doc = @mutable.parse("<div class=a><p><b>x</b></p></div>")
  let b = doc.find("b").unwrap()
  assert_eq(b.closest("p").unwrap().name(), "p")
  assert_eq(b.closest(".a").unwrap().name(), "div")
  assert_eq(b.closest("b").unwrap(), b)
  assert_eq(b.closest("video"), None)
}

///|
test "position binary search finds early lines" {
  let doc = @mutable.parse("<p>a</p>\n<p>b</p>\n<p>c</p>\n<p>d</p>")
  assert_eq(doc.position(1), { line: 1, column: 2 })
  assert_eq(doc.position(10), { line: 2, column: 2 })
}

///|
test "text nodes support reads and edits" {
  let doc = @mutable.parse("<div>text<!--c--></div>")
  let div = doc.find("div").unwrap()
  guard div.children() is [@mutable.Node::Text(text), ..] else {
    abort("unexpected children")
  }
  assert_eq(text.document(), doc)
  assert_eq(text.start(), Some(5))
  assert_eq(text.end(), Some(9))
  assert_eq(text.parent(), Some(@mutable.Parent::Element(div)))
  assert_eq(text.value(), "text")
  let copy = text.clone()
  assert_eq(copy.value(), "text")
  assert_false(copy == text)
  text.before([@mutable.Content::Text("B")])
  text.after([@mutable.Content::Text("A")])
  assert_eq(doc.stringify(), "<div>BtextA<!--c--></div>")
  text.replace([@mutable.Content::Text("R")])
  assert_eq(doc.stringify(), "<div>BRA<!--c--></div>")
  text.remove() // the replaced handle is detached, so this is a no-op
  assert_eq(doc.stringify(), "<div>BRA<!--c--></div>")
  guard div.children() is [_, @mutable.Node::Text(inserted), ..] else {
    abort("unexpected children")
  }
  inserted.remove()
  assert_eq(doc.stringify(), "<div>BA<!--c--></div>")
}

///|
test "comment nodes support reads and edits" {
  let doc = @mutable.parse("<div>text<!--c--></div>")
  let div = doc.find("div").unwrap()
  guard div.children() is [_, @mutable.Node::Comment(comment)] else {
    abort("unexpected children")
  }
  assert_eq(comment.document(), doc)
  assert_eq(comment.start(), Some(9))
  assert_eq(comment.end(), Some(17))
  assert_eq(comment.parent(), Some(@mutable.Parent::Element(div)))
  assert_eq(comment.value(), "c")
  let copy = comment.clone()
  assert_eq(copy.value(), "c")
  assert_false(copy == comment)
  comment.before([@mutable.Content::Text("B")])
  comment.after([@mutable.Content::Text("A")])
  assert_eq(doc.stringify(), "<div>textB<!--c-->A</div>")
  comment.replace([@mutable.Content::Text("R")])
  assert_eq(doc.stringify(), "<div>textBRA</div>")
  comment.remove() // the replaced handle is detached, so this is a no-op
  assert_eq(doc.stringify(), "<div>textBRA</div>")
  guard div.children() is [_, _, @mutable.Node::Text(inserted), ..] else {
    abort("unexpected children")
  }
  inserted.remove()
  assert_eq(doc.stringify(), "<div>textBA</div>")
}

///|
test "directive nodes support reads and edits" {
  let doc = @mutable.parse("<!doctype html><p>a</p>")
  guard doc.children() is [@mutable.Node::Directive(directive), ..] else {
    abort("unexpected children")
  }
  assert_eq(directive.document(), doc)
  assert_eq(directive.start(), Some(0))
  assert_eq(directive.end(), Some(15))
  assert_eq(directive.parent(), Some(@mutable.Parent::Document(doc)))
  assert_eq(directive.value(), "doctype html")
  let copy = directive.clone()
  assert_eq(copy.value(), "doctype html")
  assert_false(copy == directive)
  directive.before([@mutable.Content::Text("B")])
  directive.after([@mutable.Content::Text("A")])
  assert_eq(doc.stringify(), "B<!doctype html>A<p>a</p>")
  directive.replace([@mutable.Content::Text("R")])
  assert_eq(doc.stringify(), "BRA<p>a</p>")
  directive.remove() // the replaced handle is detached, so this is a no-op
  assert_eq(doc.stringify(), "BRA<p>a</p>")
  guard doc.children() is [_, @mutable.Node::Text(inserted), ..] else {
    abort("unexpected children")
  }
  inserted.remove()
  assert_eq(doc.stringify(), "BA<p>a</p>")
}

///|
test "node delegates to the wrapped leaf state" {
  let doc = @mutable.parse("<p>a</p><!--c-->")
  guard doc.children() is [@mutable.Node::Element(p), @mutable.Node::Comment(comment)] else {
    abort("unexpected children")
  }
  let node = @mutable.Node::Comment(comment)
  assert_eq(node.document(), doc)
  assert_eq(node.start(), Some(8))
  assert_eq(node.end(), Some(16))
  assert_eq(node.parent(), Some(@mutable.Parent::Document(doc)))
  assert_eq(@mutable.stringify(node), "<!--c-->")
  let copy = node.clone()
  assert_eq(@mutable.stringify(copy), "<!--c-->")
  assert_false(copy == node)
  node.before([@mutable.Content::Text("B")])
  node.after([@mutable.Content::Text("A")])
  assert_eq(doc.stringify(), "<p>a</p>B<!--c-->A")
  node.replace([@mutable.Content::Text("R")])
  assert_eq(doc.stringify(), "<p>a</p>BRA")
  node.remove() // the replaced handle is detached, so this is a no-op
  assert_eq(doc.stringify(), "<p>a</p>BRA")
  assert_eq(p.document(), doc)
}
