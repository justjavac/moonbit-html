///|
priv struct Context {
  tree : @internal.Tree
  mut lines : Array[Int32]?
  identity : Int32
}

///|
let context_counter : Ref[Int32] = { val: 0, }

///|
fn Context::new(tree : @internal.Tree) -> Context {
  context_counter.val += 1
  { tree, lines: None, identity: context_counter.val, }
}

///|
/// An HTML document produced by `parse`.
pub struct Document {
  priv ctx : Context
}

///|
/// An element handle. Handles are cheap views into the document's compact tree.
pub struct Element {
  priv ctx : Context
  priv id : Int32
}

///|
/// A text node, including foreign-content CDATA sections.
pub struct Text {
  priv ctx : Context
  priv id : Int32
}

///|
/// A normal or bogus comment.
pub struct Comment {
  priv ctx : Context
  priv id : Int32
}

///|
/// A doctype declaration.
pub struct Directive {
  priv ctx : Context
  priv id : Int32
}

///|
/// A child node in an HTML document.
#derive(Eq, Debug)
pub(all) enum Node {
  Element(Element)
  Text(Text)
  Comment(Comment)
  Directive(Directive)
}

///|
/// The parent of a top-level or nested node.
#derive(Eq, Debug)
pub(all) enum Parent {
  Document(Document)
  Element(Element)
}

///|
/// A one-based line and column in the original UTF-16 source.
#derive(Eq, Debug)
pub(all) struct Position {
  line : Int32
  column : Int32
}

///|
/// A compiled CSS selector list.
pub struct Selector {
  priv compiled : @internal.Selector
}

///|
/// A malformed or unsupported CSS selector.
pub suberror SelectorError {
  InvalidSelector(String)
}

///|
/// Values that can be serialized back to their exact original HTML source.
pub trait Stringify {
  fn stringify(Self) -> String
}

///|
pub fn[T : Stringify] stringify(target : T) -> String {
  target.stringify()
}

///|
fn compile_selector(input : String) -> @internal.Selector raise SelectorError {
  @internal.compile(input) catch {
    @internal.SelectorSyntax::Message(message) =>
      raise SelectorError::InvalidSelector(message)
  }
}

///|
/// Compile a selector once for repeated matching.
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
fn element(ctx : Context, id : Int32) -> Element {
  { ctx, id, }
}

///|
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
/// Parse HTML without raising on malformed markup. Recovery follows htmlparser2,
/// not the WHATWG browser tree-construction algorithm.
pub fn parse(source : String) -> Document {
  { ctx: Context::new(@internal.build(source)), }
}

///|
/// The exact source from which this document was parsed.
pub fn Document::source(self : Document) -> String {
  self.ctx.tree.source
}

///|
pub fn Document::start(_self : Document) -> Int32 {
  0
}

///|
pub fn Document::end(self : Document) -> Int32 {
  self.ctx.tree.source.length()
}

///|
/// The decoded text of all text nodes in document order.
pub fn Document::text(self : Document) -> String {
  @internal.text(self.ctx.tree, 0)
}

///|
/// Top-level nodes in source order.
pub fn Document::children(self : Document) -> Array[Node] {
  children(self.ctx, 0)
}

///|
/// Find the first matching element, or return `None`.
pub fn Document::find(
  self : Document,
  selector : String,
) -> Element? raise SelectorError {
  find_one(self.ctx, 0, selector)
}

///|
/// Find all matching elements in source order.
pub fn Document::all(
  self : Document,
  selector : String,
) -> Array[Element] raise SelectorError {
  find_all(self.ctx, 0, selector)
}

///|
/// Find the first element using a selector compiled by `Selector::parse`.
pub fn Document::find_with(self : Document, selector : Selector) -> Element? {
  let found = @internal.all(self.ctx.tree, 0, selector.compiled, limit=1)
  if found.is_empty() {
    None
  } else {
    Some(element(self.ctx, found[0]))
  }
}

///|
/// Find all elements using a selector compiled by `Selector::parse`.
pub fn Document::all_with(
  self : Document,
  selector : Selector,
) -> Array[Element] {
  @internal.all(self.ctx.tree, 0, selector.compiled).map(id => {
    element(self.ctx, id)
  })
}

///|
/// Convert a UTF-16 source offset to a one-based line and column.
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
pub fn Element::name(self : Element) -> String {
  self.ctx.tree.name[self.id]
}

///|
pub fn Element::document(self : Element) -> Document {
  { ctx: self.ctx, }
}

///|
pub fn Element::start(self : Element) -> Int32 {
  self.ctx.tree.start[self.id]
}

///|
pub fn Element::end(self : Element) -> Int32 {
  self.ctx.tree.end[self.id]
}

///|
pub fn Element::parent(self : Element) -> Parent {
  let parent = self.ctx.tree.parent[self.id]
  if parent == 0 {
    Parent::Document({ ctx: self.ctx, })
  } else {
    Parent::Element(element(self.ctx, parent))
  }
}

///|
pub fn Element::children(self : Element) -> Array[Node] {
  children(self.ctx, self.id)
}

///|
/// Return an independent map of lowercase attribute names and decoded values.
pub fn Element::attributes(self : Element) -> Map[String, String] {
  @internal.attributes(self.ctx.tree, self.id).copy()
}

///|
/// Read an attribute without distinguishing its ASCII letter case.
pub fn Element::get_attr(self : Element, name : String) -> String? {
  @internal.attribute(self.ctx.tree, self.id, name.to_lower())
}

///|
pub fn Element::has_attr(self : Element, name : String) -> Bool {
  self.get_attr(name) is Some(_)
}

///|
/// The decoded text of all descendant text nodes.
pub fn Element::text(self : Element) -> String {
  @internal.text(self.ctx.tree, self.id)
}

///|
/// The element's inner HTML exactly as written.
pub fn Element::html(self : Element) -> String {
  @internal.slice(
    self.ctx.tree.source,
    self.ctx.tree.from[self.id],
    self.ctx.tree.to[self.id],
  )
}

///|
pub fn Element::find(
  self : Element,
  selector : String,
) -> Element? raise SelectorError {
  find_one(self.ctx, self.id, selector)
}

///|
pub fn Element::all(
  self : Element,
  selector : String,
) -> Array[Element] raise SelectorError {
  find_all(self.ctx, self.id, selector)
}

///|
/// Find the first descendant using a precompiled selector.
pub fn Element::find_with(self : Element, selector : Selector) -> Element? {
  let found = @internal.all(self.ctx.tree, self.id, selector.compiled, limit=1)
  if found.is_empty() {
    None
  } else {
    Some(element(self.ctx, found[0]))
  }
}

///|
/// Find all descendants using a precompiled selector.
pub fn Element::all_with(self : Element, selector : Selector) -> Array[Element] {
  @internal.all(self.ctx.tree, self.id, selector.compiled).map(id => {
    element(self.ctx, id)
  })
}

///|
pub fn Element::matches(
  self : Element,
  selector : String,
) -> Bool raise SelectorError {
  @internal.matches(self.ctx.tree, self.id, compile_selector(selector))
}

///|
/// Return this element or its nearest matching ancestor.
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
/// Match this element against a precompiled selector.
pub fn Element::matches_with(self : Element, selector : Selector) -> Bool {
  @internal.matches(self.ctx.tree, self.id, selector.compiled)
}

///|
/// Return this element or its nearest ancestor matching a precompiled selector.
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
pub fn Node::document(self : Node) -> Document {
  match self {
    Element(node) => node.document()
    Text(node) => node.document()
    Comment(node) => node.document()
    Directive(node) => node.document()
  }
}

///|
pub fn Node::start(self : Node) -> Int32 {
  match self {
    Element(node) => node.start()
    Text(node) => node.start()
    Comment(node) => node.start()
    Directive(node) => node.start()
  }
}

///|
pub fn Node::end(self : Node) -> Int32 {
  match self {
    Element(node) => node.end()
    Text(node) => node.end()
    Comment(node) => node.end()
    Directive(node) => node.end()
  }
}

///|
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
pub fn Text::value(self : Text) -> String {
  @internal.value(self.ctx.tree, self.id)
}

///|
pub fn Text::document(self : Text) -> Document {
  { ctx: self.ctx, }
}

///|
pub fn Text::start(self : Text) -> Int32 {
  self.ctx.tree.start[self.id]
}

///|
pub fn Text::end(self : Text) -> Int32 {
  self.ctx.tree.end[self.id]
}

///|
pub fn Text::parent(self : Text) -> Parent {
  leaf_parent(self.ctx, self.id)
}

///|
pub impl Stringify for Text with fn stringify(self) {
  @internal.slice(self.ctx.tree.source, self.start(), self.end())
}

///|
pub fn Comment::value(self : Comment) -> String {
  @internal.value(self.ctx.tree, self.id)
}

///|
pub fn Comment::document(self : Comment) -> Document {
  { ctx: self.ctx, }
}

///|
pub fn Comment::start(self : Comment) -> Int32 {
  self.ctx.tree.start[self.id]
}

///|
pub fn Comment::end(self : Comment) -> Int32 {
  self.ctx.tree.end[self.id]
}

///|
pub fn Comment::parent(self : Comment) -> Parent {
  leaf_parent(self.ctx, self.id)
}

///|
pub impl Stringify for Comment with fn stringify(self) {
  @internal.slice(self.ctx.tree.source, self.start(), self.end())
}

///|
pub fn Directive::value(self : Directive) -> String {
  @internal.value(self.ctx.tree, self.id)
}

///|
pub fn Directive::document(self : Directive) -> Document {
  { ctx: self.ctx, }
}

///|
pub fn Directive::start(self : Directive) -> Int32 {
  self.ctx.tree.start[self.id]
}

///|
pub fn Directive::end(self : Directive) -> Int32 {
  self.ctx.tree.end[self.id]
}

///|
pub fn Directive::parent(self : Directive) -> Parent {
  leaf_parent(self.ctx, self.id)
}

///|
pub impl Stringify for Directive with fn stringify(self) {
  @internal.slice(self.ctx.tree.source, self.start(), self.end())
}

///|
fn leaf_parent(ctx : Context, id : Int32) -> Parent {
  let parent = ctx.tree.parent[id]
  if parent == 0 {
    Parent::Document({ ctx, })
  } else {
    Parent::Element(element(ctx, parent))
  }
}
