#!/usr/bin/env python3
"""Tiny LSP test client: drives m2lsp over stdio and prints what comes back."""
import json, subprocess, sys, os

class Client:
    def __init__(self, exe, env=None):
        e = dict(os.environ); e.update(env or {})
        self.p = subprocess.Popen([exe], stdin=subprocess.PIPE, stdout=subprocess.PIPE, env=e)
        self.n = 0
        self.notes = []

    def _send(self, obj):
        b = json.dumps(obj).encode()
        self.p.stdin.write(b"Content-Length: %d\r\n\r\n" % len(b) + b)
        self.p.stdin.flush()

    def _read(self):
        length = None
        while True:
            line = self.p.stdout.readline()
            if not line:
                raise EOFError("server closed")
            line = line.strip()
            if not line:
                break
            if line.lower().startswith(b"content-length:"):
                length = int(line.split(b":")[1])
        return json.loads(self.p.stdout.read(length))

    def notify(self, method, params):
        self._send({"jsonrpc": "2.0", "method": method, "params": params})

    def request(self, method, params):
        self.n += 1
        self._send({"jsonrpc": "2.0", "id": self.n, "method": method, "params": params})
        while True:
            m = self._read()
            if m.get("id") == self.n and "method" not in m:
                return m
            self.notes.append(m)

    def wait_note(self, method):
        for i, m in enumerate(self.notes):
            if m.get("method") == method:
                return self.notes.pop(i)
        while True:
            m = self._read()
            if m.get("method") == method:
                return m
            self.notes.append(m)

    def close(self):
        self.request("shutdown", None)
        self.notify("exit", None)
        self.p.wait(timeout=5)
