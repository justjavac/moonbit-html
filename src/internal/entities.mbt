///|
const VALUE_LENGTH = 0b1100_0000_0000_0000

///|
const FLAG13 = 0b0010_0000_0000_0000

///|
const BRANCH_LENGTH = 0b0001_1111_1000_0000

///|
const JUMP_TABLE = 0b0000_0000_0111_1111

///|
const VALUE_MASK = 0b0001_1111_1111_1111

///|
fn base91_table() -> Array[Int32] {
  let table = Array::make(127, 0)
  let mut code = 0
  for char in 0x21..<=0x7e {
    if char != 0x22 && char != 0x24 && char != 0x5c {
      table[char] = code
      code += 1
    }
  }
  table
}

///|
let base91 : Array[Int32] = base91_table()

///|
fn decode_trie_dict(
  input : String,
  result_length : Int32,
  atom_count : Int32,
  dict1_atom_count : Int32,
  ngram_count : Int32,
  dict_size : Int32,
) -> Array[Int32] {
  let base = 91
  let two_char_bias = dict_size * (base - 1)
  let mut pos = 0
  fn read_slot_code() -> Int32 {
    let first = base91[code_at(input, pos)]
    pos += 1
    if first < dict_size {
      first
    } else {
      let second = base91[code_at(input, pos)]
      pos += 1
      first * base - two_char_bias + second
    }
  }
  let dict2_atom_count = atom_count - dict1_atom_count
  let slot_count = atom_count + ngram_count
  let single = Array::make(slot_count, 0)
  let start = Array::make(slot_count, 0)
  let length = Array::make(slot_count, 0)
  for i in dict1_atom_count..<dict_size {
    single[i] = -1
  }
  for i in (dict_size + dict2_atom_count)..<slot_count {
    single[i] = -1
  }
  fn decode_delta(count : Int32, offset : Int32) -> Unit {
    let mut previous = 0
    let mut slot = offset
    let end = offset + count
    while slot < end {
      let code = base91[code_at(input, pos)]
      pos += 1
      if code < 89 {
        previous += code
        single[slot] = previous
        slot += 1
      } else if code == 89 {
        let mut run = base91[code_at(input, pos)] + 2
        pos += 1
        while run > 0 {
          previous += 1
          single[slot] = previous
          slot += 1
          run -= 1
        }
      } else {
        let next = base91[code_at(input, pos)]
        pos += 1
        if next < 90 {
          let after = base91[code_at(input, pos)]
          pos += 1
          previous += 89 + next * base + after
        } else {
          let second = base91[code_at(input, pos)]
          let third = base91[code_at(input, pos + 1)]
          let fourth = base91[code_at(input, pos + 2)]
          pos += 3
          previous += 89 + second * 8281 + third * base + fourth
        }
        single[slot] = previous
        slot += 1
      }
    }
  }
  decode_delta(dict1_atom_count, 0)
  decode_delta(dict2_atom_count, dict_size)
  let references = Array::make(ngram_count * 2, 0)
  let mut pool_size = 0
  let mut ngram_index = 0
  fn read_references(count : Int32, start_slot : Int32) -> Unit {
    for index in 0..<count {
      let slot = start_slot + index
      let a = read_slot_code()
      let b = read_slot_code()
      references[ngram_index * 2] = a
      references[ngram_index * 2 + 1] = b
      ngram_index += 1
      start[slot] = pool_size
      let entry_length = (if single[a] < 0 { length[a] } else { 1 }) +
        (if single[b] < 0 { length[b] } else { 1 })
      length[slot] = entry_length
      pool_size += entry_length
    }
  }
  read_references(
    ngram_count - dict_size + dict1_atom_count,
    dict_size + dict2_atom_count,
  )
  read_references(dict_size - dict1_atom_count, dict1_atom_count)
  let pool = Array::make(pool_size, 0)
  let mut write = 0
  for index in 0..<ngram_index {
    for half in 0..<2 {
      let source = references[index * 2 + half]
      let value = single[source]
      if value < 0 {
        let mut read = start[source]
        let read_end = read + length[source]
        while read < read_end {
          pool[write] = pool[read]
          write += 1
          read += 1
        }
      } else {
        pool[write] = value
        write += 1
      }
    }
  }
  let output = Array::make(result_length, 0)
  let mut output_index = 0
  while pos < input.length() {
    let mut slot = base91[code_at(input, pos)]
    pos += 1
    if slot >= dict_size {
      slot = slot * base - two_char_bias + base91[code_at(input, pos)]
      pos += 1
    }
    let value = single[slot]
    if value < 0 {
      let mut read = start[slot]
      let read_end = read + length[slot]
      while read < read_end {
        output[output_index] = pool[read]
        output_index += 1
        read += 1
      }
    } else {
      output[output_index] = value
      output_index += 1
    }
  }
  output
}

///|
let html_tree : Array[Int32] = decode_trie_dict(
  packed_html_entities, 13494, 2713, 49, 25, 61,
)

///|
fn determine_branch(
  tree : Array[Int32],
  current : Int32,
  node : Int32,
  char : Int32,
) -> Int32 {
  let branch_count = (current & BRANCH_LENGTH) >> 7
  let jump_offset = current & JUMP_TABLE
  if jump_offset != 0 {
    if branch_count == 0 {
      return if char == jump_offset { node } else { -1 }
    }
    let slot = char - jump_offset
    if slot < 0 || slot >= branch_count {
      return -1
    }
    let stored = tree[node + slot]
    return if stored == 0 {
      -1
    } else {
      (node + branch_count + stored - 1) & 0xffff
    }
  }
  if branch_count == 0 {
    return -1
  }
  let packed_slots = (branch_count + 1) >> 1
  let branch_end = node + packed_slots + branch_count
  for index in 0..<branch_count {
    let packed = tree[node + (index >> 1)]
    let key = (packed >> ((index & 1) << 3)) & 0xff
    if key == char {
      return (branch_end + tree[node + packed_slots + index]) & 0xffff
    }
    if key > char {
      return -1
    }
  }
  -1
}

///|
fn codepoint_string(code : Int32) -> String {
  let replaced = replace_codepoint(code)
  match replaced.to_char() {
    Some(char) => char.to_string()
    None => "\u{fffd}"
  }
}

///|
fn trie_value(tree : Array[Int32], node : Int32, length : Int32) -> String {
  if length == 1 {
    return codepoint_string(tree[node] & VALUE_MASK)
  }
  if length == 2 {
    return codepoint_string(tree[node + 1])
  }
  let first = tree[node + 1]
  let second = tree[node + 2]
  if first >= 0xd800 && first <= 0xdbff && second >= 0xdc00 && second <= 0xdfff {
    return codepoint_string(
      0x10000 + ((first - 0xd800) << 10) + second - 0xdc00,
    )
  }
  codepoint_string(first) + codepoint_string(second)
}

///|
fn replace_codepoint(code : Int32) -> Int32 {
  if code == 0 || (code >= 0xd800 && code <= 0xdfff) || code > 0x10ffff {
    return 0xfffd
  }
  if code >= 128 && code <= 159 {
    let replacements = [
      8364, 0, 8218, 402, 8222, 8230, 8224, 8225, 710, 8240, 352, 8249, 338, 0, 381,
      0, 0, 8216, 8217, 8220, 8221, 8226, 8211, 8212, 732, 8482, 353, 8250, 339,
      0, 382, 376,
    ]
    let replacement = replacements[code - 128]
    return if replacement == 0 { code } else { replacement }
  }
  code
}

///|
fn numeric_entity(input : String, start : Int32) -> (Int32, Int32) {
  let mut offset = start + 1
  let mut code = 0
  let mut digit_start = offset
  if offset < input.length() && (code_at(input, offset) | 32) == 120 {
    offset += 1
    digit_start = offset
    while offset < input.length() {
      let char = code_at(input, offset)
      let digit = if char >= 48 && char <= 57 {
        char - 48
      } else if (char | 32) >= 97 && (char | 32) <= 102 {
        (char | 32) - 97 + 10
      } else {
        break
      }
      code = code * 16 + digit
      if code > 0x110000 {
        code = 0x110000
      }
      offset += 1
    }
  } else {
    while offset < input.length() {
      let digit = code_at(input, offset) - 48
      if digit < 0 || digit > 9 {
        break
      }
      code = code * 10 + digit
      if code > 0x110000 {
        code = 0x110000
      }
      offset += 1
    }
  }
  if offset == digit_start {
    return (0, 0)
  }
  if offset < input.length() && code_at(input, offset) == 59 {
    offset += 1
  }
  (offset - start, code)
}

///|
fn invalid_attribute_end(code : Int32) -> Bool {
  code == 61 || is_alpha(code) || (code >= 48 && code <= 57)
}

///|
pub fn decode_html(input : String, attribute~ : Bool = false) -> String {
  let tree = html_tree
  let mut offset = find_from(input, "&", 0)
  if offset < 0 {
    return input
  }
  let input_length = input.length()
  let mut chunk_start = 0
  let output = StringBuilder()
  let root = tree[0]
  let root_jump = root & JUMP_TABLE
  let root_branches = (root & BRANCH_LENGTH) >> 7
  while offset >= 0 {
    let entity_start = offset + 1
    let first = code_at(input, entity_start)
    let mut consumed = 0
    let mut value = ""
    if first == 35 {
      let (used, code) = numeric_entity(input, entity_start)
      consumed = used
      if consumed > 0 {
        value = codepoint_string(code)
      }
    } else if is_alpha(first) {
      let root_slot = first - root_jump
      let mut node = -1
      if root_slot >= 0 && root_slot < root_branches {
        let stored = tree[1 + root_slot]
        if stored != 0 {
          node = (root_branches + stored) & 0xffff
        }
      }
      let mut best_node = 0
      let mut best_length = 0
      let mut current = if node < 0 { 0 } else { tree[node] }
      let mut index = entity_start + 1
      let mut walking = true
      while walking && index < input_length {
        let mut descending = true
        while descending &&
              (current & (VALUE_LENGTH | FLAG13)) == 0 &&
              (current & JUMP_TABLE) != 0 {
          let jump = current & JUMP_TABLE
          let branches = (current & BRANCH_LENGTH) >> 7
          if branches == 0 {
            if code_at(input, index) != jump {
              walking = false
              break
            }
            node += 1
          } else {
            let slot = code_at(input, index) - jump
            if slot < 0 || slot >= branches {
              walking = false
              break
            }
            let stored = tree[node + 1 + slot]
            if stored == 0 {
              walking = false
              break
            }
            node = (node + branches + stored) & 0xffff
          }
          current = tree[node]
          index += 1
          if index >= input_length {
            walking = false
            break
          }
          if (current & (VALUE_LENGTH | FLAG13)) != 0 ||
            (current & JUMP_TABLE) == 0 {
            descending = false
          }
        }
        if !walking || index >= input_length {
          break
        }
        if (current & (VALUE_LENGTH | FLAG13)) == FLAG13 {
          let run_length = (current & BRANCH_LENGTH) >> 7
          if code_at(input, index) != (current & JUMP_TABLE) {
            break
          }
          index += 1
          let remaining = run_length - 1
          let mut word = node + 1
          let mut packed_index = 0
          while packed_index < remaining {
            let packed = tree[word]
            let expected = if (packed_index & 1) == 0 {
              packed & 0xff
            } else {
              (packed >> 8) & 0xff
            }
            if code_at(input, index) != expected {
              walking = false
              break
            }
            index += 1
            packed_index += 1
            if (packed_index & 1) == 0 {
              word += 1
            }
          }
          if !walking {
            break
          }
          node += 1 + (run_length >> 1)
          current = tree[node]
          continue
        }
        let value_length = current >> 14
        let char = code_at(input, index)
        if value_length != 0 {
          if char == 59 {
            consumed = index - entity_start + 1
            value = trie_value(tree, node, value_length)
            break
          }
          if (current & FLAG13) == 0 {
            consumed = index - entity_start
            best_node = node
            best_length = value_length
          }
          if value_length == 1 {
            break
          }
        }
        let next = determine_branch(
          tree,
          current,
          node + (if value_length != 0 { value_length } else { 1 }),
          char,
        )
        if next < 0 {
          break
        }
        node = next
        current = tree[node]
        index += 1
      }
      if value == "" {
        let final_length = current >> 14
        if final_length != 0 && (current & FLAG13) == 0 {
          consumed = index - entity_start
          best_node = node
          best_length = final_length
        }
        if consumed > 0 {
          value = trie_value(tree, best_node, best_length)
        }
      }
    }
    let unterminated_attribute = attribute &&
      first != 35 &&
      consumed > 0 &&
      code_at(input, entity_start + consumed - 1) != 59 &&
      entity_start + consumed < input_length &&
      invalid_attribute_end(code_at(input, entity_start + consumed))
    if consumed == 0 || unterminated_attribute {
      offset = entity_start
    } else {
      if chunk_start < offset {
        output.write_view(input.unsafe_view(start=chunk_start, end=offset))
      }
      output.write_string(value)
      offset = entity_start + consumed
      chunk_start = offset
    }
    if code_at(input, offset) != 38 {
      offset = find_from(input, "&", offset)
    }
  }
  output.write_view(input.unsafe_view(start=chunk_start, end=input_length))
  output.to_string()
}

///|
pub fn escape_text(input : String) -> String {
  escape(input, false)
}

///|
pub fn escape_attribute(input : String) -> String {
  escape(input, true)
}

///|
fn escape(input : String, attribute : Bool) -> String {
  let output = StringBuilder()
  let mut start = 0
  for i in 0..<input.length() {
    let code = code_at(input, i)
    let replacement = match code {
      38 => "&amp;"
      60 if !attribute => "&lt;"
      62 if !attribute => "&gt;"
      34 if attribute => "&quot;"
      160 => "&nbsp;"
      _ => continue
    }
    if start < i {
      output.write_view(input.unsafe_view(start~, end=i))
    }
    output.write_string(replacement)
    start = i + 1
  }
  if start == 0 {
    return input
  }
  output.write_view(input.unsafe_view(start~, end=input.length()))
  output.to_string()
}
