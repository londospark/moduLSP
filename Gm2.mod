IMPLEMENTATION MODULE Gm2;

FROM SYSTEM IMPORT ADDRESS, ADR;
FROM libc IMPORT system, getenv, getpid;
FROM Text IMPORT Buf, CharPtr, Init, Release, Add, AddCh, AddCard, AddJson, AddJsonRange,
                 Copy, CopyRange, Append, Len, IsDigit, IsIdChar;
FROM Symbols IMPORT Doc, PathLen;
FROM Files IMPORT ReadFile, WriteFile, Exists, DirName, BaseName, ShellQuote;
FROM Lexer IMPORT OffsetOf;
IMPORT Units;

CONST
  MaxDiag = 200;

VAR
  tmpDir: ARRAY [0..255] OF CHAR;
  flags: ARRAY [0..255] OF CHAR;
  includes: ARRAY [0..1023] OF CHAR;   (* ready-made " -I'dir'" list *)

PROCEDURE Run (cmd: ARRAY OF CHAR);
VAR r: INTEGER;
BEGIN
  r := system (ADR (cmd))
END Run;

PROCEDURE Env (name: ARRAY OF CHAR; VAR value: ARRAY OF CHAR);
VAR
  p: ADDRESS;
  cp: CharPtr;
  i: CARDINAL;
BEGIN
  value[0] := 0C;
  p := getenv (ADR (name));
  IF p # NIL THEN
    cp := p;
    i := 0;
    WHILE (cp^[i] # 0C) AND (i < HIGH (value)) DO
      value[i] := cp^[i];
      INC (i)
    END;
    value[i] := 0C
  END
END Env;

PROCEDURE Contains (s, sub: ARRAY OF CHAR): BOOLEAN;
VAR i, j, n, m: CARDINAL; ok: BOOLEAN;
BEGIN
  n := Len (s); m := Len (sub);
  IF m = 0 THEN RETURN TRUE END;
  i := 0;
  WHILE i + m <= n DO
    ok := TRUE; j := 0;
    WHILE ok AND (j < m) DO
      IF s[i + j] # sub[j] THEN ok := FALSE END;
      INC (j)
    END;
    IF ok THEN RETURN TRUE END;
    INC (i)
  END;
  RETURN FALSE
END Contains;

(* Ask gm2 where a library file lives and add that directory to the .def search path. *)
PROCEDURE AddLibDir (rel: ARRAY OF CHAR);
VAR
  cmd, out, dir: ARRAY [0..511] OF CHAR;
  b: Buf;
  n: CARDINAL;
BEGIN
  Copy (cmd, 'gm2 -print-file-name=');
  Append (cmd, rel);
  Append (cmd, ' > ');
  Append (cmd, tmpDir);
  Append (cmd, '/lib.txt 2>/dev/null');
  Run (cmd);
  Copy (out, tmpDir);
  Append (out, '/lib.txt');
  Init (b);
  IF ReadFile (out, b) AND (b.len > 0) THEN
    n := b.len;
    WHILE (n > 0) AND ((b.data^[n - 1] = 12C) OR (b.data^[n - 1] = 15C)) DO DEC (n) END;
    IF (n > 0) AND (b.data^[0] = '/') THEN
      CopyRange (out, b.data, 0, n);
      IF Exists (out) THEN
        DirName (out, dir);
        Units.AddDir (dir)
      END
    END
  END;
  Release (b)
END AddLibDir;

PROCEDURE AddIncludes (list: ARRAY OF CHAR);
VAR
  i, st, n: CARDINAL;
  dir, q: ARRAY [0..PathLen - 1] OF CHAR;
BEGIN
  i := 0;
  WHILE i <= Len (list) DO
    st := i;
    WHILE (i < Len (list)) AND (list[i] # ':') DO INC (i) END;
    IF i > st THEN
      n := 0;
      WHILE (st < i) AND (n < HIGH (dir)) DO
        dir[n] := list[st];
        INC (n); INC (st)
      END;
      dir[n] := 0C;
      Units.AddDir (dir);
      ShellQuote (dir, q);
      Append (includes, ' -I');
      Append (includes, q)
    END;
    INC (i)
  END
END AddIncludes;

PROCEDURE Setup;
VAR
  pid: Buf;
  cmd: ARRAY [0..511] OF CHAR;
  list: ARRAY [0..1023] OF CHAR;
BEGIN
  Init (pid);
  AddCard (pid, VAL (CARDINAL, getpid ()));
  Copy (tmpDir, '/tmp/m2lsp-');
  Append (tmpDir, '');
  CopyRange (cmd, pid.data, 0, pid.len);
  Append (tmpDir, cmd);
  Release (pid);
  Copy (cmd, 'mkdir -p ');
  Append (cmd, tmpDir);
  Run (cmd);
  Env ('M2LSP_FLAGS', flags);
  includes[0] := 0C;
  Env ('M2LSP_INCLUDE', list);
  AddIncludes (list);
  IF Contains (flags, '-fiso') THEN
    AddLibDir ('m2/m2iso/ASCII.def');
    AddLibDir ('m2/m2pim/SYSTEM.def')
  ELSE
    AddLibDir ('m2/m2pim/SYSTEM.def');
    AddLibDir ('m2/m2iso/ASCII.def')
  END
END Setup;

(* ---- diagnostics ---- *)

PROCEDURE RangeHas (t: CharPtr; lo, hi: CARDINAL; sub: ARRAY OF CHAR): BOOLEAN;
VAR i, j, m: CARDINAL; ok: BOOLEAN;
BEGIN
  m := Len (sub);
  i := lo;
  WHILE i + m <= hi DO
    ok := TRUE; j := 0;
    WHILE ok AND (j < m) DO
      IF t^[i + j] # sub[j] THEN ok := FALSE END;
      INC (j)
    END;
    IF ok THEN RETURN TRUE END;
    INC (i)
  END;
  RETURN FALSE
END RangeHas;

PROCEDURE Check (d: Doc; VAR out: Buf; VAR first: BOOLEAN);
VAR
  base, dir, qdir, qfile, qerr, file, errFile, cmd: ARRAY [0..1023] OF CHAR;
  eb: Buf;
  p, ls, le, n, line, col, off, k, count: CARDINAL;
  sevStart, sevEnd, msgStart, sev: CARDINAL;
  t: CharPtr;
  ok: BOOLEAN;
  fl: CARDINAL;
BEGIN
  BaseName (d^.path, base);
  DirName (d^.path, dir);
  Copy (file, tmpDir);
  Append (file, '/');
  Append (file, base);
  Copy (errFile, tmpDir);
  Append (errFile, '/err.txt');
  IF NOT WriteFile (file, d^.text) THEN RETURN END;
  ShellQuote (dir, qdir);
  ShellQuote (file, qfile);
  ShellQuote (errFile, qerr);
  Copy (cmd, 'gm2 -fsyntax-only ');
  Append (cmd, flags);
  Append (cmd, ' -I');
  Append (cmd, qdir);
  Append (cmd, includes);
  Append (cmd, ' -x modula-2 ');
  Append (cmd, qfile);
  Append (cmd, ' 2> ');
  Append (cmd, qerr);
  Append (cmd, ' >/dev/null');
  Run (cmd);
  Init (eb);
  count := 0;
  IF ReadFile (errFile, eb) THEN
    t := eb.data;
    fl := Len (file);
    p := 0;
    WHILE (p < eb.len) AND (count < MaxDiag) DO
      ls := p;
      WHILE (p < eb.len) AND (t^[p] # 12C) DO INC (p) END;
      le := p;
      INC (p);
      (* "<file>:LINE[:COL]: severity: message" *)
      ok := (le - ls > fl + 2);
      k := 0;
      WHILE ok AND (k < fl) DO
        IF t^[ls + k] # file[k] THEN ok := FALSE END;
        INC (k)
      END;
      IF ok AND (t^[ls + fl] = ':') AND IsDigit (t^[ls + fl + 1]) THEN
        n := ls + fl + 1;
        line := 0;
        WHILE (n < le) AND IsDigit (t^[n]) DO
          line := line * 10 + (ORD (t^[n]) - ORD ('0')); INC (n)
        END;
        col := 1;
        IF (n < le) AND (t^[n] = ':') AND (n + 1 < le) AND IsDigit (t^[n + 1]) THEN
          INC (n);
          col := 0;
          WHILE (n < le) AND IsDigit (t^[n]) DO
            col := col * 10 + (ORD (t^[n]) - ORD ('0')); INC (n)
          END
        END;
        IF (n < le) AND (t^[n] = ':') THEN
          INC (n);
          WHILE (n < le) AND (t^[n] = ' ') DO INC (n) END;
          sevStart := n;
          WHILE (n < le) AND (t^[n] # ':') DO INC (n) END;
          sevEnd := n;
          msgStart := n + 1;
          WHILE (msgStart < le) AND (t^[msgStart] = ' ') DO INC (msgStart) END;
          sev := 0;
          IF (sevEnd - sevStart >= 5) AND (t^[sevStart] = 'e') THEN sev := 1
          ELSIF (sevEnd - sevStart >= 5) AND (t^[sevStart] = 'f') THEN sev := 1
          ELSIF (sevEnd - sevStart >= 7) AND (t^[sevStart] = 'w') THEN sev := 2
          ELSIF (sevEnd - sevStart = 4) AND (t^[sevStart] = 'n') THEN sev := 3 END;
          IF (sev # 0) AND (line > 0) AND (n < le)
             AND NOT RangeHas (t, msgStart, le, 'dynamic module registration') THEN
            IF col = 0 THEN col := 1 END;
            off := OffsetOf (d^.text.data, d^.text.len, line - 1, col - 1);
            k := 0;
            WHILE (off + k < d^.text.len) AND IsIdChar (d^.text.data^[off + k]) DO INC (k) END;
            IF k = 0 THEN k := 1 END;
            IF first THEN first := FALSE ELSE AddCh (out, ',') END;
            Add (out, '{"range":{"start":{"line":');
            AddCard (out, line - 1);
            Add (out, ',"character":'); AddCard (out, col - 1);
            Add (out, '},"end":{"line":'); AddCard (out, line - 1);
            Add (out, ',"character":'); AddCard (out, col - 1 + k);
            Add (out, '}},"severity":'); AddCard (out, sev);
            Add (out, ',"source":"gm2","message":');
            AddJsonRange (out, t, msgStart, le);
            AddCh (out, '}');
            INC (count)
          END
        END
      END
    END
  END;
  Release (eb)
END Check;

END Gm2.
