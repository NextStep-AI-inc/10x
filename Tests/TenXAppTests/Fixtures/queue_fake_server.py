#!/usr/bin/env python3
"""Controlled queue fixture for SessionController integration tests."""

import json
import os
import sys


control_directory = sys.argv[1]
session_path = os.path.join(control_directory, "session.jsonl")
queue = []
messages = []
persisted_entries = [{
    "type": "message",
    "id": "persisted-older-user",
    "parentId": None,
    "timestamp": "2026-08-24T20:00:00.500Z",
    "message": {
        "role": "user",
        "content": [{"type": "text", "text": "Older unannotated message"}],
        "timestamp": 1787601600500,
    },
}]
next_message_id = 1
reject_next = False
defer_next_state = False
deferred_states = []
echo_before_next_ack = False
deferred_prompt_responses = []


def emit(value):
    print(json.dumps(value, separators=(",", ":")), flush=True)


def state(count):
    return {
        "model": {"id": "fake", "provider": "test", "name": "Fake"},
        "isStreaming": True,
        "sessionFile": session_path,
        "contextUsage": {"tokens": 1000, "contextWindow": 200000, "percent": 1},
        "queuedMessageCount": count,
    }


def response(command, data=None, success=True, error=None):
    value = {
        "id": command["id"],
        "type": "response",
        "command": command["type"],
        "success": success,
        "data": data or {},
    }
    if error is not None:
        value["error"] = error
    return value


def write_history():
    header = {
        "type": "session",
        "version": 3,
        "id": "queue-test",
        "timestamp": "2026-08-24T20:00:00.000Z",
        "cwd": control_directory,
    }
    with open(session_path, "w", encoding="utf-8") as handle:
        for entry in [header] + persisted_entries:
            handle.write(json.dumps(entry, separators=(",", ":")) + "\n")


def publish(item, persist):
    global next_message_id
    text = item["text"]
    timestamp = 1787601600000 + next_message_id * 1000
    message = {
        "id": f"user-{next_message_id}",
        "role": "user",
        "content": [{"type": "text", "text": text}],
        "timestamp": timestamp,
    }
    if persist:
        persisted_id = f"persisted-user-{next_message_id}"
        persisted_entries.append({
            "type": "message",
            "id": persisted_id,
            "parentId": persisted_entries[-1]["id"] if persisted_entries else None,
            "timestamp": f"2026-08-24T20:00:{next_message_id:02d}.000Z",
            "message": {
                "role": "user",
                "content": [{"type": "text", "text": text}],
                "timestamp": timestamp,
            },
        })
        write_history()
    next_message_id += 1
    messages.append(message)
    if persist:
        emit({"type": "turn_end"})
    # OMP removes the input after the prior turn ends and before the next
    # turn/user lifecycle begins.
    emit({"type": "turn_start"})
    emit({"type": "message_start", "message": message})
    emit({"type": "message_end", "message": message})


def consume():
    if not queue:
        raise RuntimeError("queue is empty")
    steer_index = next((index for index, item in enumerate(queue)
                        if item["behavior"] == "steer"), None)
    publish(queue.pop(steer_index if steer_index is not None else 0), persist=True)


emit({
    "type": "ready",
    "protocolVersion": 1,
    "supportedProtocolVersions": [1, 2],
    "maxFrameBytes": 1048576,
    "maxReassembledFrameBytes": 67108864,
})

for line in sys.stdin:
    command = json.loads(line)
    kind = command["type"]
    if kind == "negotiate_protocol":
        emit(response(command, {"protocolVersion": 2}))
    elif kind == "get_state":
        current = response(command, state(len(queue)))
        if defer_next_state:
            defer_next_state = False
            deferred_states.append(current)
            open(os.path.join(control_directory, "state-deferred"), "w").close()
        else:
            emit(current)
    elif kind in {"get_messages", "get_messages_page"}:
        data = {"messages": list(messages)}
        if kind == "get_messages_page":
            data["nextCursor"] = None
        emit(response(command, data))
    elif kind == "get_available_commands":
        emit(response(command, {"commands": []}))
    elif kind == "prompt":
        if reject_next:
            reject_next = False
            emit(response(command, success=False, error="controlled rejection"))
        else:
            queue.append({
                "text": command.get("message", ""),
                "behavior": command.get("streamingBehavior"),
            })
            if echo_before_next_ack:
                echo_before_next_ack = False
                publish(queue.pop(), persist=False)
                deferred_prompt_responses.append(response(command))
                open(os.path.join(control_directory, "echoed-before-ack"), "w").close()
            else:
                emit(response(command))
    elif kind == "queue_test_control":
        action = command.get("action")
        if action == "consume":
            consume()
        elif action == "reject-next":
            reject_next = True
        elif action == "defer-next-state":
            defer_next_state = True
        elif action == "release-deferred-state":
            for deferred in deferred_states:
                emit(deferred)
            deferred_states = []
        elif action == "echo-before-next-ack":
            echo_before_next_ack = True
        elif action == "release-prompt-ack":
            for deferred in deferred_prompt_responses:
                emit(deferred)
            deferred_prompt_responses = []
        else:
            emit(response(command, success=False, error=f"unknown action: {action}"))
            continue
        # For release, the old state is on the wire before the control ack.
        emit(response(command))
    else:
        emit(response(command))
