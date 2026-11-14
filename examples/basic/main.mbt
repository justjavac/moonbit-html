///|
fn main raise {
  let doc = @html.parse(
    "<head><title>Hi &amp; bye</title><link rel=canonical href=\"/\"></head>",
  )
  let title = doc.find("head > title").unwrap()
  println(title.text())
  println(doc.find("link").unwrap().get_attr("href").unwrap())
  println(title.stringify())

  let editable = @mutable.parse("<ul><li>a</li></ul>")
  editable.find("li").unwrap().set_attr("class", "first")
  println(editable.stringify())
}
