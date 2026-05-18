use std::collections::HashMap;
use std::collections::HashSet;
use std::path::Path;
use std::sync::Arc;

use crate::ModelProviderInfo;
use crate::Prompt;
use crate::client::ModelClientSession;
use crate::client_common::LocalShellOutputCompactionContext;
use crate::client_common::ResponseEvent;
use crate::client_common::compact_apply_patch_output;
use crate::client_common::compact_json_output;
use crate::client_common::compact_local_shell_output;
use crate::client_common::compact_web_search_action;
#[cfg(test)]
use crate::codex::PreviousTurnSettings;
use crate::codex::Session;
use crate::codex::TurnContext;
use crate::codex::get_last_assistant_message_from_turn;
use crate::error::CodexErr;
use crate::error::Result as CodexResult;
use crate::protocol::CompactedItem;
use crate::protocol::EventMsg;
use crate::protocol::TurnStartedEvent;
use crate::protocol::WarningEvent;
use crate::util::backoff;
use codex_protocol::items::ContextCompactionItem;
use codex_protocol::items::TurnItem;
use codex_protocol::models::ContentItem;
use codex_protocol::models::FunctionCallOutputBody;
use codex_protocol::models::FunctionCallOutputContentItem;
use codex_protocol::models::FunctionCallOutputPayload;
use codex_protocol::models::LocalShellAction;
use codex_protocol::models::ResponseInputItem;
use codex_protocol::models::ResponseItem;
use codex_protocol::models::WebSearchAction;
use codex_protocol::user_input::UserInput;
use codex_utils_output_truncation::TruncationPolicy;
use codex_utils_output_truncation::approx_token_count;
use codex_utils_output_truncation::truncate_function_output_items_with_policy;
use codex_utils_output_truncation::truncate_text;
use futures::prelude::*;
use tracing::error;

pub const SUMMARIZATION_PROMPT: &str = include_str!("../templates/compact/prompt.md");
pub const SUMMARY_PREFIX: &str = include_str!("../templates/compact/summary_prefix.md");
const COMPACT_USER_MESSAGE_MAX_TOKENS: usize = usize::MAX;
const COMPACT_TOOL_OUTPUT_MAX_TOKENS: usize = 500;

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
struct PreCompressedToolOutputStats {
    item_count: usize,
    saved_tokens: i64,
}

/// Controls whether compaction replacement history must include initial context.
///
/// Pre-turn/manual compaction variants use `DoNotInject`: they replace history with a summary and
/// clear `reference_context_item`, so the next regular turn will fully reinject initial context
/// after compaction.
///
/// Mid-turn compaction must use `BeforeLastUserMessage` because the model is trained to see the
/// compaction summary as the last item in history after mid-turn compaction; we therefore inject
/// initial context into the replacement history just above the last real user message.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum InitialContextInjection {
    BeforeLastUserMessage,
    DoNotInject,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum CompactionTriggerSource {
    Manual,
    PreTurn,
    MidTurn,
    ModelSwitch,
}

impl CompactionTriggerSource {
    pub(crate) fn as_str(self) -> &'static str {
        match self {
            Self::Manual => "manual",
            Self::PreTurn => "pre_turn",
            Self::MidTurn => "mid_turn",
            Self::ModelSwitch => "model_switch",
        }
    }
}

pub(crate) fn should_use_remote_compact_task(provider: &ModelProviderInfo) -> bool {
    provider.is_openai()
}

pub(crate) async fn run_inline_auto_compact_task(
    sess: Arc<Session>,
    turn_context: Arc<TurnContext>,
    initial_context_injection: InitialContextInjection,
    trigger_source: CompactionTriggerSource,
) -> CodexResult<()> {
    let prompt = turn_context.compact_prompt().to_string();
    let input = vec![UserInput::Text {
        text: prompt,
        // Compaction prompt is synthesized; no UI element ranges to preserve.
        text_elements: Vec::new(),
    }];

    run_compact_task_inner(
        sess,
        turn_context,
        input,
        initial_context_injection,
        trigger_source,
        /*emit_error_event*/ false,
    )
    .await?;
    Ok(())
}

pub(crate) async fn run_compact_task(
    sess: Arc<Session>,
    turn_context: Arc<TurnContext>,
    input: Vec<UserInput>,
) -> CodexResult<()> {
    let start_event = EventMsg::TurnStarted(TurnStartedEvent {
        turn_id: turn_context.sub_id.clone(),
        model_context_window: turn_context.model_context_window(),
        collaboration_mode_kind: turn_context.collaboration_mode.mode,
    });
    sess.send_event(&turn_context, start_event).await;
    run_compact_task_inner(
        sess.clone(),
        turn_context,
        input,
        InitialContextInjection::DoNotInject,
        CompactionTriggerSource::Manual,
        /*emit_error_event*/ true,
    )
    .await
}

async fn run_compact_task_inner(
    sess: Arc<Session>,
    turn_context: Arc<TurnContext>,
    input: Vec<UserInput>,
    initial_context_injection: InitialContextInjection,
    trigger_source: CompactionTriggerSource,
    emit_error_event: bool,
) -> CodexResult<()> {
    let mut compaction_item = ContextCompactionItem::new();
    compaction_item.trigger_source = Some(trigger_source.as_str().to_string());
    compaction_item.provider_mode = Some("local".to_string());
    compaction_item.reference_context_reestablished = Some(matches!(
        initial_context_injection,
        InitialContextInjection::BeforeLastUserMessage
    ));
    sess.emit_turn_item_started(
        &turn_context,
        &TurnItem::ContextCompaction(compaction_item.clone()),
    )
    .await;
    let initial_input_for_turn: ResponseInputItem = ResponseInputItem::from(input);

    let mut history = sess.clone_history().await;
    history.record_items(
        &[initial_input_for_turn.into()],
        turn_context.truncation_policy,
    );

    let mut truncated_count = 0usize;

    let max_retries = turn_context.provider.stream_max_retries();
    let mut retries = 0;
    let mut client_session = sess.services.model_client.new_session();
    // Reuse one client session so turn-scoped state (sticky routing, websocket incremental
    // request tracking)
    // survives retries within this compact turn.

    loop {
        // Clone is required because of the loop
        let mut turn_input = history
            .clone()
            .for_prompt(&turn_context.model_info.input_modalities);
        let pre_compressed_tool_output_stats = pre_compress_tool_outputs(
            &mut turn_input,
            COMPACT_TOOL_OUTPUT_MAX_TOKENS,
        );
        let turn_input_len = turn_input.len();
        let prompt = Prompt {
            input: turn_input,
            base_instructions: sess.get_base_instructions().await,
            personality: turn_context.personality,
            ..Default::default()
        };
        let turn_metadata_header = turn_context.turn_metadata_state.current_header_value();
        let attempt_result = drain_to_completed(
            &sess,
            turn_context.as_ref(),
            &mut client_session,
            turn_metadata_header.as_deref(),
            &prompt,
        )
        .await;

        match attempt_result {
            Ok(()) => {
                if pre_compressed_tool_output_stats.item_count > 0 {
                    compaction_item.micro_compaction_item_count =
                        Some(pre_compressed_tool_output_stats.item_count as i64);
                }
                if pre_compressed_tool_output_stats.saved_tokens > 0 {
                    compaction_item.micro_compaction_saved_tokens =
                        Some(pre_compressed_tool_output_stats.saved_tokens);
                }
                if truncated_count > 0 {
                    compaction_item.trimmed_item_count = Some(truncated_count as i64);
                    sess.notify_background_event(
                        turn_context.as_ref(),
                        format!(
                            "Trimmed {truncated_count} older thread item(s) before compacting so the prompt fits the model context window."
                        ),
                    )
                    .await;
                }
                break;
            }
            Err(CodexErr::Interrupted) => {
                return Err(CodexErr::Interrupted);
            }
            Err(e @ CodexErr::ContextWindowExceeded) => {
                if turn_input_len > 1 {
                    // Trim from the beginning to preserve cache (prefix-based) and keep recent messages intact.
                    error!(
                        "Context window exceeded while compacting; removing oldest history item. Error: {e}"
                    );
                    history.remove_first_item();
                    truncated_count += 1;
                    retries = 0;
                    continue;
                }
                sess.set_total_tokens_full(turn_context.as_ref()).await;
                if emit_error_event {
                    let event = EventMsg::Error(e.to_error_event(/*message_prefix*/ None));
                    sess.send_event(&turn_context, event).await;
                }
                return Err(e);
            }
            Err(e) => {
                if retries < max_retries {
                    retries += 1;
                    let delay = backoff(retries);
                    sess.notify_stream_error(
                        turn_context.as_ref(),
                        format!("Reconnecting... {retries}/{max_retries}"),
                        e,
                    )
                    .await;
                    tokio::time::sleep(delay).await;
                    continue;
                } else {
                    if emit_error_event {
                        let event = EventMsg::Error(e.to_error_event(/*message_prefix*/ None));
                        sess.send_event(&turn_context, event).await;
                    }
                    return Err(e);
                }
            }
        }
    }

    let history_snapshot = sess.clone_history().await;
    let history_items = history_snapshot.raw_items();
    let summary_suffix = get_last_assistant_message_from_turn(history_items).unwrap_or_default();
    let summary_text = format!("{SUMMARY_PREFIX}\n{summary_suffix}");
    let user_messages = collect_user_messages(history_items);
    let recent_artifact_refs = collect_recent_artifact_refs(history_items, sess.recent_artifact_refs().await);

    let mut new_history = build_compacted_history(Vec::new(), &user_messages, &summary_text);

    if matches!(
        initial_context_injection,
        InitialContextInjection::BeforeLastUserMessage
    ) {
        let initial_context = sess.build_initial_context(turn_context.as_ref()).await;
        new_history =
            insert_initial_context_before_last_real_user_or_summary(new_history, initial_context);
    }
    let ghost_snapshots: Vec<ResponseItem> = history_items
        .iter()
        .filter(|item| matches!(item, ResponseItem::GhostSnapshot { .. }))
        .cloned()
        .collect();
    new_history.extend(ghost_snapshots);
    let reference_context_item = match initial_context_injection {
        InitialContextInjection::DoNotInject => None,
        InitialContextInjection::BeforeLastUserMessage => Some(turn_context.to_turn_context_item()),
    };
    let compacted_item = CompactedItem {
        message: summary_text.clone(),
        replacement_history: Some(new_history.clone()),
        recent_artifact_refs,
    };
    sess.replace_compacted_history(new_history, reference_context_item, compacted_item)
        .await;
    sess.recompute_token_usage(&turn_context).await;

    sess.emit_turn_item_completed(
        &turn_context,
        TurnItem::ContextCompaction(compaction_item),
    )
    .await;
    sess.clear_auto_compact_failure_state().await;
    let warning = EventMsg::Warning(WarningEvent {
        message: "Heads up: Long threads and multiple compactions can cause the model to be less accurate. Start a new thread when possible to keep threads small and targeted.".to_string(),
    });
    sess.send_event(&turn_context, warning).await;
    Ok(())
}

pub fn content_items_to_text(content: &[ContentItem]) -> Option<String> {
    let mut pieces = Vec::new();
    for item in content {
        match item {
            ContentItem::InputText { text } | ContentItem::OutputText { text } => {
                if !text.is_empty() {
                    pieces.push(text.as_str());
                }
            }
            ContentItem::InputImage { .. } => {}
        }
    }
    if pieces.is_empty() {
        None
    } else {
        Some(pieces.join("\n"))
    }
}

pub(crate) fn collect_user_messages(items: &[ResponseItem]) -> Vec<String> {
    items
        .iter()
        .filter_map(|item| match crate::event_mapping::parse_turn_item(item) {
            Some(TurnItem::UserMessage(user)) => Some(user.message()),
            _ => None,
        })
        .collect()
}

pub(crate) fn collect_recent_artifact_refs(
    items: &[ResponseItem],
    previous_refs: Option<Vec<String>>,
) -> Option<Vec<String>> {
    const MAX_RECENT_ARTIFACT_REFS: usize = 5;

    let mut refs = Vec::new();
    let mut seen = HashSet::new();

    for item in items.iter().rev() {
        collect_artifact_refs_from_response_item(item, &mut refs, &mut seen, MAX_RECENT_ARTIFACT_REFS);
        if refs.len() >= MAX_RECENT_ARTIFACT_REFS {
            break;
        }
    }

    if refs.len() < MAX_RECENT_ARTIFACT_REFS
        && let Some(previous_refs) = previous_refs
    {
        for reference in previous_refs.into_iter().rev() {
            push_recent_artifact_ref(&reference, &mut refs, &mut seen, MAX_RECENT_ARTIFACT_REFS);
            if refs.len() >= MAX_RECENT_ARTIFACT_REFS {
                break;
            }
        }
    }

    refs.reverse();
    (!refs.is_empty()).then_some(refs)
}

fn collect_artifact_refs_from_response_item(
    item: &ResponseItem,
    refs: &mut Vec<String>,
    seen: &mut HashSet<String>,
    limit: usize,
) {
    match item {
        ResponseItem::FunctionCall {
            name, arguments, ..
        } => {
            collect_artifact_refs_from_function_call(name, arguments, refs, seen, limit);
        }
        _ => {}
    }
}

fn collect_artifact_refs_from_function_call(
    _name: &str,
    arguments: &str,
    refs: &mut Vec<String>,
    seen: &mut HashSet<String>,
    limit: usize,
) {
    if let Ok(value) = serde_json::from_str::<serde_json::Value>(arguments) {
        for key in ["file_path", "notebook_path", "path"] {
            if let Some(path) = value.get(key).and_then(serde_json::Value::as_str) {
                push_recent_artifact_ref(path, refs, seen, limit);
                if refs.len() >= limit {
                    break;
                }
            }
        }
    }
}

fn push_recent_artifact_ref(
    value: impl AsRef<str>,
    refs: &mut Vec<String>,
    seen: &mut HashSet<String>,
    limit: usize,
) {
    if refs.len() >= limit {
        return;
    }
    let normalized = normalize_recent_artifact_ref(value.as_ref());
    if let Some(normalized) = normalized
        && seen.insert(normalized.clone())
    {
        refs.push(normalized);
    }
}

fn normalize_recent_artifact_ref(value: &str) -> Option<String> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return None;
    }
    let path = Path::new(trimmed);
    let normalized = path.to_string_lossy().replace('\\', "/");
    if normalized.is_empty() {
        None
    } else {
        Some(normalized)
    }
}

pub(crate) fn is_summary_message(message: &str) -> bool {
    message.starts_with(format!("{SUMMARY_PREFIX}\n").as_str())
}

fn approx_content_item_token_count(items: &[FunctionCallOutputContentItem]) -> usize {
    items.iter().fold(0usize, |acc, item| match item {
        FunctionCallOutputContentItem::InputText { text } => {
            acc.saturating_add(approx_token_count(text))
        }
        FunctionCallOutputContentItem::InputImage { .. } => acc,
    })
}

fn compact_function_output_text(
    text: &str,
    tool_name: Option<&str>,
    policy: TruncationPolicy,
) -> Option<String> {
    match tool_name {
        Some("apply_patch") => compact_apply_patch_output(text, policy),
        _ => None,
    }
    .or_else(|| compact_json_output(text, policy))
}

fn truncate_payload(
    body: &mut FunctionCallOutputBody,
    policy: &TruncationPolicy,
    tool_name: Option<&str>,
) -> i64 {
    match body {
        FunctionCallOutputBody::Text(text) => {
            let original_tokens = approx_token_count(text);
            let truncated = compact_function_output_text(text, tool_name, *policy)
                .unwrap_or_else(|| truncate_text(text, *policy));
            if truncated.len() < text.len() {
                let truncated_tokens = approx_token_count(&truncated);
                *text = truncated;
                original_tokens.saturating_sub(truncated_tokens) as i64
            } else {
                0
            }
        }
        FunctionCallOutputBody::ContentItems(items) => {
            let original_tokens = approx_content_item_token_count(items);
            let truncated = truncate_function_output_items_with_policy(items, *policy);
            if truncated != *items {
                let truncated_tokens = approx_content_item_token_count(&truncated);
                *items = truncated;
                original_tokens.saturating_sub(truncated_tokens) as i64
            } else {
                0
            }
        }
    }
}

fn truncate_tool_search_tools(
    tools: &mut Vec<serde_json::Value>,
    policy: &TruncationPolicy,
) -> i64 {
    let original = match serde_json::to_string(tools) {
        Ok(serialized) => serialized,
        Err(_) => return 0,
    };
    let truncated = truncate_text(&original, *policy);
    if truncated.len() >= original.len() {
        return 0;
    }
    let original_tokens = approx_token_count(&original);
    let compacted_tools = vec![build_tool_search_compaction_summary(tools)];
    let compacted = serde_json::to_string(&compacted_tools).unwrap_or_default();
    *tools = compacted_tools;
    original_tokens.saturating_sub(approx_token_count(&compacted)) as i64
}

fn build_tool_search_compaction_summary(tools: &[serde_json::Value]) -> serde_json::Value {
    let preview_names = tools
        .iter()
        .filter_map(tool_search_preview_name)
        .take(3)
        .collect::<Vec<String>>();
    serde_json::json!({
        "type": "tool_search_compacted",
        "compacted": true,
        "tool_count": tools.len(),
        "preview_names": preview_names,
    })
}

struct LocalShellOutputContext {
    command: Vec<String>,
    working_directory: Option<String>,
}

fn truncate_local_shell_output_payload(
    output: &mut FunctionCallOutputPayload,
    call_id: &str,
    context: &LocalShellOutputContext,
    policy: &TruncationPolicy,
) -> i64 {
    let Some(raw) = output.text_content() else {
        return truncate_payload(&mut output.body, policy, Some("local_shell"));
    };
    let Some(compacted) = compact_local_shell_output(
        raw,
        LocalShellOutputCompactionContext {
            call_id,
            command: &context.command,
            working_directory: context.working_directory.as_deref(),
        },
        *policy,
    ) else {
        return truncate_payload(&mut output.body, policy, Some("local_shell"));
    };

    let original_tokens = approx_token_count(raw);
    let compacted_tokens = approx_token_count(&compacted);
    output.body = FunctionCallOutputBody::Text(compacted);
    original_tokens.saturating_sub(compacted_tokens) as i64
}

fn truncate_web_search_call_action(action: &mut WebSearchAction, policy: &TruncationPolicy) -> i64 {
    let original = match serde_json::to_string(action) {
        Ok(serialized) => serialized,
        Err(_) => return 0,
    };
    let Some(compacted) = compact_web_search_action(action, *policy) else {
        return 0;
    };
    let compacted_serialized = match serde_json::to_string(&compacted) {
        Ok(serialized) => serialized,
        Err(_) => return 0,
    };
    let original_tokens = approx_token_count(&original);
    *action = compacted;
    original_tokens.saturating_sub(approx_token_count(&compacted_serialized)) as i64
}

fn tool_search_preview_name(tool: &serde_json::Value) -> Option<String> {
    let object = tool.as_object()?;
    for key in ["name", "title", "id"] {
        if let Some(value) = object.get(key).and_then(serde_json::Value::as_str) {
            if !value.trim().is_empty() {
                return Some(value.to_string());
            }
        }
    }
    let function = object.get("function")?.as_object()?;
    for key in ["name", "title", "id"] {
        if let Some(value) = function.get(key).and_then(serde_json::Value::as_str) {
            if !value.trim().is_empty() {
                return Some(value.to_string());
            }
        }
    }
    None
}

fn pre_compress_tool_outputs(
    items: &mut [ResponseItem],
    max_tokens: usize,
) -> PreCompressedToolOutputStats {
    let policy = TruncationPolicy::Tokens(max_tokens);
    let mut stats = PreCompressedToolOutputStats::default();
    let mut local_shell_calls: HashMap<String, LocalShellOutputContext> = HashMap::new();
    let mut function_tool_names: HashMap<String, String> = HashMap::new();
    let mut custom_tool_names: HashMap<String, String> = HashMap::new();
    for item in items.iter_mut() {
        let saved_tokens = match item {
            ResponseItem::LocalShellCall {
                call_id: Some(call_id),
                action: LocalShellAction::Exec(exec),
                ..
            } => {
                local_shell_calls.insert(
                    call_id.clone(),
                    LocalShellOutputContext {
                        command: exec.command.clone(),
                        working_directory: exec.working_directory.clone(),
                    },
                );
                0
            }
            ResponseItem::FunctionCall {
                call_id, name, ..
            } => {
                function_tool_names.insert(call_id.clone(), name.clone());
                0
            }
            ResponseItem::CustomToolCall { call_id, name, .. } => {
                custom_tool_names.insert(call_id.clone(), name.clone());
                0
            }
            ResponseItem::FunctionCallOutput { call_id, output } => {
                if let Some(context) = local_shell_calls.remove(call_id) {
                    truncate_local_shell_output_payload(output, call_id, &context, &policy)
                } else {
                    let tool_name = function_tool_names.remove(call_id);
                    truncate_payload(&mut output.body, &policy, tool_name.as_deref())
                }
            }
            ResponseItem::CustomToolCallOutput {
                call_id,
                name,
                output,
            } => {
                let tool_name = name.clone().or_else(|| custom_tool_names.remove(call_id));
                truncate_payload(&mut output.body, &policy, tool_name.as_deref())
            }
            ResponseItem::ToolSearchOutput { tools, .. } => {
                truncate_tool_search_tools(tools, &policy)
            }
            ResponseItem::WebSearchCall {
                action: Some(action), ..
            } => truncate_web_search_call_action(action, &policy),
            _ => 0,
        };
        if saved_tokens > 0 {
            stats.item_count += 1;
            stats.saved_tokens = stats.saved_tokens.saturating_add(saved_tokens);
        }
    }
    stats
}

/// Inserts canonical initial context into compacted replacement history at the
/// model-expected boundary.
///
/// Placement rules:
/// - Prefer immediately before the last real user message.
/// - If no real user messages remain, insert before the compaction summary so
///   the summary stays last.
/// - If there are no user messages, insert before the last compaction item so
///   that item remains last (remote compaction may return only compaction items).
/// - If there are no user messages or compaction items, append the context.
pub(crate) fn insert_initial_context_before_last_real_user_or_summary(
    mut compacted_history: Vec<ResponseItem>,
    initial_context: Vec<ResponseItem>,
) -> Vec<ResponseItem> {
    let mut last_user_or_summary_index = None;
    let mut last_real_user_index = None;
    for (i, item) in compacted_history.iter().enumerate().rev() {
        let Some(TurnItem::UserMessage(user)) = crate::event_mapping::parse_turn_item(item) else {
            continue;
        };
        // Compaction summaries are encoded as user messages, so track both:
        // the last real user message (preferred insertion point) and the last
        // user-message-like item (fallback summary insertion point).
        last_user_or_summary_index.get_or_insert(i);
        if !is_summary_message(&user.message()) {
            last_real_user_index = Some(i);
            break;
        }
    }
    let last_compaction_index = compacted_history
        .iter()
        .enumerate()
        .rev()
        .find_map(|(i, item)| matches!(item, ResponseItem::Compaction { .. }).then_some(i));
    let insertion_index = last_real_user_index
        .or(last_user_or_summary_index)
        .or(last_compaction_index);

    // Re-inject canonical context from the current session since we stripped it
    // from the pre-compaction history. Prefer placing it before the last real
    // user message; if there is no real user message left, place it before the
    // summary or compaction item so the compaction item remains last.
    if let Some(insertion_index) = insertion_index {
        compacted_history.splice(insertion_index..insertion_index, initial_context);
    } else {
        compacted_history.extend(initial_context);
    }

    compacted_history
}

pub(crate) fn build_compacted_history(
    initial_context: Vec<ResponseItem>,
    user_messages: &[String],
    summary_text: &str,
) -> Vec<ResponseItem> {
    build_compacted_history_with_limit(
        initial_context,
        user_messages,
        summary_text,
        COMPACT_USER_MESSAGE_MAX_TOKENS,
    )
}

fn build_compacted_history_with_limit(
    mut history: Vec<ResponseItem>,
    user_messages: &[String],
    summary_text: &str,
    max_tokens: usize,
) -> Vec<ResponseItem> {
    let mut selected_messages: Vec<String> = Vec::new();
    if max_tokens > 0 {
        let mut remaining = max_tokens;
        for message in user_messages.iter().rev() {
            if remaining == 0 {
                break;
            }
            let tokens = approx_token_count(message);
            if tokens <= remaining {
                selected_messages.push(message.clone());
                remaining = remaining.saturating_sub(tokens);
            } else {
                let truncated = truncate_text(message, TruncationPolicy::Tokens(remaining));
                selected_messages.push(truncated);
                break;
            }
        }
        selected_messages.reverse();
    }

    for message in &selected_messages {
        history.push(ResponseItem::Message {
            id: None,
            role: "user".to_string(),
            content: vec![ContentItem::InputText {
                text: message.clone(),
            }],
            end_turn: None,
            phase: None,
        });
    }

    let summary_text = if summary_text.is_empty() {
        "(no summary available)".to_string()
    } else {
        summary_text.to_string()
    };

    history.push(ResponseItem::Message {
        id: None,
        role: "user".to_string(),
        content: vec![ContentItem::InputText { text: summary_text }],
        end_turn: None,
        phase: None,
    });

    history
}

async fn drain_to_completed(
    sess: &Session,
    turn_context: &TurnContext,
    client_session: &mut ModelClientSession,
    turn_metadata_header: Option<&str>,
    prompt: &Prompt,
) -> CodexResult<()> {
    let mut stream = client_session
        .stream(
            prompt,
            &turn_context.model_info,
            &turn_context.session_telemetry,
            turn_context.reasoning_effort,
            turn_context.reasoning_summary,
            turn_context.config.service_tier,
            turn_metadata_header,
        )
        .await?;
    loop {
        let maybe_event = stream.next().await;
        let Some(event) = maybe_event else {
            return Err(CodexErr::Stream(
                "stream closed before response.completed".into(),
                None,
            ));
        };
        match event {
            Ok(ResponseEvent::OutputItemDone(item)) => {
                sess.record_into_history(std::slice::from_ref(&item), turn_context)
                    .await;
            }
            Ok(ResponseEvent::ServerReasoningIncluded(included)) => {
                sess.set_server_reasoning_included(included).await;
            }
            Ok(ResponseEvent::RateLimits(snapshot)) => {
                sess.update_rate_limits(turn_context, snapshot).await;
            }
            Ok(ResponseEvent::Completed { token_usage, .. }) => {
                sess.update_token_usage_info(turn_context, token_usage.as_ref())
                    .await;
                return Ok(());
            }
            Ok(_) => continue,
            Err(e) => return Err(e),
        }
    }
}

#[cfg(test)]
#[path = "compact_tests.rs"]
mod tests;
