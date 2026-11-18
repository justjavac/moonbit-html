///|
/// The kind of a mutable node state.
#derive(Eq)
priv enum StateKind {
  Document
  Element
  Text
  Comment
  Directive
}

///|
/// A mutable node: tree link, parent/children links, and lazy caches.
priv struct State {
  kind : StateKind
  mut doc : State?
  mut parent : State?
  mut source : String
  mut tree : @internal.Tree?
  mut id : Int32
  mut start : Int32
  mut end : Int32
  mut name : String
  children : Array[State]
  mut attrs : Map[String, String]?
  mut written_names : Map[String, String]?
  mut value : String?
  mut changed : Bool
  mut dirty : Bool
  identity : Int32
}

///|
/// Monotonic source of state identities.
let state_counter : Ref[Int32] = { val: 0, }

///|
/// Allocate a fresh state with a new identity.
fn create(kind : StateKind, doc : State?, name~ : String = "") -> State {
  state_counter.val += 1
  {
    kind,
    doc,
    parent: None,
    source: "",
    tree: None,
    id: -1,
    start: -1,
    end: -1,
    name,
    children: [],
    attrs: None,
    written_names: None,
    value: None,
    changed: true,
    dirty: true,
    identity: state_counter.val,
  }
}

///|
/// Map an internal node kind to a `StateKind`.
fn kind_of(kind : @internal.Kind) -> StateKind {
  match kind {
    Document => StateKind::Document
    Element => StateKind::Element
    Text => StateKind::Text
    Comment => StateKind::Comment
    Directive => StateKind::Directive
  }
}

///|
/// The document state owning this state.
fn doc_of(state : State) -> State {
  state.doc.unwrap_or(state)
}

///|
/// Materialize a parsed tree as child states of `doc`.
fn load(tree : @internal.Tree, doc : State) -> Array[State] {
  let states : Array[State?] = Array::make(tree.size, None)
  let top : Array[State] = []
  for id in 1..<tree.size {
    state_counter.val += 1
    let state : State = {
      kind: kind_of(tree.kind[id]),
      doc: Some(doc),
      parent: None,
      source: tree.source,
      tree: Some(tree),
      id,
      start: tree.start[id],
      end: tree.end[id],
      name: tree.name[id],
      children: [],
      attrs: None,
      written_names: None,
      value: None,
      changed: false,
      dirty: false,
      identity: state_counter.val,
    }
    states[id] = Some(state)
    let parent = tree.parent[id]
    if parent == 0 {
      top.push(state)
    } else {
      state.parent = states[parent]
      states[parent].unwrap().children.push(state)
    }
  }
  top
}

///|
/// Build the root state of a mutable document from source.
fn document(source : String) -> State {
  let tree = @internal.build(source)
  let doc = create(StateKind::Document, None)
  doc.source = source
  doc.tree = Some(tree)
  doc.id = 0
  doc.start = 0
  doc.end = source.length()
  doc.changed = false
  doc.dirty = false
  for child in load(tree, doc) {
    child.parent = Some(doc)
    doc.children.push(child)
  }
  doc
}

///|
/// The state's attribute map, built on first use and cached.
fn attributes(state : State) -> Map[String, String] {
  if state.attrs is Some(cached) {
    return cached
  }
  let result = match state.tree {
    Some(tree) => @internal.attributes(tree, state.id).copy()
    None => Map([])
  }
  state.attrs = Some(result)
  result
}

///|
/// The state's decoded leaf content, cached.
fn state_value(state : State) -> String {
  if state.value is Some(value) {
    return value
  }
  let result = match state.tree {
    Some(tree) => @internal.value(tree, state.id)
    None => ""
  }
  state.value = Some(result)
  result
}

///|
/// The decoded text of all descendant text states.
fn state_text(state : State) -> String {
  if state.kind == StateKind::Text {
    return state_value(state)
  }
  let output = StringBuilder()
  for child in state.children {
    if child.kind == StateKind::Text {
      output.write_string(state_value(child))
    } else if child.kind == StateKind::Element {
      output.write_string(state_text(child))
    }
  }
  output.to_string()
}

///|
/// Mark a state and its ancestors dirty so serialization rebuilds them.
fn touch(state : State?) -> Unit {
  let mut current = state
  while current is Some(value) && !value.dirty {
    value.dirty = true
    current = value.parent
  }
}

///|
/// Reassign a state and its descendants to a document.
fn adopt(state : State, doc : State) -> Unit {
  if doc_of(state).identity == doc.identity {
    return
  }
  state.doc = Some(doc)
  for child in state.children {
    adopt(child, doc)
  }
}

///|
/// Unlink a state from its parent.
fn detach(state : State) -> Unit {
  guard state.parent is Some(parent) else { return }
  let mut at = -1
  for i in 0..<parent.children.length() {
    if parent.children[i].identity == state.identity {
      at = i
    }
  }
  if at != -1 {
    let _ = parent.children.remove(at)
  }
  state.parent = None
  touch(Some(parent))
}

///|
/// Splice states into a parent's children at an index, with validation.
fn insert(
  parent : State,
  index : Int32,
  items : Array[State],
) -> Unit raise HtmlError {
  if parent.kind == StateKind::Element && @internal.is_void(parent.name) {
    raise HtmlError::InvalidInsertion("Cannot add children to <\{parent.name}>")
  }
  for item in items {
    if item.kind == StateKind::Document {
      raise HtmlError::InvalidInsertion("Cannot insert a document")
    }
    let mut current = Some(parent)
    while current is Some(ancestor) {
      if ancestor.identity == item.identity {
        raise HtmlError::InvalidInsertion("Cannot insert a node into itself")
      }
      current = ancestor.parent
    }
  }
  let mut at = index
  for item in items {
    if item.parent is Some(existing) && existing.identity == parent.identity {
      for i in 0..<parent.children.length() {
        if parent.children[i].identity == item.identity && i < at {
          at -= 1
        }
      }
    }
    detach(item)
  }
  for item in items {
    adopt(item, doc_of(parent))
    item.parent = Some(parent)
  }
  for i in 0..<items.length() {
    parent.children.insert(at + i, items[i])
  }
  touch(Some(parent))
}

///|
/// Deep-copy a state tree with fresh identities.
fn clone_state(state : State) -> State {
  state_counter.val += 1
  let copy : State = {
    ..state,
    parent: None,
    children: [],
    identity: state_counter.val,
  }
  for child in state.children {
    let next = clone_state(child)
    next.parent = Some(copy)
    copy.children.push(next)
  }
  copy
}

///|
/// Create a fresh text state holding a literal string.
fn text_node(doc : State, input : String) -> State {
  let state = create(StateKind::Text, Some(doc))
  state.value = Some(input)
  state
}

///|
/// Parse an HTML string into states for insertion.
fn fragment(doc : State, html : String, foreign : Bool) -> Array[State] {
  load(@internal.build(html, foreign~), doc)
}

///|
/// Set or replace one attribute, recording renames.
fn set_attribute(state : State, name : String, value : String) -> Unit {
  let key = name.to_lower()
  let current = attributes(state)
  if key != name && !current.contains(key) {
    let names = state.written_names.unwrap_or(Map([])).copy()
    names[key] = name
    state.written_names = Some(names)
  }
  let attrs = current.copy()
  attrs[key] = value
  state.attrs = Some(attrs)
  state.changed = true
  touch(Some(state))
}

///|
/// Remove one attribute if present.
fn remove_attribute(state : State, key : String) -> Unit {
  let current = attributes(state)
  if !current.contains(key) {
    return
  }
  let attrs = current.copy()
  attrs.remove(key)
  state.attrs = Some(attrs)
  if state.written_names is Some(names) {
    let updated = names.copy()
    updated.remove(key)
    state.written_names = Some(updated)
  }
  state.changed = true
  touch(Some(state))
}

///|
/// Change an element's tag name, with void/raw-text validation.
fn rename(state : State, input : String) -> Unit raise HtmlError {
  let lower = input.to_lower()
  let inside = within(state)
  let name = if inside {
    @internal.svg_name(lower)
  } else if lower == "image" {
    "img"
  } else {
    lower
  }
  if @internal.is_void(name) && state.children.length() > 0 {
    raise HtmlError::InvalidName(
      "Cannot rename <\{state.name}> with children to <\{name}>",
    )
  }
  let raw = !inside && @internal.is_raw(name)
  if raw && state.children.any(child => child.kind == StateKind::Element) {
    raise HtmlError::InvalidName(
      "Cannot rename <\{state.name}> with child elements to <\{name}>",
    )
  }
  state.name = name
  state.changed = true
  touch(Some(state))
}

///|
/// Whether `input` round-trips as a comment/directive value.
fn valid_leaf(html : String, kind : @internal.Kind, input : String) -> Bool {
  let tree = @internal.build(html)
  tree.size == 2 && tree.kind[1] == kind && @internal.value(tree, 1) == input
}

///|
/// Replace a leaf state's content.
fn set_value(state : State, input : String) -> Unit {
  state.value = Some(input)
  state.changed = true
  touch(Some(state))
}

///|
/// Swap all children of a state for new states.
fn replace_children(
  state : State,
  items : Array[State],
) -> Unit raise HtmlError {
  for child in state.children {
    detach(child)
  }
  insert(state, 0, items)
}

///|
/// Serialize attributes added on top of the source's own.
fn added(
  state : State,
  entries : Array[(String, String)],
  from : Int32,
) -> String {
  let output = StringBuilder()
  for i in from..<entries.length() {
    let (key, value) = entries[i]
    let name = match state.written_names {
      Some(names) => names.get(key).unwrap_or(key)
      None => key
    }
    output.write_string(
      " " + name + "=\"" + @internal.escape_attribute(value) + "\"",
    )
  }
  output.to_string()
}

///|
/// Close an open tag, self-closing when `slash` is set.
fn tag_end(tag : String, slash : Bool) -> String {
  if !slash {
    return tag + ">"
  }
  let code = @internal.code_at(tag, tag.length() - 1)
  tag + (if code == 34 || code == 39 { "/>" } else { " />" })
}

///|
/// Whether the state's element was self-closing in the source.
fn self_closed(tree : @internal.Tree, state : State) -> Bool {
  tree.from[state.id] == tree.end[state.id] &&
  @internal.self_closing(state.source, tree.head[state.id])
}

///|
/// Serialize the state's open tag, preserving untouched source when possible.
fn open_tag(state : State, slash : Bool) -> String {
  let entries = attributes(state).to_array()
  guard state.tree is Some(tree) else {
    return tag_end("<" + state.name + added(state, entries, 0), slash)
  }
  let list = @internal.pairs(tree, state.id)
  let count = list.length() / 2
  let mut kept = entries.length() >= count
  for i in 0..<count {
    if !kept {
      break
    }
    kept = entries[i].0 == list[i * 2] && entries[i].1 == list[i * 2 + 1]
  }
  let bare = self_closed(tree, state)
  let last_empty = count > 0 && list[list.length() - 1] == ""
  let extra = if kept { added(state, entries, count) } else { "" }
  if kept && !(extra.length() > 0 && last_empty) {
    let head = tree.head[state.id]
    let mut rest = @internal.slice(state.source, head, tree.from[state.id] - 1)
      .trim_end()
      .to_owned()
    if bare {
      rest = rest.trim_end().to_owned()
      if rest.has_suffix("/") {
        rest = @internal.slice(rest, 0, rest.length() - 1).trim_end().to_owned()
      }
    }
    let name = if state.name == tree.name[state.id] {
      @internal.slice(state.source, state.start, head)
    } else {
      "<" + state.name
    }
    return tag_end(name + rest + extra, slash)
  }
  let spans = @internal.spans(tree, state.id)
  let output = StringBuilder()
  output.write_char('<')
  output.write_string(state.name)
  for entry in entries {
    let (key, value) = entry
    let at = @internal.find_pair(spans, key, stride=3)
    let raw = if at == -1 { "" } else { spans[at + 2] }
    let intact = raw.length() > 0 &&
      ({
        let last = @internal.code_at(raw, raw.length() - 1)
        !@internal.is_space(last) && last != 61
      })
    if intact && @internal.attribute(tree, state.id, key) == Some(value) {
      output.write_char(' ')
      output.write_string(raw)
      continue
    }
    let name = match state.written_names {
      Some(names) if names.get(key) is Some(written) => written
      _ => if at == -1 { key } else { spans[at + 1] }
    }
    output.write_char(' ')
    output.write_string(name)
    output.write_string("=\"")
    output.write_string(@internal.escape_attribute(value))
    output.write_char('"')
  }
  tag_end(output.to_string(), slash)
}

///|
/// Whether the state's element had a close tag in the source.
fn ended(state : State) -> Bool {
  guard state.kind == StateKind::Element &&
    state.tree is Some(tree) &&
    state.name == tree.name[state.id] else {
    return true
  }
  self_closed(tree, state) || tree.to[state.id] != tree.end[state.id]
}

///|
/// Whether serialization may drop the close tag for this element.
fn unclosed(state : State, parent : State, next : State?) -> Bool {
  guard state.kind == StateKind::Element &&
    state.tree is Some(tree) &&
    state.name == tree.name[state.id] else {
    return false
  }
  let id = state.id
  if tree.to[id] != tree.end[id] || @internal.is_void(state.name) {
    return false
  }
  if self_closed(tree, state) ||
    @internal.code_at(state.source, state.start + 1) == 47 {
    return false
  }
  let after = tree.stop[id]
  let sibling = after < tree.size && tree.parent[after] == tree.parent[id]
  if next is Some(next_state) {
    let same = next_state.tree is Some(next_tree) &&
      next_tree.source == tree.source &&
      next_state.id == after
    return !(sibling && same && next_state.name == tree.name[after])
  }
  if ended(parent) {
    return false
  }
  sibling || parent.tree is None || parent.id != tree.parent[id]
}

///|
/// Serialize the state's children.
fn content(state : State) -> String {
  let output = StringBuilder()
  for i in 0..<state.children.length() {
    let child = state.children[i]
    output.write_string(serialize(child))
    if unclosed(
        child,
        state,
        if i + 1 < state.children.length() {
          Some(state.children[i + 1])
        } else {
          None
        },
      ) {
      output.write_string("</" + child.name + ">")
    }
  }
  output.to_string()
}

///|
/// Whether the state is inside foreign (SVG/MathML) content.
fn foreign_state(state : State) -> Bool {
  if state.kind != StateKind::Element {
    return false
  }
  if state.name == "svg" || state.name == "math" {
    return true
  }
  if @internal.is_integration(state.name) {
    return false
  }
  within(state)
}

///|
/// Whether the state's ancestors put it in foreign content.
fn within(state : State) -> Bool {
  if state.parent is Some(parent) {
    return foreign_state(parent)
  }
  match state.tree {
    Some(tree) if state.kind != StateKind::Document =>
      @internal.foreign(tree, tree.parent[state.id])
    _ => false
  }
}

///|
/// How child text is written for a raw-text parent.
fn text_mode(name : String, foreign : Bool) -> Int32 {
  if foreign || !@internal.is_raw(name) {
    return 0
  }
  if @internal.is_literal(name) {
    2
  } else {
    1
  }
}

///|
/// The text mode implied by the state's current parent.
fn current_mode(state : State?) -> Int32 {
  guard state is Some(value) &&
    value.kind == StateKind::Element &&
    @internal.is_raw(value.name) else {
    return 0
  }
  text_mode(value.name, within(value))
}

///|
/// Whether a text state moved across a raw-text boundary.
fn misplaced(state : State) -> Bool {
  guard state.kind == StateKind::Text &&
    state.tree is Some(tree) &&
    state.parent is Some(_) else {
    return false
  }
  if tree.start[state.id] != tree.from[state.id] {
    return !within(state)
  }
  let parent = tree.parent[state.id]
  let before = if @internal.is_raw(tree.name[parent]) {
    text_mode(tree.name[parent], @internal.foreign(tree, tree.parent[parent]))
  } else {
    0
  }
  current_mode(state.parent) != before
}

///|
/// Serialize the state, reusing the source slice when untouched.
fn serialize(state : State) -> String {
  if !state.dirty && !misplaced(state) {
    return @internal.slice(state.source, state.start, state.end)
  }
  match state.kind {
    Document => content(state)
    Text =>
      if current_mode(state.parent) == 2 {
        state_value(state)
      } else {
        @internal.escape_text(state_value(state))
      }
    Comment => "<!--" + state_value(state) + "-->"
    Directive => "<!" + state_value(state) + ">"
    Element => {
      let body = content(state)
      let bare = state.tree is Some(tree) && self_closed(tree, state)
      let own = state.tree is Some(tree) && state.name == tree.name[state.id]
      if state.tree is Some(tree) &&
        own &&
        !(bare && state.children.length() > 0) {
        let head = if state.changed {
          open_tag(state, bare)
        } else {
          @internal.slice(state.source, state.start, tree.from[state.id])
        }
        return head +
          body +
          @internal.slice(state.source, tree.to[state.id], state.end)
      }
      let tail = if @internal.is_void(state.name) {
        ""
      } else {
        "</" + state.name + ">"
      }
      open_tag(state, false) + body + tail
    }
  }
}

///|
/// Serialize the state's inner content.
fn inner(state : State) -> String {
  if !state.dirty && state.tree is Some(tree) {
    return @internal.slice(state.source, tree.from[state.id], tree.to[state.id])
  }
  content(state)
}
