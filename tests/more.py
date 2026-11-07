#!/usr/bin/env python3
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from lsp_client import Client
exe = sys.argv[1]
fx = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixture")
uri = "file://" + os.path.join(fx, "More.mod")
text = open(os.path.join(fx, "More.mod")).read(); lines = text.split("\n")
c = Client(exe)
c.request("initialize", {"capabilities": {}})
c.notify("textDocument/didOpen", {"textDocument": {"uri": uri, "languageId": "modula2", "version": 1, "text": text}})
c.wait_note("textDocument/publishDiagnostics")
def at(snippet, needle):
    for i, l in enumerate(lines):
        if snippet in l:
            return {"line": i, "character": l.find(snippet) + snippet.find(needle) + len(needle)}
    raise KeyError(snippet)
def comp(p):
    r = c.request("textDocument/completion", {"textDocument": {"uri": uri}, "position": p})["result"]
    return sorted(i["label"] for i in r["items"] if i["label"][0].islower())
def hov(snippet, needle):
    r = c.request("textDocument/hover", {"textDocument": {"uri": uri}, "position": at(snippet, needle)})["result"]
    return r and r["contents"]["value"].split("\n")[1]
ok = True
def check(name, got, want):
    global ok
    bad = got != want
    ok &= not bad
    print("%-22s %s%s" % (name, got, "   <-- expected %s" % (want,) if bad else ""))
check("local type lp^.", comp(at("lp^.alpha", "lp^.")), ["alpha", "beta"])
check("variant tk.", comp(at("tk.num", "tk.")), ["kind", "neg", "num", "other", "pos", "tail", "text"])
check("hover local fld", hov("lp^.alpha", "alp"), "alpha, beta: INTEGER")
check("hover type", hov("Token = RECORD", "Tok"), "Token = RECORD")
check("hover const", hov("Limit = 16", "Lim"), "Limit = 16")
check("hover small", hov("small: RECORD", "sma"), "small: RECORD")
check("hover inline fld", hov("small: RECORD a: INTEGER END", "RECORD a"), "a: INTEGER")
print("ALL OK" if ok else "FAILURES")
c.close()
