#!/usr/bin/env python3
"""Native acceptance fixture for timeout and explicit-cancel responses."""

import signal
import sys

sys.dont_write_bytecode = True

import attention as fixture


ROOT = "/tmp/10x-session-recovery-home"
TIMEOUT_MS = 60_000

fixture.PROJECT_PATH = f"{ROOT}/projects/attention-edge"
fixture.SESSION_PATH = (
    f"{ROOT}/.omp/agent/sessions/-projects-attention-edge/session.jsonl"
)
fixture.CONTROL_LOG = f"{ROOT}/fixtures/attention-edge-control.jsonl"
fixture.SESSION_ID = "attention-edge-acceptance-session"
fixture.TITLE = "Attention timeout and cancel acceptance"
fixture.MODEL = {
    **fixture.MODEL,
    "id": "attention-edge-fixture",
    "name": "Attention Edge Fixture",
}
fixture.REQUESTS = (
    (
        1.0,
        {
            "type": "extension_ui_request",
            "id": "attention-edge-timeout-confirm",
            "method": "confirm",
            "title": "Let this request time out",
            "message": "Wait briefly without choosing Run or Cancel.",
            # ExtensionUIRouter interprets timeout as integer milliseconds.
            "timeout": TIMEOUT_MS,
        },
    ),
    (
        4.5,
        {
            "type": "extension_ui_request",
            "id": "attention-edge-explicit-cancel-input",
            "method": "input",
            "title": "Cancel this input explicitly",
            "placeholder": "Leave empty and choose Cancel",
        },
    ),
)


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, lambda _signum, _frame: fixture.stop_event.set())
    raise SystemExit(fixture.main())
