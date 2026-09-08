#!/usr/bin/env python3
"""Deterministic RPC fixture for controlled DETAILS acceptance."""

from datetime import datetime, timezone
import json
import os
import sys
import time


ROOT = "/tmp/10x-session-recovery-home"
PROJECT_PATH = f"{ROOT}/projects/details"
BUCKET_PATH = f"{ROOT}/.omp/agent/sessions/-projects-details"
SESSION_PATH = f"{BUCKET_PATH}/details-control.jsonl"
CHILD_PATH = f"{BUCKET_PATH}/details-control/details-child.jsonl"
CONTROL_PATH = f"{ROOT}/fixtures/details-control.jsonl"
SESSION_ID = "details-control"
CHILD_SESSION_ID = "details-child"
USER_ID = "details-user-1"
ASSISTANT_ID = "details-assistant-1"
BASH_TOOL_ID = "details-bash-1"
TASK_TOOL_ID = "details-task-1"
SUBAGENT_ID = "details-child-agent"
BASH_COMMAND = "for i in $(seq 1 45); do printf 'DETAILS line %02d\\n' \"$i\"; sleep 1; done"


def now_milliseconds():
    return int(time.time() * 1000)


def allowlisted_session_path(path):
    if not isinstance(path, str) or not path:
        return None
    candidate = os.path.realpath(path)
    for allowed in (SESSION_PATH, CHILD_PATH):
        if candidate == os.path.realpath(allowed):
            return allowed
    return None


def resume_path_from_arguments(arguments):
    for index, argument in enumerate(arguments):
        if argument != "-r":
            continue
        if index + 1 >= len(arguments):
            return ""
        return arguments[index + 1]
    return None


def iso_timestamp(milliseconds):
    instant = datetime.fromtimestamp(milliseconds / 1000, tz=timezone.utc)
    return instant.isoformat(timespec="milliseconds").replace("+00:00", "Z")


def append_control(value):
    record = {"at": iso_timestamp(now_milliseconds()), **value}
    with open(CONTROL_PATH, "a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, separators=(",", ":")) + "\n")


def emit(value, control=None):
    print(json.dumps(value, separators=(",", ":")), flush=True)
    if control is not None:
        append_control(control)


def response(command, data=None, success=True, error=None):
    value = {
        "id": command.get("id"),
        "type": "response",
        "command": command.get("type", "unknown"),
        "success": success,
    }
    if data is not None:
        value["data"] = data
    if error is not None:
        value["error"] = error
    return value


def assistant_message(content, started_at, completed_at=None):
    message = {
        "id": ASSISTANT_ID,
        "role": "assistant",
        "content": content,
        "api": "test",
        "provider": "test",
        "model": "details-control",
        "timestamp": started_at,
        "usage": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0,
            "totalTokens": 0,
            "cost": {
                "input": 0,
                "output": 0,
                "cacheRead": 0,
                "cacheWrite": 0,
                "total": 0,
            },
        },
    }
    if completed_at is not None:
        message["stopReason"] = "stop"
        message["completedAt"] = completed_at
        message["duration"] = completed_at - started_at
        message["ttft"] = 50
    return message


def message_entry(entry_id, parent_id, message):
    return {
        "type": "message",
        "id": entry_id,
        "parentId": parent_id,
        "timestamp": iso_timestamp(message["timestamp"]),
        "message": message,
    }


def load_messages(path):
    messages = []
    try:
        with open(path, encoding="utf-8") as handle:
            for line in handle:
                try:
                    entry = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if entry.get("type") == "message" and isinstance(entry.get("message"), dict):
                    messages.append(entry["message"])
    except FileNotFoundError:
        pass
    return messages


def write_jsonl(path, entries):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    temporary_path = path + ".tmp"
    with open(temporary_path, "w", encoding="utf-8") as handle:
        for entry in entries:
            handle.write(json.dumps(entry, separators=(",", ":")) + "\n")
    os.replace(temporary_path, path)


def write_child_transcript(created_at):
    child_user = {
        "id": "details-child-user",
        "role": "user",
        "content": [{"type": "text", "text": "Inspect the controlled DETAILS child session."}],
        "attribution": "user",
        "timestamp": created_at,
    }
    child_assistant = {
        "id": "details-child-assistant",
        "role": "assistant",
        "content": [{"type": "text", "text": "The reported child session opened successfully."}],
        "api": "test",
        "provider": "test",
        "model": "details-child",
        "timestamp": created_at + 1000,
        "completedAt": created_at + 1500,
        "duration": 500,
        "stopReason": "stop",
    }
    write_jsonl(CHILD_PATH, [
        {
            "type": "session",
            "version": 3,
            "id": CHILD_SESSION_ID,
            "timestamp": iso_timestamp(created_at),
            "cwd": PROJECT_PATH,
            "title": "DETAILS child acceptance",
            "parentSession": SESSION_PATH,
        },
        message_entry("details-child-entry-1", None, child_user),
        message_entry("details-child-entry-2", "details-child-entry-1", child_assistant),
    ])


def subagent_result():
    return {
        "content": [{"type": "text", "text": "Controlled child inspection completed."}],
        "details": {
            "results": [{
                "index": 0,
                "id": SUBAGENT_ID,
                "agent": "worker",
                "task": "Inspect DETAILS child",
                "description": "Inspect the controlled DETAILS child transcript",
                "output": "Controlled child inspection completed.",
                "exitCode": 0,
                "durationMs": 1800,
                "tokens": 120,
                "requests": 1,
                "toolCount": 3,
                "resolvedModel": "test/details-child:low",
                "modelRole": "fast",
                "sessionFile": CHILD_PATH,
            }],
        },
    }


def persist_parent(
        user_message, assistant, started_at, tool_started_at,
        bash_result=None, task_result=None):
    custom_start = {
        "type": "custom",
        "customType": "tool_execution_start",
        "data": {
            "toolCallId": BASH_TOOL_ID,
            "toolName": "bash",
            "startedAt": iso_timestamp(tool_started_at),
            "args": {"command": BASH_COMMAND},
        },
        "id": "details-tool-start-entry",
        "parentId": "details-user-entry",
        "timestamp": iso_timestamp(tool_started_at),
    }
    entries = [
        {
            "type": "session",
            "version": 3,
            "id": SESSION_ID,
            "timestamp": iso_timestamp(started_at),
            "cwd": PROJECT_PATH,
            "title": "DETAILS controlled acceptance",
        },
        message_entry("details-user-entry", None, user_message),
        custom_start,
        message_entry("details-assistant-entry", "details-tool-start-entry", assistant),
    ]
    if bash_result is not None:
        entries.append(message_entry(
            "details-bash-result-entry", "details-assistant-entry", bash_result))
    if task_result is not None:
        entries.append(message_entry(
            "details-task-result-entry", "details-bash-result-entry", task_result))
    write_jsonl(SESSION_PATH, entries)


def run_turn(command):
    emit(response(command, {"agentInvoked": True}))
    started_at = now_milliseconds()
    prompt = command.get("message") or "Run the controlled DETAILS fixture."
    user_message = {
        "id": USER_ID,
        "role": "user",
        "content": [{"type": "text", "text": prompt}],
        "attribution": "user",
        "timestamp": started_at,
    }
    bash_call = {
        "type": "toolCall",
        "id": BASH_TOOL_ID,
        "name": "bash",
        "arguments": {"command": BASH_COMMAND},
    }
    task_call = {
        "type": "toolCall",
        "id": TASK_TOOL_ID,
        "name": "task",
        "arguments": {"task": "Inspect the controlled DETAILS child transcript"},
    }
    running_content = [
        {"type": "text", "text": "Streaming a controlled long command and child report."},
        bash_call,
        task_call,
    ]

    emit({"type": "turn_start"})
    emit({"type": "message_start", "message": user_message})
    emit({"type": "message_end", "message": user_message})
    emit({"type": "agent_start"})
    emit({"type": "message_start", "message": assistant_message([], started_at)})
    emit({"type": "message_update", "message": assistant_message(running_content, started_at)})

    tool_started_at = now_milliseconds()
    persist_parent(
        user_message,
        assistant_message(running_content, started_at),
        started_at,
        tool_started_at,
    )
    emit({
        "type": "tool_execution_start",
        "toolCallId": BASH_TOOL_ID,
        "toolName": "bash",
        "args": bash_call["arguments"],
    }, control={"direction": "event", "type": "tool_execution_start",
                "toolCallId": BASH_TOOL_ID, "startedAt": iso_timestamp(tool_started_at)})

    child_recent_tools = [
        {"tool": "read", "args": {"path": f"{PROJECT_PATH}/README.md"}, "endMs": 600},
        {"tool": "grep", "args": {"query": "DETAILS marker"}, "endMs": 1200},
        {"tool": "bash", "args": {"command": "printf 'child complete\\n'"}, "endMs": 1800},
    ]
    output_lines = []
    for line_number in range(1, 46):
        output_lines.append(f"DETAILS line {line_number:02d}")
        cumulative_output = "\n".join(output_lines)
        emit({
            "type": "tool_execution_update",
            "toolCallId": BASH_TOOL_ID,
            "toolName": "bash",
            "args": bash_call["arguments"],
            "partialResult": {
                "content": [{"type": "text", "text": cumulative_output}],
            },
        }, control={"direction": "event", "type": "tool_execution_update",
                    "lineCount": line_number, "cumulativeBytes": len(cumulative_output)})

        if line_number == 3:
            emit({
                "type": "subagent_lifecycle",
                "payload": {
                    "id": SUBAGENT_ID,
                    "agent": "worker",
                    "description": "Inspect the controlled DETAILS child transcript",
                    "status": "started",
                    "sessionFile": CHILD_PATH,
                    "parentToolCallId": TASK_TOOL_ID,
                    "index": 0,
                },
            })
        if line_number in {5, 20, 40}:
            emit({
                "type": "subagent_progress",
                "payload": {
                    "index": 0,
                    "agent": "worker",
                    "task": "Inspect DETAILS child",
                    "assignment": "Validate the reported child transcript",
                    "parentToolCallId": TASK_TOOL_ID,
                    "sessionFile": CHILD_PATH,
                    "progress": {
                        "id": SUBAGENT_ID,
                        "status": "running",
                        "durationMs": line_number * 1000,
                        "resolvedModel": "test/details-child:low",
                        "modelRole": "fast",
                        "currentTool": "bash",
                        "recentTools": child_recent_tools,
                        "recentOutput": [
                            "Read the fixture marker.",
                            "Matched the DETAILS marker.",
                            f"Observed parent output through line {line_number:02d}.",
                        ],
                        "toolCount": 3,
                        "tokens": 120,
                        "requests": 1,
                        "cost": 0,
                    },
                },
            })
        time.sleep(1.0)

    completed_at = now_milliseconds()
    final_output = "\n".join(output_lines)
    bash_result_payload = {
        "content": [{"type": "text", "text": final_output}],
        "details": {"wallTimeMs": completed_at - tool_started_at},
    }
    emit({
        "type": "tool_execution_end",
        "toolCallId": BASH_TOOL_ID,
        "toolName": "bash",
        "result": bash_result_payload,
        "isError": False,
    }, control={"direction": "event", "type": "tool_execution_end",
                "toolCallId": BASH_TOOL_ID, "lineCount": len(output_lines),
                "elapsedMs": completed_at - tool_started_at})
    emit({
        "type": "subagent_lifecycle",
        "payload": {
            "id": SUBAGENT_ID,
            "agent": "worker",
            "description": "Inspect the controlled DETAILS child transcript",
            "status": "completed",
            "sessionFile": CHILD_PATH,
            "parentToolCallId": TASK_TOOL_ID,
            "index": 0,
        },
    })
    task_result_payload = subagent_result()
    emit({
        "type": "tool_execution_end",
        "toolCallId": TASK_TOOL_ID,
        "toolName": "task",
        "result": task_result_payload,
        "isError": False,
    })

    final_content = running_content + [{
        "type": "text",
        "text": "The controlled long command and child report completed.",
    }]
    final_assistant = assistant_message(final_content, started_at, completed_at)
    bash_result = {
        "id": "details-bash-result",
        "role": "toolResult",
        "toolCallId": BASH_TOOL_ID,
        "toolName": "bash",
        **bash_result_payload,
        "isError": False,
        "timestamp": completed_at,
    }
    task_result = {
        "id": "details-task-result",
        "role": "toolResult",
        "toolCallId": TASK_TOOL_ID,
        "toolName": "task",
        **task_result_payload,
        "isError": False,
        "timestamp": completed_at,
    }
    persist_parent(
        user_message,
        final_assistant,
        started_at,
        tool_started_at,
        bash_result,
        task_result,
    )
    messages = [user_message, final_assistant, bash_result, task_result]
    emit({"type": "message_update", "message": final_assistant})
    emit({"type": "message_end", "message": final_assistant})
    emit({"type": "agent_end", "messages": messages, "isTerminal": True})
    emit({"type": "turn_end"}, control={"direction": "event", "type": "turn_end",
                                          "elapsedMs": completed_at - started_at})
    return messages


os.makedirs(BUCKET_PATH, exist_ok=True)
os.makedirs(PROJECT_PATH, exist_ok=True)
os.makedirs(os.path.dirname(CONTROL_PATH), exist_ok=True)
if not os.path.exists(f"{PROJECT_PATH}/README.md"):
    with open(f"{PROJECT_PATH}/README.md", "w", encoding="utf-8") as handle:
        handle.write("DETAILS marker for controlled acceptance.\n")
write_child_transcript(now_milliseconds())

reported_resume_path = resume_path_from_arguments(sys.argv[1:])
if reported_resume_path is None:
    active_path = SESSION_PATH
else:
    active_path = allowlisted_session_path(reported_resume_path)
    if active_path is None:
        sys.stderr.write("DETAILS fixture rejected an unknown resume path.\n")
        raise SystemExit(2)
messages = load_messages(active_path)
is_streaming = False

emit({
    "type": "ready",
    "protocolVersion": 1,
    "supportedProtocolVersions": [1, 2],
    "maxFrameBytes": 1048576,
    "maxReassembledFrameBytes": 67108864,
})

for line in sys.stdin:
    try:
        command = json.loads(line)
    except json.JSONDecodeError:
        emit({"type": "response", "command": "parse", "success": False,
              "error": "malformed input"})
        continue
    kind = command.get("type")
    append_control({"direction": "command", "type": kind, "id": command.get("id")})
    if kind == "negotiate_protocol":
        emit(response(command, {"protocolVersion": 2}))
    elif kind == "switch_session":
        reported_path = command.get("sessionPath") or command.get("path")
        selected_path = allowlisted_session_path(reported_path)
        if selected_path is None:
            emit(response(command, success=False, error="unknown controlled session"))
            continue
        active_path = selected_path
        messages = load_messages(active_path)
        emit(response(command))
    elif kind == "get_state":
        is_child = active_path == CHILD_PATH
        emit(response(command, {
            "model": {"id": "details-control", "provider": "test", "name": "DETAILS Control"},
            "thinkingLevel": "medium",
            "isStreaming": is_streaming,
            "sessionId": CHILD_SESSION_ID if is_child else SESSION_ID,
            "sessionName": "DETAILS child acceptance" if is_child else "DETAILS controlled acceptance",
            "sessionFile": active_path,
            "contextUsage": {"tokens": 0, "contextWindow": 200000, "percent": 0},
            "queuedMessageCount": 0,
        }))
    elif kind in {"get_messages", "get_messages_page"}:
        data = {"messages": list(messages)}
        if kind == "get_messages_page":
            data["nextCursor"] = None
        emit(response(command, data))
    elif kind == "get_available_commands":
        emit(response(command, {"commands": []}))
    elif kind == "get_available_models":
        emit(response(command, {"models": []}))
    elif kind == "set_subagent_subscription":
        emit(response(command, {"level": command.get("level", "progress")}))
    elif kind == "prompt":
        if active_path != SESSION_PATH:
            emit(response(command, success=False, error="child fixture is read-only"))
        elif messages:
            emit(response(command, success=False, error="fixture turn already completed"))
        else:
            is_streaming = True
            messages = run_turn(command)
            is_streaming = False
    elif kind == "abort":
        emit(response(command))
    else:
        emit(response(command, {}))
