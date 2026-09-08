#!/usr/bin/env python3
"""Controlled RPC fixture for intentional Stop and Restart lifecycle tests."""

import json
import os
import subprocess
import sys
import threading
import time


control_directory = sys.argv[1]
session_path = sys.argv[2]
write_lock = threading.Lock()


def marker(name):
    return os.path.join(control_directory, name)


def touch(name):
    open(marker(name), "w", encoding="utf-8").close()


def emit(value):
    with write_lock:
        sys.stdout.write(json.dumps(value, separators=(",", ":")) + "\n")
        sys.stdout.flush()


def late_events():
    while not os.path.exists(marker("emit-late")):
        time.sleep(0.001)
    emit({"type": "agent_start"})
    emit({
        "type": "message_end",
        "message": {
            "id": "late-revival",
            "role": "assistant",
            "content": [{"type": "text", "text": "Late work revived"}],
            "stopReason": "stop",
        },
    })
    emit({
        "type": "tool_execution_end",
        "toolCallId": "running-tool",
        "toolName": "bash",
        "result": {"content": [{"type": "text", "text": "late result"}]},
        "isError": False,
    })
    emit({"type": "agent_end", "messages": [], "isTerminal": True})
    touch("late-emitted")


heartbeat_path = marker("child-heartbeat")
child = subprocess.Popen([
    sys.executable,
    "-u",
    "-c",
    """
import os, sys, time
with open(sys.argv[1], "a", encoding="utf-8") as handle:
    handle.write(str(os.getpid()) + "\\n")
while True:
    with open(sys.argv[2], "ab") as handle:
        handle.write(b"x")
    time.sleep(0.01)
""",
    marker("child-pids"),
    heartbeat_path,
])

emit({
    "type": "ready",
    "protocolVersion": 1,
    "supportedProtocolVersions": [1, 2],
    "maxFrameBytes": 1048576,
    "maxReassembledFrameBytes": 67108864,
})

for raw_line in sys.stdin:
    command = json.loads(raw_line)
    command_id = command.get("id")
    command_type = command.get("type")
    with open(marker("commands"), "a", encoding="utf-8") as log:
        log.write((command_type or "unknown") + "\n")

    if command_type == "negotiate_protocol":
        emit({
            "id": command_id,
            "type": "response",
            "command": command_type,
            "success": True,
            "data": {"protocolVersion": 2},
        })
    elif command_type == "get_state":
        emit({
            "id": command_id,
            "type": "response",
            "command": command_type,
            "success": True,
            "data": {
                "model": {"id": "fake", "provider": "test"},
                "isStreaming": False,
                "queuedMessageCount": 3,
                "sessionId": "stop-fixture",
                "sessionFile": session_path,
            },
        })
    elif command_type == "get_messages_page":
        emit({
            "id": command_id,
            "type": "response",
            "command": command_type,
            "success": True,
            "data": {"messages": [], "nextCursor": None},
        })
    elif command_type == "prompt":
        emit({
            "id": command_id,
            "type": "response",
            "command": command_type,
            "success": True,
            "data": {"agentInvoked": True},
        })
        emit({"type": "agent_start"})
        emit({
            "type": "tool_execution_start",
            "toolCallId": "running-tool",
            "toolName": "bash",
            "args": {"command": "sleep 10"},
        })
        touch("prompt-started")
    elif command_type == "abort":
        emit({
            "id": command_id,
            "type": "response",
            "command": command_type,
            "success": True,
        })
        touch("abort-accepted")
        threading.Thread(target=late_events, daemon=True).start()
    else:
        emit({
            "id": command_id,
            "type": "response",
            "command": command_type or "unknown",
            "success": True,
            "data": {"commands": []} if command_type == "get_available_commands" else {},
        })

# Keep shutdown observable long enough for rapid Restart coverage.
time.sleep(0.4)
