///|
test "parse / justjavac/html" (it : @bench.T) {
  it.bench(fn() {
    let doc = @html.parse(wikipedia_html)
    it.keep(doc.children().length())
  })
}

///|
test "parse / justjavac/html mutable" (it : @bench.T) {
  it.bench(fn() {
    let doc = @mutable.parse(wikipedia_html)
    it.keep(doc.children().length())
  })
}

///|
test "parse / moonbit-community/html" (it : @bench.T) {
  it.bench(fn() {
    let doc = @community.parse(wikipedia_html)
    it.keep(doc.nodes.length())
  })
}

///|
test "parse / marianoguerra/html" (it : @bench.T) {
  it.bench(fn() {
    let doc = @mariano.parse(wikipedia_html) catch {
      _ => abort("HTML operation failed")
    }
    it.keep(doc.document().children.length())
  })
}

///|
test "parse / Milky2018/html" (it : @bench.T) {
  it.bench(fn() {
    let doc = @milky.parse(wikipedia_html)
    it.keep(doc.nodes.length())
  })
}

///|
test "parse / bobzhang/html_parser" (it : @bench.T) {
  it.bench(fn() {
    let doc = @bob.parse(wikipedia_html) catch {
      _ => abort("HTML operation failed")
    }
    it.keep(doc.root.children().length())
  })
}

///|
test "parse+stringify / justjavac/html" (it : @bench.T) {
  it.bench(fn() {
    let doc = @html.parse(wikipedia_html)
    it.keep(doc.stringify().length())
  })
}

///|
test "parse+stringify / justjavac/html mutable" (it : @bench.T) {
  it.bench(fn() {
    let doc = @mutable.parse(wikipedia_html)
    it.keep(doc.stringify().length())
  })
}

///|
test "parse+stringify / moonbit-community/html" (it : @bench.T) {
  it.bench(fn() {
    let doc = @community.parse(wikipedia_html)
    it.keep(doc.to_html().length())
  })
}

///|
test "parse+stringify / marianoguerra/html" (it : @bench.T) {
  it.bench(fn() {
    let doc = @mariano.parse(wikipedia_html) catch {
      _ => abort("HTML operation failed")
    }
    it.keep(
      @mariano.to_html(doc.document(), style=@mariano_write.Minified).length(),
    )
  })
}

///|
test "parse+stringify / Milky2018/html" (it : @bench.T) {
  it.bench(fn() {
    let doc = @milky.parse(wikipedia_html)
    it.keep(doc.to_html().length())
  })
}

///|
test "parse+stringify / bobzhang/html_parser" (it : @bench.T) {
  it.bench(fn() {
    let doc = @bob.parse(wikipedia_html) catch {
      _ => abort("HTML operation failed")
    }
    it.keep(
      (doc.to_html() catch { _ => abort("HTML operation failed") }).length(),
    )
  })
}

///|
test "read all / justjavac/html" (it : @bench.T) {
  let all = @html.Selector::parse("*")
  it.bench(fn() {
    let doc = @html.parse(wikipedia_html)
    let mut total = doc.text().length()
    for element in doc.all_with(all) {
      total += element.attributes().length()
    }
    it.keep(total)
  })
}

///|
test "query / justjavac/html" (it : @bench.T) {
  let doc = @html.parse(wikipedia_html)
  let selectors = [
    @html.Selector::parse("a"),
    @html.Selector::parse("img:not([alt])"),
    @html.Selector::parse("link[rel=canonical]"),
  ]
  let title = @html.Selector::parse("head > title")
  it.bench(fn() {
    let mut total = 0
    for selector in selectors {
      total += doc.all_with(selector).length()
    }
    it.keep(total + doc.find_with(title).unwrap().text().length())
  })
}

///|
test "query / justjavac/html mutable" (it : @bench.T) {
  let doc = @mutable.parse(wikipedia_html)
  it.bench(fn() {
    let mut total = 0
    for selector in ["a", "img:not([alt])", "link[rel=canonical]"] {
      total += (doc.all(selector) catch { _ => abort("query failed") }).length()
    }
    let title = doc.find("head > title") catch { _ => abort("query failed") }
    it.keep(total + title.unwrap().text().length())
  })
}

///|
test "query structural / justjavac/html" (it : @bench.T) {
  let doc = @html.parse(wikipedia_html)
  let selector = @html.Selector::parse("li:nth-child(2n+1), p + p, nav > a")
  it.bench(fn() {
    for _ in 0..<10 {
      it.keep(doc.all_with(selector).length())
    }
  })
}

///|
test "query structural / justjavac/html mutable" (it : @bench.T) {
  let doc = @mutable.parse(wikipedia_html)
  it.bench(fn() {
    for _ in 0..<10 {
      let found = doc.all("li:nth-child(2n+1), p + p, nav > a") catch {
        _ => abort("query failed")
      }
      it.keep(found.length())
    }
  })
}
