///|
test "attribute matching covers operators and flags" {
  let doc = @mutable.parse(
    "<a href=\"/x\" data-id=\"AbC\">a</a><p class=\"one two\" lang=\"en-US\">b</p>",
  )
  assert_eq(doc.all("[data-id]").length(), 1)
  assert_eq(doc.all("[data-id=\"abc\" i]").length(), 1)
  assert_eq(doc.all("[class~=two]").length(), 1)
  assert_eq(doc.all("[class~=\"\"]").length(), 0)
  assert_eq(doc.all("[lang|=en]").length(), 1)
  assert_eq(doc.all("[href^=\"/\"]").length(), 1)
  assert_eq(doc.all("[href$=\"x\"]").length(), 1)
  assert_eq(doc.all("[href*=\"/x\"]").length(), 1)
}

///|
test "matching edge cases on tags, ids, and detached nodes" {
  let doc = @mutable.parse("<div><p class=a>x</p><span></span><p>y</p></div>")
  let p = doc.find("p").unwrap()
  assert_false(p.matches("video"))
  assert_false(p.matches("#missing"))
  assert_true(p.matches(":is(p)"))
  // Subsequent siblings skip non-matching elements in between.
  let second = doc.all("p")[1]
  assert_true(second.matches("p.a ~ p"))
  assert_true(second.matches("span + p"))
  assert_false(second.matches("p.a + p"))
  // Detached elements match nth selectors as only children.
  second.remove()
  assert_true(second.matches(":first-child"))
  assert_false(second.matches("p ~ p"))
}

///|
test "closest checks ancestors up to the document" {
  let doc = @mutable.parse("<div><p><b>x</b></p></div>")
  let b = doc.find("b").unwrap()
  assert_eq(b.closest("video"), None)
}

///|
test "invalid selectors raise HtmlError" {
  let failed : Result[@mutable.Element?, @mutable.HtmlError] = Ok(
    @mutable.parse("<p></p>").find("a["),
  ) catch {
    e => Err(e)
  }
  assert_true(failed is Err(@mutable.HtmlError::InvalidSelector(_)))
}
