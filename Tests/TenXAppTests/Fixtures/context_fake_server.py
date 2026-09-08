#!/usr/bin/env python3
"""Controlled context-read and manual-compaction RPC fixture."""
import json
import sys
import time
mode = sys.argv[1]
command_log = sys.argv[2] if len(sys.argv) > 2 else None
state_reads = 0
is_compacted = False

def emit(value):
    print(json.dumps(value), flush=True)

emit({'type':'ready','protocolVersion':1,'supportedProtocolVersions':[1,2]})
for line in sys.stdin:
    command = json.loads(line)
    kind = command['type']
    if command_log:
        with open(command_log, 'a', encoding='utf-8') as log:
            log.write(kind + '\n')
    data = {}
    success = True
    if kind == 'negotiate_protocol':
        data = {'protocolVersion':2}
    elif kind == 'get_state':
        state_reads += 1
        success = not (mode == "transient" and state_reads == 3)
        tokens = 32000 if is_compacted else 84000 + (state_reads-1)*1000
        data = {'model':{'id':'fake','provider':'test'},'isStreaming':mode == 'compact-streaming',
                'sessionFile':'/tmp/context-fixture.jsonl',
                'queuedMessageCount':1 if mode == 'compact-queued' else 0,
                'contextUsage':{'tokens':tokens,'contextWindow':200000,'percent':16 if is_compacted else 42}}
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
    emit({'id':command['id'],'type':'response','command':kind,'success':success,'data':data})
