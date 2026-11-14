///|
/// Errors raised by invalid selectors or tree edits.
pub suberror HtmlError {
  InvalidSelector(String)
  InvalidName(String)
  InvalidInsertion(String)
  InvalidValue(String)
  NoParent
}

///|
/// A mutable HTML document.
pub struct Document {
  priv state : State
}

///|
pub struct Element {
  priv state : State
}

///|
pub struct Text {
  priv state : State
}

///|
pub struct Comment {
  priv state : State
}

///|
pub struct Directive {
  priv state : State
}

///|
#derive(Eq, Debug)
pub(all) enum Node {
  Element(Element)
  Text(Text)
  Comment(Comment)
  Directive(Directive)
}

///|
#derive(Eq, Debug)
pub(all) enum Parent {
  Document(Document)
  Element(Element)
}

///|
/// Content to insert. Strings are always inserted as text, never parsed as HTML.
pub(all) enum Content {
  Node(Node)
  Text(String)
}

///|
#derive(Eq, Debug)
pub(all) struct Position {
  line : Int32
  column : Int32
}

///|
pub trait Stringify {
  fn stringify(Self) -> String
}

///|
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
/// Parse a mutable document. Malformed HTML is recovered without raising.
pub fn parse(source : String) -> Document {
  { state: document(source), }
}

///|
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
fn wrap_parent(state : State) -> Parent {
  if state.kind == StateKind::Document {
    Parent::Document({ state, })
  } else {
    Parent::Element({ state, })
  }
}

///|
fn node_children(state : State) -> Array[Node] {
  state.children.map(wrap)
}

///|
fn find_state(state : State, selector : String) -> Element? raise HtmlError {
  let found = all(state, compile(selector), limit=1)
  if found.is_empty() {
    None
  } else {
    Some({ state: found[0], })
  }
}

///|
fn all_states(
  state : State,
  selector : String,
) -> Array[Element] raise HtmlError {
  all(state, compile(selector)).map(state => { state, })
}

///|
fn offset(state : State, start : Bool) -> Int32? {
  if state.tree is Some(_) && state.source == doc_of(state).source {
    Some(if start { state.start } else { state.end })
  } else {
    None
  }
}

///|
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
fn content_states(target : State, items : Array[Content]) -> Array[State] {
  items.map(item => {
    match item {
      Content::Text(text) => text_node(doc_of(target), text)
      Content::Node(node) => unwrap(node)
    }
  })
}

///|
fn unwrap(node : Node) -> State {
  match node {
    Element(node) => node.state
    Text(node) => node.state
    Comment(node) => node.state
    Directive(node) => node.state
  }
}

///|
fn insert_before(node : Node, items : Array[Content]) -> Unit raise HtmlError {
  let state = unwrap(node)
  let (parent, at) = state_index(state)
  insert(parent, at, content_states(parent, items))
}

///|
fn insert_after(node : Node, items : Array[Content]) -> Unit raise HtmlError {
  let state = unwrap(node)
  let (parent, at) = state_index(state)
  insert(parent, at + 1, content_states(parent, items))
}

///|
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
fn clone_node(node : Node) -> Node {
  wrap(clone_state(unwrap(node)))
}

///|
pub fn Document::source(self : Document) -> String {
  self.state.source
}

///|
pub fn Document::start(_self : Document) -> Int32 {
  0
}

///|
pub fn Document::end(self : Document) -> Int32 {
  self.state.source.length()
}

///|
pub fn Document::text(self : Document) -> String {
  state_text(self.state)
}

///|
pub fn Document::children(self : Document) -> Array[Node] {
  node_children(self.state)
}

///|
pub fn Document::find(
  self : Document,
  selector : String,
) -> Element? raise HtmlError {
  find_state(self.state, selector)
}

///|
pub fn Document::all(
  self : Document,
  selector : String,
) -> Array[Element] raise HtmlError {
  all_states(self.state, selector)
}

///|
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
pub fn Element::name(self : Element) -> String {
  self.state.name
}

///|
pub fn Element::document(self : Element) -> Document {
  { state: doc_of(self.state), }
}

///|
pub fn Element::start(self : Element) -> Int32? {
  offset(self.state, true)
}

///|
pub fn Element::end(self : Element) -> Int32? {
  offset(self.state, false)
}

///|
pub fn Element::parent(self : Element) -> Parent? {
  self.state.parent.map(wrap_parent)
}

///|
pub fn Element::children(self : Element) -> Array[Node] {
  node_children(self.state)
}

///|
pub fn Element::attributes(self : Element) -> Map[String, String] {
  attributes(self.state).copy()
}

///|
pub fn Element::get_attr(self : Element, name : String) -> String? {
  attributes(self.state).get(name.to_lower())
}

///|
pub fn Element::has_attr(self : Element, name : String) -> Bool {
  self.get_attr(name) is Some(_)
}

///|
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
pub fn Element::remove_attr(self : Element, name : String) -> Unit {
  remove_attribute(self.state, name.to_lower())
}

///|
pub fn Element::set_name(self : Element, name : String) -> Unit raise HtmlError {
  if !valid_tag_name(name) {
    raise HtmlError::InvalidName("Invalid tag name: \"\{name}\"")
  }
  rename(self.state, name)
}

///|
pub fn Element::text(self : Element) -> String {
  state_text(self.state)
}

///|
pub fn Element::set_text(self : Element, text : String) -> Unit raise HtmlError {
  replace_children(self.state, [text_node(doc_of(self.state), text)])
}

///|
pub fn Element::html(self : Element) -> String {
  inner(self.state)
}

///|
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
pub fn Element::find(
  self : Element,
  selector : String,
) -> Element? raise HtmlError {
  find_state(self.state, selector)
}

///|
pub fn Element::all(
  self : Element,
  selector : String,
) -> Array[Element] raise HtmlError {
  all_states(self.state, selector)
}

///|
pub fn Element::matches(
  self : Element,
  selector : String,
) -> Bool raise HtmlError {
  matches(self.state, compile(selector))
}

///|
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
pub fn Element::clone(self : Element) -> Element {
  match clone_node(Node::Element(self)) {
    Element(copy) => copy
    _ => abort("unreachable")
  }
}

///|
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
pub fn Element::prepend(
  self : Element,
  items : Array[Content],
) -> Unit raise HtmlError {
  insert(self.state, 0, content_states(self.state, items))
}

///|
pub fn Element::before(
  self : Element,
  items : Array[Content],
) -> Unit raise HtmlError {
  insert_before(Node::Element(self), items)
}

///|
pub fn Element::after(
  self : Element,
  items : Array[Content],
) -> Unit raise HtmlError {
  insert_after(Node::Element(self), items)
}

///|
pub fn Element::replace(
  self : Element,
  items : Array[Content],
) -> Unit raise HtmlError {
  replace_node(Node::Element(self), items)
}

///|
pub fn Element::remove(self : Element) -> Unit {
  detach(self.state)
}

///|
pub impl Stringify for Element with fn stringify(self) {
  serialize(self.state)
}

///|
pub fn Node::document(self : Node) -> Document {
  { state: doc_of(unwrap(self)), }
}

///|
pub fn Node::start(self : Node) -> Int32? {
  offset(unwrap(self), true)
}

///|
pub fn Node::end(self : Node) -> Int32? {
  offset(unwrap(self), false)
}

///|
pub fn Node::parent(self : Node) -> Parent? {
  unwrap(self).parent.map(wrap_parent)
}

///|
pub fn Node::before(
  self : Node,
  items : Array[Content],
) -> Unit raise HtmlError {
  insert_before(self, items)
}

///|
pub fn Node::after(self : Node, items : Array[Content]) -> Unit raise HtmlError {
  insert_after(self, items)
}

///|
pub fn Node::replace(
  self : Node,
  items : Array[Content],
) -> Unit raise HtmlError {
  replace_node(self, items)
}

///|
pub fn Node::remove(self : Node) -> Unit {
  detach(unwrap(self))
}

///|
pub fn Node::clone(self : Node) -> Node {
  clone_node(self)
}

///|
pub impl Stringify for Node with fn stringify(self) {
  serialize(unwrap(self))
}

///|
pub fn Text::value(self : Text) -> String {
  state_value(self.state)
}

///|
pub fn Text::set_value(self : Text, value : String) -> Unit {
  set_value(self.state, value)
}

///|
pub fn Text::document(self : Text) -> Document {
  { state: doc_of(self.state), }
}

///|
pub fn Text::start(self : Text) -> Int32? {
  offset(self.state, true)
}

///|
pub fn Text::end(self : Text) -> Int32? {
  offset(self.state, false)
}

///|
pub fn Text::parent(self : Text) -> Parent? {
  self.state.parent.map(wrap_parent)
}

///|
pub fn Text::clone(self : Text) -> Text {
  match clone_node(Node::Text(self)) {
    Text(copy) => copy
    _ => abort("unreachable")
  }
}

///|
pub fn Text::before(
  self : Text,
  items : Array[Content],
) -> Unit raise HtmlError {
  insert_before(Node::Text(self), items)
}

///|
pub fn Text::after(self : Text, items : Array[Content]) -> Unit raise HtmlError {
  insert_after(Node::Text(self), items)
}

///|
pub fn Text::replace(
  self : Text,
  items : Array[Content],
) -> Unit raise HtmlError {
  replace_node(Node::Text(self), items)
}

///|
pub fn Text::remove(self : Text) -> Unit {
  detach(self.state)
}

///|
pub impl Stringify for Text with fn stringify(self) {
  serialize(self.state)
}

///|
pub fn Comment::value(self : Comment) -> String {
  state_value(self.state)
}

///|
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
pub fn Comment::document(self : Comment) -> Document {
  { state: doc_of(self.state), }
}

///|
pub fn Comment::start(self : Comment) -> Int32? {
  offset(self.state, true)
}

///|
pub fn Comment::end(self : Comment) -> Int32? {
  offset(self.state, false)
}

///|
pub fn Comment::parent(self : Comment) -> Parent? {
  self.state.parent.map(wrap_parent)
}

///|
pub fn Comment::clone(self : Comment) -> Comment {
  match clone_node(Node::Comment(self)) {
    Comment(copy) => copy
    _ => abort("unreachable")
  }
}

///|
pub fn Comment::before(
  self : Comment,
  items : Array[Content],
) -> Unit raise HtmlError {
  insert_before(Node::Comment(self), items)
}

///|
pub fn Comment::after(
  self : Comment,
  items : Array[Content],
) -> Unit raise HtmlError {
  insert_after(Node::Comment(self), items)
}

///|
pub fn Comment::replace(
  self : Comment,
  items : Array[Content],
) -> Unit raise HtmlError {
  replace_node(Node::Comment(self), items)
}

///|
pub fn Comment::remove(self : Comment) -> Unit {
  detach(self.state)
}

///|
pub impl Stringify for Comment with fn stringify(self) {
  serialize(self.state)
}

///|
pub fn Directive::value(self : Directive) -> String {
  state_value(self.state)
}

///|
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
pub fn Directive::document(self : Directive) -> Document {
  { state: doc_of(self.state), }
}

///|
pub fn Directive::start(self : Directive) -> Int32? {
  offset(self.state, true)
}

///|
pub fn Directive::end(self : Directive) -> Int32? {
  offset(self.state, false)
}

///|
pub fn Directive::parent(self : Directive) -> Parent? {
  self.state.parent.map(wrap_parent)
}

///|
pub fn Directive::clone(self : Directive) -> Directive {
  match clone_node(Node::Directive(self)) {
    Directive(copy) => copy
    _ => abort("unreachable")
  }
}

///|
pub fn Directive::before(
  self : Directive,
  items : Array[Content],
) -> Unit raise HtmlError {
  insert_before(Node::Directive(self), items)
}

///|
pub fn Directive::after(
  self : Directive,
  items : Array[Content],
) -> Unit raise HtmlError {
  insert_after(Node::Directive(self), items)
}

///|
pub fn Directive::replace(
  self : Directive,
  items : Array[Content],
) -> Unit raise HtmlError {
  replace_node(Node::Directive(self), items)
}

///|
pub fn Directive::remove(self : Directive) -> Unit {
  detach(self.state)
}

///|
pub impl Stringify for Directive with fn stringify(self) {
  serialize(self.state)
}
