# Distinct Fresh Sessions

## Problem

10x has two paths for creating a session. A warm OMP client previously started
with `--no-session`, while a cold client started without an explicit session
mode. When the user's OMP configuration enables `autoResume`, the cold client
resumes the most recent session for the project instead of creating a fresh one.

Two cold clients can therefore report the same persisted session path. The
process manager indexes active clients by that path, so the later registration
replaces the first owner and the application routes both launches to the same
session controller. Both OMP processes may also write the same JSONL file.

## Design

Real OMP validation showed that `--no-session` is not a valid fresh-session
contract: it creates an in-memory `SessionManager`, and a later `new_session`
command remains non-persistent. Those sessions cannot appear in the library or
be resumed after the process exits.

Every client intended for `openNew` will instead start with an explicit
`--session-dir` pointing at OMP's normal bucket for the canonical project path.
OMP treats this as an explicit session destination, bypasses `autoResume`, and
creates a fresh persisted JSONL file at process startup.

The lifecycle is:

1. Canonicalize the project path and derive its normal OMP session bucket.
2. Start OMP with `--session-dir <bucket>`.
3. For a checked-out warm client, send `new_session` to replace the unused warm
   identity; for a cold client, use the fresh identity created at startup.
4. Apply any requested model and thinking selections.
5. Read `get_state` and register the returned persisted session path.

If OMP does not return `sessionFile`, opening fails and the process is shut down.
10x never registers an in-memory fallback as if it were a persisted session.

Before installing an active handle, the process manager will reject a session
path already owned by another managed client. The rejected client will be shut
down and the existing owner will remain unchanged. This guard is defense in
depth for invalid or future OMP responses; it is not a retry mechanism.

## Error Handling

Duplicate ownership will surface as a typed process-manager error containing
the duplicate session path. The normal `SessionController.openNew` failure path
will present the runtime failure without replacing or closing the existing
session.

If `new_session` or `get_state` fails, the opening transition will be discarded
and its child process shut down through the existing cleanup path.

## Tests

- Cold and warm configurations include the canonical project's
  `--session-dir` and do not include `--no-session`.
- A cold `openNew` reads the startup-created session with `get_state`; a warm
  checkout sends `new_session` before `get_state`.
- A missing `sessionFile` fails the opening and shuts down the child.
- Two cold `openNew` calls for one project can return distinct persisted paths
  and retain distinct client handles.
- An opt-in integration test runs two `openNew` calls against the installed OMP
  binary and verifies two distinct JSONL paths in one project bucket.
- A duplicate path response fails the later opening, preserves the original
  handle, and shuts down the rejected client.
- Existing warm checkout, resume, cancellation, and shutdown tests remain
  green.

## Scope

This change only corrects new-session ownership in `OmpKit`. It does not alter
OMP configuration, session grouping, UI routing, or existing-session resume
behavior.
