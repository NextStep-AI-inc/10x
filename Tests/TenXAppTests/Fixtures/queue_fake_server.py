#!/usr/bin/env python3
"""Controlled queue fixture for SessionController integration tests."""

import json
import os
import sys


control_directory = sys.argv[1]
session_path = os.path.join(control_directory, "session.jsonl")
queue = []
messages = []
next_message_id = 1
reject_next = False
defer_next_state = False
deferred_states = []


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


def consume():
    global next_message_id
    if not queue:
        raise RuntimeError("queue is empty")
    emit({"type": "turn_end"})
    text = queue.pop(0)["text"]
    message = {
        "id": f"user-{next_message_id}",
        "role": "user",
        "content": [{"type": "text", "text": text}],
    }
    next_message_id += 1
    messages.append(message)
    # OMP removes the input after the prior turn ends and before the next
    # turn/user lifecycle begins.
    emit({"type": "turn_start"})
    emit({"type": "message_start", "message": message})
    emit({"type": "message_end", "message": message})


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
        else:
            emit(response(command, success=False, error=f"unknown action: {action}"))
            continue
        # For release, the old state is on the wire before the control ack.
        emit(response(command))
    else:
        emit(response(command))
