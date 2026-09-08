#!/usr/bin/env python3
"""Context read contract: local report, malformed report, unsupported capability."""
import json
import sys
mode = sys.argv[1]
state_reads = 0

def emit(value):
    print(json.dumps(value), flush=True)

emit({'type':'ready','protocolVersion':1,'supportedProtocolVersions':[1,2]})
for line in sys.stdin:
    command = json.loads(line)
    kind = command['type']
    data = {}
    success = True
    if kind == 'negotiate_protocol':
        data = {'protocolVersion':2}
    elif kind == 'get_state':
        state_reads += 1
        success = not (mode == "transient" and state_reads == 3)
        data = {'model':{'id':'fake','provider':'test'},'isStreaming':False,
                'sessionFile':'/tmp/context-fixture.jsonl',
                'contextUsage':{'tokens':84000 + (state_reads-1)*1000,'contextWindow':200000,'percent':42}}
    elif kind == 'get_available_commands':
        data = {'commands': [] if mode == 'unsupported' else [{'name':'context','source':'builtin'}]}
    elif kind == 'get_messages':
        data = {'messages':[]}
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
    emit({'id':command['id'],'type':'response','command':kind,'success':success,'data':data})
