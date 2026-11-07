IMPLEMENTATION MODULE Lint;

FROM Text IMPORT Buf, Add, AddCh, AddCard, AddJson, Eq, Append, Copy;
FROM Symbols IMPORT Doc, Name, SymKind;
IMPORT Nav;

CONST
  MaxMembers = 256;
  ShowMax = 8;

PROCEDURE CheckCase (d: Doc; c: CARDINAL; VAR out: Buf; VAR first: BOOLEAN);
VAR
  ed: Doc;
  et: INTEGER;
  members: ARRAY [0..MaxMembers - 1] OF CARDINAL;   (* symbol index of each member, in order *)
  covered: ARRAY [0..MaxMembers - 1] OF BOOLEAN;
  nm, k, m, lo, hi, shown, missing, tok: CARDINAL;
  known, inRange: BOOLEAN;
  msg: ARRAY [0..511] OF CHAR;
  tokp: CARDINAL;
BEGIN
  IF d^.syms^[c].hasElse OR d^.syms^[c].opaque THEN RETURN END;
  tok := d^.syms^[c].tok;
  IF NOT Nav.SelectorEnum (d, d^.syms^[c].imp, d^.toks^[tok].start, ed, et) THEN RETURN END;
  (* enumeration members in declaration order *)
  nm := 0;
  k := 0;
  WHILE (k < ed^.nsyms) AND (nm < MaxMembers) DO
    IF (ed^.syms^[k].kind = skEnum) AND (ed^.syms^[k].owner = et) THEN
      members[nm] := k;
      covered[nm] := FALSE;
      INC (nm)
    END;
    INC (k)
  END;
  IF nm = 0 THEN RETURN END;
  (* labels *)
  inRange := FALSE;
  lo := 0;
  k := 0;
  WHILE k < d^.nsyms DO
    IF (d^.syms^[k].kind = skLabel) AND (d^.syms^[k].owner = VAL (INTEGER, c)) THEN
      known := FALSE;
      m := 0;
      WHILE (m < nm) AND NOT known DO
        IF Eq (ed^.syms^[members[m]].name, d^.syms^[k].name) THEN known := TRUE ELSE INC (m) END
      END;
      IF NOT known THEN RETURN END;   (* a label we cannot place: stay quiet rather than guess *)
      IF inRange THEN
        hi := m;
        IF hi < lo THEN hi := lo; lo := m END;
        FOR m := lo TO hi DO covered[m] := TRUE END;
        inRange := FALSE
      ELSIF d^.syms^[k].isRecord THEN
        lo := m;
        inRange := TRUE
      ELSE
        covered[m] := TRUE
      END
    END;
    INC (k)
  END;
  missing := 0;
  FOR m := 0 TO nm - 1 DO
    IF NOT covered[m] THEN INC (missing) END
  END;
  IF missing = 0 THEN RETURN END;
  Copy (msg, 'CASE has no ELSE and does not handle ');
  Append (msg, ed^.syms^[et].name);
  Append (msg, ': ');
  shown := 0;
  FOR m := 0 TO nm - 1 DO
    IF NOT covered[m] THEN
      IF shown < ShowMax THEN
        IF shown > 0 THEN Append (msg, ', ') END;
        Append (msg, ed^.syms^[members[m]].name)
      END;
      INC (shown)
    END
  END;
  IF shown > ShowMax THEN Append (msg, ', ...') END;
  IF first THEN first := FALSE ELSE AddCh (out, ',') END;
  Add (out, '{"range":{"start":{"line":');
  AddCard (out, d^.toks^[tok].line);
  Add (out, ',"character":'); AddCard (out, d^.toks^[tok].col);
  Add (out, '},"end":{"line":'); AddCard (out, d^.toks^[tok].line);
  Add (out, ',"character":'); AddCard (out, d^.toks^[tok].col + 4);
  Add (out, '}},"severity":2,"source":"m2lsp","message":');
  AddJson (out, msg);
  AddCh (out, '}')
END CheckCase;

PROCEDURE Check (d: Doc; VAR out: Buf; VAR first: BOOLEAN);
VAR k: CARDINAL;
BEGIN
  k := 0;
  WHILE k < d^.nsyms DO
    IF d^.syms^[k].kind = skCase THEN CheckCase (d, k, out, first) END;
    INC (k)
  END
END Check;

END Lint.
