///|
let selector_html : String = "<!doctype html>\n<html lang=\"en-US\">\n<head>\n\t<title>Fixture</title>\n\t<meta name=\"description\" content=\"A page\">\n\t<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n\t<link rel=\"canonical\" href=\"https://example.com/\">\n\t<link rel=\"stylesheet alternate\" href=\"/a.css\">\n</head>\n<body class=\"home page\">\n\t<header id=\"top\"><nav><a href=\"/\">Home</a><a href=\"/about/\" class=\"active\">About</a></nav></header>\n\t<main>\n\t\t<h1>Title</h1>\n\t\t<p class=\"lead intro\">One <a href=\"https://other.com\" target=\"_blank\" rel=\"noopener\">ext</a></p>\n\t\t<p>Two <img src=\"a.png\" alt=\"A\"><img src=\"b.png\"></p>\n\t\t<p></p>\n\t\t<ul><li>1</li><li class=\"x\">2</li><li>3</li><li>4</li><li class=\"x\">5</li></ul>\n\t\t<div data-Mixed=\"Value\" data-list=\"a b c\" lang=\"en-GB\"><span>s</span><!-- c --></div>\n\t\t<svg viewBox=\"0 0 1 1\"><clipPath id=\"c\"><rect/></clipPath></svg>\n\t\t<template id=\"t\"><p class=\"x\">t</p><template><li class=\"x\">n</li></template></template>\n\t</main>\n\t<footer><p>Bye</p></footer>\n</body>\n</html>"

///|
fn names(elements : Array[@html.Element]) -> Array[String] {
  elements.map(element => element.name())
}

///|
test "CSS type, attribute, class, and ID selectors" {
  let doc = @html.parse(selector_html)
  assert_eq(doc.all("a").length(), 3)
  assert_eq(doc.all("A").length(), 3)
  assert_eq(doc.all("head > title").length(), 1)
  assert_eq(doc.all("head>title").length(), 1)
  assert_eq(doc.all("meta[name=description]").length(), 1)
  assert_eq(doc.all("meta[name=\"viewport\"]").length(), 1)
  assert_eq(doc.all("link[rel=canonical]").length(), 1)
  assert_eq(doc.all("link[rel~=alternate]").length(), 1)
  assert_eq(doc.all("html[lang|=en]").length(), 1)
  assert_eq(doc.all("[lang|=en]").length(), 2)
  assert_eq(doc.all("a[href^=https]").length(), 1)
  assert_eq(doc.all("a[href$=\"/\"]").length(), 2)
  assert_eq(doc.all("a[href*=other]").length(), 1)
  assert_eq(doc.all("[data-mixed=value i]").length(), 1)
  assert_eq(doc.all("[data-mixed=Value]").length(), 1)
  assert_eq(doc.all("[data-list~=b]").length(), 1)
  assert_eq(doc.all("img[alt]").length(), 1)
  assert_eq(doc.all("img:not([alt])").length(), 1)
  assert_eq(doc.all("#top").length(), 1)
  assert_eq(doc.all("#top a").length(), 2)
  assert_eq(doc.all(".active").length(), 1)
  assert_eq(doc.all("p.lead.intro").length(), 1)
  assert_eq(doc.all(".lead, .active").length(), 2)
  assert_eq(doc.all("body.home").length(), 1)
}

///|
test "CSS combinators and structural pseudo classes" {
  let doc = @html.parse(selector_html)
  assert_eq(doc.all("main > p").length(), 3)
  assert_eq(doc.all("main p").length(), 3)
  assert_eq(doc.all("h1 + p").length(), 1)
  assert_eq(doc.all("h1 ~ p").length(), 3)
  assert_eq(doc.all("p + p").length(), 2)
  assert_eq(doc.all("li:first-child").length(), 1)
  assert_eq(doc.all("li:last-child").length(), 1)
  assert_eq(doc.all("li:nth-child(2n+1)").length(), 3)
  assert_eq(doc.all("li:nth-child(odd)").length(), 3)
  assert_eq(doc.all("li:nth-child(even)").length(), 2)
  assert_eq(doc.all("li:nth-child(3)").length(), 1)
  assert_eq(doc.all("li:nth-child(-n+2)").length(), 2)
  assert_eq(doc.all("li:nth-last-child(2)").length(), 1)
  assert_eq(doc.all("li.x:nth-of-type(2)").length(), 1)
  assert_eq(doc.all("p:first-of-type").length(), 2)
  assert_eq(doc.all("p:last-of-type").length(), 2)
  assert_eq(doc.all("span:only-child").length(), 1)
  assert_eq(doc.all("p:empty").length(), 1)
  assert_eq(names(doc.all(":root")), ["html"])
  assert_eq(doc.all("li:not(.x)").length(), 3)
  assert_eq(doc.all("li:not(:first-child):not(:last-child)").length(), 3)
  assert_eq(doc.all(":is(h1, footer p)").length(), 2)
  assert_eq(doc.all(":where(nav) a").length(), 2)
  assert_eq(doc.all("svg rect").length(), 1)
  assert_eq(doc.all("ul > li.x + li").length(), 1)
  assert_eq(doc.all("header a.active, main img[src$='.png']").length(), 3)
  assert_eq(doc.all("p, li").length(), 9)
}

///|
test "query scope, template contents, and result limit behavior" {
  let doc = @html.parse(selector_html)
  let main = doc.find("main").unwrap()
  assert_eq(main.all("p").length(), 3)
  assert_eq(doc.all("p").length(), 4)
  assert_eq(doc.all("template").length(), 1)
  assert_eq(doc.all("template p").length(), 0)
  assert_eq(doc.all("main .x").length(), 2)
  let outer = doc.find("template").unwrap()
  assert_eq(names(outer.all(".x")), ["p"])
  assert_eq(outer.all("li").length(), 0)
  let inner = outer.find("template").unwrap()
  assert_eq(names(inner.all(".x")), ["li"])
}

///|
test "foreign names are case sensitive" {
  let doc = @html.parse(selector_html)
  assert_eq(names(doc.all("clipPath")), ["clipPath"])
  assert_eq(doc.all("clippath"), [])
}

///|
test "identifier and string escapes" {
  let doc = @html.parse("<a id=\"a:b\" class=\"1x\" title='say \"hi\"'></a>")
  for selector in ["#a\\:b", ".\\31 x", "[title=\"say \\\"hi\\\"\"]"] {
    assert_eq(doc.all(selector).length(), 1)
  }
}

///|
test "unsupported and malformed selectors raise SelectorError" {
  let doc = @html.parse(selector_html)
  for
    bad in [
      "", "a >", "[href", "a:hover", ":nth-child(x)", "a,,b", "'x'", "[title=\"x]",
    ] {
    let result : Result[Array[@html.Element], @html.SelectorError] = Ok(
      doc.all(bad),
    ) catch {
      e => Err(e)
    }
    assert_true(result is Err(@html.SelectorError::InvalidSelector(_)))
  }
  for selector in ["[constructor]", "[toString]", "[__proto__]"] {
    assert_eq(doc.all(selector), [])
  }
}
