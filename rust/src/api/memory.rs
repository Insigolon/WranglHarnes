//! Per-skill memory persisted as JSON Lines, owned by Rust.
//!
//! Format: one entry per line, each line is `{"task":"...","result":"..."}`.
//! JSONL is easier to truncate, append, and parse without a real JSON crate.
//!
//! Dart resolves the platform docs directory (since `path_provider` is a
//! Flutter plugin) and passes a full file path in — Rust never touches the
//! platform abstraction.

use std::fs;
use std::io::Write;
use std::path::Path;

use crate::json_min::{escape_string, extract_string_field, unescape_string};

pub struct MemoryEntry {
    pub task: String,
    pub result: String,
}

/// Load every entry from `path`. Missing or unreadable files yield an empty
/// list — corrupted memory is never fatal.
#[flutter_rust_bridge::frb(sync)]
pub fn memory_load(path: String) -> Vec<MemoryEntry> {
    let raw = match fs::read_to_string(&path) {
        Ok(s) => s,
        Err(_) => return Vec::new(),
    };
    raw.lines().filter_map(parse_line).collect()
}

fn parse_line(line: &str) -> Option<MemoryEntry> {
    let line = line.trim();
    if line.is_empty() {
        return None;
    }
    let task = extract_string_field(line, "task")?;
    let result = extract_string_field(line, "result")?;
    Some(MemoryEntry {
        task: unescape_string(&task),
        result: unescape_string(&result),
    })
}

/// Append one entry, truncate `result` to the last `summary_chars`, and
/// rewrite the file so it holds at most `max_entries` lines (oldest dropped).
/// Errors are swallowed — memory is best-effort and must not crash the loop.
#[flutter_rust_bridge::frb(sync)]
pub fn memory_append(
    path: String,
    task: String,
    result: String,
    max_entries: u32,
    summary_chars: u32,
) {
    let summary = tail_chars(&result, summary_chars as usize);
    let mut entries = memory_load(path.clone());
    entries.push(MemoryEntry {
        task,
        result: summary,
    });
    let cap = max_entries as usize;
    if entries.len() > cap {
        let drop = entries.len() - cap;
        entries.drain(0..drop);
    }
    let _ = write_all(&path, &entries);
}

fn tail_chars(s: &str, n: usize) -> String {
    let count = s.chars().count();
    if count <= n {
        return s.to_string();
    }
    s.chars().skip(count - n).collect()
}

fn write_all(path: &str, entries: &[MemoryEntry]) -> std::io::Result<()> {
    if let Some(parent) = Path::new(path).parent() {
        let _ = fs::create_dir_all(parent);
    }
    let tmp = format!("{path}.tmp");
    {
        let mut f = fs::File::create(&tmp)?;
        for e in entries {
            writeln!(
                f,
                "{{\"task\":\"{}\",\"result\":\"{}\"}}",
                escape_string(&e.task),
                escape_string(&e.result)
            )?;
        }
        f.flush()?;
    }
    fs::rename(&tmp, path)
}

/// Render entries for injection into a system prompt. Returns an empty string
/// when there are no entries so the caller can skip the "Relevant memory:"
/// section entirely.
#[flutter_rust_bridge::frb(sync)]
pub fn memory_render(entries: Vec<MemoryEntry>) -> String {
    if entries.is_empty() {
        return String::new();
    }
    entries
        .iter()
        .map(|e| format!("- {} → {}", e.task, e.result))
        .collect::<Vec<_>>()
        .join("\n")
}
