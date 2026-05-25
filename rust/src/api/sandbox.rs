//! Sandbox-side helpers that Rust can own without owning the actual tool
//! execution (which lives in Dart, where the plugins are).

/// Cap text-tool output at `max_chars`. Tool results that exceed the cap are
/// truncated to keep the conversation history bounded — same rule the
/// agent-harness skill calls out (<= 500 chars before re-entering the loop).
#[flutter_rust_bridge::frb(sync)]
pub fn truncate_tool_text(text: String, max_chars: u32) -> String {
    let cap = max_chars as usize;
    if text.chars().count() <= cap {
        return text;
    }
    text.chars().take(cap).collect()
}
