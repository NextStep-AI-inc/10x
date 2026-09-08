"""Reproduces the 10x warm-client persistence bug against omp.

Run from any git repo: python3 omp-no-session-probe.py
A) mirrors OmpKit.SessionProcessManager.warm() (RpcClient adds --no-session);
B) is the same child without that flag. Only B ever reports a sessionFile.
"""
import json, subprocess, sys, time, os
def run(args, cwd):
    p = subprocess.Popen(["omp"]+args, cwd=cwd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    def send(cmd):
        p.stdin.write(json.dumps(cmd)+"\n"); p.stdin.flush()
    def read_until(pred, timeout=25):
        end=time.time()+timeout
        while time.time()<end:
            line=p.stdout.readline()
            if not line: break
            try: f=json.loads(line)
            except: continue
            if pred(f): return f
        return None
    send({"id":"s0","type":"get_state"})
    st0=read_until(lambda f: f.get("id")=="s0")
    print("  before new_session: sessionFile =", (st0 or {}).get("data",{}).get("sessionFile"))
    send({"id":"n1","type":"new_session"})
    r=read_until(lambda f: f.get("id")=="n1")
    print("  new_session ->", r and r.get("success"), (r or {}).get("data"))
    send({"id":"s1","type":"get_state"})
    st=read_until(lambda f: f.get("id")=="s1")
    d=(st or {}).get("data",{})
    print("  after new_session: sessionFile =", d.get("sessionFile"), "| sessionId =", d.get("sessionId"))
    p.stdin.close(); p.terminate()
    try: p.wait(timeout=5)
    except: p.kill()
cwd=os.environ.get("PROBE_CWD", os.getcwd())  # any git repo directory
print("A) omp --mode rpc --no-title --no-session   (what 10x's warm client uses)")
run(["--mode","rpc","--no-title","--no-session"], cwd)
print("B) omp --mode rpc --no-title   (persisting)")
run(["--mode","rpc","--no-title"], cwd)
