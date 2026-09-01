#!/usr/bin/env python3
"""Minimal omp RPC stand-in for SessionController composer-controls tests.

Modes (argv[1]):
  basic            — ready + get_state; records command types when OMP_FAKE_RECORD is set
  catalog-update   — get_available_commands returns compact then emits a retry replacement
  delayed-catalog-update — get_available_commands returns compact; tests inject the delayed frame
  startup-catalog-update — emits startup update before returning the complete RPC snapshot
  startup-unsupported-catalog — emits startup update before reporting unsupported discovery
  blocked-ready    — waits for SIGUSR1 before emitting ready
  malformed-catalog — get_available_commands returns malformed command data
  unsupported-catalog — get_available_commands reports unsupported
  malformed-catalog-update — valid command discovery followed by malformed replacement data
  prompt-failure   — prompt reports a transport failure
  slash-local      — slash prompt succeeds locally without invoking an agent
  slash-agent      — slash prompt invokes an agent in the response
  slash-legacy-agent — slash prompt relies on lifecycle events for agent detection
  slash-failure    — slash prompt reports a transport failure
  slash-streaming-record — records streaming behavior for slash prompts
  fast-unsupported — set_fast_mode succeeds with active=false
  fast-rpc-fail    — set_fast_mode returns success=false (transport failure)
  set-model-echo   — set_model returns the requested model id/provider
"""
import json
import os
import signal
import time
import sys

mode = sys.argv[1] if len(sys.argv) > 1 else "basic"
record_path = os.environ.get("OMP_FAKE_RECORD")
prompt_record_path = os.environ.get("OMP_FAKE_PROMPT_RECORD")
W = sys.stdout


def emit(obj):
    W.write(json.dumps(obj, separators=(",", ":")) + "\n")
    W.flush()


def record(ctype):
    if not record_path or not ctype:
        return
    with open(record_path, "a", encoding="utf-8") as handle:
        handle.write(ctype + "\n")


def record_prompt(cmd):
    if not prompt_record_path:
        return
    record = {
        "message": cmd.get("message"),
        "images": cmd.get("images", []),
        "streamingBehavior": cmd.get("streamingBehavior"),
    }
    with open(prompt_record_path, "a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, separators=(",", ":")) + "\n")


STATE = {
    "model": {"id": "fake", "provider": "test", "name": "Fake"},
    "thinkingLevel": "auto",
    "fastModeEnabled": False,
    "fastModeActive": False,
    "isStreaming": False,
    "sessionId": "fake-session",
    "sessionFile": "/tmp/fake.jsonl",
}

COMPACT_CATALOG = {"commands": [{"name": "compact", "source": "builtin"}]}
RETRY_CATALOG = {"commands": [{"name": "retry", "source": "builtin"}]}
STARTUP_CATALOG = {"commands": [{"name": "startup", "source": "builtin"}]}
RPC_CATALOG = {"commands": [{"name": "rpc", "source": "builtin"}]}

if mode == "blocked-ready":
    ready_pid_path = os.environ.get("OMP_FAKE_READY_PID")
    if ready_pid_path:
        pending_ready_pid_path = ready_pid_path + ".tmp"
        with open(pending_ready_pid_path, "w", encoding="utf-8") as handle:
            handle.write(str(os.getpid()))
        os.replace(pending_ready_pid_path, ready_pid_path)
    ready = False

    def release_ready(_signum, _frame):
        nonlocal_ready[0] = True

    nonlocal_ready = [ready]
    signal.signal(signal.SIGUSR1, release_ready)
    while not nonlocal_ready[0]:
        signal.pause()

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
    elif ctype == "get_available_commands":
        if mode == "unsupported-catalog":
            emit({"id": cid, "type": "response", "command": "get_available_commands",
                  "success": False, "error": "unsupported"})
        elif mode == "malformed-catalog":
            emit({"id": cid, "type": "response", "command": "get_available_commands",
                  "success": True, "data": {"commands": "wrong"}})
        elif mode == "startup-catalog-update":
            emit({"type": "available_commands_update", **STARTUP_CATALOG})
            emit({"id": cid, "type": "response", "command": "get_available_commands",
                  "success": True, "data": RPC_CATALOG})
        elif mode == "startup-unsupported-catalog":
            emit({"type": "available_commands_update", **STARTUP_CATALOG})
            emit({"id": cid, "type": "response", "command": "get_available_commands",
                  "success": False, "error": "unsupported"})
        else:
            emit({"id": cid, "type": "response", "command": "get_available_commands",
                  "success": True, "data": COMPACT_CATALOG if mode in {
                      "catalog-update", "delayed-catalog-update", "malformed-catalog-update"
                  } else {"commands": []}})
    elif ctype == "set_fast_mode":
        enabled = bool(cmd.get("enabled"))
        if mode == "fast-rpc-fail":
            emit({"id": cid, "type": "response", "command": "set_fast_mode",
                  "success": False, "error": "fast mode unavailable"})
        elif mode == "fast-unsupported":
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
    elif ctype == "set_subagent_subscription":
        emit({"id": cid, "type": "response", "command": "set_subagent_subscription", "success": True})
        if mode == "catalog-update":
            emit({"type": "available_commands_update", **RETRY_CATALOG})
        elif mode == "malformed-catalog-update":
            emit({"type": "available_commands_update", "commands": "wrong"})
    elif ctype == "prompt":
        record_prompt(cmd)
        if mode in {"prompt-failure", "slash-failure"}:
            emit({"id": cid, "type": "response", "command": "prompt",
                  "success": False, "error": "prompt unavailable"})
        elif mode == "slash-local":
            emit({"id": cid, "type": "response", "command": "prompt",
                  "success": True, "data": {"agentInvoked": False}})
        elif mode == "slash-agent":
            time.sleep(0.2)
            emit({"id": cid, "type": "response", "command": "prompt",
                  "success": True, "data": {"agentInvoked": True}})
        elif mode == "slash-legacy-agent":
            emit({"id": cid, "type": "response", "command": "prompt",
                  "success": True, "data": {}})
            emit({"type": "turn_start"})
        elif mode == "slash-streaming-record":
            emit({"id": cid, "type": "response", "command": "prompt",
                  "success": True, "data": {"agentInvoked": True}})
            if not str(cmd.get("message", "")).startswith("/"):
                emit({"type": "agent_start"})
        else:
            emit({"id": cid, "type": "response", "command": "prompt", "success": True})
    else:
        emit({"id": cid, "type": "response", "command": ctype or "parse", "success": True})
