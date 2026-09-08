#!/usr/bin/env python3
import json
import os
import sys
import time


def emit(value):
    print(json.dumps(value), flush=True)


pid_file = os.environ.get("SESSION_MAP_FAKE_PID_FILE")
if pid_file:
    with open(pid_file, "w", encoding="utf-8") as handle:
        handle.write(str(os.getpid()))

configuration_file = os.environ.get("SESSION_MAP_FAKE_CONFIGURATION_FILE")
if configuration_file:
    with open(configuration_file, "w", encoding="utf-8") as handle:
        json.dump({"argv": sys.argv[1:], "cwd": os.getcwd()}, handle)

case = os.environ.get("SESSION_MAP_FAKE_CASE", "partial-final")
if case == "cancelled-startup":
    time.sleep(30)

emit({"type": "ready", "protocolVersion": 1})
for line in sys.stdin:
    request = json.loads(line)
    if request.get("type") != "prompt":
        continue
    if case == "timeout":
        emit({"type": "response", "id": request["id"], "command": "prompt", "success": True})
        time.sleep(30)
        continue
    if case == "eof":
        emit({"type": "response", "id": request["id"], "command": "prompt", "success": True})
        sys.exit(0)
    if case == "provider-error":
        emit({"type": "response", "id": request["id"], "command": "prompt", "success": True})
        emit({"type": "provider_error", "error": "fixture provider unavailable"})
        time.sleep(30)
        continue
    emit({"type": "message_update", "message": {
        "id": "writer", "role": "assistant",
        "content": [{"type": "text", "text": "<sessionmap headline=\"Partial map\" phase=\"planning\"><summary>Partial.</summary></sessionmap>"}]
    }})
    emit({"type": "response", "id": request["id"], "command": "prompt", "success": True})
    emit({"type": "agent_end", "isTerminal": False})
    final_text = "not xml" if case == "malformed-final" else "<sessionmap headline=\"Final map\" phase=\"planning\"><summary>Complete.</summary></sessionmap>"
    emit({"type": "message_end", "message": {
        "id": "writer", "role": "assistant",
        "content": [{"type": "text", "text": final_text}]
    }})
    emit({"type": "agent_end", "isTerminal": True})
    break
