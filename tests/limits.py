#!/usr/bin/env python3
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from lsp_client import Client
exe = sys.argv[1]
fx = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixture")
uri = "file://" + os.path.join(fx, "Limits.mod")
text = open(os.path.join(fx, "Limits.mod")).read(); lines = text.split("\n")
c = Client(exe)
c.request("initialize", {"capabilities": {}})
c.notify("textDocument/didOpen", {"textDocument": {"uri": uri, "languageId": "modula2", "version": 1, "text": text}})
c.wait_note("textDocument/publishDiagnostics")
def at(line_starts, needle, extra=0):
    for i, l in enumerate(lines):
        if l.strip().startswith(line_starts) or line_starts in l:
            col = l.find(needle) + len(needle) + extra
            return {"line": i, "character": col}
    raise KeyError(line_starts)
def comp(p):
    r = c.request("textDocument/completion", {"textDocument": {"uri": uri}, "position": p})["result"]
    return sorted(i["label"] for i in r["items"] if i["label"].islower() or i["label"][0].islower())
def hov(p):
    r = c.request("textDocument/hover", {"textDocument": {"uri": uri}, "position": p})["result"]
    return r and r["contents"]["value"].split("\n")[1]
checks = [
 ("grid[1].",            comp(at("grid[1].tag", "grid[1].")),            ["cell", "tag"]),
 ("cfg.",                comp(at("cfg.inner.depth", "cfg.")),            ["inner", "name"]),
 ("cfg.inner.",          comp(at("cfg.inner.depth", "cfg.inner.")),      ["depth"]),
 ("Current ().",         comp(at("Current ().size", "Current ().")),      ["kind", "origin", "size"]),
 ("NewShape(..)^.",      comp(at("^.origin.x", "^.")),                    ["kind", "origin", "size"]),
 ("WITH cfg: bare",      [x for x in comp(at("    name := 1", "    na")) if x in ("name", "inner")], ["name"]),
 ("WITH nested: bare",   [x for x in comp(at("      depth := 3", "      de")) if x in ("depth", "name")], ["depth"]),
 ("WITH sh^: bare",      [x for x in comp(at("    kind := Circle", "    ki")) if x in ("kind", "size", "origin")], ["kind"]),
]
ok = True
for name, got, want in checks:
    flag = "" if want is None or got == want else "   <-- expected %s" % want
    if flag: ok = False
    print("%-20s %s%s" % (name, got, flag))
print("hover WITH field 'depth':", hov(at("      depth := 3", "      dep")))
print("hover WITH field 'name': ", hov(at("    name := 1", "    nam")))
print("ALL OK" if ok else "FAILURES")
c.close()
