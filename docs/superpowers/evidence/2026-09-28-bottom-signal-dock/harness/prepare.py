from pathlib import Path
import json, sys
qa=Path(__file__).resolve().parent
root=qa/'profile'
(root/'.bun/bin').mkdir(parents=True,exist_ok=True)
(root/'fixtures').mkdir(parents=True,exist_ok=True)
s=Path('docs/superpowers/evidence/2026-09-08-ui-refinements/native-fixture.py').read_text()
s=s.replace('ui-refinements','bottom-dock').replace('ui-refinement','bottom-dock').replace('UI refinement acceptance','Bottom dock acceptance').replace('openai-codex','dock-fixture')
s=s.replace("session = bucket / 'session.jsonl'", "session = Path(sys.argv[sys.argv.index('-r') + 1]) if '-r' in sys.argv else bucket / ('session-' + str(os.getpid()) + '.jsonl')")
s=s.replace("'at': iso(), **value", "'at': iso(), 'pid': os.getpid(), 'session': str(session), **value")
s=s.replace('catalog_error = False', 'catalog_error = False\ncontext_percent = 42\nlast_action = None\nstate_delay = 0\nstate_error = False')
s=s.replace("        catalog_error = bool(action.get('catalogError', False))", """        catalog_error = bool(action.get('catalogError', False))
        if action.get('target') in (None, session.name):
            context_percent = action.get('percent', context_percent)
            state_delay = action.get('stateDelay', 0)
            state_error = action.get('stateError', False)
            if action.get('id') != last_action:
                last_action = action.get('id')
                for event in action.get('events', []):
                    emit(event)
                    record({'fixtureEvent': event})
                if action.get('exit'):
                    sys.exit(3)""")
s=s.replace("    elif kind == 'get_state':\n        reply", "    elif kind == 'get_state':\n        time.sleep(state_delay)\n        if state_error:\n            reply(command, success=False, error='Controlled context read failure')\n            continue\n        reply")
s=s.replace("'tokens': 84000, 'contextWindow': 200000, 'percent': 42", "'tokens': int(context_percent * 2000), 'contextWindow': 200000, 'percent': context_percent")
s=s.replace("    elif kind == 'get_available_models':", """    elif kind == 'get_login_providers':
        reply(command, {'providers': [{'id': 'dock-fixture', 'name': 'Local fixture', 'available': True, 'authenticated': True}]})
    elif kind == 'switch_session':
        session = Path(command.get('sessionPath', command.get('path', str(session))))
        entries = [json.loads(line) for line in session.read_text().splitlines() if line]
        messages = [entry['message'] for entry in entries if entry.get('type') == 'message']
        reply(command)
    elif kind == 'get_available_models':""")
s=s.replace("if action.get('finish') and is_streaming:", "if action.get('target') in (None, session.name) and action.get('finish') and is_streaming:")
s=s.replace("        edit_fixture()", "        assistant('The local run is active. You can steer or queue a follow-up while it waits.')")
(qa/'runtime.py').write_text(s)
wrapper='''#!%s
import json, os, sys, time
from pathlib import Path
root=Path(%r)
if '--version' in sys.argv:
    print('0.0.0-local-dock-qa')
elif 'config' in sys.argv:
    print('{}')
elif 'usage' in sys.argv:
    print(json.dumps({'generatedAt':int(time.time()*1000),'reports':[{'provider':'dock-fixture','fetchedAt':int(time.time()*1000),'metadata':{'email':'qa@example.test'},'limits':[{'id':'session','label':'Session','scope':{'provider':'dock-fixture'},'window':{'id':'session','label':'Session'},'amount':{'usedFraction':0.36,'unit':'percent'},'status':'ok'}]}],'accountsWithoutUsage':[],'disabledCredentials':[]}))
elif '--mode' in sys.argv:
    os.execv(%r,[%r,%r,str(root),*sys.argv[1:]])
else:
    print('{}')
''' % (sys.executable,str(root),sys.executable,sys.executable,str(qa/'runtime.py'))
(root/'.bun/bin/omp').write_text(wrapper)
(root/'.bun/bin/omp').chmod(0o755)
project=root/'projects/bottom-dock'
project.mkdir(parents=True,exist_ok=True)
bucket=root/'.omp/agent/sessions/-projects-bottom-dock'
bucket.mkdir(parents=True,exist_ok=True)
for i in range(1,3):
    p=bucket/f'acceptance-{i}.jsonl'
    if not p.exists():
        p.write_text(json.dumps({'type':'session','version':3,'id':f'dock-qa-{i}','timestamp':'2026-09-28T19:00:00.000Z','cwd':str(project),'title':f'Bottom dock acceptance {i}'})+'\n')
print(qa)
