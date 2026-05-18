use crate::config::types::Personality;
use crate::error::Result;
pub use codex_api::common::ResponseEvent;
use codex_protocol::models::BaseInstructions;
use codex_protocol::models::FunctionCallOutputBody;
use codex_protocol::models::ResponseItem;
use codex_protocol::models::WebSearchAction;
use codex_tools::ToolSpec;
use codex_utils_output_truncation::TruncationPolicy;
use codex_utils_output_truncation::approx_token_count;
use codex_utils_output_truncation::truncate_text;
use futures::Stream;
use serde::Deserialize;
use serde_json::Value;
use std::collections::HashSet;
use std::pin::Pin;
use std::task::Context;
use std::task::Poll;
use tokio::sync::mpsc;

/// Review thread system prompt. Edit `core/src/review_prompt.md` to customize.
pub const REVIEW_PROMPT: &str = include_str!("../review_prompt.md");

// Centralized templates for review-related user messages
pub const REVIEW_EXIT_SUCCESS_TMPL: &str = include_str!("../templates/review/exit_success.xml");
pub const REVIEW_EXIT_INTERRUPTED_TMPL: &str =
    include_str!("../templates/review/exit_interrupted.xml");

/// API request payload for a single model turn
#[derive(Default, Debug, Clone)]
pub struct Prompt {
    /// Conversation context input items.
    pub input: Vec<ResponseItem>,

    /// Tools available to the model, including additional tools sourced from
    /// external MCP servers.
    pub(crate) tools: Vec<ToolSpec>,

    /// Whether parallel tool calls are permitted for this prompt.
    pub(crate) parallel_tool_calls: bool,

    pub base_instructions: BaseInstructions,

    /// Optionally specify the personality of the model.
    pub personality: Option<Personality>,

    /// Optional the output schema for the model's response.
    pub output_schema: Option<Value>,
}

impl Prompt {
    pub(crate) fn get_formatted_input(&self) -> Vec<ResponseItem> {
        let mut input = self.input.clone();

        // when using the *Freeform* apply_patch tool specifically, tool outputs
        // should be structured text, not json. Do NOT reserialize when using
        // the Function tool - note that this differs from the check above for
        // instructions. We declare the result as a named variable for clarity.
        let is_freeform_apply_patch_tool_present = self.tools.iter().any(|tool| match tool {
            ToolSpec::Freeform(f) => f.name == "apply_patch",
            _ => false,
        });
        if is_freeform_apply_patch_tool_present {
            reserialize_shell_outputs(&mut input);
        }

        input
    }
}

fn reserialize_shell_outputs(items: &mut [ResponseItem]) {
    let mut shell_call_ids: HashSet<String> = HashSet::new();

    items.iter_mut().for_each(|item| match item {
        ResponseItem::LocalShellCall { call_id, id, .. } => {
            if let Some(identifier) = call_id.clone().or_else(|| id.clone()) {
                shell_call_ids.insert(identifier);
            }
        }
        ResponseItem::CustomToolCall {
            id: _,
            status: _,
            call_id,
            name,
            input: _,
        } => {
            if name == "apply_patch" {
                shell_call_ids.insert(call_id.clone());
            }
        }
        ResponseItem::FunctionCall { name, call_id, .. }
            if is_shell_tool_name(name) || name == "apply_patch" =>
        {
            shell_call_ids.insert(call_id.clone());
        }
        ResponseItem::FunctionCallOutput {
            call_id, output, ..
        }
        | ResponseItem::CustomToolCallOutput {
            call_id, output, ..
        } => {
            if shell_call_ids.remove(call_id)
                && let Some(structured) = output
                    .text_content()
                    .and_then(parse_structured_shell_output)
            {
                output.body = FunctionCallOutputBody::Text(structured);
            }
        }
        _ => {}
    })
}

fn is_shell_tool_name(name: &str) -> bool {
    matches!(name, "shell" | "container.exec")
}

pub(crate) struct LocalShellOutputCompactionContext<'a> {
    pub call_id: &'a str,
    pub command: &'a [String],
    pub working_directory: Option<&'a str>,
}

#[derive(Deserialize)]
struct ExecOutputJson {
    output: String,
    metadata: ExecOutputMetadataJson,
}

#[derive(Deserialize)]
struct ExecOutputMetadataJson {
    exit_code: i32,
    duration_seconds: f32,
}

struct ParsedShellOutput {
    exit_code: i32,
    duration_seconds: Option<f32>,
    total_output_lines: Option<u32>,
    output: String,
}

pub(crate) fn compact_local_shell_output(
    raw: &str,
    context: LocalShellOutputCompactionContext<'_>,
    policy: TruncationPolicy,
) -> Option<String> {
    let truncated = truncate_text(raw, policy);
    if truncated.len() >= raw.len() {
        return None;
    }

    let parsed = parse_shell_output(raw)?;
    let compacted = build_compacted_shell_output(&parsed, context);
    if approx_token_count(&compacted) >= approx_token_count(raw) {
        return None;
    }
    Some(compacted)
}

pub(crate) fn compact_json_output(
    raw: &str,
    policy: TruncationPolicy,
) -> Option<String> {
    let truncated = truncate_text(raw, policy);
    if truncated.len() >= raw.len() {
        return None;
    }

    let parsed = serde_json::from_str::<Value>(raw).ok()?;
    let compacted = build_compacted_json_output(&parsed)?;
    if approx_token_count(&compacted) >= approx_token_count(raw) {
        return None;
    }
    Some(compacted)
}

pub(crate) fn compact_apply_patch_output(raw: &str, policy: TruncationPolicy) -> Option<String> {
    let truncated = truncate_text(raw, policy);
    if truncated.len() >= raw.len() {
        return None;
    }

    let compacted = build_compacted_apply_patch_output(raw);
    if approx_token_count(&compacted) >= approx_token_count(raw) {
        return None;
    }
    Some(compacted)
}

pub(crate) fn compact_web_search_action(
    action: &WebSearchAction,
    policy: TruncationPolicy,
) -> Option<WebSearchAction> {
    let serialized = serde_json::to_string(action).ok()?;
    let truncated = truncate_text(&serialized, policy);
    if truncated.len() >= serialized.len() {
        return None;
    }

    let compacted = build_compacted_web_search_action(action);
    let compacted_serialized = serde_json::to_string(&compacted).ok()?;
    if approx_token_count(&compacted_serialized) >= approx_token_count(&serialized) {
        return None;
    }
    Some(compacted)
}

fn parse_structured_shell_output(raw: &str) -> Option<String> {
    let parsed: ExecOutputJson = serde_json::from_str(raw).ok()?;
    Some(build_structured_output(&parsed))
}

fn parse_shell_output(raw: &str) -> Option<ParsedShellOutput> {
    parse_shell_output_json(raw).or_else(|| parse_shell_output_sections(raw))
}

fn parse_shell_output_json(raw: &str) -> Option<ParsedShellOutput> {
    let parsed: ExecOutputJson = serde_json::from_str(raw).ok()?;
    let (output, total_output_lines) = match strip_total_output_header(&parsed.output) {
        Some((stripped, total_lines)) => (stripped.to_string(), Some(total_lines)),
        None => (parsed.output.clone(), None),
    };
    Some(ParsedShellOutput {
        exit_code: parsed.metadata.exit_code,
        duration_seconds: Some(parsed.metadata.duration_seconds),
        total_output_lines,
        output,
    })
}

fn parse_shell_output_sections(raw: &str) -> Option<ParsedShellOutput> {
    let mut lines = raw.lines();
    let exit_code = lines
        .next()?
        .strip_prefix("Exit code: ")?
        .trim()
        .parse::<i32>()
        .ok()?;
    let mut duration_seconds = None;
    let mut total_output_lines = None;
    let mut found_output_header = false;
    let mut output_lines: Vec<&str> = Vec::new();

    for line in lines {
        if found_output_header {
            output_lines.push(line);
            continue;
        }
        if let Some(value) = line.strip_prefix("Wall time: ") {
            duration_seconds = value
                .strip_suffix(" seconds")
                .and_then(|seconds| seconds.trim().parse::<f32>().ok());
            continue;
        }
        if let Some(value) = line.strip_prefix("Total output lines: ") {
            total_output_lines = value.trim().parse::<u32>().ok();
            continue;
        }
        if line == "Output:" {
            found_output_header = true;
        }
    }

    if !found_output_header {
        return None;
    }

    Some(ParsedShellOutput {
        exit_code,
        duration_seconds,
        total_output_lines,
        output: output_lines.join("\n"),
    })
}

fn build_structured_output(parsed: &ExecOutputJson) -> String {
    let mut sections = Vec::new();
    sections.push(format!("Exit code: {}", parsed.metadata.exit_code));
    sections.push(format!(
        "Wall time: {} seconds",
        parsed.metadata.duration_seconds
    ));

    let mut output = parsed.output.clone();
    if let Some((stripped, total_lines)) = strip_total_output_header(&parsed.output) {
        sections.push(format!("Total output lines: {total_lines}"));
        output = stripped.to_string();
    }

    sections.push("Output:".to_string());
    sections.push(output);

    sections.join("\n")
}

fn build_compacted_shell_output(
    parsed: &ParsedShellOutput,
    context: LocalShellOutputCompactionContext<'_>,
) -> String {
    let mut sections = Vec::new();
    sections.push("[shell output compacted; preserved command metadata and output tail]".to_string());
    sections.push(format!("Command: {}", compact_command_preview(context.command)));
    if let Some(working_directory) = context.working_directory.filter(|cwd| !cwd.trim().is_empty()) {
        sections.push(format!("Working directory: {working_directory}"));
    }
    sections.push(format!("Exit code: {}", parsed.exit_code));
    if let Some(duration_seconds) = parsed.duration_seconds {
        sections.push(format!("Wall time: {} seconds", duration_seconds));
    }
    if let Some(total_output_lines) = parsed.total_output_lines {
        sections.push(format!("Total output lines: {total_output_lines}"));
    }
    let output_tail = compact_output_tail(&parsed.output, 12, 1200);
    if !output_tail.is_empty() {
        sections.push("Output tail:".to_string());
        sections.push(output_tail);
    }
    sections.push(format!(
        "[output compacted; replay locator: call_id={}; tool_name=local_shell]",
        context.call_id
    ));
    sections.join("\n")
}

fn build_compacted_json_output(value: &Value) -> Option<String> {
    let summary = match value {
        Value::Object(map) => serde_json::json!({
            "type": "json_output_compacted",
            "compacted": true,
            "shape": "object",
            "key_count": map.len(),
            "top_level_keys": map.keys().take(12).cloned().collect::<Vec<String>>(),
            "primary_fields": collect_object_primary_fields(map),
            "collection_counts": collect_object_collection_counts(map),
        }),
        Value::Array(items) => serde_json::json!({
            "type": "json_output_compacted",
            "compacted": true,
            "shape": "array",
            "item_count": items.len(),
            "preview_items": items.iter().take(3).map(summarize_json_preview).collect::<Vec<Value>>(),
        }),
        _ => return None,
    };
    serde_json::to_string_pretty(&summary).ok()
}

fn collect_object_primary_fields(
    map: &serde_json::Map<String, Value>,
) -> serde_json::Map<String, Value> {
    let mut fields = serde_json::Map::new();
    for key in ["status", "id", "name", "title", "type", "path", "url", "query"] {
        let Some(value) = map.get(key) else {
            continue;
        };
        if matches!(value, Value::String(_) | Value::Number(_) | Value::Bool(_)) {
            fields.insert(key.to_string(), value.clone());
        }
    }
    fields
}

fn collect_object_collection_counts(
    map: &serde_json::Map<String, Value>,
) -> serde_json::Map<String, Value> {
    let mut counts = serde_json::Map::new();
    for (key, value) in map {
        match value {
            Value::Array(items) => {
                counts.insert(key.clone(), Value::from(items.len()));
            }
            Value::Object(object) => {
                counts.insert(key.clone(), Value::from(object.len()));
            }
            _ => {}
        }
        if counts.len() >= 6 {
            break;
        }
    }
    counts
}

fn summarize_json_preview(value: &Value) -> Value {
    match value {
        Value::Object(map) => {
            let primary_fields = collect_object_primary_fields(map);
            if !primary_fields.is_empty() {
                Value::Object(primary_fields)
            } else {
                serde_json::json!({
                    "shape": "object",
                    "key_count": map.len(),
                    "top_level_keys": map.keys().take(6).cloned().collect::<Vec<String>>(),
                })
            }
        }
        Value::Array(items) => serde_json::json!({
            "shape": "array",
            "item_count": items.len(),
        }),
        Value::String(text) => Value::String(compact_text_head(text, 120)),
        Value::Number(_) | Value::Bool(_) | Value::Null => value.clone(),
    }
}

fn build_compacted_apply_patch_output(raw: &str) -> String {
    let mut sections = Vec::new();
    sections.push(
        "[apply_patch output compacted; preserved changed target preview and output tail]"
            .to_string(),
    );
    let changed_targets = extract_apply_patch_targets(raw);
    if !changed_targets.is_empty() {
        sections.push(format!("Changed targets: {}", changed_targets.join(", ")));
    }
    let total_output_lines = raw.lines().count();
    if total_output_lines > 0 {
        sections.push(format!("Total output lines: {total_output_lines}"));
    }
    let output_head = compact_output_head(raw, 4, 400);
    if !output_head.is_empty() {
        sections.push("Output head:".to_string());
        sections.push(output_head);
    }
    let output_tail = compact_output_tail(raw, 8, 800);
    if !output_tail.is_empty() {
        sections.push("Output tail:".to_string());
        sections.push(output_tail);
    }
    sections.join("\n")
}

fn build_compacted_web_search_action(action: &WebSearchAction) -> WebSearchAction {
    match action {
        WebSearchAction::Search { query, queries } => WebSearchAction::Search {
            query: query.as_ref().map(|value| compact_text_head(value, 240)),
            queries: queries
                .as_ref()
                .map(|values| compact_string_list(values, 3, 160)),
        },
        WebSearchAction::OpenPage { url } => WebSearchAction::OpenPage {
            url: url.as_ref().map(|value| compact_text_head(value, 240)),
        },
        WebSearchAction::FindInPage { url, pattern } => WebSearchAction::FindInPage {
            url: url.as_ref().map(|value| compact_text_head(value, 240)),
            pattern: pattern.as_ref().map(|value| compact_text_head(value, 160)),
        },
        WebSearchAction::Other => WebSearchAction::Other,
    }
}

fn extract_apply_patch_targets(output: &str) -> Vec<String> {
    let mut targets = Vec::new();
    for line in output.lines() {
        let Some(target) = extract_apply_patch_target_from_line(line.trim()) else {
            continue;
        };
        if targets.iter().any(|existing| existing == target) {
            continue;
        }
        targets.push(target.to_string());
        if targets.len() >= 6 {
            break;
        }
    }
    targets
}

fn extract_apply_patch_target_from_line(line: &str) -> Option<&str> {
    for prefix in [
        "*** Update File: ",
        "*** Add File: ",
        "*** Delete File: ",
        "*** Move to: ",
        "M ",
        "A ",
        "D ",
    ] {
        let Some(target) = line.strip_prefix(prefix) else {
            continue;
        };
        let target = target.trim();
        if !target.is_empty() {
            return Some(target);
        }
    }
    None
}

fn compact_command_preview(command: &[String]) -> String {
    let joined = if command.is_empty() {
        "<empty command>".to_string()
    } else {
        command.join(" ")
    };
    compact_text_head(&joined, 200)
}

fn compact_output_head(output: &str, max_lines: usize, max_chars: usize) -> String {
    let meaningful_lines = output
        .lines()
        .filter(|line| !line.trim().is_empty())
        .take(max_lines)
        .collect::<Vec<&str>>();
    if meaningful_lines.is_empty() {
        return compact_text_head(output, max_chars);
    }
    let head = meaningful_lines.join("\n");
    compact_text_head(&head, max_chars)
}

fn compact_output_tail(output: &str, max_lines: usize, max_chars: usize) -> String {
    let meaningful_lines = output
        .lines()
        .filter(|line| !line.trim().is_empty())
        .collect::<Vec<&str>>();
    if meaningful_lines.is_empty() {
        return compact_text_tail(output, max_chars);
    }
    let start = meaningful_lines.len().saturating_sub(max_lines);
    let mut tail = meaningful_lines[start..].join("\n");
    if start > 0 {
        tail = format!("...\n{tail}");
    }
    compact_text_tail(&tail, max_chars)
}

fn compact_text_head(text: &str, max_chars: usize) -> String {
    let total_chars = text.chars().count();
    if total_chars <= max_chars {
        return text.to_string();
    }
    let head = text.chars().take(max_chars).collect::<String>();
    format!("{head}…")
}

fn compact_text_tail(text: &str, max_chars: usize) -> String {
    let chars = text.chars().collect::<Vec<char>>();
    if chars.len() <= max_chars {
        return text.to_string();
    }
    let tail = chars[chars.len() - max_chars..].iter().collect::<String>();
    format!("…{tail}")
}

fn compact_string_list(values: &[String], max_items: usize, max_chars: usize) -> Vec<String> {
    let mut compacted = values
        .iter()
        .take(max_items)
        .map(|value| compact_text_head(value, max_chars))
        .collect::<Vec<String>>();
    if values.len() > max_items {
        compacted.push(format!(
            "… [{} more item(s) compacted]",
            values.len() - max_items
        ));
    }
    compacted
}

fn strip_total_output_header(output: &str) -> Option<(&str, u32)> {
    let after_prefix = output.strip_prefix("Total output lines: ")?;
    let (total_segment, remainder) = after_prefix.split_once('\n')?;
    let total_lines = total_segment.parse::<u32>().ok()?;
    let remainder = remainder.strip_prefix('\n').unwrap_or(remainder);
    Some((remainder, total_lines))
}

pub(crate) mod tools {
    pub(crate) use codex_tools::FreeformTool;
    pub(crate) use codex_tools::FreeformToolFormat;
    pub(crate) use codex_tools::ResponsesApiTool;
    pub(crate) use codex_tools::ToolSearchOutputTool;
    pub(crate) use codex_tools::ToolSpec;
}

pub struct ResponseStream {
    pub(crate) rx_event: mpsc::Receiver<Result<ResponseEvent>>,
}

impl Stream for ResponseStream {
    type Item = Result<ResponseEvent>;

    fn poll_next(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        self.rx_event.poll_recv(cx)
    }
}

#[cfg(test)]
#[path = "client_common_tests.rs"]
mod tests;
