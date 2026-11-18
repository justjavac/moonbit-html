///|
/// Shared per-document state: the parse tree, a lazy line table, and an identity used by `Eq`.
priv struct Context {
  tree : @internal.Tree
  mut lines : Array[Int32]?
  identity : Int32
}

///|
/// Monotonic source of document identities.
let context_counter : Ref[Int32] = { val: 0, }

///|
/// Create shared context for a freshly parsed tree.
fn Context::new(tree : @internal.Tree) -> Context {
  context_counter.val += 1
  { tree, lines: None, identity: context_counter.val, }
}

///|
/// An HTML document produced by `parse`.
///
/// The document owns the compact parse tree; every handle obtained from it
/// (`Element`, `Text`, `Comment`, `Directive`) is a cheap view that stores no
/// content of its own. Attribute maps, decoded text, and the line table are
/// computed lazily on first read.
///
/// ```mbt nocheck
/// let doc = @html.parse("<p>Hello &amp; goodbye</p>")
/// doc.find("p").unwrap().text() // "Hello & goodbye"
/// ```
pub struct Document {
  priv ctx : Context
}

///|
/// A handle to an element node in a `Document`.
///
/// Handles are cheap views into the document's compact tree: copying one
/// costs nothing, and two handles compare equal (`Eq`) exactly when they point
/// at the same node of the same document. Offsets returned by `start` and
/// `end` are zero-based UTF-16 code-unit offsets into the original source.
pub struct Element {
  priv ctx : Context
  priv id : Int32
}

///|
/// A handle to a text node, including foreign-content CDATA sections.
///
/// `value` returns the entity-decoded content, while `stringify` returns the
/// exact original source slice.
pub struct Text {
  priv ctx : Context
  priv id : Int32
}

///|
/// A handle to a normal or bogus comment node.
///
/// `value` returns the comment content without the `<!--` and `-->` markers.
pub struct Comment {
  priv ctx : Context
  priv id : Int32
}

///|
/// A handle to a doctype declaration.
///
/// `value` returns the raw content of the declaration, e.g. `doctype html`
/// for `<!doctype html>`.
pub struct Directive {
  priv ctx : Context
  priv id : Int32
}

///|
/// A child node in an HTML document: an element, text, comment, or directive.
///
/// Returned by `children`. All node kinds share the `document`, `start`,
/// `end`, `parent`, and `stringify` methods.
#derive(Eq, Debug)
pub(all) enum Node {
  Element(Element)
  Text(Text)
  Comment(Comment)
  Directive(Directive)
}

///|
/// The parent of a node: either the document or an enclosing element.
#derive(Eq, Debug)
pub(all) enum Parent {
  Document(Document)
  Element(Element)
}

///|
/// A one-based line and column in the original UTF-16 source.
///
/// Both `line` and `column` start at 1. Columns count UTF-16 code units, not
/// Unicode scalar values or grapheme clusters.
#derive(Eq, Debug)
pub(all) struct Position {
  line : Int32
  column : Int32
}

///|
/// A CSS selector list compiled by `Selector::parse`.
///
/// Compiling once and reusing the value with `find_with`, `all_with`,
/// `matches_with`, and `closest_with` skips re-parsing the selector text on
/// every query and enables precomputed candidate-tag lookups.
pub struct Selector {
  priv compiled : @internal.Selector
}

///|
/// A malformed or unsupported CSS selector.
///
/// Raised by the selector-taking functions (`find`, `all`, `matches`,
/// `closest`, and `Selector::parse`); the message describes the first syntax
/// problem found.
pub suberror SelectorError {
  InvalidSelector(String)
}

///|
/// Values that can be serialized back to HTML.
///
/// For nodes of an immutable document the result is always the exact original
/// source slice, so `parse(source).stringify() == source`.
pub trait Stringify {
  fn stringify(Self) -> String
}

///|
/// Serialize any `Stringify` value to its HTML string.
///
/// Equivalent to calling the value's own `stringify` method; useful when the
/// concrete node type is abstracted away.
///
/// ```mbt nocheck
/// @html.stringify(@html.parse("<p>a</p>")) // "<p>a</p>"
/// ```
pub fn[T : Stringify] stringify(target : T) -> String {
  target.stringify()
}

///|
/// Compile selector text, remapping the internal error type to `SelectorError`.
fn compile_selector(input : String) -> @internal.Selector raise SelectorError {
  @internal.compile(input) catch {
    @internal.SelectorSyntax::Message(message) =>
      raise SelectorError::InvalidSelector(message)
  }
}

///|
/// Compile a CSS selector list once for repeated matching.
///
/// Raises `SelectorError` for a malformed or unsupported selector. Use the
/// result with `find_with`, `all_with`, `matches_with`, or `closest_with`.
///
/// ```mbt nocheck
/// let content = @html.Selector::parse("div.content").unwrap()
/// doc.find_with(content) // like doc.find("div.content"), without re-parsing
/// ```
pub fn Selector::parse(input : String) -> Selector raise SelectorError {
  { compiled: compile_selector(input), }
}

///|
pub impl Eq for Document with fn equal(self, other) {
  self.ctx.identity == other.ctx.identity
}

///|
pub impl Eq for Element with fn equal(self, other) {
  self.id == other.id && self.ctx.identity == other.ctx.identity
}

///|
pub impl Eq for Text with fn equal(self, other) {
  self.id == other.id && self.ctx.identity == other.ctx.identity
}

///|
pub impl Eq for Comment with fn equal(self, other) {
  self.id == other.id && self.ctx.identity == other.ctx.identity
}

///|
pub impl Eq for Directive with fn equal(self, other) {
  self.id == other.id && self.ctx.identity == other.ctx.identity
}

///|
pub impl Debug for Document with fn to_repr(self) {
  Repr::Repr("Document(offsets=0..\{self.end()})")
}

///|
pub impl Debug for Element with fn to_repr(self) {
  Repr::Repr("Element(\{self.name()}, offsets=\{self.start()}..\{self.end()})")
}

///|
pub impl Debug for Text with fn to_repr(self) {
  Repr::Repr("Text(\{self.value()})")
}

///|
pub impl Debug for Comment with fn to_repr(self) {
  Repr::Repr("Comment(\{self.value()})")
}

///|
pub impl Debug for Directive with fn to_repr(self) {
  Repr::Repr("Directive(\{self.value()})")
}

///|
/// Wrap a tree node id as a `Node` of the matching kind.
fn wrap(ctx : Context, id : Int32) -> Node {
  match ctx.tree.kind[id] {
    Element => Node::Element({ ctx, id, })
    Text => Node::Text({ ctx, id, })
    Comment => Node::Comment({ ctx, id, })
    Directive => Node::Directive({ ctx, id, })
    Document => abort("document cannot be a child node")
  }
}

///|
/// Wrap a tree node id as an `Element` handle.
fn element(ctx : Context, id : Int32) -> Element {
  { ctx, id, }
}

///|
/// Collect the direct children of a tree node as wrapped `Node`s.
fn children(ctx : Context, id : Int32) -> Array[Node] {
  let output : Array[Node] = []
  let mut current = id + 1
  while current < ctx.tree.stop[id] {
    output.push(wrap(ctx, current))
    current = ctx.tree.stop[current]
  }
  output
}

///|
/// Compile `selector` and return the first match under `id`, or `None`.
fn find_one(
  ctx : Context,
  id : Int32,
  selector : String,
) -> Element? raise SelectorError {
  let compiled = compile_selector(selector)
  let found = @internal.all(ctx.tree, id, compiled, limit=1)
  if found.is_empty() {
    None
  } else {
    Some(element(ctx, found[0]))
  }
}

///|
/// Compile `selector` and return every match under `id` in source order.
fn find_all(
  ctx : Context,
  id : Int32,
  selector : String,
) -> Array[Element] raise SelectorError {
  @internal.all(ctx.tree, id, compile_selector(selector)).map(id => {
    element(ctx, id)
  })
}

///|
/// Parse HTML into an immutable document.
///
/// Never raises: malformed markup is recovered htmlparser2-style (implied end
/// tags, foreign content, and bogus comments are handled leniently), which is
/// not the WHATWG browser tree-construction algorithm. Do not use the result
/// as a security boundary, e.g. as an HTML sanitizer.
///
/// ```mbt nocheck
/// let doc = @html.parse("<ul><li>one<li>two</ul>")
/// doc.all("li").length() // 2
/// ```
pub fn parse(source : String) -> Document {
  { ctx: Context::new(@internal.build(source)), }
}

///|
/// The exact source string the document was parsed from.
pub fn Document::source(self : Document) -> String {
  self.ctx.tree.source
}

///|
/// The start of the document's range: always `0`.
pub fn Document::start(_self : Document) -> Int32 {
  0
}

///|
/// The end of the document's range: the source length in UTF-16 code units.
pub fn Document::end(self : Document) -> Int32 {
  self.ctx.tree.source.length()
}

///|
/// The decoded text of all text nodes in document order.
///
/// Entities are decoded on the fly; tags, comments, and directives contribute
/// nothing.
pub fn Document::text(self : Document) -> String {
  @internal.text(self.ctx.tree, 0)
}

///|
/// The document's top-level nodes in source order.
pub fn Document::children(self : Document) -> Array[Node] {
  children(self.ctx, 0)
}

///|
/// The first element matching `selector` in source order, or `None`.
///
/// Raises `SelectorError` for a malformed or unsupported selector.
///
/// ```mbt nocheck
/// doc.find("main > p.intro")
/// ```
pub fn Document::find(
  self : Document,
  selector : String,
) -> Element? raise SelectorError {
  find_one(self.ctx, 0, selector)
}

///|
/// All elements matching `selector` in source order.
///
/// Raises `SelectorError` for a malformed or unsupported selector.
pub fn Document::all(
  self : Document,
  selector : String,
) -> Array[Element] raise SelectorError {
  find_all(self.ctx, 0, selector)
}

///|
/// The first element matching a selector compiled by `Selector::parse`, or
/// `None`.
pub fn Document::find_with(self : Document, selector : Selector) -> Element? {
  let found = @internal.all(self.ctx.tree, 0, selector.compiled, limit=1)
  if found.is_empty() {
    None
  } else {
    Some(element(self.ctx, found[0]))
  }
}

///|
/// All elements matching a selector compiled by `Selector::parse`.
pub fn Document::all_with(
  self : Document,
  selector : Selector,
) -> Array[Element] {
  @internal.all(self.ctx.tree, 0, selector.compiled).map(id => {
    element(self.ctx, id)
  })
}

///|
/// Convert a zero-based UTF-16 source offset to a one-based `Position`.
///
/// The line table is built on the first call and cached on the document.
pub fn Document::position(self : Document, offset : Int32) -> Position {
  if self.ctx.lines is None {
    let lines : Array[Int32] = []
    let mut at = @internal.find_from(self.ctx.tree.source, "\n", 0)
    while at != -1 {
      lines.push(at)
      at = @internal.find_from(self.ctx.tree.source, "\n", at + 1)
    }
    self.ctx.lines = Some(lines)
  }
  let lines = self.ctx.lines.unwrap()
  let mut low = 0
  let mut high = lines.length()
  while low < high {
    let middle = (low + high) >> 1
    if lines[middle] < offset {
      low = middle + 1
    } else {
      high = middle
    }
  }
  {
    line: low + 1,
    column: offset - (if low > 0 { lines[low - 1] + 1 } else { 0 }) + 1,
  }
}

///|
pub impl Stringify for Document with fn stringify(self) {
  self.source()
}

///|
/// The tag name.
///
/// HTML element names are lowercase; foreign-content (SVG/MathML) names keep
/// their canonical camelCase form, e.g. `foreignObject`.
pub fn Element::name(self : Element) -> String {
  self.ctx.tree.name[self.id]
}

///|
/// The document this element belongs to.
pub fn Element::document(self : Element) -> Document {
  { ctx: self.ctx, }
}

///|
/// The zero-based UTF-16 offset at which the element's open tag starts.
pub fn Element::start(self : Element) -> Int32 {
  self.ctx.tree.start[self.id]
}

///|
/// The zero-based UTF-16 offset just past the element.
///
/// For void elements this is the end of the open tag; for all others it is
/// just past the close tag, so `source[start..end]` spans the whole element.
pub fn Element::end(self : Element) -> Int32 {
  self.ctx.tree.end[self.id]
}

///|
/// The element's parent: an enclosing element, or the document for top-level
/// elements.
pub fn Element::parent(self : Element) -> Parent {
  let parent = self.ctx.tree.parent[self.id]
  if parent == 0 {
    Parent::Document({ ctx: self.ctx, })
  } else {
    Parent::Element(element(self.ctx, parent))
  }
}

///|
/// The element's child nodes in source order.
pub fn Element::children(self : Element) -> Array[Node] {
  children(self.ctx, self.id)
}

///|
/// An independent map of the element's attributes.
///
/// Keys are lowercase and values are entity-decoded. The returned map is a
/// copy: mutating it does not affect the document.
pub fn Element::attributes(self : Element) -> Map[String, String] {
  @internal.attributes(self.ctx.tree, self.id).copy()
}

///|
/// The decoded value of an attribute, matched without regard to ASCII case,
/// or `None` if the attribute is absent.
///
/// A present-but-empty attribute such as `disabled` returns `Some("")`.
pub fn Element::get_attr(self : Element, name : String) -> String? {
  @internal.attribute(self.ctx.tree, self.id, name.to_lower())
}

///|
/// Whether the element has the attribute, matched without regard to ASCII
/// case.
pub fn Element::has_attr(self : Element, name : String) -> Bool {
  self.get_attr(name) is Some(_)
}

///|
/// The decoded text of all descendant text nodes, concatenated in source
/// order.
pub fn Element::text(self : Element) -> String {
  @internal.text(self.ctx.tree, self.id)
}

///|
/// The element's inner HTML exactly as written in the source, without
/// decoding or reformatting.
pub fn Element::html(self : Element) -> String {
  @internal.slice(
    self.ctx.tree.source,
    self.ctx.tree.from[self.id],
    self.ctx.tree.to[self.id],
  )
}

///|
/// The first matching descendant element in source order, or `None`.
///
/// Raises `SelectorError` for a malformed or unsupported selector.
pub fn Element::find(
  self : Element,
  selector : String,
) -> Element? raise SelectorError {
  find_one(self.ctx, self.id, selector)
}

///|
/// All matching descendant elements in source order.
///
/// Raises `SelectorError` for a malformed or unsupported selector.
pub fn Element::all(
  self : Element,
  selector : String,
) -> Array[Element] raise SelectorError {
  find_all(self.ctx, self.id, selector)
}

///|
/// The first matching descendant using a selector compiled by
/// `Selector::parse`, or `None`.
pub fn Element::find_with(self : Element, selector : Selector) -> Element? {
  let found = @internal.all(self.ctx.tree, self.id, selector.compiled, limit=1)
  if found.is_empty() {
    None
  } else {
    Some(element(self.ctx, found[0]))
  }
}

///|
/// All matching descendants using a selector compiled by `Selector::parse`.
pub fn Element::all_with(self : Element, selector : Selector) -> Array[Element] {
  @internal.all(self.ctx.tree, self.id, selector.compiled).map(id => {
    element(self.ctx, id)
  })
}

///|
/// Whether the element itself matches `selector`.
///
/// Raises `SelectorError` for a malformed or unsupported selector.
pub fn Element::matches(
  self : Element,
  selector : String,
) -> Bool raise SelectorError {
  @internal.matches(self.ctx.tree, self.id, compile_selector(selector))
}

///|
/// The element itself if it matches `selector`, otherwise the nearest
/// matching ancestor; `None` if neither matches.
///
/// Raises `SelectorError` for a malformed or unsupported selector.
pub fn Element::closest(
  self : Element,
  selector : String,
) -> Element? raise SelectorError {
  let compiled = compile_selector(selector)
  let mut id = self.id
  while id > 0 {
    if @internal.matches(self.ctx.tree, id, compiled) {
      return Some(element(self.ctx, id))
    }
    id = self.ctx.tree.parent[id]
  }
  None
}

///|
/// Whether the element itself matches a selector compiled by
/// `Selector::parse`.
pub fn Element::matches_with(self : Element, selector : Selector) -> Bool {
  @internal.matches(self.ctx.tree, self.id, selector.compiled)
}

///|
/// The element itself if it matches a selector compiled by `Selector::parse`,
/// otherwise the nearest matching ancestor; `None` if neither matches.
pub fn Element::closest_with(self : Element, selector : Selector) -> Element? {
  let mut id = self.id
  while id > 0 {
    if @internal.matches(self.ctx.tree, id, selector.compiled) {
      return Some(element(self.ctx, id))
    }
    id = self.ctx.tree.parent[id]
  }
  None
}

///|
pub impl Stringify for Element with fn stringify(self) {
  @internal.slice(self.ctx.tree.source, self.start(), self.end())
}

///|
/// The document this node belongs to.
pub fn Node::document(self : Node) -> Document {
  match self {
    Element(node) => node.document()
    Text(node) => node.document()
    Comment(node) => node.document()
    Directive(node) => node.document()
  }
}

///|
/// The zero-based UTF-16 offset at which this node starts.
pub fn Node::start(self : Node) -> Int32 {
  match self {
    Element(node) => node.start()
    Text(node) => node.start()
    Comment(node) => node.start()
    Directive(node) => node.start()
  }
}

///|
/// The zero-based UTF-16 offset just past this node.
pub fn Node::end(self : Node) -> Int32 {
  match self {
    Element(node) => node.end()
    Text(node) => node.end()
    Comment(node) => node.end()
    Directive(node) => node.end()
  }
}

///|
/// The node's parent: an enclosing element, or the document for top-level
/// nodes.
pub fn Node::parent(self : Node) -> Parent {
  match self {
    Element(node) => node.parent()
    Text(node) => node.parent()
    Comment(node) => node.parent()
    Directive(node) => node.parent()
  }
}

///|
pub impl Stringify for Node with fn stringify(self) {
  match self {
    Element(node) => node.stringify()
    Text(node) => node.stringify()
    Comment(node) => node.stringify()
    Directive(node) => node.stringify()
  }
}

///|
/// The text content with entities decoded, e.g. `&amp;` becomes `&`.
pub fn Text::value(self : Text) -> String {
  @internal.value(self.ctx.tree, self.id)
}

///|
/// The document this text node belongs to.
pub fn Text::document(self : Text) -> Document {
  { ctx: self.ctx, }
}

///|
/// The zero-based UTF-16 offset at which the text starts.
pub fn Text::start(self : Text) -> Int32 {
  self.ctx.tree.start[self.id]
}

///|
/// The zero-based UTF-16 offset just past the text.
pub fn Text::end(self : Text) -> Int32 {
  self.ctx.tree.end[self.id]
}

///|
/// The text node's parent: an enclosing element, or the document for
/// top-level text.
pub fn Text::parent(self : Text) -> Parent {
  leaf_parent(self.ctx, self.id)
}

///|
pub impl Stringify for Text with fn stringify(self) {
  @internal.slice(self.ctx.tree.source, self.start(), self.end())
}

///|
/// The comment content without the surrounding `<!--` and `-->`.
pub fn Comment::value(self : Comment) -> String {
  @internal.value(self.ctx.tree, self.id)
}

///|
/// The document this comment belongs to.
pub fn Comment::document(self : Comment) -> Document {
  { ctx: self.ctx, }
}

///|
/// The zero-based UTF-16 offset at which the comment starts, pointing at `<!`.
pub fn Comment::start(self : Comment) -> Int32 {
  self.ctx.tree.start[self.id]
}

///|
/// The zero-based UTF-16 offset just past the comment's `-->`.
pub fn Comment::end(self : Comment) -> Int32 {
  self.ctx.tree.end[self.id]
}

///|
/// The comment's parent: an enclosing element, or the document for top-level
/// comments.
pub fn Comment::parent(self : Comment) -> Parent {
  leaf_parent(self.ctx, self.id)
}

///|
pub impl Stringify for Comment with fn stringify(self) {
  @internal.slice(self.ctx.tree.source, self.start(), self.end())
}

///|
/// The directive's raw content, e.g. `doctype html` for `<!doctype html>`.
pub fn Directive::value(self : Directive) -> String {
  @internal.value(self.ctx.tree, self.id)
}

///|
/// The document this directive belongs to.
pub fn Directive::document(self : Directive) -> Document {
  { ctx: self.ctx, }
}

///|
/// The zero-based UTF-16 offset at which the directive starts, pointing at `<!`.
pub fn Directive::start(self : Directive) -> Int32 {
  self.ctx.tree.start[self.id]
}

///|
/// The zero-based UTF-16 offset just past the directive's closing `>`.
pub fn Directive::end(self : Directive) -> Int32 {
  self.ctx.tree.end[self.id]
}

///|
/// The directive's parent: always the document, since directives only appear
/// at the top level.
pub fn Directive::parent(self : Directive) -> Parent {
  leaf_parent(self.ctx, self.id)
}

///|
pub impl Stringify for Directive with fn stringify(self) {
  @internal.slice(self.ctx.tree.source, self.start(), self.end())
}

///|
/// Resolve the parent of a leaf (non-element) node as a `Parent` value.
fn leaf_parent(ctx : Context, id : Int32) -> Parent {
  let parent = ctx.tree.parent[id]
  if parent == 0 {
    Parent::Document({ ctx, })
  } else {
    Parent::Element(element(ctx, parent))
  }
}
