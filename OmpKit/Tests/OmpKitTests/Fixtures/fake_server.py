#!/usr/bin/env python3
"""Scripted omp RPC stand-in. Modes via argv[1]:
  basic     — ready, negotiate ok, echoes get_state with canned data
  chunked   — get_state answered as a 3-part rpc_chunk sequence
  late-error— prompt acked ok, then error response with the same id
  silent    — ready, then never answers anything (timeout testing)
  noisy     — like basic, but emits unknown frames + setWidget before each response
"""
import json, sys, base64

mode = sys.argv[1] if len(sys.argv) > 1 else "basic"
W = sys.stdout


def emit(obj):
    # Compact separators match real omp output byte-for-byte.
    W.write(json.dumps(obj, separators=(",", ":")) + "\n")
    W.flush()


emit({"type": "ready", "protocolVersion": 1, "supportedProtocolVersions": [1, 2],
      "maxFrameBytes": 1048576, "maxReassembledFrameBytes": 67108864})
if mode == "noisy":
    emit({"type": "available_commands_update", "commands": []})
    emit({"type": "extension_ui_request", "id": "w1", "method": "setWidget", "widgetKey": "x"})

STATE = {"model": {"id": "fake", "provider": "test"}, "isStreaming": False,
         "sessionId": "fake-session", "sessionFile": "/tmp/fake.jsonl"}

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
        emit({"id": cid, "type": "response", "command": "negotiate_protocol",
              "success": True, "data": {"protocolVersion": 2}})
    elif ctype == "get_state":
        if mode == "noisy":
            emit({"type": "notice", "level": "info", "message": "before response", "source": "fake"})
        if mode == "chunked":
            payload = json.dumps({"id": cid, "type": "response", "command": "get_state",
                                  "success": True, "data": STATE}).encode()
            n = 3
            size = (len(payload) + n - 1) // n
            for i in range(n):
                part = payload[i * size:(i + 1) * size]
                emit({"type": "rpc_chunk", "chunkId": "ck1", "index": i, "count": n,
                      "byteLength": len(payload), "data": base64.b64encode(part).decode()})
        else:
            emit({"id": cid, "type": "response", "command": "get_state", "success": True, "data": STATE})
    elif ctype == "prompt":
        emit({"id": cid, "type": "response", "command": "prompt", "success": True,
              "data": {"agentInvoked": True}})
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
