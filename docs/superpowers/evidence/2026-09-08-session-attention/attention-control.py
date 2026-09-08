#!/usr/bin/env python3
"""Deterministic RPC fixture for pending-decision and Stop acceptance."""

from datetime import datetime, timezone
import json
import os
import signal
import sys
import threading
import time


ROOT = "/tmp/10x-session-recovery-home"
PROJECT_PATH = f"{ROOT}/projects/attention"
SESSION_PATH = f"{ROOT}/.omp/agent/sessions/-projects-attention/session.jsonl"
CONTROL_LOG = f"{ROOT}/fixtures/attention-control.jsonl"
SESSION_ID = "attention-acceptance-session"
TITLE = "Attention acceptance"
MODEL = {
    "id": "attention-fixture",
    "name": "Attention Fixture",
    "provider": "test",
    "api": "test",
    "thinking": {"efforts": ["low", "medium", "high"], "requiresEffort": False},
}
REQUESTS = (
    (
        12.0,
        {
            "type": "extension_ui_request",
            "id": "attention-confirm-1",
            "method": "confirm",
            "title": "Continue the acceptance turn?",
            "message": "Confirm this controlled fixture step.",
        },
    ),
    (
        14.0,
        {
            "type": "extension_ui_request",
            "id": "attention-select-1",
            "method": "select",
            "title": "Choose a fixture path",
            "options": ["Direct", "Reviewed"],
            "optionDetails": [
                {"description": "Continue directly"},
                {"description": "Record the reviewed path"},
            ],
        },
    ),
    (
        16.0,
        {
            "type": "extension_ui_request",
            "id": "attention-input-1",
            "method": "input",
            "title": "Add a fixture note",
            "placeholder": "Optional acceptance note",
        },
    ),
)


output_lock = threading.Lock()
state_lock = threading.Lock()
log_lock = threading.Lock()
stop_event = threading.Event()
turn_started_at = None
pending = {}
messages = []
is_streaming = False
turn_finished = False


def emit(value):
    with output_lock:
        print(json.dumps(value, separators=(",", ":")), flush=True)


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


def milliseconds():
    return int(time.time() * 1000)


def iso_timestamp(value):
    instant = datetime.fromtimestamp(value / 1000, tz=timezone.utc)
    return instant.isoformat(timespec="milliseconds").replace("+00:00", "Z")


def log_control(value):
    entry = {"at": iso_timestamp(milliseconds()), **value}
    with log_lock:
        with open(CONTROL_LOG, "a", encoding="utf-8") as handle:
            handle.write(json.dumps(entry, separators=(",", ":")) + "\n")


def history_entry(entry_id, parent_id, message):
    return {
        "type": "message",
        "id": entry_id,
        "parentId": parent_id,
        "timestamp": iso_timestamp(message["timestamp"]),
        "message": message,
    }


def usage():
    return {
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
    }


def assistant_message(message_id, text, timestamp, completed_at=None, stop_reason="stop"):
    value = {
        "id": message_id,
        "role": "assistant",
        "content": [{"type": "text", "text": text}],
        "api": "test",
        "provider": "test",
        "model": MODEL["id"],
        "timestamp": timestamp,
        "usage": usage(),
    }
    if completed_at is not None:
        value.update({
            "stopReason": stop_reason,
            "completedAt": completed_at,
            "duration": max(0, completed_at - timestamp),
            "ttft": 50,
        })
    return value


def initial_entries():
    base = 1_788_765_600_000
    entries = []
    parent_id = None
    for index in range(1, 13):
        user_time = base + index * 120_000
        assistant_time = user_time + 2_000
        user = {
            "id": f"attention-history-user-{index:02d}",
            "role": "user",
            "content": [{
                "type": "text",
                "text": (
                    f"Acceptance history item {index}. Keep this neutral transcript line "
                    "available for scroll-position checks."
                ),
            }],
            "attribution": "user",
            "timestamp": user_time,
        }
        user_entry_id = f"attention-entry-{index:02d}-user"
        entries.append(history_entry(user_entry_id, parent_id, user))
        assistant = assistant_message(
            f"attention-history-assistant-{index:02d}",
            (
                f"Recorded neutral acceptance history item {index}. This older response "
                "adds enough transcript height for deliberate scrolling."
            ),
            assistant_time,
            assistant_time + 1_000,
        )
        assistant_entry_id = f"attention-entry-{index:02d}-assistant"
        entries.append(history_entry(assistant_entry_id, user_entry_id, assistant))
        parent_id = assistant_entry_id
    return entries


def write_session(message_entries):
    os.makedirs(os.path.dirname(SESSION_PATH), exist_ok=True)
    entries = [{
        "type": "session",
        "version": 3,
        "id": SESSION_ID,
        "timestamp": "2026-09-07T20:00:00.000Z",
        "cwd": PROJECT_PATH,
        "title": TITLE,
    }, *message_entries]
    temporary = SESSION_PATH + ".tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        for entry in entries:
            handle.write(json.dumps(entry, separators=(",", ":")) + "\n")
    os.replace(temporary, SESSION_PATH)


def load_messages():
    loaded = []
    try:
        with open(SESSION_PATH, encoding="utf-8") as handle:
            for line in handle:
                try:
                    entry = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if entry.get("type") == "message" and isinstance(entry.get("message"), dict):
                    loaded.append(entry["message"])
    except FileNotFoundError:
        pass
    return loaded


def reset_fixture():
    os.makedirs(PROJECT_PATH, exist_ok=True)
    os.makedirs(os.path.dirname(CONTROL_LOG), exist_ok=True)
    write_session(initial_entries())
    with open(CONTROL_LOG, "w", encoding="utf-8"):
        pass


def persist_current_messages():
    entries = []
    parent_id = None
    for index, message in enumerate(messages, start=1):
        entry_id = f"attention-runtime-entry-{index:03d}"
        entries.append(history_entry(entry_id, parent_id, message))
        parent_id = entry_id
    write_session(entries)


def finish_turn(stop_reason="stop"):
    global is_streaming, turn_finished
    with state_lock:
        if turn_finished or not is_streaming:
            return
        turn_finished = True
        is_streaming = False
        completed_at = milliseconds()
        assistant = messages[-1]
        final_text = (
            "Fixture decisions resolved. The controlled turn is complete."
            if stop_reason == "stop"
            else "Fixture turn stopped while decisions were pending."
        )
        final_assistant = assistant_message(
            assistant["id"], final_text, assistant["timestamp"], completed_at, stop_reason)
        messages[-1] = final_assistant
        snapshot = list(messages)
        persist_current_messages()
    emit({"type": "message_update", "message": final_assistant})
    emit({"type": "message_end", "message": final_assistant})
    emit({"type": "agent_end", "messages": snapshot, "isTerminal": True})
    emit({"type": "turn_end"})
    log_control({"direction": "event", "type": "turn_end", "stopReason": stop_reason})


def run_timeline(started_at):
    for delay, request in REQUESTS:
        remaining = delay - (time.monotonic() - started_at)
        if remaining > 0 and stop_event.wait(remaining):
            return
        with state_lock:
            if not is_streaming or turn_finished:
                return
            pending[request["id"]] = request["method"]
        emit(request)
        log_control({
            "direction": "event",
            "type": "extension_ui_request",
            "id": request["id"],
            "method": request["method"],
            "elapsedMs": int((time.monotonic() - started_at) * 1000),
        })


def start_turn(command):
    global is_streaming, turn_finished, turn_started_at
    with state_lock:
        if is_streaming or turn_finished:
            return False
        is_streaming = True
        turn_finished = False
        turn_started_at = time.monotonic()
        timestamp = milliseconds()
        prompt_text = command.get("message") if isinstance(command.get("message"), str) else ""
        user = {
            "id": "attention-live-user-1",
            "role": "user",
            "content": [{"type": "text", "text": prompt_text}],
            "attribution": "user",
            "timestamp": timestamp,
        }
        assistant = assistant_message(
            "attention-live-assistant-1",
            "Waiting for three controlled fixture decisions.",
            timestamp + 1,
        )
        messages.extend([user, assistant])
        persist_current_messages()
    emit(response(command, {"agentInvoked": True}))
    emit({"type": "turn_start"})
    emit({"type": "message_start", "message": user})
    emit({"type": "message_end", "message": user})
    emit({"type": "agent_start"})
    emit({"type": "message_start", "message": assistant})
    emit({"type": "message_update", "message": assistant})
    threading.Thread(target=run_timeline, args=(turn_started_at,), daemon=True).start()
    return True


def sanitize_response(command):
    result = {}
    for key in ("confirmed", "cancelled", "timedOut"):
        if isinstance(command.get(key), bool):
            result[key] = command[key]
    if isinstance(command.get("value"), str):
        result["hasValue"] = True
        result["valueLength"] = len(command["value"])
    return result


def handle_extension_response(command):
    request_id = command.get("id")
    with state_lock:
        method = pending.pop(request_id, None)
        remaining = list(pending)
        should_finish = method is not None and not remaining and len(pending) == 0
        all_emitted = all(delay <= (time.monotonic() - turn_started_at) for delay, _ in REQUESTS) \
            if turn_started_at is not None else False
    log_control({
        "direction": "command",
        "type": "extension_ui_response",
        "id": request_id,
        "matchedMethod": method,
        "body": sanitize_response(command),
    })
    if should_finish and all_emitted:
        finish_turn()


def abort_turn(command):
    with state_lock:
        active = is_streaming and not turn_finished
        request_ids = list(pending)
        pending.clear()
    log_control({
        "direction": "command",
        "type": "abort",
        "id": command.get("id"),
        "wasStreaming": active,
        "pendingIds": request_ids,
    })
    emit(response(command, {}))
    if not active:
        return
    stop_event.set()
    for index, request_id in enumerate(request_ids, start=1):
        emit({
            "type": "extension_ui_request",
            "id": f"attention-cancel-{index}",
            "method": "cancel",
            "targetId": request_id,
        })
    finish_turn("aborted")


def state_data():
    with state_lock:
        streaming = is_streaming
        pending_count = len(pending)
    return {
        "model": MODEL,
        "thinkingLevel": "medium",
        "fastModeEnabled": False,
        "fastModeActive": False,
        "isStreaming": streaming,
        "sessionId": SESSION_ID,
        "sessionName": TITLE,
        "sessionFile": SESSION_PATH,
        "contextUsage": {"tokens": 2400, "contextWindow": 200000, "percent": 1.2},
        "queuedMessageCount": 0,
        "pendingRequestCount": pending_count,
    }


def main():
    global messages
    if "--reset" in sys.argv:
        reset_fixture()
        return 0
    if not os.path.exists(SESSION_PATH):
        reset_fixture()
    messages = load_messages()
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
            emit({"type": "response", "command": "parse", "success": False, "error": "malformed input"})
            continue
        kind = command.get("type")
        if kind not in {"extension_ui_response", "abort"}:
            entry = {"direction": "command", "type": kind, "id": command.get("id")}
            if kind == "prompt":
                entry["messageLength"] = len(command.get("message", "")) \
                    if isinstance(command.get("message"), str) else 0
                entry["imageCount"] = len(command.get("images", [])) \
                    if isinstance(command.get("images"), list) else 0
            log_control(entry)
        if kind == "negotiate_protocol":
            emit(response(command, {"protocolVersion": 2}))
        elif kind == "get_state":
            emit(response(command, state_data()))
        elif kind in {"get_messages", "get_messages_page"}:
            with state_lock:
                data = {"messages": list(messages)}
            if kind == "get_messages_page":
                data["nextCursor"] = None
            emit(response(command, data))
        elif kind == "get_available_commands":
            emit(response(command, {"commands": [{"name": "compact", "source": "builtin"}]}))
        elif kind == "get_available_models":
            emit(response(command, {"models": [MODEL]}))
        elif kind == "set_subagent_subscription":
            emit(response(command, {"level": command.get("level", "progress")}))
        elif kind == "prompt":
            if not start_turn(command):
                emit(response(command, success=False, error="fixture accepts one active turn"))
        elif kind == "extension_ui_response":
            handle_extension_response(command)
        elif kind == "abort":
            abort_turn(command)
        elif kind == "shutdown":
            stop_event.set()
            emit(response(command, {}))
            return 0
        else:
            emit(response(command, {}))
    stop_event.set()
    return 0


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, lambda _signum, _frame: stop_event.set())
    raise SystemExit(main())
