#!/usr/bin/env python3
"""Local RPC fixture for native popup/delivery UI acceptance; no model work.

Usage: native-fixture.py PROFILE_ROOT [OMP RPC arguments]
Create PROFILE_ROOT/fixtures/ui-refinement-control.json with {"finish": true}
to finish the current run and consume queued prompts. This is a fixture event,
not an application control. Every received RPC command is logged without images.
"""
from collections import deque
from datetime import datetime, timezone
from pathlib import Path
import difflib
import json
import os
import select
import sys
import time
import uuid

root = Path(sys.argv[1]).resolve()
project = root / 'projects/ui-refinements'
bucket = root / '.omp/agent/sessions/-projects-ui-refinements'
session = bucket / 'session.jsonl'
control = root / 'fixtures/ui-refinement-control.json'
trace = root / 'fixtures/ui-refinement-rpc.jsonl'
for directory in [project, bucket, control.parent]:
    directory.mkdir(parents=True, exist_ok=True)


def now_ms():
    return int(time.time() * 1000)


def iso(ms=None):
    return datetime.fromtimestamp((ms or now_ms()) / 1000, timezone.utc).isoformat(timespec='milliseconds').replace('+00:00', 'Z')


def emit(value):
    print(json.dumps(value, separators=(',', ':')), flush=True)


def record(value):
    with trace.open('a') as stream:
        stream.write(json.dumps({'at': iso(), **value}, separators=(',', ':')) + '\n')


def reply(command, data=None, success=True, error=None):
    value = {'id': command.get('id'), 'type': 'response', 'command': command.get('type'), 'success': success, 'data': data or {}}
    if error:
        value['error'] = error
    emit(value)


if not session.exists():
    session.write_text(json.dumps({'type': 'session', 'version': 3, 'id': 'ui-refinement-native',
                                  'timestamp': iso(), 'cwd': str(project), 'title': 'UI refinement acceptance'}) + '\n')
entries = [json.loads(line) for line in session.read_text().splitlines() if line]
parent = next((entry['id'] for entry in reversed(entries) if entry.get('type') == 'message'), None)
messages = [entry['message'] for entry in entries if entry.get('type') == 'message']
queue = []
is_streaming = False
started_at = None
catalog_error = False
selected_model = {'id': 'fixture-standard', 'name': 'Standard fixture', 'provider': 'openai-codex', 'contextWindow': 200000, 'reasoning': True, 'input': ['text', 'image']}
# Use the signed-in QA provider ID so the real authenticated-catalog filter runs.
# These are still entirely local fixture models; the wrapper handles every RPC.
models = [selected_model, {'id': 'fixture-compact', 'name': 'Compact fixture', 'provider': 'openai-codex', 'contextWindow': 100000, 'reasoning': True, 'input': ['text', 'image']}]

models += [{**selected_model, 'id': f'fixture-option-{index}', 'name': f'Layout fixture option {index}'} for index in range(1, 15)]


def persist(message):
    global parent
    # OMP's durable entry ID differs from the live message identity. The nested
    # user message intentionally has no id or mode, matching the real runtime.
    entry_id = uuid.uuid4().hex[:8]
    entry = {'type': 'message', 'id': entry_id, 'parentId': parent, 'timestamp': iso(message['timestamp']), 'message': message}
    with session.open('a') as stream:
        stream.write(json.dumps(entry, separators=(',', ':')) + '\n')
    parent = entry_id
    messages.append(message)
    return entry_id


def user_echo(command):
    content = [{'type': 'text', 'text': command.get('message', '')}]
    for attachment in command.get('images', []):
        content.append({'type': 'image', 'data': attachment['data'], 'mimeType': attachment['mimeType']})
    message = {'role': 'user', 'content': content, 'attribution': 'user', 'timestamp': now_ms()}
    emit({'type': 'message_start', 'message': message})
    entry_id = persist(message)
    emit({'type': 'message_end', 'message': message})
    record({'event': 'user-echo', 'entryID': entry_id, 'mode': command.get('streamingBehavior'), 'text': command.get('message', '')})


def assistant(text):
    stamp = now_ms()
    message = {'role': 'assistant', 'id': uuid.uuid4().hex, 'api': 'test', 'provider': 'test',
               'model': selected_model['id'], 'content': [{'type': 'text', 'text': text}],
               'timestamp': stamp, 'completedAt': stamp + 10, 'duration': 10, 'stopReason': 'stop'}
    emit({'type': 'message_start', 'message': message})
    persist(message)
    emit({'type': 'message_end', 'message': message})


def edit_fixture():
    stamp = now_ms()
    patches = []
    for filename, previous, current in [
        ('layout.swift', 'let title = "Previous layout"\nlet width = 620\n', 'let title = "Refined layout"\nlet width = 720\n'),
        ('Sources/Components/VeryLongDirectoryName/FollowUpPresentation.swift', 'let mode = "standard"\n', 'let mode = "follow-up"\n'),
    ]:
        path = project / filename
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(current)
        patches.append(''.join(difflib.unified_diff(previous.splitlines(True), current.splitlines(True), fromfile=f'a/{filename}', tofile=f'b/{filename}')))
    # Single-file and multi-file surfaces are both real ToolPresentation paths.
    for index, diff in enumerate([patches[0], ''.join(patches)]):
        tool_id = uuid.uuid4().hex
        args = {'path': 'layout.swift'} if index == 0 else {'patch': ''.join(patches)}
        tool_name = 'edit' if index == 0 else 'apply_patch'
        call = {'type': 'toolCall', 'id': tool_id, 'name': tool_name, 'arguments': args}
        message = {'id': uuid.uuid4().hex, 'role': 'assistant', 'api': 'test', 'provider': 'test',
                   'model': selected_model['id'], 'content': [call], 'timestamp': stamp + index}
        emit({'type': 'message_start', 'message': message})
        emit({'type': 'tool_execution_start', 'toolCallId': tool_id, 'toolName': tool_name, 'args': args})
        result = {'content': [{'type': 'text', 'text': 'Applied the controlled layout change.'}], 'details': {'diff': diff}}
        persist(message)
        emit({'type': 'message_end', 'message': message})
        persist({'role': 'toolResult', 'toolCallId': tool_id, 'toolName': tool_name,
                 'content': result['content'], 'details': result['details'], 'isError': False, 'timestamp': now_ms()})
        emit({'type': 'tool_execution_end', 'toolCallId': tool_id, 'toolName': tool_name, 'result': result, 'isError': False})


def finish_run():
    global is_streaming, started_at
    assistant('The controlled run is complete. Follow-up and steer messages keep their recorded presentation.')
    emit({'type': 'turn_end'})
    emit({'type': 'agent_end'})
    is_streaming = False
    started_at = None
    while queue:
        command = queue.pop(0)
        emit({'type': 'agent_start'})
        emit({'type': 'turn_start'})
        user_echo(command)
        assistant('Received the queued message.')
        emit({'type': 'turn_end'})
        emit({'type': 'agent_end'})
    record({'event': 'finished', 'remainingQueue': len(queue)})


emit({'type': 'ready', 'protocolVersion': 1, 'supportedProtocolVersions': [1, 2],
      'maxFrameBytes': 1048576, 'maxReassembledFrameBytes': 67108864})
record({'event': 'launched', 'session': str(session)})
input_buffer = b''
input_lines = deque()
while True:
    if control.exists():
        try:
            action = json.loads(control.read_text())
        except (json.JSONDecodeError, OSError):
            action = {}
        catalog_error = bool(action.get('catalogError', False))
        if action.get('finish') and is_streaming:
            control.write_text(json.dumps({**action, 'finish': False}))
            finish_run()
    if not input_lines:
        ready, _, _ = select.select([sys.stdin], [], [], 0.1)
        if not ready:
            continue
        chunk = os.read(sys.stdin.fileno(), 65536)
        if not chunk:
            break
        parts = (input_buffer + chunk).split(b'\n')
        input_buffer = parts.pop()
        input_lines.extend(parts)
        if not input_lines:
            continue
    try:
        command = json.loads(input_lines.popleft())
    except json.JSONDecodeError:
        continue
    kind = command.get('type')
    record({'command': kind, 'mode': command.get('streamingBehavior'),
            'message': command.get('message'), 'modelId': command.get('modelId')})
    if kind == 'negotiate_protocol':
        reply(command, {'protocolVersion': 2})
    elif kind == 'get_state':
        reply(command, {'sessionFile': str(session), 'sessionId': 'ui-refinement-native',
                        'sessionName': 'UI refinement acceptance', 'model': selected_model,
                        'thinkingLevel': 'high', 'isStreaming': is_streaming, 'queuedMessageCount': len(queue),
                        'contextUsage': {'tokens': 84000, 'contextWindow': 200000, 'percent': 42}})
    elif kind in ['get_messages', 'get_messages_page']:
        reply(command, {'messages': messages, 'nextCursor': None})
    elif kind == 'get_available_models':
        reply(command, {'models': models}, not catalog_error,
              'Controlled catalog warning for native flyout verification.' if catalog_error else None)
    elif kind == 'get_available_commands':
        reply(command, {'commands': [{'name': 'context', 'source': 'builtin'}, {'name': 'compact', 'source': 'builtin'}]})
    elif kind == 'set_model':
        selected_model = next((model for model in models if model['id'] == command.get('modelId')), selected_model)
        reply(command, selected_model)
    elif kind == 'set_thinking_level':
        reply(command, {'level': command.get('level', 'high')})
    elif kind == 'prompt' and command.get('message') == '/context':
        emit({'type': 'command_output', 'text': 'Context window: 200000 tokens (42% used)\n  System prompt    [█░] 4%  8000 tokens\n  System tools     [█░] 3%  6000 tokens\n  Messages         [█░] 35%  70000 tokens\n  Free             [█░] 58%  116000 tokens'})
        reply(command, {'agentInvoked': False})
    elif kind == 'prompt' and is_streaming:
        queue.append(command)
        reply(command, {'agentInvoked': True})
    elif kind == 'prompt':
        is_streaming = True
        started_at = now_ms()
        # Echo before ACK exercises the application's actual prompt race.
        emit({'type': 'agent_start'})
        emit({'type': 'turn_start'})
        user_echo(command)
        reply(command, {'agentInvoked': True})
        edit_fixture()
    elif kind == 'abort':
        is_streaming = False
        queue.clear()
        emit({'type': 'turn_end'})
        emit({'type': 'agent_end'})
        reply(command)
    elif kind == 'compact':
        reply(command, success=False, error='Controlled compaction failure. Try again.')
    elif kind == 'shutdown':
        reply(command)
        break
    else:
        reply(command)
