///|
pub fn code_at(source : String, index : Int32) -> Int32 {
  if index >= 0 && index < source.length() {
    source.unsafe_get(index).to_int()
  } else {
    -1
  }
}

///|
pub fn unsafe_code_at(source : String, index : Int32) -> Int32 {
  source.unsafe_get(index).to_int()
}

///|
pub fn slice(source : String, start : Int32, end : Int32) -> String {
  source.unsafe_substring(start~, end~)
}

///|
pub fn starts_at(source : String, value : String, start : Int32) -> Bool {
  let length = value.length()
  start >= 0 &&
  start + length <= source.length() &&
  source.unsafe_range_equal(start~, value, other_start=0, len=length)
}

///|
fn find_impl(source : String, value : String, start : Int32) -> Int32 {
  if start > source.length() {
    return -1
  }
  match source.unsafe_view(start~, end=source.length()).find(value) {
    Some(index) => start + index
    None => -1
  }
}

///|
pub fn find_from(source : String, value : String, start : Int32) -> Int32 {
  find_impl(source, value, start)
}

///|
fn find_in_impl(
  source : String,
  value : String,
  start : Int32,
  end : Int32,
) -> Int32 {
  match source.unsafe_view(start~, end~).find(value) {
    Some(index) => start + index
    None => -1
  }
}

///|
/// Like `find_from`, but the match must end at or before `end`.
fn find_in(
  source : String,
  value : String,
  start : Int32,
  end : Int32,
) -> Int32 {
  if start < 0 || end > source.length() || start >= end {
    return -1
  }
  find_in_impl(source, value, start, end)
}

///|
pub fn is_alpha(code : Int32) -> Bool {
  (code >= 97 && code <= 122) || (code >= 65 && code <= 90)
}

///|
pub fn is_space(code : Int32) -> Bool {
  code == 32 || code == 9 || code == 10 || code == 13 || code == 12
}
