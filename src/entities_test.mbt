///|
test "named entities decode through the packed trie" {
  let doc = @html.parse(
    "<p>&amp; &lt;&gt; &nbsp; &angst; &fjlig; &ThickSpace;</p>",
  )
  assert_eq(
    doc.text(),
    "& <> \u{a0} \u{c5} fj \u{205f}\u{200a}",
  )
}

///|
test "legacy entities without semicolons use the longest match" {
  assert_eq(@html.parse("<p>&amp</p>").text(), "&")
  assert_eq(@html.parse("<p>&notit;</p>").text(), "\u{ac}it;")
  assert_eq(@html.parse("<p>&fake; &fake</p>").text(), "&fake; &fake")
}

///|
test "numeric entities handle decimal, hex, and bad input" {
  assert_eq(@html.parse("<p>&#65;&#x41;</p>").text(), "AA")
  assert_eq(@html.parse("<p>&#xD800; &#0;</p>").text(), "\u{fffd} \u{fffd}")
  assert_eq(@html.parse("<p>&#x110000;&#99999999;</p>").text(), "\u{fffd}\u{fffd}")
  assert_eq(@html.parse("<p>&#xFFFFFFFFF;</p>").text(), "\u{fffd}")
  assert_eq(@html.parse("<p>&#150;</p>").text(), "\u{2013}")
  // No digits means the text stays as written.
  assert_eq(@html.parse("<p>&#; &#x;</p>").text(), "&#; &#x;")
}

///|
test "entities decode inside attribute values" {
  let doc = @html.parse("<a title=\"&amp; &#65; &notit;\">x</a>")
  // In attributes a legacy entity followed by alphanumerics stays literal.
  assert_eq(doc.find("a").unwrap().get_attr("title"), Some("& A &notit;"))
}
