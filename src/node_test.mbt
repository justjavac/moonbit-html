///|
test "leaf handles compare by identity" {
  let doc = @html.parse("a<!--x--><!doctype html><p>b</p>")
  let other = @html.parse("a<!--x--><!doctype html><p>b</p>")
  guard doc.children()
    is [Text(text_a), Comment(comment), Directive(directive), Element(p)] else {
    abort("unexpected children")
  }
  guard p.children() is [Text(text_b)] else { abort("unexpected <p> children") }
  assert_eq(text_a, text_a)
  assert_eq(comment, comment)
  assert_eq(directive, directive)
  assert_false(text_a == text_b)
  guard other.children()
    is [Text(other_text), Comment(other_comment), Directive(other_directive), ..] else {
    abort("unexpected children")
  }
  assert_false(text_a == other_text)
  assert_false(comment == other_comment)
  assert_false(directive == other_directive)
}

///|
test "debug representations name every node kind" {
  let doc = @html.parse("<!doctype html>\nt<!--x--><p>a</p>")
  debug_inspect(doc, content=(
    #|"Document(offsets=0..33)"
  ))
  guard doc.children() is [Directive(directive), Text(text), Comment(comment), Element(p)] else {
    abort("unexpected children")
  }
  debug_inspect(directive, content=(
    #|"Directive(doctype html)"
  ))
  debug_inspect(text, content=(
    #|"Text(\nt)"
  ))
  debug_inspect(comment, content=(
    #|"Comment(x)"
  ))
  debug_inspect(p, content=(
    #|"Element(p, offsets=25..33)"
  ))
}

///|
test "precompiled queries return None when nothing matches" {
  let doc = @html.parse("<p>a</p>")
  let selector = @html.Selector::parse("video")
  assert_eq(doc.find_with(selector), None)
  assert_eq(doc.all_with(selector), [])
  let p = doc.find("p").unwrap()
  assert_eq(p.find_with(selector), None)
  assert_eq(p.all_with(selector), [])
  assert_eq(p.closest_with(selector), None)
}

///|
test "node delegates to the wrapped element" {
  let doc = @html.parse("<div><p>a</p></div>")
  let div = doc.find("div").unwrap()
  guard doc.children() is [Element(node)] else { abort("expected an element") }
  assert_eq(node.document(), doc)
  assert_eq(node.start(), div.start())
  assert_eq(node.end(), div.end())
  assert_eq(node.parent(), @html.Parent::Document(doc))
  assert_eq(node.stringify(), "<div><p>a</p></div>")
}

///|
test "top-level leaf nodes have the document as parent" {
  let doc = @html.parse("<!doctype html><!--x--><p>a</p>")
  guard doc.children() is [Directive(directive), Comment(comment), ..] else {
    abort("unexpected children")
  }
  assert_eq(directive.parent(), @html.Parent::Document(doc))
  assert_eq(comment.parent(), @html.Parent::Document(doc))
  let nested = @html.parse("<p><!--x-->a</p>")
  let p = nested.find("p").unwrap()
  guard p.children() is [Comment(inner), ..] else { abort("unexpected children") }
  assert_eq(inner.parent(), @html.Parent::Element(p))
}
