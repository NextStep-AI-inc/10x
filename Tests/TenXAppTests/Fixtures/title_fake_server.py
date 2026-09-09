#!/usr/bin/env python3
import json
import os
import sys

session_file = sys.argv[1]
command_log = sys.argv[2]
reject_prompt = len(sys.argv) > 3 and sys.argv[3] == "reject"


def emit(value):
    print(json.dumps(value, separators=(",", ":")), flush=True)


def log(command):
    entry = {"type": command.get("type")}
    if command.get("type") == "set_session_name":
        entry["title"] = command.get("name")
    with open(command_log, "a", encoding="utf-8") as handle:
        handle.write(json.dumps(entry, separators=(",", ":")) + "\n")


def persist_title(title):
    with open(session_file, "r", encoding="utf-8") as handle:
        lines = handle.readlines()
    header = json.loads(lines[0])
    header["title"] = title
    temporary = session_file + ".tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        handle.write(json.dumps(header, separators=(",", ":")) + "\n")
        handle.writelines(lines[1:])
    os.replace(temporary, session_file)


emit({"type": "ready", "protocolVersion": 1, "supportedProtocolVersions": [1, 2],
      "maxFrameBytes": 1048576, "maxReassembledFrameBytes": 67108864})
for line in sys.stdin:
    command = json.loads(line)
    request_id = command.get("id")
    command_type = command.get("type")
    log(command)
    if command_type == "negotiate_protocol":
        data = {"protocolVersion": 2}
    elif command_type == "get_state":
        data = {"model": {"id": "gpt-test", "provider": "test"},
                "isStreaming": False, "sessionFile": session_file}
    elif command_type == "get_messages_page":
        data = {"messages": [], "nextCursor": None}
    elif command_type == "prompt" and reject_prompt:
        emit({"id": request_id, "type": "response", "command": command_type,
              "success": False, "error": "prompt rejected"})
        continue
    elif command_type == "set_session_name":
        persist_title(command.get("name", ""))
        data = {}
    else:
        data = {"agentInvoked": True} if command_type == "prompt" else {}
    emit({"id": request_id, "type": "response", "command": command_type,
          "success": True, "data": data})
    if command_type == "prompt":
        emit({"type": "agent_start"})
        emit({"type": "agent_end", "messages": [], "isTerminal": True})
