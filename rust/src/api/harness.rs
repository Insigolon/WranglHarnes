//! Pure, deterministic harness logic for the Wrangl on-device agent.
//!
//! This crate intentionally holds **no IO and no model access** — those live
//! in Dart (flutter_gemma) and Kotlin (screen capture). Rust owns only the
//! stateless transforms that a lightweight model gets wrong often enough to
//! warrant a hardened implementation: parsing model output, gating it with
//! evals, and the deterministic slice of skill routing.

// ─── Output parsing ──────────────────────────────────────────────────────────

#[derive(Debug, Clone, PartialEq)]
pub enum ParsedKind {
    ToolCall,
    FinalAnswer,
}

/// The result of defensively parsing one model turn.
///
/// `args_json` is returned as a raw JSON substring; Dart decodes it with its
/// built-in `jsonDecode`, so Rust never needs a JSON dependency.
pub struct ParsedOutput {
    pub kind: ParsedKind,
    pub tool: Option<String>,
    pub args_json: Option<String>,
    pub content: Option<String>,
}

/// Strip markdown code fences and surrounding whitespace/backticks.
fn clean(raw: &str) -> String {
    let mut s = raw.trim().to_string();
    // Remove a leading ```json / ```tool_call / ``` fence.
    if let Some(rest) = s.strip_prefix("```") {
        // drop the fence-language token up to the first newline
        let rest = match rest.find('\n') {
            Some(i) => &rest[i + 1..],
            None => rest,
        };
        s = rest.to_string();
    }
    s.trim().trim_end_matches('`').trim().to_string()
}

/// Extract a quoted string value for `"<field>": "<value>"`.
fn extract_string_field(s: &str, field: &str) -> Option<String> {
    let key = format!("\"{field}\"");
    let kpos = s.find(&key)?;
    let after = &s[kpos + key.len()..];
    let colon = after.find(':')?;
    let after = &after[colon + 1..];
    let q = after.find('"')?;
    let rest = &after[q + 1..];
    // find the closing quote, honoring simple backslash escapes
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

/// Extract a balanced `{...}` object substring for `"<field>": {...}`.
fn extract_object_field(s: &str, field: &str) -> Option<String> {
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

/// Defensively parse one model turn into a tool call or a final answer.
///
/// Order of preference: an explicit `"tool"` field → tool call; a `"answer"`
/// or `"result"` field → final answer; otherwise the whole cleaned text is
/// treated as the final answer (lightweight models often skip the wrapper).
#[flutter_rust_bridge::frb(sync)]
pub fn parse_output(raw: String) -> ParsedOutput {
    let s = clean(&raw);

    if let Some(tool) = extract_string_field(&s, "tool") {
        let args_json = extract_object_field(&s, "args");
        return ParsedOutput {
            kind: ParsedKind::ToolCall,
            tool: Some(tool),
            args_json,
            content: None,
        };
    }

    let content = extract_string_field(&s, "answer")
        .or_else(|| extract_string_field(&s, "result"))
        .unwrap_or_else(|| s.clone());

    ParsedOutput {
        kind: ParsedKind::FinalAnswer,
        tool: None,
        args_json: None,
        content: Some(content),
    }
}

// ─── Evaluation gate ─────────────────────────────────────────────────────────

/// Aggregated verdict over all guardrail checks for one model turn.
pub struct EvalReport {
    pub passed: bool,
    pub score: f32,
    pub reason: String,
    /// A prompt to feed back to the model on failure (empty when passed).
    pub retry_prompt: String,
}

/// Run the standing guardrails against a single model turn.
///
/// - `output_raw`: the current model output.
/// - `valid_tools`: the scoped tool names for the active skill.
/// - `prev_assistant_outputs`: prior assistant turns (NOT including current),
///   used to detect the model getting stuck repeating itself.
#[flutter_rust_bridge::frb(sync)]
pub fn evaluate(
    output_raw: String,
    valid_tools: Vec<String>,
    prev_assistant_outputs: Vec<String>,
) -> EvalReport {
    let parsed = parse_output(output_raw.clone());
    let mut failures: Vec<String> = Vec::new();
    let mut passed_checks = 0u32;
    let total_checks = 3u32;

    // 1. FormatCheck — a final answer must carry non-empty content.
    let format_ok = match parsed.kind {
        ParsedKind::ToolCall => parsed.tool.is_some(),
        ParsedKind::FinalAnswer => {
            parsed.content.as_deref().map(|c| !c.trim().is_empty()).unwrap_or(false)
        }
    };
    if format_ok {
        passed_checks += 1;
    } else {
        failures.push("Response was empty or could not be parsed".to_string());
    }

    // 2. LoopDetector — identical consecutive assistant outputs.
    let loop_ok = match prev_assistant_outputs.last() {
        Some(prev) => prev.trim() != output_raw.trim(),
        None => true,
    };
    if loop_ok {
        passed_checks += 1;
    } else {
        failures.push("Your last two responses were identical — try a different approach".to_string());
    }

    // 3. ToolHallucinationCheck — only the scoped tools may be called.
    let tool_ok = match (&parsed.kind, &parsed.tool) {
        (ParsedKind::ToolCall, Some(t)) => valid_tools.iter().any(|v| v == t),
        _ => true,
    };
    if tool_ok {
        passed_checks += 1;
    } else {
        let name = parsed.tool.clone().unwrap_or_default();
        failures.push(format!(
            "Tool '{}' does not exist. Available tools: [{}]",
            name,
            valid_tools.join(", ")
        ));
    }

    let score = passed_checks as f32 / total_checks as f32;
    if failures.is_empty() {
        EvalReport { passed: true, score, reason: "all checks passed".to_string(), retry_prompt: String::new() }
    } else {
        let retry = format!(
            "Your previous response had issues:\n{}\nPlease try again, addressing each issue.",
            failures.iter().map(|f| format!("  - {f}")).collect::<Vec<_>>().join("\n")
        );
        EvalReport { passed: false, score, reason: failures.join("; "), retry_prompt: retry }
    }
}

// ─── Skill routing (deterministic slice) ───────────────────────────────────────

pub struct SkillDesc {
    pub name: String,
    pub description: String,
}

/// Deterministic fast-path router. Returns the matched skill name, or "none"
/// to signal that Dart should fall back to an LLM routing call.
///
/// Only ever returns a skill that is actually present in `skills`.
#[flutter_rust_bridge::frb(sync)]
pub fn route_skill(task: String, skills: Vec<SkillDesc>) -> String {
    let has = |name: &str| skills.iter().any(|s| s.name == name);
    let t = task.trim().to_lowercase();

    let starts_any = |prefixes: &[&str]| prefixes.iter().any(|p| t.starts_with(p));
    let contains_any = |needles: &[&str]| needles.iter().any(|n| t.contains(n));

    if has("apps") && starts_any(&["open ", "launch ", "start ", "go to "]) {
        return "apps".to_string();
    }
    if has("screen")
        && contains_any(&[
            "on my screen",
            "on screen",
            "what's on",
            "whats on",
            "read this",
            "read the screen",
            "what does this say",
            "screenshot",
            "this page",
            "look at my screen",
            "see my screen",
        ])
    {
        return "screen".to_string();
    }
    if has("web") && starts_any(&["search ", "google ", "look up ", "find online"]) {
        return "web".to_string();
    }

    "none".to_string()
}
