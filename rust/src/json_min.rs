//! Tiny zero-dep helpers for chopping up JSON-ish text. Used by the harness
//! (defensive parsing of model output) and by memory (line-based persistence).
//!
//! Not a real JSON parser — only the operations we actually need: clean a
//! fenced code block, extract a quoted string value by key, extract a
//! balanced object substring by key, and escape a string for output.

/// Strip a leading ```` ``` ```` (with optional language tag) and trailing
/// whitespace/backticks.
pub(crate) fn clean(raw: &str) -> String {
    let mut s = raw.trim().to_string();
    if let Some(rest) = s.strip_prefix("```") {
        let rest = match rest.find('\n') {
            Some(i) => &rest[i + 1..],
            None => rest,
        };
        s = rest.to_string();
    }
    s.trim().trim_end_matches('`').trim().to_string()
}

/// Extract a quoted string value for `"<field>": "<value>"`, honoring simple
/// backslash escapes. Returns the raw inner text (escapes not decoded — the
/// caller decides whether to interpret them).
pub(crate) fn extract_string_field(s: &str, field: &str) -> Option<String> {
    let key = format!("\"{field}\"");
    let kpos = s.find(&key)?;
    let after = &s[kpos + key.len()..];
    let colon = after.find(':')?;
    let after = &after[colon + 1..];
    let q = after.find('"')?;
    let rest = &after[q + 1..];
    let bytes = rest.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        match bytes[i] {
            b'\\' => i += 2,
            b'"' => return Some(rest[..i].to_string()),
            _ => i += 1,
        }
    }
    None
}

/// Extract the balanced `{...}` substring for `"<field>": {...}`.
pub(crate) fn extract_object_field(s: &str, field: &str) -> Option<String> {
    let key = format!("\"{field}\"");
    let kpos = s.find(&key)?;
    let after = &s[kpos + key.len()..];
    let brace = after.find('{')?;
    let region = &after[brace..];
    let bytes = region.as_bytes();
    let mut depth = 0i32;
    let mut in_str = false;
    let mut i = 0;
    while i < bytes.len() {
        let c = bytes[i];
        if in_str {
            match c {
                b'\\' => i += 1,
                b'"' => in_str = false,
                _ => {}
            }
        } else {
            match c {
                b'"' => in_str = true,
                b'{' => depth += 1,
                b'}' => {
                    depth -= 1;
                    if depth == 0 {
                        return Some(region[..=i].to_string());
                    }
                }
                _ => {}
            }
        }
        i += 1;
    }
    None
}

/// Escape a string for embedding inside a JSON string literal (no surrounding
/// quotes). Conservatively escapes control characters as `\u00xx`.
pub(crate) fn escape_string(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    for c in s.chars() {
        match c {
            '\\' => out.push_str("\\\\"),
            '"' => out.push_str("\\\""),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => {
                out.push_str(&format!("\\u{:04x}", c as u32));
            }
            c => out.push(c),
        }
    }
    out
}

/// Decode the simple backslash escapes that [`extract_string_field`] preserves
/// verbatim: `\"`, `\\`, `\n`, `\r`, `\t`. Unknown escapes are kept literally.
pub(crate) fn unescape_string(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut chars = s.chars();
    while let Some(c) = chars.next() {
        if c != '\\' {
            out.push(c);
            continue;
        }
        match chars.next() {
            Some('n') => out.push('\n'),
            Some('r') => out.push('\r'),
            Some('t') => out.push('\t'),
            Some('"') => out.push('"'),
            Some('\\') => out.push('\\'),
            Some(other) => {
                out.push('\\');
                out.push(other);
            }
            None => out.push('\\'),
        }
    }
    out
}
