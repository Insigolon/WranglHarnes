//! Pure, deterministic harness logic for the Wrangl on-device agent.
//!
//! This crate intentionally holds **no model access and no platform code** —
//! those live in Dart (flutter_gemma) and Kotlin (screen capture, app launch).
//! Rust owns the stateless decisions a lightweight model gets wrong often
//! enough to warrant a hardened, testable implementation:
//!
//!  - [`parse_output`] — turn a raw model reply into a tool call or a final
//!    answer, tolerating fences and missing wrappers.
//!  - [`evaluate`] — run the standing guardrails (format / loop / hallucinated
//!    tool) and produce a retry prompt on failure.
//!  - [`decide_next`] — the inner loop's branching logic: given one model
//!    turn, what should Dart do next (call a tool, retry, emit a final
//!    answer, or abort).

use crate::json_min::{clean, extract_object_field, extract_string_field};

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

/// Defensively parse one model turn into a tool call or a final answer.
///
/// Order of preference: an explicit `"tool"` field → tool call; an `"answer"`
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
    evaluate_internal(&output_raw, &valid_tools, &prev_assistant_outputs)
}

fn evaluate_internal(
    output_raw: &str,
    valid_tools: &[String],
    prev_assistant_outputs: &[String],
) -> EvalReport {
    let parsed = parse_output(output_raw.to_string());
    let mut failures: Vec<String> = Vec::new();
    let mut passed_checks = 0u32;
    let total_checks = 3u32;

    // 1. FormatCheck — a final answer must carry non-empty content.
    let format_ok = match parsed.kind {
        ParsedKind::ToolCall => parsed.tool.is_some(),
        ParsedKind::FinalAnswer => parsed
            .content
            .as_deref()
            .map(|c| !c.trim().is_empty())
            .unwrap_or(false),
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
        failures
            .push("Your last two responses were identical — try a different approach".to_string());
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
        EvalReport {
            passed: true,
            score,
            reason: "all checks passed".to_string(),
            retry_prompt: String::new(),
        }
    } else {
        let retry = format!(
            "Your previous response had issues:\n{}\nPlease try again, addressing each issue.",
            failures
                .iter()
                .map(|f| format!("  - {f}"))
                .collect::<Vec<_>>()
                .join("\n")
        );
        EvalReport {
            passed: false,
            score,
            reason: failures.join("; "),
            retry_prompt: retry,
        }
    }
}

// ─── Inner-loop decision ─────────────────────────────────────────────────────

#[derive(Debug, Clone, PartialEq)]
pub enum DecisionAction {
    /// Dart should run [`StepDecision::tool_name`] with the args in
    /// [`StepDecision::tool_args_json`], then call [`decide_next`] again with
    /// the next model output.
    CallTool,
    /// Loop is done; return [`StepDecision::final_text`] to the user.
    EmitFinal,
    /// Append [`StepDecision::retry_feedback`] as a user turn and re-run the
    /// model. [`StepDecision::retries_after`] is the new retry counter.
    Retry,
    /// Out of retries; return [`StepDecision::final_text`] as a partial answer.
    Aborted,
}

/// One iteration of the inner agent loop, expressed as a pure decision.
///
/// Dart's role is reduced to: run the model, hand the raw output here, do
/// whatever this struct says (execute a tool, append a retry prompt, or
/// return), and repeat.
///
/// `new_assistant_log` is what Dart should append to the conversation history
/// as the assistant turn this iteration (empty when nothing should be logged,
/// e.g. on an `Aborted` final). For `Retry` the caller still appends the raw
/// turn before the retry_feedback so the model sees what it did.
pub struct StepDecision {
    pub action: DecisionAction,
    pub tool_name: Option<String>,
    pub tool_args_json: Option<String>,
    pub final_text: Option<String>,
    pub retry_feedback: Option<String>,
    pub new_assistant_log: String,
    pub retries_after: u32,
}

/// Decide what Dart should do after one model turn.
///
/// All state Dart needs to thread through the loop is passed in by value here;
/// Rust holds no mutable state across calls. That keeps the FFI surface tiny
/// and makes `decide_next` trivially unit-testable.
#[flutter_rust_bridge::frb(sync)]
pub fn decide_next(
    raw_model_output: String,
    valid_tools: Vec<String>,
    prev_assistant_outputs: Vec<String>,
    retries_so_far: u32,
    max_retries: u32,
) -> StepDecision {
    let parsed = parse_output(raw_model_output.clone());
    let ev = evaluate_internal(&raw_model_output, &valid_tools, &prev_assistant_outputs);

    match parsed.kind {
        ParsedKind::ToolCall => {
            if !ev.passed {
                return retry_or_abort(
                    &ev,
                    retries_so_far,
                    max_retries,
                    raw_model_output, // log the bad tool call before the retry prompt
                );
            }
            StepDecision {
                action: DecisionAction::CallTool,
                tool_name: parsed.tool,
                tool_args_json: parsed.args_json,
                final_text: None,
                retry_feedback: None,
                new_assistant_log: raw_model_output,
                retries_after: retries_so_far,
            }
        }
        ParsedKind::FinalAnswer => {
            let content = parsed.content.unwrap_or_else(|| raw_model_output.clone());
            if ev.passed {
                return StepDecision {
                    action: DecisionAction::EmitFinal,
                    tool_name: None,
                    tool_args_json: None,
                    final_text: Some(content),
                    retry_feedback: None,
                    new_assistant_log: raw_model_output,
                    retries_after: retries_so_far,
                };
            }
            if retries_so_far < max_retries {
                return StepDecision {
                    action: DecisionAction::Retry,
                    tool_name: None,
                    tool_args_json: None,
                    final_text: None,
                    retry_feedback: Some(ev.retry_prompt),
                    new_assistant_log: raw_model_output,
                    retries_after: retries_so_far + 1,
                };
            }
            // Out of retries on a final answer — return what we have.
            StepDecision {
                action: DecisionAction::Aborted,
                tool_name: None,
                tool_args_json: None,
                final_text: Some(content),
                retry_feedback: None,
                new_assistant_log: String::new(),
                retries_after: retries_so_far,
            }
        }
    }
}

fn retry_or_abort(
    ev: &EvalReport,
    retries_so_far: u32,
    max_retries: u32,
    raw_for_log: String,
) -> StepDecision {
    if retries_so_far < max_retries {
        StepDecision {
            action: DecisionAction::Retry,
            tool_name: None,
            tool_args_json: None,
            final_text: None,
            retry_feedback: Some(ev.retry_prompt.clone()),
            new_assistant_log: raw_for_log,
            retries_after: retries_so_far + 1,
        }
    } else {
        StepDecision {
            action: DecisionAction::Aborted,
            tool_name: None,
            tool_args_json: None,
            final_text: Some(format!("I could not complete that: {}", ev.reason)),
            retry_feedback: None,
            new_assistant_log: String::new(),
            retries_after: retries_so_far,
        }
    }
}
