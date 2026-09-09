#!/usr/bin/env python3
"""RPC fixture that leaves the first prompt delivery permanently unconfirmed."""

from datetime import datetime, timezone
import json
import os
import signal
import sys

sys.dont_write_bytecode = True

import attention as fixture


ROOT = "/tmp/10x-session-recovery-home"
PROJECT_PATH = f"{ROOT}/projects/draft-unconfirmed"
SESSION_PATH = (
    f"{ROOT}/.omp/agent/sessions/-projects-draft-unconfirmed/session.jsonl"
)
CONTROL_PATH = f"{ROOT}/fixtures/draft-unconfirmed-control.jsonl"
SESSION_ID = "draft-unconfirmed-acceptance-session"
TITLE = "Unconfirmed draft acceptance"

fixture.PROJECT_PATH = PROJECT_PATH
fixture.SESSION_PATH = SESSION_PATH
fixture.CONTROL_LOG = CONTROL_PATH
fixture.SESSION_ID = SESSION_ID
fixture.TITLE = TITLE
fixture.MODEL = {
    **fixture.MODEL,
    "id": "draft-unconfirmed-fixture",
    "name": "Draft Unconfirmed Fixture",
}


def timestamp():
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace(
        "+00:00", "Z")


def control_entries():
    try:
        with open(CONTROL_PATH, encoding="utf-8") as handle:
            return [json.loads(line) for line in handle if line.strip()]
    except FileNotFoundError:
        return []


def append_control(value):
    os.makedirs(os.path.dirname(CONTROL_PATH), exist_ok=True)
    entry = {"at": timestamp(), **value}
    with open(CONTROL_PATH, "a", encoding="utf-8") as handle:
        handle.write(json.dumps(entry, separators=(",", ":")) + "\n")


def log_control(value):
    if value.get("direction") == "command" and value.get("type") == "prompt":
        prompt_count = sum(
            entry.get("direction") == "command" and entry.get("type") == "prompt"
            for entry in control_entries()
        )
        prompt_ordinal = prompt_count + 1
        value = {
            **value,
            "promptOrdinal": prompt_ordinal,
            "isReplay": prompt_ordinal > 1,
            "disposition": (
                "withheld-unconfirmed" if prompt_ordinal == 1 else "replay-rejected"
            ),
        }
    append_control(value)


def seed_session(truncate_control=False):
    os.makedirs(PROJECT_PATH, exist_ok=True)
    os.makedirs(os.path.dirname(SESSION_PATH), exist_ok=True)
    temporary = SESSION_PATH + ".tmp"
    session = {
        "type": "session",
        "version": 3,
        "id": SESSION_ID,
        "timestamp": "2026-09-08T17:45:00.000Z",
        "cwd": PROJECT_PATH,
        "title": TITLE,
    }
    with open(temporary, "w", encoding="utf-8") as handle:
        handle.write(json.dumps(session, separators=(",", ":")) + "\n")
    os.replace(temporary, SESSION_PATH)
    if truncate_control:
        os.makedirs(os.path.dirname(CONTROL_PATH), exist_ok=True)
        with open(CONTROL_PATH, "w", encoding="utf-8"):
            pass


def hold_or_reject_prompt(command):
    prompt_count = sum(
        entry.get("direction") == "command" and entry.get("type") == "prompt"
        for entry in control_entries()
    )
    if prompt_count > 1:
        fixture.emit(fixture.response(
            command,
            success=False,
            error="replayed unconfirmed prompt rejected by acceptance fixture",
        ))
    # The first prompt intentionally receives no response and produces no echo.
    # No prompt is added to fixture.messages or the persisted session.
    return True


def record_launch():
    entries = control_entries()
    append_control({
        "direction": "fixture",
        "type": "process_launch",
        "launchOrdinal": sum(entry.get("type") == "process_launch" for entry in entries) + 1,
        "priorPromptCount": sum(
            entry.get("direction") == "command" and entry.get("type") == "prompt"
            for entry in entries
        ),
    })


def exit_on_signal(_signum, _frame):
    raise SystemExit(0)


def main():
    if "--reset" in sys.argv:
        seed_session(truncate_control=True)
        return 0
    if not os.path.exists(SESSION_PATH):
        seed_session(truncate_control=False)
    fixture.reset_fixture = lambda: seed_session(truncate_control=False)
    fixture.log_control = log_control
    fixture.start_turn = hold_or_reject_prompt
    record_launch()
    return fixture.main()


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, exit_on_signal)
    signal.signal(signal.SIGINT, exit_on_signal)
    raise SystemExit(main())
