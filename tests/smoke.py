#!/usr/bin/env python3
import sys, os, json
sys.path.insert(0, os.path.dirname(__file__))
from lsp_client import Client

exe = sys.argv[1]
fx = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixture")
uri = "file://" + os.path.join(fx, "Demo.mod")
text = open(os.path.join(fx, "Demo.mod")).read()
lines = text.split("\n")

def pos(needle, nth=0, delta=0):
    """position just after `needle` (nth occurrence), plus delta columns"""
    seen = 0
    for i, l in enumerate(lines):
        start = 0
        while True:
            c = l.find(needle, start)
            if c < 0: break
            if seen == nth:
                return {"line": i, "character": c + len(needle) + delta}
            seen += 1; start = c + 1
    raise KeyError(needle)

c = Client(exe)
r = c.request("initialize", {"processId": None, "rootUri": None, "capabilities": {}})
print("init:", list(r["result"]["capabilities"].keys()))
c.notify("initialized", {})
c.notify("textDocument/didOpen", {"textDocument": {"uri": uri, "languageId": "modula2", "version": 1, "text": text}})
d = c.wait_note("textDocument/publishDiagnostics")
print("diagnostics:")
for x in d["params"]["diagnostics"]:
    print("  ", x["range"]["start"], x["severity"], x["message"])

def comp(p):
    r = c.request("textDocument/completion", {"textDocument": {"uri": uri}, "position": p})["result"]
    return [i["label"] for i in r["items"]]

print("after 'sh^.':     ", comp(pos("sh^.", 0)))
print("after 'sh^.origin.':", comp(pos("sh^.origin.", 0)))
print("after 'p.':       ", comp(pos("  p.", 0)))
print("after 'Shapes.':  ", comp(pos("Shapes.", 0)))
print("prefix 'loc':     ", comp(pos("  loc", 0)))   # in Describe? line is 'local := ' -> inside proc
print("prefix 'Wri':     ", comp(pos("  Wri", 0)) if False else "-")
print("prefix 'to' in proc:", comp(pos("  total := to", 0)))
print("prefix 'IN' (kw): ", [l for l in comp(pos("  total := tot", 0)) if l.isupper()][:5])

def show(name, p):
    r = c.request("textDocument/" + name, {"textDocument": {"uri": uri}, "position": p})
    print(name, json.dumps(r.get("result"))[:300])

show("hover", pos("Area (", 0, -4))
show("hover", pos("sh^.origin.", 0, -3))
show("definition", pos("s := NewShape", 0, -4))
show("definition", pos("Shapes.count", 0, -2))
show("definition", pos("local := Area", 0, -8))
show("hover", pos("  total := total", 0, -3))
r = c.request("textDocument/documentSymbol", {"textDocument": {"uri": uri}})["result"]
print("symbols:", [(s["name"], s["kind"], s.get("containerName")) for s in r])
c.close()
print("ok")
