#!/usr/bin/env python3
import sys, os, json, time
sys.path.insert(0, os.path.dirname(__file__))
from lsp_client import Client
exe = sys.argv[1]
fx = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixture")
c = Client(exe, env={"M2LSP_FLAGS": ""})
c.request("initialize", {"processId": None, "rootUri": None, "capabilities": {}})
def opn(name, text):
    uri = "file://" + os.path.join(fx, name)
    c.notify("textDocument/didOpen", {"textDocument": {"uri": uri, "languageId": "modula2", "version": 1, "text": text}})
    return uri, c.wait_note("textDocument/publishDiagnostics")["params"]["diagnostics"]
def comp(uri, l, ch):
    r = c.request("textDocument/completion", {"textDocument": {"uri": uri}, "position": {"line": l, "character": ch}})
    return r.get("result") and [i["label"] for i in r["result"]["items"]]
def req(m, uri, l, ch):
    return c.request("textDocument/" + m, {"textDocument": {"uri": uri}, "position": {"line": l, "character": ch}}).get("result")

uri, d = opn("Empty.mod", "")
print("empty diag:", [x["message"][:60] for x in d])
print("empty completion count:", len(comp(uri, 0, 0)), "hover:", req("hover", uri, 0, 0), "def:", req("definition", uri, 5, 5))
c.notify("textDocument/didChange", {"textDocument": {"uri": uri}, "contentChanges": [{"text": "(* unterminated\nMODULE X;\nVAR a: ARRAY [0..3] OF RECORD q: INTEGER END;"}]})
print("garbage completion:", len(comp(uri, 2, 10)), req("hover", uri, 99, 99))
c.notify("textDocument/didChange", {"textDocument": {"uri": uri}, "contentChanges": [{"text": "MODULE X;\nVAR a: ARRAY [0..3] OF RECORD q: INTEGER END;\nBEGIN\n  a[1].\nEND X.\n"}]})
print("a[1]. ->", comp(uri, 3, 7))
c.notify("textDocument/didChange", {"textDocument": {"uri": uri}, "contentChanges": [{"text": "MODULE X;\nBEGIN\n  WriteString('a.b'); (* x. *)\nEND X.\n"}]})
print("in string:", comp(uri, 2, 16), "in comment:", comp(uri, 2, 26))
# syntax errors
uri2, d = opn("Bad.mod", "MODULE Bad;\nVAR x: CARDINAL;\nBEGIN\n  x := 1 +;\n  IF x THEN\nEND Bad.\n")
for x in d: print("bad diag:", x["range"]["start"], x["severity"], x["message"][:70])
# def file doc
uri3, d = opn("Shapes.def", open(os.path.join(fx, "Shapes.def")).read())
print("def diag:", [x["message"][:60] for x in d])
r = c.request("textDocument/documentSymbol", {"textDocument": {"uri": uri3}})["result"]
print("def symbols:", [(s["name"], s["kind"], s.get("containerName")) for s in r])
# perf
big = open(os.path.join(fx, "Demo.mod")).read()
body = "\n".join("PROCEDURE P%d (a: CARDINAL; b: Shape);\nVAR v%d: CARDINAL;\nBEGIN\n  v%d := a\nEND P%d;\n" % (i, i, i, i) for i in range(3000))
src = "MODULE Big;\nFROM Shapes IMPORT Shape;\n" + body + "BEGIN\nEND Big.\n"
print("big size:", len(src))
t = time.time()
uri4 = "file://" + os.path.join(fx, "Big.mod")
c.notify("textDocument/didOpen", {"textDocument": {"uri": uri4, "languageId": "modula2", "version": 1, "text": src}})
c.request("textDocument/documentSymbol", {"textDocument": {"uri": uri4}})
print("scan+symbols: %.2fs" % (time.time() - t))
t = time.time(); n = len(comp(uri4, 5000, 3) or []); print("completion %d items %.2fs" % (n, time.time() - t))
c.wait_note("textDocument/publishDiagnostics")
c.close(); print("ok")
