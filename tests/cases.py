#!/usr/bin/env python3
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from lsp_client import Client
exe = sys.argv[1]
fx = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixture")
uri = "file://" + os.path.join(fx, "Cases.mod")
text = open(os.path.join(fx, "Cases.mod")).read()
c = Client(exe)
c.request("initialize", {"capabilities": {}})
c.notify("textDocument/didOpen", {"textDocument": {"uri": uri, "languageId": "modula2", "version": 1, "text": text}})
d = c.wait_note("textDocument/publishDiagnostics")["params"]["diagnostics"]
got = sorted((x["range"]["start"]["line"] + 1, x["message"]) for x in d if x["source"] == "m2lsp")
for g in got: print(g)
want = [(21, "CASE has no ELSE and does not handle Kind: Hexagon"),
        (38, "CASE has no ELSE and does not handle Kind: Triangle, Hexagon")]
print("others from gm2:", [x["message"][:50] for x in d if x["source"] != "m2lsp"])
print("ALL OK" if got == want else "FAILURES, wanted %s" % want)
c.close()
