#!/usr/bin/env python3
"""Minimal omp RPC stand-in for SessionController composer-controls tests.

Modes (argv[1]):
  basic            — ready + get_state; records command types when OMP_FAKE_RECORD is set
  fast-unsupported — set_fast_mode succeeds with active=false
  set-model-echo   — set_model returns the requested model id/provider
"""
import json
import os
import sys

mode = sys.argv[1] if len(sys.argv) > 1 else "basic"
record_path = os.environ.get("OMP_FAKE_RECORD")
W = sys.stdout


def emit(obj):
    W.write(json.dumps(obj, separators=(",", ":")) + "\n")
    W.flush()


def record(ctype):
    if not record_path or not ctype:
        return
    with open(record_path, "a", encoding="utf-8") as handle:
        handle.write(ctype + "\n")


STATE = {
    "model": {"id": "fake", "provider": "test", "name": "Fake"},
    "thinkingLevel": "auto",
    "isStreaming": False,
    "sessionId": "fake-session",
    "sessionFile": "/tmp/fake.jsonl",
}

emit({"type": "ready", "protocolVersion": 1, "supportedProtocolVersions": [1, 2],
      "maxFrameBytes": 1048576, "maxReassembledFrameBytes": 67108864})

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
    record(ctype)
    if ctype == "negotiate_protocol":
        emit({"id": cid, "type": "response", "command": "negotiate_protocol",
              "success": True, "data": {"protocolVersion": 2}})
    elif ctype == "get_state":
        emit({"id": cid, "type": "response", "command": "get_state", "success": True, "data": STATE})
    elif ctype == "set_fast_mode":
        enabled = bool(cmd.get("enabled"))
        if mode == "fast-unsupported":
            emit({"id": cid, "type": "response", "command": "set_fast_mode",
                  "success": True, "data": {"enabled": False, "active": False}})
        else:
            emit({"id": cid, "type": "response", "command": "set_fast_mode",
                  "success": True, "data": {"enabled": enabled, "active": True}})
    elif ctype == "set_model":
        provider = cmd.get("provider", "test")
        model_id = cmd.get("modelId", "fake")
        model = {"id": model_id, "provider": provider, "name": model_id}
        STATE["model"] = model
        emit({"id": cid, "type": "response", "command": "set_model",
              "success": True, "data": model})
    elif ctype == "set_thinking_level":
        level = cmd.get("level", "auto")
        STATE["thinkingLevel"] = level
        emit({"id": cid, "type": "response", "command": "set_thinking_level", "success": True})
    else:
        emit({"id": cid, "type": "response", "command": ctype or "parse", "success": True})
