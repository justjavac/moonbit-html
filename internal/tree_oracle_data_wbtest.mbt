///|
let tree_oracles : Array[(String, String, Array[String])] = [
  ("empty", "", []),
  ("text only", "hello &amp; world", ["0|text|hello & world"]),
  (
    "basic document",
    "<!doctype html><html><head><title>Hi</title></head><body><p>x</p></body></html>",
    [
      "0|directive|", "0|element|html {}", "1|element|head {}", "2|element|title {}",
      "3|text|Hi", "1|element|body {}", "2|element|p {}", "3|text|x",
    ],
  ),
  (
    "uppercase tags",
    "<DIV ID=a><SPAN>x</SPAN></DIV>",
    ["0|element|div {\"id\":\"a\"}", "1|element|span {}", "2|text|x"],
  ),
  (
    "attributes, quoted",
    "<a href=\"x\" title='y' data-z=z>t</a>",
    [
      "0|element|a {\"href\":\"x\",\"title\":\"y\",\"data-z\":\"z\"}", "1|text|t",
    ],
  ),
  (
    "attributes, no value",
    "<input disabled checked>",
    ["0|element|input {\"disabled\":\"\",\"checked\":\"\"}"],
  ),
  (
    "attributes, duplicates",
    "<a href=\"first\" href=\"second\">t</a>",
    ["0|element|a {\"href\":\"first\"}", "1|text|t"],
  ),
  (
    "attributes, mixed case",
    "<meta charSet=\"utf-8\" ConTent=x>",
    ["0|element|meta {\"charset\":\"utf-8\",\"content\":\"x\"}"],
  ),
  (
    "attributes, entities",
    "<a href=\"?a=1&amp;b=2&lt;\" title=\"&quot;q&quot;\">t</a>",
    ["0|element|a {\"href\":\"?a=1&b=2<\",\"title\":\"\\\"q\\\"\"}", "1|text|t"],
  ),
  (
    "attributes, '>' in quotes",
    "<div title=\"a>b\" data-x='c>d'>x</div>",
    ["0|element|div {\"title\":\"a>b\",\"data-x\":\"c>d\"}", "1|text|x"],
  ),
  (
    "attributes, unquoted slash",
    "<a href=/x/>t</a>",
    ["0|element|a {\"href\":\"/x/\"}", "1|text|t"],
  ),
  (
    "attributes, newlines",
    "<a\n  href=\"x\"\n  class=\"y\"\n>t</a>",
    ["0|element|a {\"href\":\"x\",\"class\":\"y\"}", "1|text|t"],
  ),
  (
    "attributes, doubled quote",
    "<a href=\"/x\"\">link</a><p>Hello</p>",
    [
      "0|element|a {\"href\":\"/x\",\"\\\"\":\"\"}", "1|text|link", "0|element|p {}",
      "1|text|Hello",
    ],
  ),
  (
    "attributes, doubled single quote",
    "<a b='c''>x</a><p>y</p>",
    [
      "0|element|a {\"b\":\"c\",\"'\":\"\"}", "1|text|x", "0|element|p {}", "1|text|y",
    ],
  ),
  (
    "attributes, quote in name",
    "<div data-x\"y>one</div><p>Hello</p><span z\">two</span>",
    [
      "0|element|div {\"data-x\\\"y\":\"\"}", "1|text|one", "0|element|p {}", "1|text|Hello",
      "0|element|span {\"z\\\"\":\"\"}", "1|text|two",
    ],
  ),
  (
    "attributes, quote in unquoted value",
    "<div class=a\"b>one</div><p>Hello</p><span title=\"t\">two</span>",
    [
      "0|element|div {\"class\":\"a\\\"b\"}", "1|text|one", "0|element|p {}", "1|text|Hello",
      "0|element|span {\"title\":\"t\"}", "1|text|two",
    ],
  ),
  (
    "attributes, apostrophe in unquoted value",
    "<a b=c'd e=f>x</a>",
    ["0|element|a {\"b\":\"c'd\",\"e\":\"f\"}", "1|text|x"],
  ),
  (
    "attributes, leading equals",
    "<a =b c>x</a>",
    ["0|element|a {\"=b\":\"\",\"c\":\"\"}", "1|text|x"],
  ),
  (
    "attributes, slash between",
    "<a b = \"c\" / d>x</a>",
    ["0|element|a {\"b\":\"c\",\"d\":\"\"}", "1|text|x"],
  ),
  (
    "attributes, quote after value",
    "<a b=\"c\"d e>x</a>",
    ["0|element|a {\"b\":\"c\",\"d\":\"\",\"e\":\"\"}", "1|text|x"],
  ),
  (
    "attributes, empty unquoted",
    "<a b= >x</a><a c=>y</a>",
    [
      "0|element|a {\"b\":\"\"}", "1|text|x", "0|element|a {\"c\":\"\"}", "1|text|y",
    ],
  ),
  (
    "self-closing svg, unquoted slash",
    "<svg><path d=M0/><path d=M1/></svg>",
    [
      "0|element|svg {}", "1|element|path {\"d\":\"M0/\"}", "2|element|path {\"d\":\"M1/\"}",
    ],
  ),
  (
    "self-closing svg, spaced slash",
    "<svg><path d=M0 / ><path/></svg>",
    ["0|element|svg {}", "1|element|path {\"d\":\"M0\"}", "1|element|path {}"],
  ),
  (
    "self-closing svg, quoted slash",
    "<svg><path d=\"M0/\"/><path/></svg>",
    ["0|element|svg {}", "1|element|path {\"d\":\"M0/\"}", "1|element|path {}"],
  ),
  (
    "self-closing html",
    "<div/><span>x</span>",
    ["0|element|div {}", "1|element|span {}", "2|text|x"],
  ),
  (
    "void elements",
    "<p>a<br>b<img src=x>c<hr>d</p>",
    [
      "0|element|p {}", "1|text|a", "1|element|br {}", "1|text|b", "1|element|img {\"src\":\"x\"}",
      "1|text|c", "0|element|hr {}", "0|text|d", "0|element|p {}",
    ],
  ),
  (
    "implied p close",
    "<p>one<p>two<div>three</div>",
    [
      "0|element|p {}", "1|text|one", "0|element|p {}", "1|text|two", "0|element|div {}",
      "1|text|three",
    ],
  ),
  (
    "implied li close",
    "<ul><li>a<li>b</ul>",
    [
      "0|element|ul {}", "1|element|li {}", "2|text|a", "1|element|li {}", "2|text|b",
    ],
  ),
  (
    "implied table",
    "<table><tr><td>a<td>b<tr><td>c</table>",
    [
      "0|element|table {}", "1|element|tr {}", "2|element|td {}", "3|text|a", "2|element|td {}",
      "3|text|b", "1|element|tr {}", "2|element|td {}", "3|text|c",
    ],
  ),
  (
    "implied option",
    "<select><option>a<option>b<optgroup><option>c</select>",
    [
      "0|element|select {}", "1|element|option {}", "2|text|a", "1|element|option {}",
      "2|text|b", "1|element|optgroup {}", "2|element|option {}", "3|text|c",
    ],
  ),
  (
    "implied dd/dt",
    "<dl><dt>a<dd>b<dt>c</dl>",
    [
      "0|element|dl {}", "1|element|dt {}", "2|text|a", "1|element|dd {}", "2|text|b",
      "1|element|dt {}", "2|text|c",
    ],
  ),
  (
    "implied heading",
    "<h1>a<h2>b</h2>",
    ["0|element|h1 {}", "1|text|a", "0|element|h2 {}", "1|text|b"],
  ),
  (
    "implied a",
    "<a href=1>one<a href=2>two</a>",
    [
      "0|element|a {\"href\":\"1\"}", "1|text|one", "0|element|a {\"href\":\"2\"}",
      "1|text|two",
    ],
  ),
  (
    "body closes head",
    "<html><head><link rel=x><body>y</body>",
    [
      "0|element|html {}", "1|element|head {}", "2|element|link {\"rel\":\"x\"}",
      "1|element|body {}", "2|text|y",
    ],
  ),
  ("stray close p", "<div></p></div>", ["0|element|div {}", "1|element|p {}"]),
  (
    "stray close br",
    "<div></br></div>",
    ["0|element|div {}", "1|element|br {}"],
  ),
  ("stray close tag", "<div></span>x</div>", ["0|element|div {}", "1|text|x"]),
  (
    "unclosed elements",
    "<div><span>x",
    ["0|element|div {}", "1|element|span {}", "2|text|x"],
  ),
  (
    "misnested",
    "<b><i>x</b>y</i>",
    ["0|element|b {}", "1|element|i {}", "2|text|x", "0|text|y"],
  ),
  (
    "nested form",
    "<form><form><input></form></form>",
    ["0|element|form {}", "1|element|input {}"],
  ),
  (
    "comment",
    "<!-- hi --><p>x</p>",
    ["0|comment|", "0|element|p {}", "1|text|x"],
  ),
  (
    "comment, unclosed",
    "<p>x<!-- never",
    ["0|element|p {}", "1|text|x", "1|comment|"],
  ),
  (
    "bogus comment",
    "<p>x</ 3>y</p>",
    ["0|element|p {}", "1|text|x", "1|comment|", "1|text|y"],
  ),
  (
    "processing instruction",
    "<?xml version=1?><p>x</p>",
    ["0|comment|", "0|element|p {}", "1|text|x"],
  ),
  (
    "directive",
    "<!DOCTYPE html><p>x</p>",
    ["0|directive|", "0|element|p {}", "1|text|x"],
  ),
  (
    "script, raw",
    "<script>if (a < b && c > d) document.write(\"<p>x</p>\")</script>",
    [
      "0|element|script {}", "1|text|if (a < b && c > d) document.write(\"<p>x</p>\")",
    ],
  ),
  (
    "script, uppercase close",
    "<script>x</SCRIPT>y",
    ["0|element|script {}", "1|text|x", "0|text|y"],
  ),
  ("script, unclosed", "<script>x<p>y", ["0|element|script {}", "1|text|x<p>y"]),
  (
    "style, raw",
    "<style>a > b { content: '&amp;' }</style>",
    ["0|element|style {}", "1|text|a > b { content: '&amp;' }"],
  ),
  (
    "title, entities",
    "<title>a &amp; b <i>c</i></title>",
    ["0|element|title {}", "1|text|a & b <i>c</i>"],
  ),
  (
    "textarea",
    "<textarea><b>&lt;x&gt;</b></textarea>",
    ["0|element|textarea {}", "1|text|<b><x></b>"],
  ),
  (
    "plaintext",
    "<plaintext><b>x</b></plaintext>",
    ["0|element|plaintext {}", "1|text|<b>x</b></plaintext>"],
  ),
  (
    "noscript",
    "<noscript><img src=x></noscript>",
    ["0|element|noscript {}", "1|element|img {\"src\":\"x\"}"],
  ),
  (
    "lone <",
    "<p>a < b and c <3 d</p>",
    ["0|element|p {}", "1|text|a < b and c <3 d"],
  ),
  (
    "text entities",
    "<p>&copy; &#169; &#xA9; &nbsp;&notanentity; &amp</p>",
    ["0|element|p {}", "1|text|© © ©  ¬anentity; &"],
  ),
  (
    "svg names",
    "<svg viewBox='0 0 1 1'><clipPath id=c><rect/></clipPath><foreignObject><div>x</div></foreignObject></svg>",
    [
      "0|element|svg {\"viewbox\":\"0 0 1 1\"}", "1|element|clipPath {\"id\":\"c\"}",
      "2|element|rect {}", "1|element|foreignObject {}", "2|element|div {}", "3|text|x",
    ],
  ),
  (
    "svg self-closing",
    "<svg/><p>x</p>",
    ["0|element|svg {}", "0|element|p {}", "1|text|x"],
  ),
  (
    "svg title",
    "<svg><title><b>x</b></title></svg>",
    ["0|element|svg {}", "1|element|title {}", "2|element|b {}", "3|text|x"],
  ),
  (
    "math",
    "<math><mi>x</mi><mo>+</mo></math>",
    [
      "0|element|math {}", "1|element|mi {}", "2|text|x", "1|element|mo {}", "2|text|+",
    ],
  ),
  ("image alias", "<image src=x>", ["0|element|img {\"src\":\"x\"}"]),
  (
    "whitespace",
    "\n  <div>\n\t<span> x </span>\n  </div>\n",
    [
      "0|text|\n  ", "0|element|div {}", "1|text|\n\t", "1|element|span {}", "2|text| x ",
      "1|text|\n  ", "0|text|\n",
    ],
  ),
  (
    "bogus comments",
    "<!x><!><!-x><![CDATA[x]]><?x?></ x>",
    [
      "0|comment|", "0|comment|", "0|comment|", "0|comment|", "0|comment|", "0|comment|",
    ],
  ),
  (
    "doctypes",
    "<!doctype html><!DOCTYPE html><!DocType x>",
    ["0|directive|", "0|directive|", "0|directive|"],
  ),
  ("empty end tag", "<p>a</>b</p>", ["0|element|p {}", "1|text|ab"]),
  (
    "cdata in svg",
    "<svg><style><![CDATA[a&amp;<b>]]></style></svg>",
    ["0|element|svg {}", "1|element|style {}", "2|text|a&amp;<b>"],
  ),
  ("eof in start tag", "<p>a<a href=\"x", ["0|element|p {}", "1|text|a"]),
  ("eof in unquoted value", "<p>a<a b=c", ["0|element|p {}", "1|text|a"]),
  ("eof in attribute name", "<p>a<a b", ["0|element|p {}", "1|text|a"]),
  ("eof in end tag", "<p>a</p", ["0|element|p {}", "1|text|a"]),
  ("eof after end tag open", "<p>a</", ["0|element|p {}", "1|text|a</"]),
  ("eof after lone <", "<p>a<", ["0|element|p {}", "1|text|a<"]),
  (
    "eof in bogus comment",
    "<p>a</ x",
    ["0|element|p {}", "1|text|a", "1|comment|"],
  ),
  (
    "eof in declaration",
    "<p>a<!x",
    ["0|element|p {}", "1|text|a", "1|comment|"],
  ),
  (
    "eof in raw text end tag",
    "<script>a</script",
    ["0|element|script {}", "1|text|a</script"],
  ),
  (
    "eof in rcdata end tag",
    "<title>a</title",
    ["0|element|title {}", "1|text|a</title"],
  ),
]
