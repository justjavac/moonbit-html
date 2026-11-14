///|
test "known and unknown tag names are lowercased" {
  assert_eq(tag_name("<DIV>", 1, 4), "div")
  assert_eq(tag_name("<ForeignObject>", 1, 14), "foreignobject")
  assert_eq(tag_name("<h1>", 1, 3), "h1")
  assert_eq(tag_name("<My-Element>", 1, 11), "my-element")
  assert_eq(tag_name("<divx>", 1, 5), "divx")
  assert_eq(tag_name("<dir>", 1, 4), "dir")
  assert_eq(tag_name("<Kbd>", 1, 4), "Kbd".to_lower())
  assert_eq(tag_name("<ÄBC>", 1, 4), "äbc")
}

///|
test "attribute spans and decoded pairs find the same names" {
  let heads = [
    "", " a", " A=1 a=2", " href=\"/x\" title='y' data-z=z hidden", " a = 1  b= '2'  c =\"3\"",
    " a=/x/", " a= ", " a=", " a=\"x>y\" b", " \"a\" 'b' c", " a\tb\nc\fd\re", " =a b",
    " a/b c", " a=1\"2 b", " a=&amp;b c=&copy;", " İ=1 i=2",
  ]
  for head in heads {
    for close in [">", "/>", " />"] {
      let tree = build("<x" + head + close + "</x>")
      let pairs = pairs(tree, 1)
      let spans = spans(tree, 1)
      let pair_keys : Array[String] = []
      let span_keys : Array[String] = []
      for i in 0..<(pairs.length() / 2) {
        pair_keys.push(pairs[i * 2])
      }
      for i in 0..<(spans.length() / 3) {
        span_keys.push(spans[i * 3])
        assert_true(tree.source.contains(spans[i * 3 + 2]))
        assert_true(spans[i * 3 + 2].has_prefix(spans[i * 3 + 1]))
      }
      assert_eq(span_keys, pair_keys)
    }
  }
}

///|
test "HTML named and numeric entities follow browser decoding" {
  assert_eq(decode_html("&amp; &lt; &gt; &quot; &apos;"), "& < > \" '")
  assert_eq(
    decode_html("&copy; &#169; &#xA9; &nbsp;&notanentity; &amp"),
    "© © ©  ¬anentity; &",
  )
  assert_eq(
    decode_html("&#0; &#xD800; &#x110000; &#128;"),
    "\u{fffd} \u{fffd} \u{fffd} €",
  )
  assert_eq(
    decode_html("&NotEqualTilde; &ThickSpace;"),
    "≂̸ \u{205f}\u{200a}",
  )
  assert_eq(decode_html("&ampx &amp= &amp;", attribute=true), "&ampx &amp= &")
  assert_eq(decode_html("&ampx &amp= &amp;"), "&x &= &")
}

///|
test "escaping matches HTML text and attribute contexts" {
  assert_eq(escape_text("<&>\u{a0}\""), "&lt;&amp;&gt;&nbsp;\"")
  assert_eq(escape_attribute("<&>\u{a0}\""), "<&amp;>&nbsp;&quot;")
  assert_eq(escape_text("plain"), "plain")
}
