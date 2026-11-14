///|
fn has_word(actual : String, expected : String) -> Bool {
  let wanted = expected.length()
  if wanted == 0 {
    return false
  }
  let mut start = 0
  let length = actual.length()
  for i in 0..<=length {
    if i == length || @internal.is_space(@internal.code_at(actual, i)) {
      if i - start == wanted &&
        actual.unsafe_range_equal(start~, expected, other_start=0, len=wanted) {
        return true
      }
      start = i + 1
    }
  }
  false
}

///|
fn match_attribute(state : State, rule : @internal.AttributeRule) -> Bool {
  let attrs = attributes(state)
  guard attrs.get(rule.name) is Some(found) else { return false }
  if rule.operator == @internal.Operator::Exists {
    return true
  }
  let actual = if rule.insensitive { found.to_lower() } else { found }
  let expected = if rule.insensitive {
    rule.value.to_lower()
  } else {
    rule.value
  }
  match rule.operator {
    Exists => true
    Equal => actual == expected
    Includes => has_word(actual, expected)
    DashMatch => {
      let expected_length = expected.length()
      actual == expected ||
      (
        actual.length() > expected_length &&
        @internal.code_at(actual, expected_length) == 45 &&
        actual.unsafe_range_equal(
          start=0,
          expected,
          other_start=0,
          len=expected_length,
        )
      )
    }
    Prefix => !expected.is_empty() && actual.has_prefix(expected)
    Suffix => !expected.is_empty() && actual.has_suffix(expected)
    Substring => !expected.is_empty() && actual.contains(expected)
  }
}

///|
fn match_pseudo(state : State, rule : @internal.Pseudo) -> Bool {
  match rule {
    Root => state.parent is Some(parent) && parent.kind == StateKind::Document
    Empty =>
      !state.children.any(child => {
        child.kind == StateKind::Element || child.kind == StateKind::Text
      })
    Not(selector) => !matches(state, selector)
    Is(selector) => matches(state, selector)
    Nth(a~, b~, last~, of_type~) => {
      let mut at = 0
      let mut total = 0
      if state.parent is Some(parent) {
        for child in parent.children {
          if child.kind == StateKind::Element &&
            (!of_type || child.name == state.name) {
            total += 1
            if child.identity == state.identity {
              at = total
            }
          }
        }
      } else {
        at = 1
        total = 1
      }
      let index = if last { total - at + 1 } else { at }
      if a == 0 {
        return index == b
      }
      let difference = index - b
      difference % a == 0 && difference / a >= 0
    }
  }
}

///|
fn match_compound(state : State, rule : @internal.Compound) -> Bool {
  if !rule.tag.is_empty() && state.name != rule.tag && state.name != rule.raw {
    return false
  }
  if !rule.id.is_empty() ||
    rule.classes.length() > 0 ||
    rule.attributes.length() > 0 {
    let attrs = attributes(state)
    if !rule.id.is_empty() && attrs.get("id") != Some(rule.id) {
      return false
    }
    if rule.classes.length() > 0 {
      let classes = attrs.get("class").unwrap_or("")
      for name in rule.classes {
        if !has_word(classes, name) {
          return false
        }
      }
    }
    for attribute in rule.attributes {
      if !match_attribute(state, attribute) {
        return false
      }
    }
  }
  for pseudo in rule.pseudos {
    if !match_pseudo(state, pseudo) {
      return false
    }
  }
  true
}

///|
fn match_complex(
  state : State,
  rule : @internal.Complex,
  index : Int32,
) -> Bool {
  if !match_compound(state, rule.compounds[index]) {
    return false
  }
  if index == 0 {
    return true
  }
  match rule.combinators[index - 1] {
    Child =>
      state.parent is Some(parent) &&
      parent.kind == StateKind::Element &&
      match_complex(parent, rule, index - 1)
    Descendant => {
      let mut current = state.parent
      while current is Some(parent) {
        if parent.kind == StateKind::Element &&
          match_complex(parent, rule, index - 1) {
          return true
        }
        current = parent.parent
      }
      false
    }
    NextSibling | SubsequentSibling => {
      guard state.parent is Some(parent) else { return false }
      let mut previous : State? = None
      for child in parent.children {
        if child.identity == state.identity {
          break
        }
        if child.kind == StateKind::Element {
          if rule.combinators[index - 1] ==
            @internal.Combinator::SubsequentSibling &&
            match_complex(child, rule, index - 1) {
            return true
          }
          previous = Some(child)
        }
      }
      rule.combinators[index - 1] == @internal.Combinator::NextSibling &&
      previous is Some(child) &&
      match_complex(child, rule, index - 1)
    }
  }
}

///|
fn matches(state : State, selector : @internal.Selector) -> Bool {
  if state.kind != StateKind::Element {
    return false
  }
  for rule in selector.rules {
    if match_complex(state, rule, rule.compounds.length() - 1) {
      return true
    }
  }
  false
}

///|
fn all(
  root : State,
  selector : @internal.Selector,
  limit~ : Int32 = 0x7fffffff,
) -> Array[State] {
  let output : Array[State] = []
  let stack : Array[State] = []
  for i in 0..<root.children.length() {
    let child = root.children[root.children.length() - 1 - i]
    if child.kind == StateKind::Element {
      stack.push(child)
    }
  }
  let tags = selector.candidate_tags
  while !stack.is_empty() {
    let state = stack.unsafe_pop()
    let candidate = match tags {
      Some(names) => names.contains(state.name)
      None => true
    }
    if candidate && matches(state, selector) {
      output.push(state)
      if output.length() >= limit {
        break
      }
    }
    if state.name == "template" {
      continue
    }
    for i in 0..<state.children.length() {
      let child = state.children[state.children.length() - 1 - i]
      if child.kind == StateKind::Element {
        stack.push(child)
      }
    }
  }
  output
}

///|
fn compile(input : String) -> @internal.Selector raise HtmlError {
  @internal.compile(input) catch {
    @internal.SelectorSyntax::Message(message) =>
      raise HtmlError::InvalidSelector(message)
  }
}
