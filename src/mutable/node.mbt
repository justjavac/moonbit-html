///|
/// Errors raised by invalid selectors or tree edits.
///
/// - `InvalidSelector`: a malformed or unsupported CSS selector.
/// - `InvalidName`: an invalid tag or attribute name, or a rename that is not
///   allowed (e.g. renaming an element with children to a void element).
/// - `InvalidInsertion`: an illegal tree edit, such as adding children to a
///   void element or inserting a node into itself or its own descendant.
/// - `InvalidValue`: comment or directive content that cannot be serialized,
///   e.g. a comment value containing `--`.
/// - `NoParent`: the node has no parent to insert relative to (it is
///   detached).
pub suberror HtmlError {
  InvalidSelector(String)
  InvalidName(String)
  InvalidInsertion(String)
  InvalidValue(String)
  NoParent
}

///|
/// A mutable HTML document produced by `parse`.
///
/// Nodes are stateful handles: an edit made through one handle is visible
/// through every other handle of the same document. Untouched parts keep
/// referencing the original source, so `stringify` rebuilds only edited
/// branches.
///
/// ```mbt nocheck
/// let doc = @mutable.parse("<ul><li>a</li></ul>")
/// doc.find("li").unwrap().set_attr("class", "first")
/// doc.stringify() // "<ul><li class=\"first\">a</li></ul>"
/// ```
pub struct Document {
  priv state : State
}

///|
/// A mutable handle to an element node.
///
/// The handle stays valid after edits elsewhere in the document. Once the
/// node is detached by `remove` or `replace`, further edits through this
/// handle have no effect and `parent` returns `None`.
pub struct Element {
  priv state : State
}

///|
/// A mutable handle to a text node, including foreign-content CDATA sections.
pub struct Text {
  priv state : State
}

///|
/// A mutable handle to a normal or bogus comment node.
pub struct Comment {
  priv state : State
}

///|
/// A mutable handle to a doctype declaration.
pub struct Directive {
  priv state : State
}

///|
/// A child node in a mutable document: an element, text, comment, or
/// directive.
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
/// Content to insert into a mutable tree.
///
/// `Content::Text` strings are inserted as literal text nodes and are never
/// parsed as HTML. `Content::Node` moves an existing node: it is first
/// detached from its current position.
pub(all) enum Content {
  Node(Node)
  Text(String)
}

///|
/// A one-based line and column in the original UTF-16 source.
#derive(Eq, Debug)
pub(all) struct Position {
  line : Int32
  column : Int32
}

///|
/// Values that can be serialized back to HTML.
///
/// Untouched parts of a mutable document serialize to their exact original
/// source; edited branches are rebuilt from their current state.
pub trait Stringify {
  fn stringify(Self) -> String
}

///|
/// Serialize any `Stringify` value to its HTML string.
pub fn[T : Stringify] stringify(target : T) -> String {
  target.stringify()
}

///|
pub impl Eq for Document with fn equal(self, other) {
  self.state.identity == other.state.identity
}

///|
pub impl Eq for Element with fn equal(self, other) {
  self.state.identity == other.state.identity
}

///|
pub impl Eq for Text with fn equal(self, other) {
  self.state.identity == other.state.identity
}

///|
pub impl Eq for Comment with fn equal(self, other) {
  self.state.identity == other.state.identity
}

///|
pub impl Eq for Directive with fn equal(self, other) {
  self.state.identity == other.state.identity
}

///|
pub impl Debug for Document with fn to_repr(_self) {
  Repr::Repr("Document")
}

///|
pub impl Debug for Element with fn to_repr(self) {
  Repr::Repr("Element(\{self.name()})")
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
/// Parse HTML into a mutable document.
///
/// Never raises: malformed markup is recovered the same way as in the
/// immutable `justjavac/html` package. Parsing a mutable document costs more
/// than the immutable `parse` because every node becomes a stateful handle;
/// prefer the immutable package for read-only workloads.
pub fn parse(source : String) -> Document {
  { state: document(source), }
}

///|
/// Wrap a state as a `Node` of the matching kind.
fn wrap(state : State) -> Node {
  match state.kind {
    Element => Node::Element({ state, })
    Text => Node::Text({ state, })
    Comment => Node::Comment({ state, })
    Directive => Node::Directive({ state, })
    Document => abort("document cannot be a child node")
  }
}

///|
/// Wrap a state as a `Parent`, distinguishing the document from elements.
fn wrap_parent(state : State) -> Parent {
  if state.kind == StateKind::Document {
    Parent::Document({ state, })
  } else {
    Parent::Element({ state, })
  }
}

///|
/// Wrap a state's children as `Node` handles.
fn node_children(state : State) -> Array[Node] {
  state.children.map(wrap)
}

///|
/// Compile `selector` and return the first match under `state`, or `None`.
fn find_state(state : State, selector : String) -> Element? raise HtmlError {
  let found = all(state, compile(selector), limit=1)
  if found.is_empty() {
    None
  } else {
    Some({ state: found[0], })
  }
}

///|
/// Compile `selector` and return every match under `state` in source order.
fn all_states(
  state : State,
  selector : String,
) -> Array[Element] raise HtmlError {
  all(state, compile(selector)).map(state => { state, })
}

///|
/// The state's offset in the original source, or `None` for nodes created by edits.
fn offset(state : State, start : Bool) -> Int32? {
  if state.tree is Some(_) && state.source == doc_of(state).source {
    Some(if start { state.start } else { state.end })
  } else {
    None
  }
}

///|
/// The state's parent and its index among the parent's children.
fn state_index(state : State) -> (State, Int32) raise HtmlError {
  guard state.parent is Some(parent) else { raise HtmlError::NoParent }
  for i in 0..<parent.children.length() {
    if parent.children[i].identity == state.identity {
      return (parent, i)
    }
  }
  raise HtmlError::NoParent
}

///|
/// Materialize `Content` items as states owned by the target's document.
fn content_states(target : State, items : Array[Content]) -> Array[State] {
  items.map(item => {
    match item {
      Content::Text(text) => text_node(doc_of(target), text)
      Content::Node(node) => unwrap(node)
    }
  })
}

///|
/// Extract the state behind a `Node` handle.
fn unwrap(node : Node) -> State {
  match node {
    Element(node) => node.state
    Text(node) => node.state
    Comment(node) => node.state
    Directive(node) => node.state
  }
}

///|
/// Insert items as previous siblings of `node`.
fn insert_before(node : Node, items : Array[Content]) -> Unit raise HtmlError {
  let state = unwrap(node)
  let (parent, at) = state_index(state)
  insert(parent, at, content_states(parent, items))
}

///|
/// Insert items as next siblings of `node`.
fn insert_after(node : Node, items : Array[Content]) -> Unit raise HtmlError {
  let state = unwrap(node)
  let (parent, at) = state_index(state)
  insert(parent, at + 1, content_states(parent, items))
}

///|
/// Swap `node` for the given items, detaching it unless it was re-inserted.
fn replace_node(node : Node, items : Array[Content]) -> Unit raise HtmlError {
  let state = unwrap(node)
  let (parent, at) = state_index(state)
  let next = content_states(parent, items)
  insert(parent, at, next)
  if !next.any(item => item.identity == state.identity) {
    detach(state)
  }
}

///|
/// Deep-clone a node into a detached state tree.
fn clone_node(node : Node) -> Node {
  wrap(clone_state(unwrap(node)))
}

///|
/// The original source string the document was parsed from.
///
/// Edits do not modify this string; `stringify` reflects the current tree.
pub fn Document::source(self : Document) -> String {
  self.state.source
}

///|
/// The start of the document's range: always `0`.
pub fn Document::start(_self : Document) -> Int32 {
  0
}

///|
/// The end of the document's range: the source length in UTF-16 code units.
pub fn Document::end(self : Document) -> Int32 {
  self.state.source.length()
}

///|
/// The decoded text of all text nodes in document order, reflecting edits.
pub fn Document::text(self : Document) -> String {
  state_text(self.state)
}

///|
/// The document's top-level nodes in source order.
pub fn Document::children(self : Document) -> Array[Node] {
  node_children(self.state)
}

///|
/// The first element matching `selector` in source order, or `None`.
///
/// Raises `HtmlError::InvalidSelector` for a malformed or unsupported
/// selector.
pub fn Document::find(
  self : Document,
  selector : String,
) -> Element? raise HtmlError {
  find_state(self.state, selector)
}

///|
/// All elements matching `selector` in source order.
///
/// Raises `HtmlError::InvalidSelector` for a malformed or unsupported
/// selector.
pub fn Document::all(
  self : Document,
  selector : String,
) -> Array[Element] raise HtmlError {
  all_states(self.state, selector)
}

///|
/// Convert a zero-based UTF-16 offset in the original source to a one-based
/// `Position`.
pub fn Document::position(self : Document, offset : Int32) -> Position {
  let lines : Array[Int32] = []
  let mut at = @internal.find_from(self.state.source, "\n", 0)
  while at != -1 {
    lines.push(at)
    at = @internal.find_from(self.state.source, "\n", at + 1)
  }
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
/// Insert items as the last top-level nodes of the document.
///
/// Existing nodes passed as `Content::Node` are moved from their current
/// position.
pub fn Document::append(
  self : Document,
  items : Array[Content],
) -> Unit raise HtmlError {
  insert(
    self.state,
    self.state.children.length(),
    content_states(self.state, items),
  )
}

///|
/// Insert items as the first top-level nodes of the document.
///
/// Existing nodes passed as `Content::Node` are moved from their current
/// position.
pub fn Document::prepend(
  self : Document,
  items : Array[Content],
) -> Unit raise HtmlError {
  insert(self.state, 0, content_states(self.state, items))
}

///|
pub impl Stringify for Document with fn stringify(self) {
  serialize(self.state)
}

///|
/// The tag name.
///
/// HTML element names are lowercase; foreign-content (SVG/MathML) names keep
/// their canonical camelCase form, e.g. `foreignObject`.
pub fn Element::name(self : Element) -> String {
  self.state.name
}

///|
/// The document this element belongs to.
pub fn Element::document(self : Element) -> Document {
  { state: doc_of(self.state), }
}

///|
/// The zero-based UTF-16 offset at which the element's open tag starts in the
/// original source, or `None` for elements created by edits.
pub fn Element::start(self : Element) -> Int32? {
  offset(self.state, true)
}

///|
/// The zero-based UTF-16 offset just past the element in the original
/// source, or `None` for elements created by edits.
pub fn Element::end(self : Element) -> Int32? {
  offset(self.state, false)
}

///|
/// The element's parent, or `None` if the element has been detached by
/// `remove` or `replace`.
pub fn Element::parent(self : Element) -> Parent? {
  self.state.parent.map(wrap_parent)
}

///|
/// The element's child nodes in source order.
pub fn Element::children(self : Element) -> Array[Node] {
  node_children(self.state)
}

///|
/// An independent map of the element's attributes.
///
/// Keys are lowercase and values are entity-decoded. The returned map is a
/// copy: mutating it does not affect the document; use `set_attr` instead.
pub fn Element::attributes(self : Element) -> Map[String, String] {
  attributes(self.state).copy()
}

///|
/// The decoded value of an attribute, matched without regard to ASCII case,
/// or `None` if the attribute is absent.
pub fn Element::get_attr(self : Element, name : String) -> String? {
  attributes(self.state).get(name.to_lower())
}

///|
/// Whether the element has the attribute, matched without regard to ASCII
/// case.
pub fn Element::has_attr(self : Element, name : String) -> Bool {
  self.get_attr(name) is Some(_)
}

///|
/// Whether a string is usable as an attribute name.
fn valid_attribute_name(name : String) -> Bool {
  if name.is_empty() {
    return false
  }
  for i in 0..<name.length() {
    let code = @internal.code_at(name, i)
    if @internal.is_space(code) ||
      code == 34 ||
      code == 39 ||
      code == 62 ||
      code == 47 ||
      code == 61 {
      return false
    }
  }
  true
}

///|
/// Whether a string is usable as a tag name.
fn valid_tag_name(name : String) -> Bool {
  if name.is_empty() || !@internal.is_alpha(@internal.code_at(name, 0)) {
    return false
  }
  for i in 1..<name.length() {
    let code = @internal.code_at(name, i)
    if @internal.is_space(code) ||
      code == 34 ||
      code == 39 ||
      code == 60 ||
      code == 62 ||
      code == 47 ||
      code == 61 {
      return false
    }
  }
  true
}

///|
/// Set an attribute, replacing any existing value.
///
/// Values are stored decoded and re-escaped during serialization. Raises
/// `HtmlError::InvalidName` if the name is empty or contains spaces, quotes,
/// `>`, `/`, or `=`.
pub fn Element::set_attr(
  self : Element,
  name : String,
  value : String,
) -> Unit raise HtmlError {
  if !valid_attribute_name(name) {
    raise HtmlError::InvalidName("Invalid attribute name: \"\{name}\"")
  }
  set_attribute(self.state, name, value)
}

///|
/// Remove an attribute if present, matched without regard to ASCII case.
pub fn Element::remove_attr(self : Element, name : String) -> Unit {
  remove_attribute(self.state, name.to_lower())
}

///|
/// Rename the element's tag.
///
/// Raises `HtmlError::InvalidName` for an invalid tag name, when renaming an
/// element with children to a void element (e.g. `br`), or when renaming an
/// element with child elements to a raw-text element (e.g. `script`).
pub fn Element::set_name(self : Element, name : String) -> Unit raise HtmlError {
  if !valid_tag_name(name) {
    raise HtmlError::InvalidName("Invalid tag name: \"\{name}\"")
  }
  rename(self.state, name)
}

///|
/// The decoded text of all descendant text nodes, concatenated in source
/// order.
pub fn Element::text(self : Element) -> String {
  state_text(self.state)
}

///|
/// Replace all children with a single literal text node.
///
/// The string is inserted as text, never parsed as HTML.
pub fn Element::set_text(self : Element, text : String) -> Unit raise HtmlError {
  replace_children(self.state, [text_node(doc_of(self.state), text)])
}

///|
/// The element's inner HTML, reflecting edits.
pub fn Element::html(self : Element) -> String {
  inner(self.state)
}

///|
/// Replace all children with nodes parsed from an HTML string.
///
/// The string is parsed in the element's context: raw-text elements such as
/// `script` keep their content as raw text, and foreign-content elements
/// (SVG/MathML) parse foreign markup.
pub fn Element::set_html(self : Element, html : String) -> Unit raise HtmlError {
  if @internal.is_raw(self.state.name) && !within(self.state) {
    let raw = if @internal.is_literal(self.state.name) {
      html
    } else {
      @internal.decode_html(html)
    }
    replace_children(self.state, [text_node(doc_of(self.state), raw)])
  } else {
    replace_children(
      self.state,
      fragment(doc_of(self.state), html, foreign_state(self.state)),
    )
  }
}

///|
/// The first matching descendant element in source order, or `None`.
///
/// Raises `HtmlError::InvalidSelector` for a malformed or unsupported
/// selector.
pub fn Element::find(
  self : Element,
  selector : String,
) -> Element? raise HtmlError {
  find_state(self.state, selector)
}

///|
/// All matching descendant elements in source order.
///
/// Raises `HtmlError::InvalidSelector` for a malformed or unsupported
/// selector.
pub fn Element::all(
  self : Element,
  selector : String,
) -> Array[Element] raise HtmlError {
  all_states(self.state, selector)
}

///|
/// Whether the element itself matches `selector`.
///
/// Raises `HtmlError::InvalidSelector` for a malformed or unsupported
/// selector.
pub fn Element::matches(
  self : Element,
  selector : String,
) -> Bool raise HtmlError {
  matches(self.state, compile(selector))
}

///|
/// The element itself if it matches `selector`, otherwise the nearest
/// matching ancestor; `None` if neither matches.
///
/// Raises `HtmlError::InvalidSelector` for a malformed or unsupported
/// selector.
pub fn Element::closest(
  self : Element,
  selector : String,
) -> Element? raise HtmlError {
  let compiled = compile(selector)
  let mut current = Some(self.state)
  while current is Some(state) {
    if matches(state, compiled) {
      return Some({ state, })
    }
    current = state.parent
  }
  None
}

///|
/// A deep copy of the element and its descendants.
///
/// The copy is detached: it belongs to the same document but has no parent
/// until inserted.
pub fn Element::clone(self : Element) -> Element {
  match clone_node(Node::Element(self)) {
    Element(copy) => copy
    _ => abort("unreachable")
  }
}

///|
/// Insert items as the element's last children.
///
/// Raises `HtmlError::InvalidInsertion` when adding children to a void
/// element or inserting a node into itself or its own descendant.
pub fn Element::append(
  self : Element,
  items : Array[Content],
) -> Unit raise HtmlError {
  insert(
    self.state,
    self.state.children.length(),
    content_states(self.state, items),
  )
}

///|
/// Insert items as the element's first children.
///
/// Raises `HtmlError::InvalidInsertion` when adding children to a void
/// element or inserting a node into itself or its own descendant.
pub fn Element::prepend(
  self : Element,
  items : Array[Content],
) -> Unit raise HtmlError {
  insert(self.state, 0, content_states(self.state, items))
}

///|
/// Insert items as previous siblings of this element.
///
/// Raises `HtmlError::NoParent` if the element is detached.
pub fn Element::before(
  self : Element,
  items : Array[Content],
) -> Unit raise HtmlError {
  insert_before(Node::Element(self), items)
}

///|
/// Insert items as next siblings of this element.
///
/// Raises `HtmlError::NoParent` if the element is detached.
pub fn Element::after(
  self : Element,
  items : Array[Content],
) -> Unit raise HtmlError {
  insert_after(Node::Element(self), items)
}

///|
/// Replace this element with the given items.
///
/// Afterwards this handle is detached: further edits through it have no
/// effect. Raises `HtmlError::NoParent` if the element is already detached.
pub fn Element::replace(
  self : Element,
  items : Array[Content],
) -> Unit raise HtmlError {
  replace_node(Node::Element(self), items)
}

///|
/// Detach the element from its parent.
///
/// Afterwards this handle is inert: edits through it have no effect and
/// `parent` returns `None`, but its current content remains readable.
pub fn Element::remove(self : Element) -> Unit {
  detach(self.state)
}

///|
pub impl Stringify for Element with fn stringify(self) {
  serialize(self.state)
}

///|
/// The document this node belongs to.
pub fn Node::document(self : Node) -> Document {
  { state: doc_of(unwrap(self)), }
}

///|
/// The zero-based UTF-16 offset at which the node starts in the original
/// source, or `None` for nodes created by edits.
pub fn Node::start(self : Node) -> Int32? {
  offset(unwrap(self), true)
}

///|
/// The zero-based UTF-16 offset just past the node in the original source,
/// or `None` for nodes created by edits.
pub fn Node::end(self : Node) -> Int32? {
  offset(unwrap(self), false)
}

///|
/// The node's parent, or `None` if the node has been detached.
pub fn Node::parent(self : Node) -> Parent? {
  unwrap(self).parent.map(wrap_parent)
}

///|
/// Insert items as previous siblings of this node.
///
/// Raises `HtmlError::NoParent` if the node is detached.
pub fn Node::before(
  self : Node,
  items : Array[Content],
) -> Unit raise HtmlError {
  insert_before(self, items)
}

///|
/// Insert items as next siblings of this node.
///
/// Raises `HtmlError::NoParent` if the node is detached.
pub fn Node::after(self : Node, items : Array[Content]) -> Unit raise HtmlError {
  insert_after(self, items)
}

///|
/// Replace this node with the given items, detaching the original node.
///
/// Raises `HtmlError::NoParent` if the node is already detached.
pub fn Node::replace(
  self : Node,
  items : Array[Content],
) -> Unit raise HtmlError {
  replace_node(self, items)
}

///|
/// Detach the node from its parent; later edits through this handle have no
/// effect.
pub fn Node::remove(self : Node) -> Unit {
  detach(unwrap(self))
}

///|
/// A deep copy of the node and its descendants, detached until inserted.
pub fn Node::clone(self : Node) -> Node {
  clone_node(self)
}

///|
pub impl Stringify for Node with fn stringify(self) {
  serialize(unwrap(self))
}

///|
/// The text content with entities decoded, e.g. `&amp;` becomes `&`.
pub fn Text::value(self : Text) -> String {
  state_value(self.state)
}

///|
/// Replace the text content; the value is stored decoded and re-escaped
/// during serialization.
pub fn Text::set_value(self : Text, value : String) -> Unit {
  set_value(self.state, value)
}

///|
/// The document this text node belongs to.
pub fn Text::document(self : Text) -> Document {
  { state: doc_of(self.state), }
}

///|
/// The zero-based UTF-16 offset at which the text starts in the original
/// source, or `None` for text created by edits.
pub fn Text::start(self : Text) -> Int32? {
  offset(self.state, true)
}

///|
/// The zero-based UTF-16 offset just past the text in the original source,
/// or `None` for text created by edits.
pub fn Text::end(self : Text) -> Int32? {
  offset(self.state, false)
}

///|
/// The text node's parent, or `None` if it has been detached.
pub fn Text::parent(self : Text) -> Parent? {
  self.state.parent.map(wrap_parent)
}

///|
/// A copy of the text node, detached until inserted.
pub fn Text::clone(self : Text) -> Text {
  match clone_node(Node::Text(self)) {
    Text(copy) => copy
    _ => abort("unreachable")
  }
}

///|
/// Insert items as previous siblings of this text node.
///
/// Raises `HtmlError::NoParent` if the node is detached.
pub fn Text::before(
  self : Text,
  items : Array[Content],
) -> Unit raise HtmlError {
  insert_before(Node::Text(self), items)
}

///|
/// Insert items as next siblings of this text node.
///
/// Raises `HtmlError::NoParent` if the node is detached.
pub fn Text::after(self : Text, items : Array[Content]) -> Unit raise HtmlError {
  insert_after(Node::Text(self), items)
}

///|
/// Replace this text node with the given items, detaching the original node.
///
/// Raises `HtmlError::NoParent` if the node is already detached.
pub fn Text::replace(
  self : Text,
  items : Array[Content],
) -> Unit raise HtmlError {
  replace_node(Node::Text(self), items)
}

///|
/// Detach the text node from its parent; later edits through this handle
/// have no effect.
pub fn Text::remove(self : Text) -> Unit {
  detach(self.state)
}

///|
pub impl Stringify for Text with fn stringify(self) {
  serialize(self.state)
}

///|
/// The comment content without the surrounding `<!--` and `-->`.
pub fn Comment::value(self : Comment) -> String {
  state_value(self.state)
}

///|
/// Replace the comment content.
///
/// Raises `HtmlError::InvalidValue` if the value cannot be serialized as a
/// comment, e.g. it contains `--`.
pub fn Comment::set_value(
  self : Comment,
  value : String,
) -> Unit raise HtmlError {
  if !valid_leaf("<!--" + value + "-->", @internal.Kind::Comment, value) {
    raise HtmlError::InvalidValue("Invalid comment: \"\{value}\"")
  }
  set_value(self.state, value)
}

///|
/// The document this comment belongs to.
pub fn Comment::document(self : Comment) -> Document {
  { state: doc_of(self.state), }
}

///|
/// The zero-based UTF-16 offset at which the comment starts in the original
/// source, or `None` for comments created by edits.
pub fn Comment::start(self : Comment) -> Int32? {
  offset(self.state, true)
}

///|
/// The zero-based UTF-16 offset just past the comment's `-->` in the
/// original source, or `None` for comments created by edits.
pub fn Comment::end(self : Comment) -> Int32? {
  offset(self.state, false)
}

///|
/// The comment's parent, or `None` if it has been detached.
pub fn Comment::parent(self : Comment) -> Parent? {
  self.state.parent.map(wrap_parent)
}

///|
/// A copy of the comment, detached until inserted.
pub fn Comment::clone(self : Comment) -> Comment {
  match clone_node(Node::Comment(self)) {
    Comment(copy) => copy
    _ => abort("unreachable")
  }
}

///|
/// Insert items as previous siblings of this comment.
///
/// Raises `HtmlError::NoParent` if the comment is detached.
pub fn Comment::before(
  self : Comment,
  items : Array[Content],
) -> Unit raise HtmlError {
  insert_before(Node::Comment(self), items)
}

///|
/// Insert items as next siblings of this comment.
///
/// Raises `HtmlError::NoParent` if the comment is detached.
pub fn Comment::after(
  self : Comment,
  items : Array[Content],
) -> Unit raise HtmlError {
  insert_after(Node::Comment(self), items)
}

///|
/// Replace this comment with the given items, detaching the original node.
///
/// Raises `HtmlError::NoParent` if the comment is already detached.
pub fn Comment::replace(
  self : Comment,
  items : Array[Content],
) -> Unit raise HtmlError {
  replace_node(Node::Comment(self), items)
}

///|
/// Detach the comment from its parent; later edits through this handle have
/// no effect.
pub fn Comment::remove(self : Comment) -> Unit {
  detach(self.state)
}

///|
pub impl Stringify for Comment with fn stringify(self) {
  serialize(self.state)
}

///|
/// The directive's raw content, e.g. `doctype html` for `<!doctype html>`.
pub fn Directive::value(self : Directive) -> String {
  state_value(self.state)
}

///|
/// Replace the directive's content.
///
/// Raises `HtmlError::InvalidValue` if the value cannot be serialized as a
/// directive.
pub fn Directive::set_value(
  self : Directive,
  value : String,
) -> Unit raise HtmlError {
  if !valid_leaf("<!" + value + ">", @internal.Kind::Directive, value) {
    raise HtmlError::InvalidValue("Invalid directive: \"\{value}\"")
  }
  set_value(self.state, value)
}

///|
/// The document this directive belongs to.
pub fn Directive::document(self : Directive) -> Document {
  { state: doc_of(self.state), }
}

///|
/// The zero-based UTF-16 offset at which the directive starts in the
/// original source, or `None` for directives created by edits.
pub fn Directive::start(self : Directive) -> Int32? {
  offset(self.state, true)
}

///|
/// The zero-based UTF-16 offset just past the directive's closing `>` in the
/// original source, or `None` for directives created by edits.
pub fn Directive::end(self : Directive) -> Int32? {
  offset(self.state, false)
}

///|
/// The directive's parent, or `None` if it has been detached.
pub fn Directive::parent(self : Directive) -> Parent? {
  self.state.parent.map(wrap_parent)
}

///|
/// A copy of the directive, detached until inserted.
pub fn Directive::clone(self : Directive) -> Directive {
  match clone_node(Node::Directive(self)) {
    Directive(copy) => copy
    _ => abort("unreachable")
  }
}

///|
/// Insert items as previous siblings of this directive.
///
/// Raises `HtmlError::NoParent` if the directive is detached.
pub fn Directive::before(
  self : Directive,
  items : Array[Content],
) -> Unit raise HtmlError {
  insert_before(Node::Directive(self), items)
}

///|
/// Insert items as next siblings of this directive.
///
/// Raises `HtmlError::NoParent` if the directive is detached.
pub fn Directive::after(
  self : Directive,
  items : Array[Content],
) -> Unit raise HtmlError {
  insert_after(Node::Directive(self), items)
}

///|
/// Replace this directive with the given items, detaching the original node.
///
/// Raises `HtmlError::NoParent` if the directive is already detached.
pub fn Directive::replace(
  self : Directive,
  items : Array[Content],
) -> Unit raise HtmlError {
  replace_node(Node::Directive(self), items)
}

///|
/// Detach the directive from its parent; later edits through this handle
/// have no effect.
pub fn Directive::remove(self : Directive) -> Unit {
  detach(self.state)
}

///|
pub impl Stringify for Directive with fn stringify(self) {
  serialize(self.state)
}
