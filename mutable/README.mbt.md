# `justjavac/html/mutable`

```mbt check
///|
test "edit only the necessary tags" {
  let doc = @mutable.parse("<ul><li>a</li></ul>")
  let ul = doc.find("ul").unwrap()
  ul.append(
    @mutable.parse("<li>b</li>")
    .children()
    .map(node => @mutable.Content::Node(node)),
  )
  assert_eq(doc.stringify(), "<ul><li>a</li><li>b</li></ul>")
}
```
