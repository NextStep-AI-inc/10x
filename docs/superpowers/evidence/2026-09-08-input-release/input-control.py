#!/usr/bin/env python3
"""Controlled model-catalog failure; no prompt can reach a model."""
from datetime import datetime, timezone
import json
import sys
from pathlib import Path
root = Path('/tmp/10x-session-recovery-home')
session = root / '.omp/agent/sessions/-projects-input-native/session.jsonl'
control = root / 'fixtures/input-control.jsonl'
def emit(value):
    print(json.dumps(value), flush=True)
emit({'type':'ready','protocolVersion':1,'supportedProtocolVersions':[1,2],
      'maxFrameBytes':1048576,'maxReassembledFrameBytes':67108864})
for line in sys.stdin:
    try: command = json.loads(line)
    except json.JSONDecodeError: continue
    kind = command.get('type')
    with control.open('a') as log:
        log.write(json.dumps({'at':datetime.now(timezone.utc).isoformat(),'type':kind})+'\n')
    response = {'type':'response','id':command.get('id'),'command':kind,'success':True,'data':{}}
    if kind == 'negotiate_protocol': response['data'] = {'protocolVersion':2}
    elif kind == 'get_state': response['data'] = {
        'sessionFile':str(session),'sessionId':'input-native','sessionName':'Deliberate input acceptance',
        'isStreaming':False,'queuedMessageCount':0,
        'model':{'id':'input-fixture','provider':'test','name':'Input Fixture'}}
    elif kind in ['get_messages','get_messages_page']: response['data'] = {'messages':[],'nextCursor':None}
    elif kind == 'get_available_commands': response['data'] = {'commands':[]}
    elif kind == 'get_available_models': response = {
        'type':'response','id':command.get('id'),'command':kind,'success':False,
        'error':'Controlled native model-catalog failure','code':'catalog_unavailable'}
    elif kind == 'prompt': response = {
        'type':'response','id':command.get('id'),'command':kind,'success':False,
        'error':'Input acceptance fixture does not submit model work'}
    emit(response)
    if kind == 'shutdown': break
