"""Probe real omp RPC persistence using disposable fixtures, without model calls.

Run: python3 verify-warm-persistence.py
Optional: OMP_EXECUTABLE=/path/to/omp BUN_EXECUTABLE=/path/to/bun
All profiles and session files are isolated in a temporary directory.
This verifies runtime behavior, not clicks or application relaunch behavior.
"""

import hashlib
import json
import os
from pathlib import Path
import select
import shutil
import subprocess
import tempfile
import time
import uuid


class RpcFailure(Exception):
    pass


def probe(root, command, no_session, existing):
    root.mkdir()
    cwd = root / "project"
    cwd.mkdir()
    seed = root / "existing.jsonl"
    seed_id = str(uuid.uuid4())
    records = [
        {"type": "session", "version": 3, "id": seed_id,
         "timestamp": "2026-09-07T00:00:00.000Z", "cwd": str(cwd)},
        {"type": "message", "id": "12345678", "parentId": None,
         "timestamp": "2026-09-07T00:00:01.000Z",
         "message": {"role": "user", "content": "Disposable audit fixture.",
                     "timestamp": 1788739201000}},
    ]
    seed.write_text("".join(json.dumps(row) + "\n" for row in records))
    before = hashlib.sha256(seed.read_bytes()).hexdigest()
    env = dict(os.environ, PI_CODING_AGENT_DIR=str(root / "profile"))
    env.pop("OMP_PROFILE", None)
    env.pop("PI_PROFILE", None)
    args = command + ["--mode", "rpc", "--no-title", "--session-dir", str(root / "sessions")]
    if no_session:
        args.append("--no-session")
    with (root / "stderr.log").open("wb") as errors:
        child = subprocess.Popen(args, cwd=cwd, env=env, stdin=subprocess.PIPE,
                                 stdout=subprocess.PIPE, stderr=errors)
        pending = b""
        serial = 0

        def request(kind, **fields):
            nonlocal pending, serial
            serial += 1
            request_id = str(serial)
            child.stdin.write((json.dumps(dict(id=request_id, type=kind, **fields)) + "\n").encode())
            child.stdin.flush()
            deadline = time.monotonic() + 25
            while time.monotonic() < deadline:
                while b"\n" in pending:
                    line, pending = pending.split(b"\n", 1)
                    try:
                        frame = json.loads(line)
                    except (ValueError, UnicodeDecodeError):
                        continue
                    if frame.get("id") == request_id and frame.get("type") == "response":
                        if not frame.get("success"):
                            raise RpcFailure(f"{kind}: {frame.get('error')}")
                        return frame.get("data", {})
                ready, _, _ = select.select([child.stdout], [], [], max(0, deadline - time.monotonic()))
                if ready:
                    chunk = os.read(child.stdout.fileno(), 65536)
                    if not chunk:
                        raise RuntimeError(f"Runtime exited during {kind}")
                    pending += chunk
            raise TimeoutError(kind)

        try:
            request("get_state")
            if existing:
                try:
                    request("switch_session", sessionPath=str(seed))
                except RpcFailure as error:
                    return {
                        "mode": "no-session" if no_session else "persisting control",
                        "case": "switch existing",
                        "switch_succeeded": False,
                        "switch_error": str(error).replace(str(seed), "<disposable fixture>"),
                        "fixture_bytes_changed": before != hashlib.sha256(seed.read_bytes()).hexdigest(),
                    }
            else:
                request("new_session")
            state = request("get_state")
            messages = request("get_messages").get("messages", [])
            request("set_session_name", name="Audit probe rename")
            renamed = request("get_state")
            return {
                "mode": "no-session" if no_session else "persisting control",
                "case": "switch existing" if existing else "new session",
                "session_file_present": bool(state.get("sessionFile")),
                "session_file_matches_fixture": state.get("sessionFile") == str(seed),
                "session_id_matches_fixture": state.get("sessionId") == seed_id,
                "loaded_message_count": len(messages),
                "rename_acknowledged": renamed.get("sessionName") == "Audit probe rename",
                "fixture_bytes_changed": before != hashlib.sha256(seed.read_bytes()).hexdigest(),
            }
        finally:
            child.terminate()
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait(timeout=5)


def main():
    omp = os.environ.get("OMP_EXECUTABLE") or shutil.which("omp") or str(Path.home() / ".bun/bin/omp")
    bun = os.environ.get("BUN_EXECUTABLE") or shutil.which("bun")
    command = [bun, omp] if bun else [omp]
    print(subprocess.check_output(command + ["--version"], text=True, timeout=10).strip())
    print("Model calls: 0. Fixtures and profiles: isolated temporary directories.")
    with tempfile.TemporaryDirectory(prefix="tenx-audit-persistence-") as scratch:
        results = []
        for existing in (False, True):
            for no_session in (True, False):
                result = probe(Path(scratch) / str(len(results)), command, no_session, existing)
                results.append(result)
                print(json.dumps(result, sort_keys=True))
        assert results[0]["session_file_present"] is False
        assert results[1]["session_file_present"] is True
        assert results[3]["loaded_message_count"] == 1
        assert results[3]["fixture_bytes_changed"] is True
        assert results[2]["switch_succeeded"] is False
        assert "File not found" in results[2]["switch_error"]
        assert results[2]["fixture_bytes_changed"] is False
    print("PASS: ephemeral behavior reproduced; persisting controls passed.")


if __name__ == "__main__":
    main()
