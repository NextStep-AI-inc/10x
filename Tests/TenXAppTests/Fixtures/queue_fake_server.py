#!/usr/bin/env python3
"""Controlled queue fixture for SessionController integration tests.

Run as an RPC server with a control directory, or as a short-lived controller:
    queue_fake_server.py server <control-directory>
    queue_fake_server.py control <control-directory> <action>
"""

import json
import os
import socket
import sys
import threading


def socket_path(control_directory):
    return os.path.join("/tmp", "10x-queue-" + os.path.basename(control_directory)[-36:] + ".sock")


def control(control_directory, action):
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.connect(socket_path(control_directory))
    client.sendall((json.dumps({"action": action}) + "\n").encode())
    response = b""
    while not response.endswith(b"\n"):
        chunk = client.recv(4096)
        if not chunk:
            break
        response += chunk
    client.close()
    result = json.loads(response)
    if not result.get("ok"):
        raise RuntimeError(result.get("error", "queue fixture control failed"))


class QueueServer:
    def __init__(self, control_directory):
        self.control_directory = control_directory
        self.socket_path = socket_path(control_directory)
        self.session_path = os.path.join(control_directory, "session.jsonl")
        self.state_lock = threading.Lock()
        self.write_lock = threading.Lock()
        self.queue = []
        self.messages = []
        self.next_message_id = 1
        self.reject_next = False
        self.defer_next_state = False
        self.deferred_states = []
        self.is_stopping = threading.Event()

    def emit(self, value):
        with self.write_lock:
            print(json.dumps(value, separators=(",", ":")), flush=True)

    def state(self, count):
        return {
            "model": {"id": "fake", "provider": "test", "name": "Fake"},
            "isStreaming": True,
            "sessionFile": self.session_path,
            "contextUsage": {"tokens": 1000, "contextWindow": 200000, "percent": 1},
            "queuedMessageCount": count,
        }

    def respond(self, command, data=None, success=True, error=None):
        response = {
            "id": command["id"],
            "type": "response",
            "command": command["type"],
            "success": success,
            "data": data or {},
        }
        if error is not None:
            response["error"] = error
        self.emit(response)

    def consume(self):
        self.emit({"type": "turn_end"})
        with self.state_lock:
            if not self.queue:
                raise RuntimeError("queue is empty")
            text = self.queue.pop(0)["text"]
            message = {
                "id": f"user-{self.next_message_id}",
                "role": "user",
                "content": [{"type": "text", "text": text}],
            }
            self.next_message_id += 1
            self.messages.append(message)

        # OMP removes the input after the prior turn ends and before the next
        # turn/user lifecycle begins.
        self.emit({"type": "turn_start"})
        self.emit({"type": "message_start", "message": message})
        self.emit({"type": "message_end", "message": message})

    def handle_control(self, connection):
        try:
            request = json.loads(connection.makefile().readline())
            action = request["action"]
            if action == "consume":
                self.consume()
            elif action == "reject-next":
                with self.state_lock:
                    self.reject_next = True
            elif action == "defer-next-state":
                with self.state_lock:
                    self.defer_next_state = True
            elif action == "release-deferred-state":
                with self.state_lock:
                    deferred = self.deferred_states
                    self.deferred_states = []
                for response in deferred:
                    self.emit(response)
            else:
                raise RuntimeError(f"unknown action: {action}")
            connection.sendall(b'{"ok":true}\n')
        except Exception as error:
            connection.sendall((json.dumps({"ok": False, "error": str(error)}) + "\n").encode())
        finally:
            connection.close()

    def listen_for_control(self):
        os.makedirs(self.control_directory, exist_ok=True)
        try:
            os.unlink(self.socket_path)
        except FileNotFoundError:
            pass
        listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        listener.bind(self.socket_path)
        listener.listen()
        listener.settimeout(0.1)
        try:
            while not self.is_stopping.is_set():
                try:
                    connection, _ = listener.accept()
                except socket.timeout:
                    continue
                self.handle_control(connection)
        finally:
            listener.close()

    def run(self):
        control_thread = threading.Thread(target=self.listen_for_control, daemon=True)
        control_thread.start()
        while not os.path.exists(self.socket_path):
            threading.Event().wait(0.001)
        self.emit({
            "type": "ready",
            "protocolVersion": 1,
            "supportedProtocolVersions": [1, 2],
            "maxFrameBytes": 1048576,
            "maxReassembledFrameBytes": 67108864,
        })

        try:
            for line in sys.stdin:
                command = json.loads(line)
                kind = command["type"]
                if kind == "negotiate_protocol":
                    self.respond(command, {"protocolVersion": 2})
                elif kind == "get_state":
                    with self.state_lock:
                        count = len(self.queue)
                        should_defer = self.defer_next_state
                        self.defer_next_state = False
                    response = {
                        "id": command["id"],
                        "type": "response",
                        "command": kind,
                        "success": True,
                        "data": self.state(count),
                    }
                    if should_defer:
                        with self.state_lock:
                            self.deferred_states.append(response)
                        open(os.path.join(self.control_directory, "state-deferred"), "w").close()
                    else:
                        self.emit(response)
                elif kind in {"get_messages", "get_messages_page"}:
                    with self.state_lock:
                        messages = list(self.messages)
                    data = {"messages": messages}
                    if kind == "get_messages_page":
                        data["nextCursor"] = None
                    self.respond(command, data)
                elif kind == "get_available_commands":
                    self.respond(command, {"commands": []})
                elif kind == "prompt":
                    with self.state_lock:
                        should_reject = self.reject_next
                        self.reject_next = False
                        if not should_reject:
                            self.queue.append({
                                "text": command.get("message", ""),
                                "behavior": command.get("streamingBehavior"),
                            })
                    if should_reject:
                        self.respond(command, success=False, error="controlled rejection")
                    else:
                        self.respond(command)
                else:
                    self.respond(command)
        finally:
            self.is_stopping.set()
            control_thread.join(timeout=1)
            try:
                os.unlink(self.socket_path)
            except FileNotFoundError:
                pass


if __name__ == "__main__":
    if sys.argv[1] == "control":
        control(sys.argv[2], sys.argv[3])
    else:
        QueueServer(sys.argv[2]).run()
