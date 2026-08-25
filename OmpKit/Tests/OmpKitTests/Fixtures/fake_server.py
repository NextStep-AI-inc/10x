#!/usr/bin/env python3
"""Scripted omp RPC stand-in. Modes via argv[1]:
  basic     — ready, negotiate ok, echoes get_state with canned data
  chunked   — get_state answered as a 3-part rpc_chunk sequence
  late-error— prompt acked ok, then error response with the same id
  silent    — ready, then never answers anything (timeout testing)
  slow-exit — basic behavior, then waits briefly after stdin closes
  noisy     — like basic, but emits unknown frames + setWidget before each response
"""
import base64
import json
import subprocess
import sys
import time

mode = sys.argv[1] if len(sys.argv) > 1 else "basic"
W = sys.stdout


def emit(obj):
    # Compact separators match real omp output byte-for-byte.
    W.write(json.dumps(obj, separators=(",", ":")) + "\n")
    W.flush()


if mode == "never-ready":
    time.sleep(30)
    raise SystemExit(0)
if mode == "malformed-startup":
    W.write("not-json\n")
    W.flush()
    time.sleep(30)
    raise SystemExit(0)
if mode == "premature-chunk":
    emit({"type": "rpc_chunk", "chunkId": "rpc-1", "index": 0, "count": 2,
          "byteLength": 1048576, "data": "eA=="})
    time.sleep(30)
    raise SystemExit(0)

limits = 999999 if mode == "wrong-limits" else 1048576
emit({"type": "ready", "protocolVersion": 1, "supportedProtocolVersions": [1, 2],
      "maxFrameBytes": limits, "maxReassembledFrameBytes": 67108864})
if mode == "noisy":
    emit({"type": "available_commands_update", "commands": []})
    emit({"type": "extension_ui_request", "id": "w1", "method": "setWidget", "widgetKey": "x"})
if mode == "burst-exit":
    for index in range(200):
        emit({"type": "notice", "index": index})
    raise SystemExit(0)
if mode == "grandchild":
    heartbeat = sys.argv[2]
    child = """
import sys, time
path = sys.argv[1]
while True:
    with open(path, "ab") as handle:
        handle.write(b"x")
    time.sleep(0.02)
"""
    subprocess.Popen([sys.executable, "-u", "-c", child, heartbeat])

STATE = {"model": {"id": "fake", "provider": "test"}, "isStreaming": False,
         "sessionId": "fake-session", "sessionFile": "/tmp/fake.jsonl"}
reverse_commands = []

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        cmd = json.loads(line)
    except json.JSONDecodeError:
        emit({"type": "response", "command": "parse", "success": False, "error": "malformed"})
        continue
    cid, ctype = cmd.get("id"), cmd.get("type")
    if mode == "silent" and ctype != "negotiate_protocol":
        continue
    if ctype == "negotiate_protocol":
        if mode == "negotiation-fails":
            emit({"id": cid, "type": "response", "command": "negotiate_protocol",
                  "success": False, "error": "negotiation rejected"})
        else:
            emit({"id": cid, "type": "response", "command": "negotiate_protocol",
                  "success": True, "data": {"protocolVersion": 2}})
        if mode == "crash-after-negotiation":
            time.sleep(0.2)
            sys.stderr.write("crash-after-negotiation\n")
            sys.stderr.flush()
            raise SystemExit(7)
        continue
    if mode == "reverse":
        reverse_commands.append((cid, ctype))
        if len(reverse_commands) == 3:
            for response_id, response_type in reversed(reverse_commands):
                data = STATE if response_type == "get_state" else {}
                emit({"id": response_id, "type": "response", "command": response_type,
                      "success": True, "data": data})
        continue
    if mode == "parse-error":
        emit({"type": "response", "command": "parse", "success": False,
              "error": "malformed input"})
        continue
    if ctype == "idless_error":
        emit({"type": "response", "command": ctype, "success": False,
              "error": "idless failure"})
    elif ctype == "get_state":
        if mode == "noisy":
            emit({"type": "notice", "level": "info", "message": "before response", "source": "fake"})
        if mode == "chunked":
            large_state = {**STATE, "padding": "x" * 1048576}
            payload = json.dumps(
                {"id": cid, "type": "response", "command": "get_state",
                 "success": True, "data": large_state}, separators=(",", ":")).encode()
            size = 262144
            parts = [payload[i:i + size] for i in range(0, len(payload), size)]
            for i, part in enumerate(parts):
                emit({"type": "rpc_chunk", "chunkId": "rpc-1", "index": i, "count": len(parts),
                      "byteLength": len(payload), "data": base64.b64encode(part).decode()})
        elif mode == "eof-on-get-state":
            sys.stderr.write("eof-on-get-state\n")
            sys.stderr.flush()
            raise SystemExit(5)
        elif mode == "malformed-runtime":
            W.write("not-json\n")
            W.flush()
            time.sleep(30)
        elif mode == "invalid-chunk":
            emit({"type": "rpc_chunk", "chunkId": "rpc-2", "index": 0, "count": 1,
                  "byteLength": 4, "data": "eA=="})
            time.sleep(30)
        elif mode == "no-session-file":
            state = {key: value for key, value in STATE.items() if key != "sessionFile"}
            emit({"id": cid, "type": "response", "command": "get_state",
                  "success": True, "data": state})
        else:
            emit({"id": cid, "type": "response", "command": "get_state", "success": True, "data": STATE})
    elif ctype == "prompt":
        emit({"id": cid, "type": "response", "command": "prompt", "success": True,
              "data": {"agentInvoked": True}})
        if mode == "burst":
            for index in range(100):
                emit({"type": "message_update", "index": index})
        if mode == "late-error":
            emit({"id": cid, "type": "response", "command": "prompt", "success": False,
                  "error": "late scheduling failure"})
        else:
            emit({"type": "agent_start"})
            emit({"type": "agent_end", "messages": [], "isTerminal": True})
    elif ctype == "bad_command_test":
        emit({"id": cid, "type": "response", "command": "bad_command_test",
              "success": False, "error": "nope", "code": "test_code"})
    else:
        emit({"id": cid, "type": "response", "command": ctype or "parse", "success": True})

if mode == "slow-exit":
    time.sleep(0.6)
