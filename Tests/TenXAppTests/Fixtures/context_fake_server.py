#!/usr/bin/env python3
"""Controlled context-read and manual-compaction RPC fixture."""
import json
import os
import sys
import time
mode = sys.argv[1]
command_log = sys.argv[2] if len(sys.argv) > 2 else None
state_reads = 0
is_compacted = False
is_streaming = False
queued_count = 0
deferred_state = None
defer_next_state = False
has_accepted_prompt = False

def emit(value):
    print(json.dumps(value), flush=True)

emit({'type':'ready','protocolVersion':1,'supportedProtocolVersions':[1,2]})
for line in sys.stdin:
    command = json.loads(line)
    kind = command['type']
    if command_log:
        log_path = os.path.join(command_log, 'commands.log') if os.path.isdir(command_log) else command_log
        with open(log_path, 'a', encoding='utf-8') as log:
            log.write(kind + '\n')
    data = {}
    success = True
    if kind == 'negotiate_protocol':
        data = {'protocolVersion':2}
    elif kind == 'get_state':
        state_reads += 1
        if mode == 'delayed-context' and state_reads == 3:
            open(os.path.join(command_log, 'state-deferred'), 'w').close()
            while not os.path.exists(os.path.join(command_log, 'release-state')):
                time.sleep(0.01)
        success = not ((mode == "transient" and state_reads == 3)
                       or (mode == "compact-state-failure" and is_compacted))
        if mode == 'accepted-send-stale-state':
            tokens = 87000 if has_accepted_prompt else 85000
        else:
            tokens = 32000 if is_compacted else 84000 + (state_reads-1)*1000
        data = {'model':{'id':'fake','provider':'test'},'isStreaming':mode == 'compact-streaming' or is_streaming,
                'sessionFile':'/tmp/context-fixture.jsonl',
                'queuedMessageCount':1 if mode == 'compact-queued' else queued_count,
                'contextUsage':{'tokens':tokens,'contextWindow':200000,'percent':16 if is_compacted else 42}}
        if mode == 'accepted-send-stale-state' and defer_next_state:
            defer_next_state = False
            data['contextUsage']['tokens'] = 86000
            deferred_state = {'id':command['id'],'type':'response','command':kind,'success':success,'data':data}
            open(os.path.join(command_log, 'state-deferred'), 'w').close()
            continue
        if mode == 'deferred-idle-state' and state_reads == 3:
            deferred_state = {'id':command['id'],'type':'response','command':kind,'success':success,'data':data}
            open(os.path.join(command_log, 'state-deferred'), 'w').close()
            continue
    elif kind == 'get_available_commands':
        commands = [] if mode == 'unsupported' else [{'name':'context','source':'builtin'}]
        if mode.startswith('compact-'):
            commands.append({
                'name':'compact',
                'source':'extension' if mode == 'compact-extension' else 'builtin',
            })
        data = {'commands':commands}
    elif kind in {'get_messages', 'get_messages_page'}:
        data = {'messages':[]}
        if kind == 'get_messages_page':
            data['nextCursor'] = None
    elif kind == 'prompt':
        if mode == 'accepted-send-stale-state' and command.get('message') != '/context':
            has_accepted_prompt = True
            is_streaming = True
            queued_count = 1
            emit({'id':command['id'],'type':'response','command':kind,'success':True,'data':{}})
            continue
        if mode == 'deferred-idle-state' and command.get('message') != '/context':
            is_streaming = True
            queued_count = 1
            emit({'id':command['id'],'type':'response','command':kind,'success':True,'data':{}})
            continue
        if command.get('message') != '/context':
            raise AssertionError('Context reads must not submit model work')
        text = 'changed report format' if mode == 'malformed' else '''Context window: 200000 tokens (42% used)
  System prompt    [█░] 42%  8000 tokens
  System tools     [█░] 42%  6000 tokens
  System context   [█░] 42%  5000 tokens
  Skills           [█░] 42%  3000 tokens
  Messages         [█░] 42%  62000 tokens
  Free             [█░] 42%  116000 tokens'''
        emit({'type':'command_output','text':text})
        data = {'agentInvoked':False}
    elif kind == 'set_subagent_subscription' and mode == 'compact-pending':
        emit({'id':command['id'],'type':'response','command':kind,'success':True,'data':{}})
        emit({'type':'extension_ui_request','id':'compact-pending-input','method':'confirm',
              'title':'Continue?','message':'Resolve this before compacting.'})
        continue
    elif kind == 'compact':
        if command.get('customInstructions') is not None:
            raise AssertionError('Manual compaction must not invent instructions')
        if mode == 'compact-hang':
            while True:
                time.sleep(1)
        if mode == 'compact-delayed':
            time.sleep(0.5)
        if mode == 'compact-failure':
            emit({'id':command['id'],'type':'response','command':kind,'success':False,
                  'error':'Controlled compaction failure','code':'compaction_failed'})
            continue
        if mode == 'compact-unsupported':
            emit({'id':command['id'],'type':'response','command':kind,'success':False,
                  'error':'Unsupported command','code':'unsupported_command'})
            continue
        is_compacted = True
    elif kind == 'context_test_control':
        action = command.get('action')
        if mode == 'accepted-send-stale-state' and action == 'defer-next-state':
            defer_next_state = True
        elif deferred_state:
            emit(deferred_state)
            deferred_state = None
    emit({'id':command['id'],'type':'response','command':kind,'success':success,'data':data})
