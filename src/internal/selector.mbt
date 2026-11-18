///|
/// A selector parse failure with a human-readable message.
pub suberror SelectorSyntax {
  Message(String)
}

///|
/// Attribute selector operators (`=`, `~=`, `|=`, `^=`, `$=`, `*=`).
#derive(Eq)
pub(all) enum Operator {
  Exists
  Equal
  Includes
  DashMatch
  Prefix
  Suffix
  Substring
}

///|
/// How a compound selector relates to the previous one.
#derive(Eq)
pub(all) enum Combinator {
  Descendant
  Child
  NextSibling
  SubsequentSibling
}

///|
/// One attribute condition of a compound selector.
pub struct AttributeRule {
  name : String
  operator : Operator
  value : String
  insensitive : Bool
}

///|
/// Supported pseudo-classes (`:first-child`, `:nth-*`, `:not`, ...).
pub(all) enum Pseudo {
  Root
  Empty
  Nth(a~ : Int32, b~ : Int32, last~ : Bool, of_type~ : Bool)
  Not(Selector)
  Is(Selector)
}

///|
/// A compound selector: tag/id/class/attribute/pseudo conditions.
pub struct Compound {
  mut tag : String
  mut raw : String
  mut id : String
  classes : Array[String]
  attributes : Array[AttributeRule]
  pseudos : Array[Pseudo]
}

///|
/// A full selector: a compound plus its combinator chain.
pub struct Complex {
  compounds : Array[Compound]
  combinators : Array[Combinator]
}

///|
/// A compiled selector list with precomputed candidate tags.
pub struct Selector {
  rules : Array[Complex]
  candidate_tags : Array[String]?
}

///|
/// Cursor over selector source text.
priv struct Parser {
  input : String
  mut index : Int32
}

///|
/// Bounded cache of compiled selectors keyed by source text.
let selector_cache : Map[String, Selector] = Map([])

///|
/// Abort parsing with a `SelectorSyntax` message.
fn Parser::fail(self : Parser, reason : String) -> Unit raise SelectorSyntax {
  raise SelectorSyntax::Message(
    "\{reason} at \{self.index} in selector \"\{self.input}\"",
  )
}

///|
/// Consume CSS whitespace, returning whether any was seen.
fn Parser::spaces(self : Parser) -> Bool {
  let from = self.index
  while self.index < self.input.length() &&
        is_css_space(code_at(self.input, self.index)) {
    self.index += 1
  }
  self.index > from
}

///|
/// Whether the code unit is CSS whitespace.
fn is_css_space(code : Int32) -> Bool {
  is_space(code) || code == 0xa0
}

///|
/// Whether the code unit can appear in a CSS identifier.
fn is_ident(code : Int32) -> Bool {
  code == 45 ||
  code == 95 ||
  (code >= 48 && code <= 57) ||
  is_alpha(code) ||
  code > 127
}

///|
/// Parse a CSS identifier, handling backslash escapes.
fn Parser::ident(self : Parser) -> String raise SelectorSyntax {
  let output = StringBuilder()
  while self.index < self.input.length() {
    let code = code_at(self.input, self.index)
    if code == 92 {
      self.index += 1
      let mut hex = 0
      let mut digits = 0
      while self.index < self.input.length() && digits < 6 {
        let current = code_at(self.input, self.index)
        let digit = if current >= 48 && current <= 57 {
          current - 48
        } else if (current | 32) >= 97 && (current | 32) <= 102 {
          (current | 32) - 97 + 10
        } else {
          -1
        }
        if digit < 0 {
          break
        }
        hex = hex * 16 + digit
        digits += 1
        self.index += 1
      }
      if digits > 0 {
        if self.index < self.input.length() &&
          is_css_space(code_at(self.input, self.index)) {
          self.index += 1
        }
        match hex.to_char() {
          Some(char) => output.write_char(char)
          None => output.write_char('\u{fffd}')
        }
      } else if self.index < self.input.length() {
        match self.input.get_char(self.index) {
          Some(char) => {
            output.write_char(char)
            self.index += char.utf16_len()
          }
          None => ()
        }
      }
    } else if is_ident(code) {
      match self.input.get_char(self.index) {
        Some(char) => {
          output.write_char(char)
          self.index += char.utf16_len()
        }
        None => break
      }
    } else {
      break
    }
  }
  let result = output.to_string()
  if result.is_empty() {
    self.fail("Expected an identifier")
  }
  result
}

///|
/// Parse a quoted string, handling backslash escapes.
fn Parser::quoted(self : Parser) -> String raise SelectorSyntax {
  let quote = code_at(self.input, self.index)
  self.index += 1
  let output = StringBuilder()
  while self.index < self.input.length() &&
        code_at(self.input, self.index) != quote {
    if code_at(self.input, self.index) == 92 {
      self.index += 1
    }
    if self.index < self.input.length() {
      match self.input.get_char(self.index) {
        Some(char) => {
          output.write_char(char)
          self.index += char.utf16_len()
        }
        None => ()
      }
    }
  }
  if code_at(self.input, self.index) != quote {
    self.fail("Unterminated string")
  }
  self.index += 1
  output.to_string()
}

///|
/// Parse one `[...]` attribute selector.
fn Parser::attribute(self : Parser) -> AttributeRule raise SelectorSyntax {
  self.index += 1
  let _ = self.spaces()
  let name = self.ident().to_lower()
  let _ = self.spaces()
  let mut operator = Operator::Exists
  let mut value = ""
  let mut insensitive = false
  let rest = self.input.unsafe_view(start=self.index, end=self.input.length())
  let parsed = if rest.has_prefix("~=") {
    Some((Operator::Includes, 2))
  } else if rest.has_prefix("|=") {
    Some((Operator::DashMatch, 2))
  } else if rest.has_prefix("^=") {
    Some((Operator::Prefix, 2))
  } else if rest.has_prefix("$=") {
    Some((Operator::Suffix, 2))
  } else if rest.has_prefix("*=") {
    Some((Operator::Substring, 2))
  } else if rest.has_prefix("=") {
    Some((Operator::Equal, 1))
  } else {
    None
  }
  if parsed is Some((op, length)) {
    operator = op
    self.index += length
    let _ = self.spaces()
    value = if code_at(self.input, self.index) == 34 ||
      code_at(self.input, self.index) == 39 {
      self.quoted()
    } else {
      self.ident()
    }
    let _ = self.spaces()
    let flag = code_at(self.input, self.index) | 32
    if (flag == 105 || flag == 115) &&
      (
        is_css_space(code_at(self.input, self.index + 1)) ||
        code_at(self.input, self.index + 1) == 93
      ) {
      insensitive = flag == 105
      self.index += 1
      let _ = self.spaces()
    }
  }
  if code_at(self.input, self.index) != 93 {
    self.fail("Expected closing bracket")
  }
  self.index += 1
  { name, operator, value, insensitive, }
}

///|
/// Parse an integer in a source range, or `None`.
fn parse_integer(input : String, start : Int32, end : Int32) -> Int32? {
  if start >= end {
    return None
  }
  let mut index = start
  let mut sign = 1
  if code_at(input, index) == 43 || code_at(input, index) == 45 {
    if code_at(input, index) == 45 {
      sign = -1
    }
    index += 1
  }
  if index >= end {
    return None
  }
  let mut value = 0
  while index < end {
    let digit = code_at(input, index) - 48
    if digit < 0 || digit > 9 {
      return None
    }
    value = value * 10 + digit
    index += 1
  }
  Some(sign * value)
}

///|
/// Parse an `:nth-*` expression into (a, b) coefficients.
fn nth(input : String) -> (Int32, Int32) raise SelectorSyntax {
  let cleaned = StringBuilder()
  for i in 0..<input.length() {
    if !is_css_space(code_at(input, i)) {
      match input.get_char(i) {
        Some(char) => cleaned.write_char(char)
        None => ()
      }
    }
  }
  let expr = cleaned.to_string().to_lower()
  if expr == "odd" {
    return (2, 1)
  }
  if expr == "even" {
    return (2, 0)
  }
  let mut n_at = -1
  for i in 0..<expr.length() {
    if code_at(expr, i) == 110 {
      n_at = i
      break
    }
  }
  if n_at == -1 {
    match parse_integer(expr, 0, expr.length()) {
      Some(value) => return (0, value)
      None =>
        raise SelectorSyntax::Message("Invalid nth expression: \"\{input}\"")
    }
  }
  let a = if n_at == 0 {
    1
  } else if n_at == 1 && code_at(expr, 0) == 43 {
    1
  } else if n_at == 1 && code_at(expr, 0) == 45 {
    -1
  } else {
    match parse_integer(expr, 0, n_at) {
      Some(value) => value
      None =>
        raise SelectorSyntax::Message("Invalid nth expression: \"\{input}\"")
    }
  }
  let b = if n_at + 1 == expr.length() {
    0
  } else {
    match parse_integer(expr, n_at + 1, expr.length()) {
      Some(value) => value
      None =>
        raise SelectorSyntax::Message("Invalid nth expression: \"\{input}\"")
    }
  }
  (a, b)
}

///|
/// Parse one `:pseudo-class` and its arguments.
fn Parser::pseudo(self : Parser) -> Array[Pseudo] raise SelectorSyntax {
  self.index += 1
  let name = self.ident().to_lower()
  if name == "root" {
    return [Pseudo::Root]
  }
  if name == "empty" {
    return [Pseudo::Empty]
  }
  let simple = match name {
    "first-child" => Some((false, false, false))
    "last-child" => Some((true, false, false))
    "only-child" => Some((false, false, true))
    "first-of-type" => Some((false, true, false))
    "last-of-type" => Some((true, true, false))
    "only-of-type" => Some((false, true, true))
    _ => None
  }
  if simple is Some((last, of_type, only)) {
    let first = Pseudo::Nth(a=0, b=1, last=false, of_type~)
    if only {
      return [first, Pseudo::Nth(a=0, b=1, last=true, of_type~)]
    }
    return [Pseudo::Nth(a=0, b=1, last~, of_type~)]
  }
  if code_at(self.input, self.index) != 40 {
    self.fail("Unsupported pseudo-class \":\{name}\"")
  }
  let mut depth = 1
  self.index += 1
  let from = self.index
  while self.index < self.input.length() && depth > 0 {
    let code = code_at(self.input, self.index)
    if code == 40 {
      depth += 1
    }
    if code == 41 {
      depth -= 1
    }
    self.index += 1
  }
  if depth > 0 {
    self.fail("Expected \")\"")
  }
  let args = slice(self.input, from, self.index - 1)
  let nth_kind = match name {
    "nth-child" => Some((false, false))
    "nth-last-child" => Some((true, false))
    "nth-of-type" => Some((false, true))
    "nth-last-of-type" => Some((true, true))
    _ => None
  }
  if nth_kind is Some((last, of_type)) {
    let (a, b) = nth(args)
    return [Pseudo::Nth(a~, b~, last~, of_type~)]
  }
  if name == "not" {
    return [Pseudo::Not(compile(args))]
  }
  if name == "is" || name == "where" {
    return [Pseudo::Is(compile(args))]
  }
  self.fail("Unsupported pseudo-class \":\{name}()\"")
  []
}

///|
/// Parse one compound selector.
fn Parser::compound(self : Parser) -> Compound raise SelectorSyntax {
  let output : Compound = {
    tag: "",
    raw: "",
    id: "",
    classes: [],
    attributes: [],
    pseudos: [],
  }
  let from = self.index
  if code_at(self.input, self.index) == 42 {
    self.index += 1
  } else if self.index < self.input.length() &&
    (
      is_ident(code_at(self.input, self.index)) ||
      code_at(self.input, self.index) == 92
    ) {
    output.raw = self.ident()
    output.tag = output.raw.to_lower()
  }
  while self.index < self.input.length() {
    match code_at(self.input, self.index) {
      35 => {
        self.index += 1
        output.id = self.ident()
      }
      46 => {
        self.index += 1
        output.classes.push(self.ident())
      }
      91 => output.attributes.push(self.attribute())
      58 =>
        for pseudo in self.pseudo() {
          output.pseudos.push(pseudo)
        }
      _ => break
    }
  }
  if self.index == from {
    self.fail("Expected a selector")
  }
  output
}

///|
/// Parse selector text into a compiled `Selector`, caching the result.
pub fn compile(input : String) -> Selector raise SelectorSyntax {
  if selector_cache.get(input) is Some(cached) {
    return cached
  }
  let parser : Parser = { input, index: 0, }
  let rules : Array[Complex] = []
  while true {
    let _ = parser.spaces()
    let complex : Complex = { compounds: [parser.compound()], combinators: [], }
    while true {
      let space = parser.spaces()
      let code = code_at(input, parser.index)
      if parser.index >= input.length() || code == 44 {
        break
      }
      let mut combinator = Combinator::Descendant
      if code == 62 || code == 43 || code == 126 {
        combinator = if code == 62 {
          Combinator::Child
        } else if code == 43 {
          Combinator::NextSibling
        } else {
          Combinator::SubsequentSibling
        }
        parser.index += 1
        let _ = parser.spaces()
      } else if !space {
        parser.fail("Unexpected character")
      }
      complex.combinators.push(combinator)
      complex.compounds.push(parser.compound())
    }
    rules.push(complex)
    if parser.index >= input.length() {
      break
    }
    parser.index += 1
  }
  let candidate_tags : Array[String] = []
  let mut has_candidates = true
  for rule in rules {
    let last = rule.compounds[rule.compounds.length() - 1]
    if last.tag.is_empty() {
      has_candidates = false
      break
    }
    if !candidate_tags.contains(last.tag) {
      candidate_tags.push(last.tag)
    }
    if !candidate_tags.contains(last.raw) {
      candidate_tags.push(last.raw)
    }
  }
  let selector : Selector = {
    rules,
    candidate_tags: if has_candidates {
      Some(candidate_tags)
    } else {
      None
    },
  }
  if selector_cache.length() >= 512 {
    selector_cache.clear()
  }
  selector_cache[input] = selector
  selector
}

///|
/// Whether `actual` contains `expected` as a whitespace-separated word.
fn has_word(actual : String, expected : String) -> Bool {
  let wanted = expected.length()
  if wanted == 0 {
    return false
  }
  let mut start = 0
  let mut i = 0
  let length = actual.length()
  while i <= length {
    if i == length || is_css_space(code_at(actual, i)) {
      if i - start == wanted &&
        actual.unsafe_range_equal(start~, expected, other_start=0, len=wanted) {
        return true
      }
      start = i + 1
    }
    i += 1
  }
  false
}

///|
/// Test one attribute rule against an element.
fn match_attribute(tree : Tree, id : Int32, rule : AttributeRule) -> Bool {
  guard attribute(tree, id, rule.name) is Some(found) else { return false }
  if rule.operator == Operator::Exists {
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
        code_at(actual, expected_length) == 45 &&
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
/// Test one pseudo-class against an element.
fn match_pseudo(tree : Tree, id : Int32, rule : Pseudo) -> Bool {
  match rule {
    Root => tree.parent[id] == 0
    Empty => {
      let mut current = id + 1
      while current < tree.stop[id] {
        if tree.kind[current] == Kind::Element ||
          tree.kind[current] == Kind::Text {
          return false
        }
        current = tree.stop[current]
      }
      true
    }
    Not(selector) => !matches(tree, id, selector)
    Is(selector) => matches(tree, id, selector)
    Nth(a~, b~, last~, of_type~) => {
      let parent = tree.parent[id]
      let mut at = 0
      let mut total = 0
      let mut current = parent + 1
      while current < tree.stop[parent] {
        if tree.kind[current] == Kind::Element &&
          (!of_type || tree.name[current] == tree.name[id]) {
          total += 1
          if current == id {
            at = total
          }
        }
        current = tree.stop[current]
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
/// Test a compound selector against an element.
fn match_compound(tree : Tree, id : Int32, rule : Compound) -> Bool {
  if !rule.tag.is_empty() &&
    tree.name[id] != rule.tag &&
    tree.name[id] != rule.raw {
    return false
  }
  if !rule.id.is_empty() && attribute(tree, id, "id") != Some(rule.id) {
    return false
  }
  if rule.classes.length() > 0 {
    let names = attribute(tree, id, "class").unwrap_or("")
    for name in rule.classes {
      if !has_word(names, name) {
        return false
      }
    }
  }
  for attribute_rule in rule.attributes {
    if !match_attribute(tree, id, attribute_rule) {
      return false
    }
  }
  for pseudo in rule.pseudos {
    if !match_pseudo(tree, id, pseudo) {
      return false
    }
  }
  true
}

///|
/// Test a complex selector (with combinators) against an element.
fn match_complex(
  tree : Tree,
  id : Int32,
  rule : Complex,
  index : Int32,
) -> Bool {
  if !match_compound(tree, id, rule.compounds[index]) {
    return false
  }
  if index == 0 {
    return true
  }
  match rule.combinators[index - 1] {
    Child => {
      let parent = tree.parent[id]
      parent > 0 && match_complex(tree, parent, rule, index - 1)
    }
    Descendant => {
      let mut parent = tree.parent[id]
      while parent > 0 {
        if match_complex(tree, parent, rule, index - 1) {
          return true
        }
        parent = tree.parent[parent]
      }
      false
    }
    NextSibling | SubsequentSibling => {
      let parent = tree.parent[id]
      let mut previous = 0
      let mut current = parent + 1
      while current < id {
        if tree.kind[current] == Kind::Element {
          if rule.combinators[index - 1] == SubsequentSibling &&
            match_complex(tree, current, rule, index - 1) {
            return true
          }
          previous = current
        }
        current = tree.stop[current]
      }
      rule.combinators[index - 1] == NextSibling &&
      previous > 0 &&
      match_complex(tree, previous, rule, index - 1)
    }
  }
}

///|
/// Whether the element `id` matches the compiled selector.
pub fn matches(tree : Tree, id : Int32, selector : Selector) -> Bool {
  for rule in selector.rules {
    if match_complex(tree, id, rule, rule.compounds.length() - 1) {
      return true
    }
  }
  false
}

///|
/// Precomputed candidate element ids for the selector's rightmost compound, if any.
fn candidates(tree : Tree, selector : Selector) -> Array[Int32]? {
  guard selector.candidate_tags is Some(names) else { return None }
  if tree.tags is None {
    let tags : Map[String, Array[Int32]] = Map([])
    for id in 1..<tree.size {
      if tree.kind[id] != Kind::Element {
        continue
      }
      match tags.get(tree.name[id]) {
        Some(found) => found.push(id)
        None => tags[tree.name[id]] = [id]
      }
    }
    tree.tags = Some(tags)
  }
  let output : Array[Int32] = []
  if tree.tags is Some(tags) {
    for name in names {
      if tags.get(name) is Some(ids) {
        for id in ids {
          output.push(id)
        }
      }
    }
  }
  if names.length() > 1 {
    output.sort()
  }
  Some(output)
}

///|
/// All element ids under `root` matching the compiled selector, in source order.
pub fn all(
  tree : Tree,
  root : Int32,
  selector : Selector,
  limit~ : Int32 = 0x7fffffff,
) -> Array[Int32] {
  let output : Array[Int32] = []
  let stop = tree.stop[root]
  if candidates(tree, selector) is Some(ids) {
    let templates = match tree.tags {
      Some(tags) => tags.get("template").unwrap_or([])
      None => []
    }
    let mut skip = 0
    let mut k = 0
    for id in ids {
      if id <= root {
        continue
      }
      if id >= stop {
        break
      }
      while k < templates.length() && templates[k] < id {
        let current = templates[k]
        if current > root && tree.stop[current] > skip {
          skip = tree.stop[current]
        }
        k += 1
      }
      if id < skip {
        continue
      }
      if matches(tree, id, selector) {
        output.push(id)
        if output.length() >= limit {
          break
        }
      }
    }
    return output
  }
  let mut id = root + 1
  while id < stop {
    if tree.kind[id] != Kind::Element {
      id += 1
      continue
    }
    if matches(tree, id, selector) {
      output.push(id)
      if output.length() >= limit {
        break
      }
    }
    if tree.name[id] == "template" {
      id = tree.stop[id]
    } else {
      id += 1
    }
  }
  output
}
