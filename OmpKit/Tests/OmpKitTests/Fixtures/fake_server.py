#!/usr/bin/env python3
"""Scripted omp RPC stand-in. Modes via argv[1]:
  basic     — ready, negotiate ok, echoes get_state with canned data
  chunked   — get_state answered as a 3-part rpc_chunk sequence
  late-error— prompt acked ok, then error response with the same id
  silent    — ready, then never answers anything (timeout testing)
  slow-exit — basic behavior, then waits briefly after stdin closes
  slow-turn — prompt starts an agent turn that finishes after two seconds
  background-exit — starts a turn, then exits one second after accepting event subscription
  pending-streaming — reports an active turn while a pending app open is archived
  noisy     — like basic, but emits unknown frames + setWidget before each response
  transcript-burst — one assistant message streamed as 1,000 growing snapshots
  transcript-burst-extensions — transcript-burst plus deterministic confirm requests
  reconciliation-double-boundary — emits two reconciliation boundaries with a gap
  extension-timeout — emits a short-lived confirm request and surfaces stale responses
  delayed-prompt-success — delays a prompt success response so controller replacement can race it
  delayed-prompt-failure — delays a prompt failure response so controller replacement can race it
  activity-lifecycle — scripted provider/config/runtime events for controller activity tests
  provider-account-failover — emits a provider account event before a normal response
  line-flood N S — ready, then N notice lines carrying S filler bytes each, then exit 0
  event-flood N S — like basic, but get_state is preceded by N notice events of S bytes
"""
import base64
import json
import os
import subprocess
import sys
import time

mode = sys.argv[1] if len(sys.argv) > 1 else "basic"
command_log = sys.argv[2] if mode == "command-log" and len(sys.argv) > 2 else None
W = sys.stdout


def emit(obj):
    # Compact separators match real omp output byte-for-byte.
    W.write(json.dumps(obj, separators=(",", ":")) + "\n")
    W.flush()


def log_command(command_type):
    if command_log is None:
        return
    with open(command_log, "a", encoding="utf-8") as handle:
        handle.write((command_type or "parse") + "\n")


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
if mode == "close-before-ready":
    while not os.path.exists(sys.argv[2]):
        time.sleep(0.001)
    os.close(sys.stdin.fileno())
    os.close(W.fileno())
    while not os.path.exists(sys.argv[3]):
        time.sleep(0.001)
    sys.stderr.write("close-before-ready\n")
    sys.stderr.flush()
    raise SystemExit(24)

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
if mode == "line-flood":
    flood_count, flood_size = int(sys.argv[2]), int(sys.argv[3])
    flood_payload = "y" * flood_size
    for index in range(flood_count):
        emit({"type": "notice", "index": index, "payload": flood_payload})
    raise SystemExit(0)
if mode == "stderr-held-open-exit":
    child = r"""
import os, sys, time
holding, release, released = sys.argv[1], sys.argv[2], sys.argv[3]
open(holding, "w", encoding="utf-8").close()
while not os.path.exists(release):
    time.sleep(0.001)
os.close(sys.stdout.fileno())
os.close(sys.stderr.fileno())
open(released, "w", encoding="utf-8").close()
"""
    subprocess.Popen(
        [sys.executable, "-u", "-c", child, sys.argv[2], sys.argv[3], sys.argv[4]])
    while not os.path.exists(sys.argv[2]):
        time.sleep(0.001)
    sys.stderr.write("x" * 262144 + "final-stderr-marker\n")
    sys.stderr.flush()
    raise SystemExit(31)
if mode == "continuous-inherited-output-exit":
    root = sys.argv[2]
    writer = r"""
import os, sys, time
stream_name, root = sys.argv[1], sys.argv[2]
descriptor = sys.stdout.fileno() if stream_name == "stdout" else sys.stderr.fileno()
start = os.path.join(root, stream_name + "-start")
primed = os.path.join(root, stream_name + "-primed")
stop = os.path.join(root, stream_name + "-stop")
stopped = os.path.join(root, stream_name + "-stopped")
with open(os.path.join(root, stream_name + "-pid"), "w", encoding="utf-8") as handle:
    handle.write(str(os.getpid()))
while not os.path.exists(start):
    time.sleep(0.001)
os.set_blocking(descriptor, False)
marker = ("late-" + stream_name + "-marker\n").encode()
while True:
    try:
        os.write(descriptor, marker)
        break
    except BlockingIOError:
        time.sleep(0.001)
open(primed, "w", encoding="utf-8").close()
payload = (stream_name[0] * 65536).encode()
while not os.path.exists(stop):
    try:
        os.write(descriptor, payload)
    except BlockingIOError:
        time.sleep(0.001)
os.close(sys.stdout.fileno())
os.close(sys.stderr.fileno())
open(stopped, "w", encoding="utf-8").close()
"""
    subprocess.Popen([sys.executable, "-u", "-c", writer, "stdout", root])
    subprocess.Popen([sys.executable, "-u", "-c", writer, "stderr", root])
    while not all(os.path.exists(os.path.join(root, name + "-pid"))
                  for name in ("stdout", "stderr")):
        time.sleep(0.001)
    emit({"type": "parent-final"})
    sys.stderr.write("parent-final-stderr\n")
    sys.stderr.flush()
    open(os.path.join(root, "parent-exiting"), "w", encoding="utf-8").close()
    raise SystemExit(37)
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
if mode == "unique-session-file":
    session_id = f"fake-{os.getpid()}"
    STATE["sessionId"] = session_id
    STATE["sessionFile"] = f"/tmp/{session_id}.jsonl"
if mode in ("activity-lifecycle", "pending-streaming"):
    STATE = {"model": {"id": "initial-model", "provider": "initial-provider"},
             "isStreaming": True, "sessionId": "fake-session", "sessionFile": "/tmp/fake.jsonl"}
reverse_commands = []

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        cmd = json.loads(line)
    except json.JSONDecodeError:
        log_command("parse")
        emit({"type": "response", "command": "parse", "success": False, "error": "malformed"})
        continue
    cid, ctype = cmd.get("id"), cmd.get("type")
    log_command(ctype)
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
        if mode == "crash-after-trigger":
            while not os.path.exists(sys.argv[2]):
                time.sleep(0.01)
            sys.stderr.write("crash-after-trigger\n")
            sys.stderr.flush()
            raise SystemExit(9)
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
    if mode == "reject-new-session" and ctype == "new_session":
        emit({"id": cid, "type": "response", "command": ctype,
              "success": False, "error": "new session rejected"})
        continue
    if mode == "crash-after-switch" and ctype == "switch_session":
        emit({"id": cid, "type": "response", "command": ctype, "success": True})
        time.sleep(0.2)
        sys.stderr.write("crash-after-switch\n")
        sys.stderr.flush()
        raise SystemExit(8)
    if mode == "crash-after-switch-trigger" and ctype == "switch_session":
        emit({"id": cid, "type": "response", "command": ctype, "success": True})
        while not os.path.exists(sys.argv[2]):
            time.sleep(0.01)
        sys.stderr.write("crash-after-switch-trigger\n")
        sys.stderr.flush()
        raise SystemExit(10)
    if mode == "block-new-session" and ctype == "new_session":
        open(sys.argv[3], "w", encoding="utf-8").close()
        while not os.path.exists(sys.argv[2]):
            time.sleep(0.01)
        emit({"id": cid, "type": "response", "command": ctype, "success": True})
        continue
    if ctype == "idless_error":
        emit({"type": "response", "command": ctype, "success": False,
              "error": "idless failure"})
    elif ctype == "get_state":
        if mode == "close-stdout-before-exit":
            os.close(sys.stdin.fileno())
            os.close(W.fileno())
            open(sys.argv[2], "w", encoding="utf-8").close()
            while not os.path.exists(sys.argv[3]):
                time.sleep(0.01)
            sys.stderr.write("close-stdout-before-exit\n")
            sys.stderr.flush()
            raise SystemExit(23)
        if mode == "block-get-state":
            open(sys.argv[3], "w", encoding="utf-8").close()
            while not os.path.exists(sys.argv[2]):
                time.sleep(0.01)
        if mode == "noisy":
            emit({"type": "notice", "level": "info", "message": "before response", "source": "fake"})
        if mode == "event-flood":
            flood_count, flood_size = int(sys.argv[2]), int(sys.argv[3])
            flood_payload = "z" * flood_size
            for index in range(flood_count):
                emit({"type": "notice", "index": index, "payload": flood_payload})
        if mode == "provider-account-failover":
            emit({
                "type": "provider_account_changed",
                "providerId": "openai-codex",
                "accountRef": "acct_failover",
                "reason": "automaticFailover",
                "sequence": 4,
                "future": {"ignored": True},
            })
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
        if mode == "delayed-prompt-success":
            time.sleep(0.3)
            emit({"id": cid, "type": "response", "command": "prompt", "success": True,
                  "data": {"agentInvoked": True}})
            continue
        if mode == "delayed-prompt-failure":
            time.sleep(0.3)
            emit({"id": cid, "type": "response", "command": "prompt", "success": False,
                  "error": "delayed prompt failure"})
            continue
        emit({"id": cid, "type": "response", "command": "prompt", "success": True,
              "data": {"agentInvoked": True}})
        if mode == "activity-lifecycle":
            emit({"type": "agent_start"})
            time.sleep(0.2)
            emit({"type": "config_update", "model": {
                "id": "updated-model", "provider": "updated-provider"}})
            time.sleep(0.2)
            emit({"type": "config_update", "thinkingLevel": "medium"})
            time.sleep(0.2)
            emit({"type": "config_update", "model": {"id": "provider-less-model"}})
            time.sleep(0.2)
            emit({"type": "agent_end", "messages": [], "isTerminal": True})
            continue
        if mode == "slow-turn":
            emit({"type": "agent_start"})
            time.sleep(2)
            emit({"type": "agent_end", "messages": [], "isTerminal": True})
            continue
        if mode == "burst":
            for index in range(100):
                emit({"type": "message_update", "index": index})
        elif mode in ("transcript-burst", "transcript-burst-extensions"):
            def assistant_message(text):
                return {
                    "id": "burst-message",
                    "role": "assistant",
                    "content": [{"type": "text", "text": text}],
                    "api": "test",
                    "provider": "test",
                    "model": "fake",
                    "stopReason": "stop",
                    "timestamp": 0,
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

            emit({"type": "agent_start"})
            emit({"type": "message_start", "message": assistant_message("")})
            text = ""
            for _ in range(1000):
                text += "x"
                emit({
                    "type": "message_update",
                    "message": assistant_message(text),
                    "assistantMessageEvent": {
                        "type": "text_delta",
                        "contentIndex": 0,
                        "delta": "x",
                        "partial": assistant_message(text),
                    },
                })
                if mode == "transcript-burst-extensions" and len(text) % 200 == 0:
                    emit({
                        "type": "extension_ui_request",
                        "id": f"confirm-{len(text)}",
                        "method": "confirm",
                        "title": f"Approve {len(text)}",
                        "message": "Continue?",
                    })
                time.sleep(0.002)
            emit({"type": "message_end", "message": assistant_message(text)})
            emit({"type": "agent_end", "messages": [], "isTerminal": True})
        elif mode == "reconciliation-double-boundary":
            emit({"type": "agent_start"})
            emit({"type": "message_end", "message": {
                "id": "boundary-message",
                "role": "assistant",
                "content": [{"type": "text", "text": "done"}],
                "timestamp": 0,
            }})
            time.sleep(0.1)
            emit({"type": "agent_end", "messages": [], "isTerminal": True})
        elif mode == "extension-timeout":
            emit({"type": "extension_ui_request", "id": "timeout-confirm", "method": "confirm",
                  "title": "Approve timeout", "message": "Continue?", "timeout": 120})
        if mode == "late-error":
            emit({"id": cid, "type": "response", "command": "prompt", "success": False,
                  "error": "late scheduling failure"})
        elif mode not in (
            "transcript-burst",
            "transcript-burst-extensions",
            "reconciliation-double-boundary",
        ):
            emit({"type": "agent_start"})
            emit({"type": "agent_end", "messages": [], "isTerminal": True})
    elif ctype == "bad_command_test":
        emit({"id": cid, "type": "response", "command": "bad_command_test",
              "success": False, "error": "nope", "code": "test_code"})
    elif ctype == "extension_ui_response" and mode == "extension-timeout":
        emit({"type": "message_update", "message": {"id": "leaked-timeout-response",
              "role": "assistant", "content": [{"type": "text", "text": "stale timeout leaked"}]}})
    elif mode == "block-subagent-subscription" and ctype == "set_subagent_subscription":
        # Bounded: a busy wait never sees stdin close, so an unreleased gate would
        # outlive the test that deleted its trigger directory.
        deadline = time.monotonic() + 30
        while not os.path.exists(sys.argv[2]) and time.monotonic() < deadline:
            time.sleep(0.01)
        emit({"id": cid, "type": "response", "command": ctype, "success": True})
    elif mode in ("background-exit", "pending-streaming") and ctype == "set_subagent_subscription":
        emit({"id": cid, "type": "response", "command": ctype, "success": True})
        emit({"type": "agent_start"})
        if mode == "pending-streaming":
            continue
        time.sleep(1)
        sys.stderr.write("background-exit\n")
        sys.stderr.flush()
        raise SystemExit(7)
    else:
        emit({"id": cid, "type": "response", "command": ctype or "parse", "success": True})

if mode in ("slow-exit", "pending-streaming"):
    time.sleep(0.6)
