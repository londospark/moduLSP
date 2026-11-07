IMPLEMENTATION MODULE Nav;

FROM Text IMPORT Buf, CharPtr, Init, Release, Add, AddCh, AddCard, AddBuf, AddRange,
                 AddJson, AddJsonRange, AddJsonFlat, Eq, Copy, Len, IsIdChar, IsSpace, HasPrefixCI;
FROM Lexer IMPORT Context, LineCol, KeywordCount, KeywordText;
FROM Symbols IMPORT Doc, Sym, SymKind, Name, NameLen, PathLen, Lookup, FindGlobal, FindTypeGlobal,
                    FindField, EnclosingProc, LookupType;
FROM Files IMPORT DirName, PathToUri;
IMPORT Units;
FROM Pervasive IMPORT BKind, Count, Get, Find;

CONST
  MaxChain = 15;

TYPE
  Chain = ARRAY [0..MaxChain] OF Name;

(* ---- small output helpers ---- *)

PROCEDURE Module (d: Doc; name: ARRAY OF CHAR): Doc;
VAR dir: ARRAY [0..PathLen - 1] OF CHAR;
BEGIN
  DirName (d^.path, dir);
  RETURN Units.Find (name, dir)
END Module;

PROCEDURE Flat (VAR b: Buf; p: CharPtr; lo, hi, limit: CARDINAL);
VAR n: CARDINAL; space: BOOLEAN;
BEGIN
  n := 0; space := TRUE;
  WHILE (lo < hi) AND (n < limit) DO
    IF IsSpace (p^[lo]) THEN
      IF NOT space THEN AddCh (b, ' '); INC (n) END;
      space := TRUE
    ELSE
      AddCh (b, p^[lo]); INC (n); space := FALSE
    END;
    INC (lo)
  END
END Flat;

PROCEDURE Sep (VAR out: Buf; VAR first: BOOLEAN);
BEGIN
  IF first THEN first := FALSE ELSE AddCh (out, ',') END
END Sep;

PROCEDURE Position (VAR out: Buf; line, col: CARDINAL);
BEGIN
  Add (out, '{"line":'); AddCard (out, line);
  Add (out, ',"character":'); AddCard (out, col);
  AddCh (out, '}')
END Position;

PROCEDURE RangeOfTok (VAR out: Buf; d: Doc; tok: CARDINAL);
BEGIN
  Add (out, '{"start":');
  Position (out, d^.toks^[tok].line, d^.toks^[tok].col);
  Add (out, ',"end":');
  Position (out, d^.toks^[tok].line, d^.toks^[tok].col + (d^.toks^[tok].stop - d^.toks^[tok].start));
  AddCh (out, '}')
END RangeOfTok;

(* ---- type and chain resolution ---- *)

(* The type symbol named by the declared type of symbol cur (in curD). *)
PROCEDURE TypeSymOf (curD: Doc; cur: INTEGER; VAR nextD: Doc; VAR t: INTEGER): BOOLEAN;
VAR
  u: Doc;
  i: INTEGER;
BEGIN
  IF curD^.syms^[cur].typeName[0] = 0C THEN RETURN FALSE END;
  t := -1;
  nextD := curD;
  IF curD^.syms^[cur].typeMod[0] # 0C THEN
    u := Module (curD, curD^.syms^[cur].typeMod);
    IF u = NIL THEN RETURN FALSE END;
    nextD := u;
    t := FindTypeGlobal (u, curD^.syms^[cur].typeName)
  ELSE
    i := LookupType (curD, curD^.syms^[cur].typeName, curD^.toks^[curD^.syms^[cur].tok].start);
    IF i >= 0 THEN
      IF curD^.syms^[i].kind = skType THEN
        t := i
      ELSE
        u := Module (curD, curD^.syms^[i].imp);
        IF u # NIL THEN
          nextD := u;
          t := FindTypeGlobal (u, curD^.syms^[cur].typeName)
        END
      END
    END
  END;
  RETURN t >= 0
END TypeSymOf;

(* The record type that the declared type of symbol s (in cd) leads to. *)
PROCEDURE TypeOfSym (cd: Doc; s: INTEGER; VAR rd: Doc; VAR rt: INTEGER): BOOLEAN;
VAR
  curD, nextD: Doc;
  cur, t: INTEGER;
  step: CARDINAL;
BEGIN
  curD := cd; cur := s;
  FOR step := 1 TO 8 DO
    IF curD^.syms^[cur].isRecord AND (curD^.syms^[cur].kind # skType) THEN
      rd := curD;
      IF curD^.syms^[cur].anonOwner >= 0 THEN rt := curD^.syms^[cur].anonOwner ELSE rt := cur END;
      RETURN TRUE
    END;
    IF NOT TypeSymOf (curD, cur, nextD, t) THEN RETURN FALSE END;
    IF nextD^.syms^[t].isRecord THEN
      rd := nextD; rt := t;
      RETURN TRUE
    END;
    curD := nextD; cur := t
  END;
  RETURN FALSE
END TypeOfSym;

PROCEDURE SplitChain (VAR src: Name; VAR names: Chain): CARDINAL;
VAR i, n, w: CARDINAL;
BEGIN
  n := 0; w := 0; names[0][0] := 0C;
  i := 0;
  WHILE (i < NameLen) AND (src[i] # 0C) DO
    IF src[i] = '.' THEN
      IF n < MaxChain THEN INC (n) END;
      w := 0; names[n][0] := 0C
    ELSIF w < NameLen - 1 THEN
      names[n][w] := src[i];
      INC (w);
      names[n][w] := 0C
    END;
    INC (i)
  END;
  RETURN n + 1
END SplitChain;

(* Resolve a.b.c to the thing that has members: a module (ct = -1) or a record type. *)
PROCEDURE ResolveChain (d: Doc; VAR names: Chain; count, offset: CARDINAL;
                        VAR cd: Doc; VAR ct: INTEGER): BOOLEAN;
VAR
  k, w, wc: CARDINAL;
  s, t: INTEGER;
  md, nd, wd: Doc;
  nt, wt: INTEGER;
  found: BOOLEAN;
  wnames: Chain;
BEGIN
  (* fields made visible by an enclosing WITH come first *)
  found := FALSE;
  w := d^.nsyms;
  WHILE (w > 0) AND NOT found DO
    DEC (w);
    IF (d^.syms^[w].kind = skWith) AND (d^.syms^[w].dFrom < offset) AND (offset <= d^.syms^[w].bodyEnd) THEN
      wc := SplitChain (d^.syms^[w].imp, wnames);
      IF ResolveChain (d, wnames, wc, d^.syms^[w].dFrom, wd, wt) AND (wt >= 0) THEN
        t := FindField (wd, wt, names[0]);
        IF t >= 0 THEN
          found := TRUE;
          IF NOT TypeOfSym (wd, t, cd, ct) THEN RETURN FALSE END
        END
      END
    END
  END;
  s := -1;
  IF NOT found THEN s := Lookup (d, names[0], offset) END;
  IF found THEN
    (* container already set *)
  ELSIF s >= 0 THEN
    CASE d^.syms^[s].kind OF
      skImport:
        md := Module (d, d^.syms^[s].imp);
        IF md = NIL THEN RETURN FALSE END;
        IF Eq (d^.syms^[s].name, d^.syms^[s].imp) THEN
          cd := md; ct := -1
        ELSE
          t := FindGlobal (md, names[0]);
          IF t < 0 THEN RETURN FALSE END;
          IF NOT TypeOfSym (md, t, cd, ct) THEN RETURN FALSE END
        END |
      skVar, skParam, skProc, skConst:
        IF NOT TypeOfSym (d, s, cd, ct) THEN RETURN FALSE END
    ELSE
      RETURN FALSE
    END
  ELSE
    md := Module (d, names[0]);
    IF md = NIL THEN RETURN FALSE END;
    cd := md; ct := -1
  END;
  k := 1;
  WHILE k < count DO
    IF ct = -1 THEN
      t := FindGlobal (cd, names[k])
    ELSE
      t := FindField (cd, ct, names[k])
    END;
    IF t < 0 THEN RETURN FALSE END;
    IF NOT TypeOfSym (cd, t, nd, nt) THEN RETURN FALSE END;
    cd := nd; ct := nt;
    INC (k)
  END;
  RETURN TRUE
END ResolveChain;

(* Record container of an active WITH statement (symbol w), innermost = highest index. *)
PROCEDURE WithContainer (d: Doc; w: CARDINAL; offset: CARDINAL; VAR cd: Doc; VAR ct: INTEGER): BOOLEAN;
VAR
  names: Chain;
  count: CARDINAL;
BEGIN
  IF (d^.syms^[w].kind # skWith) OR (d^.syms^[w].dFrom >= offset) OR (offset > d^.syms^[w].bodyEnd) THEN
    RETURN FALSE
  END;
  count := SplitChain (d^.syms^[w].imp, names);
  RETURN ResolveChain (d, names, count, d^.syms^[w].dFrom, cd, ct) AND (ct >= 0)
END WithContainer;

PROCEDURE WithField (d: Doc; name: ARRAY OF CHAR; offset: CARDINAL; VAR td: Doc; VAR ti: INTEGER): BOOLEAN;
VAR
  w: CARDINAL;
  cd: Doc;
  ct, t: INTEGER;
BEGIN
  w := d^.nsyms;
  WHILE w > 0 DO
    DEC (w);
    IF WithContainer (d, w, offset, cd, ct) THEN
      t := FindField (cd, ct, name);
      IF t >= 0 THEN
        td := cd; ti := t;
        RETURN TRUE
      END
    END
  END;
  RETURN FALSE
END WithField;

(* The symbol a dotted designator (a, a.b, M.x ...) names, as seen from offset. *)
PROCEDURE ResolveDesignator (d: Doc; VAR names: Chain; count, offset: CARDINAL;
                             VAR td: Doc; VAR ti: INTEGER): BOOLEAN;
VAR
  cd, md: Doc;
  ct, i, t: INTEGER;
BEGIN
  IF count = 0 THEN RETURN FALSE END;
  IF count = 1 THEN
    IF WithField (d, names[0], offset, td, ti) THEN RETURN TRUE END;
    i := Lookup (d, names[0], offset);
    IF i < 0 THEN RETURN FALSE END;
    IF (d^.syms^[i].kind = skImport) AND NOT Eq (d^.syms^[i].name, d^.syms^[i].imp) THEN
      md := Module (d, d^.syms^[i].imp);
      IF md = NIL THEN RETURN FALSE END;
      t := FindGlobal (md, names[0]);
      IF t < 0 THEN RETURN FALSE END;
      td := md; ti := t;
      RETURN TRUE
    END;
    td := d; ti := i;
    RETURN TRUE
  END;
  IF NOT ResolveChain (d, names, count - 1, offset, cd, ct) THEN RETURN FALSE END;
  IF ct = -1 THEN t := FindGlobal (cd, names[count - 1]) ELSE t := FindField (cd, ct, names[count - 1]) END;
  IF t < 0 THEN RETURN FALSE END;
  td := cd; ti := t;
  RETURN TRUE
END ResolveDesignator;

PROCEDURE HasEnumMembers (d: Doc; t: INTEGER): BOOLEAN;
VAR k: CARDINAL;
BEGIN
  k := 0;
  WHILE k < d^.nsyms DO
    IF (d^.syms^[k].kind = skEnum) AND (d^.syms^[k].owner = t) THEN RETURN TRUE END;
    INC (k)
  END;
  RETURN FALSE
END HasEnumMembers;

PROCEDURE SelectorEnum (d: Doc; VAR dotted: Name; offset: CARDINAL; VAR ed: Doc; VAR et: INTEGER): BOOLEAN;
VAR
  names: Chain;
  count, step: CARDINAL;
  td, nd: Doc;
  ti, t: INTEGER;
BEGIN
  count := SplitChain (dotted, names);
  IF NOT ResolveDesignator (d, names, count, offset, td, ti) THEN RETURN FALSE END;
  FOR step := 1 TO 8 DO
    IF NOT TypeSymOf (td, ti, nd, t) THEN RETURN FALSE END;
    IF HasEnumMembers (nd, t) THEN
      ed := nd; et := t;
      RETURN TRUE
    END;
    td := nd; ti := t
  END;
  RETURN FALSE
END SelectorEnum;

(* names of the designator that ends right before the '.' at dotPos *)
PROCEDURE ChainBefore (d: Doc; dotPos: CARDINAL; VAR names: Chain; VAR count: CARDINAL;
                       VAR firstStart: CARDINAL): BOOLEAN;
VAR
  t: CharPtr;
  tmp: Chain;
  i, j, e, depth, k: CARDINAL;
BEGIN
  t := d^.text.data;
  count := 0;
  i := dotPos;
  LOOP
    j := i;
    LOOP
      IF (j > 0) AND (t^[j - 1] = '^') THEN
        DEC (j)
      ELSIF (j > 0) AND (t^[j - 1] = ')') THEN
        depth := 0;
        REPEAT
          DEC (j);
          IF t^[j] = ')' THEN INC (depth) ELSIF t^[j] = '(' THEN DEC (depth) END
        UNTIL (depth = 0) OR (j = 0);
        WHILE (j > 0) AND (t^[j - 1] = ' ') DO DEC (j) END
      ELSIF (j > 0) AND (t^[j - 1] = ']') THEN
        depth := 0;
        REPEAT
          DEC (j);
          IF t^[j] = ']' THEN INC (depth) ELSIF t^[j] = '[' THEN DEC (depth) END
        UNTIL (depth = 0) OR (j = 0)
      ELSE
        EXIT
      END
    END;
    e := j;
    WHILE (j > 0) AND IsIdChar (t^[j - 1]) DO DEC (j) END;
    IF j = e THEN RETURN FALSE END;
    IF count > MaxChain THEN RETURN FALSE END;
    Copy (tmp[count], "");
    FOR k := j TO e - 1 DO
      IF k - j < NameLen - 1 THEN
        tmp[count][k - j] := t^[k];
        tmp[count][k - j + 1] := 0C
      END
    END;
    INC (count);
    firstStart := j;
    IF (j > 0) AND (t^[j - 1] = '.') AND NOT ((j > 1) AND (t^[j - 2] = '.')) THEN
      i := j - 1
    ELSE
      EXIT
    END
  END;
  FOR k := 1 TO count DO
    Copy (names[k - 1], tmp[count - k])
  END;
  RETURN TRUE
END ChainBefore;

(* ---- completion items ---- *)

PROCEDURE ItemHead (VAR out: Buf; label: ARRAY OF CHAR; kind: CARDINAL);
BEGIN
  Add (out, '{"label":');
  AddJson (out, label);
  Add (out, ',"kind":');
  AddCard (out, kind)
END ItemHead;

PROCEDURE SymCompletionKind (d: Doc; s: CARDINAL): CARDINAL;
BEGIN
  CASE d^.syms^[s].kind OF
    skModule: RETURN 9 |
    skConst: RETURN 21 |
    skType: IF d^.syms^[s].isRecord THEN RETURN 22 END; RETURN 7 |
    skVar, skParam: RETURN 6 |
    skField: RETURN 5 |
    skProc: RETURN 3 |
    skEnum: RETURN 20
  ELSE
    RETURN 6
  END
END SymCompletionKind;

PROCEDURE SymItem (VAR out: Buf; VAR first: BOOLEAN; d: Doc; s: CARDINAL);
VAR
  md: Doc;
  t: INTEGER;
BEGIN
  Sep (out, first);
  IF d^.syms^[s].kind = skImport THEN
    md := Module (d, d^.syms^[s].imp);
    IF Eq (d^.syms^[s].name, d^.syms^[s].imp) THEN
      ItemHead (out, d^.syms^[s].name, 9);
      Add (out, ',"detail":"module"}');
      RETURN
    END;
    IF md # NIL THEN
      t := FindGlobal (md, d^.syms^[s].name);
      IF t >= 0 THEN
        ItemHead (out, d^.syms^[s].name, SymCompletionKind (md, t));
        Add (out, ',"detail":');
        AddJsonFlat (out, md^.text.data, md^.syms^[t].dFrom, md^.syms^[t].dTo, 120);
        AddCh (out, '}');
        RETURN
      END
    END;
    ItemHead (out, d^.syms^[s].name, 6);
    Add (out, ',"detail":"from ');
    Add (out, d^.syms^[s].imp);
    Add (out, '"}');
    RETURN
  END;
  ItemHead (out, d^.syms^[s].name, SymCompletionKind (d, s));
  Add (out, ',"detail":');
  AddJsonFlat (out, d^.text.data, d^.syms^[s].dFrom, d^.syms^[s].dTo, 120);
  AddCh (out, '}')
END SymItem;

PROCEDURE ExportedKind (k: SymKind): BOOLEAN;
BEGIN
  RETURN (k = skConst) OR (k = skType) OR (k = skVar) OR (k = skProc) OR (k = skEnum)
END ExportedKind;

PROCEDURE MemberItems (VAR out: Buf; VAR first: BOOLEAN; cd: Doc; ct: INTEGER; prefix: ARRAY OF CHAR);
VAR k: CARDINAL;
BEGIN
  k := 0;
  WHILE k < cd^.nsyms DO
    IF HasPrefixCI (cd^.syms^[k].name, prefix) THEN
      IF ct = -1 THEN
        IF (cd^.syms^[k].scope = -1) AND ExportedKind (cd^.syms^[k].kind) THEN
          SymItem (out, first, cd, k)
        END
      ELSIF (cd^.syms^[k].kind = skField) AND (cd^.syms^[k].owner = ct) THEN
        SymItem (out, first, cd, k)
      END
    END;
    INC (k)
  END
END MemberItems;

PROCEDURE ScopeItems (VAR out: Buf; VAR first: BOOLEAN; d: Doc; offset: CARDINAL; prefix: ARRAY OF CHAR);
VAR
  cur: INTEGER;
  k: CARDINAL;
BEGIN
  cur := EnclosingProc (d, offset);
  LOOP
    k := 0;
    WHILE k < d^.nsyms DO
      IF (d^.syms^[k].scope = cur) AND (d^.syms^[k].kind # skField)
         AND HasPrefixCI (d^.syms^[k].name, prefix) THEN
        SymItem (out, first, d, k)
      END;
      INC (k)
    END;
    IF cur < 0 THEN EXIT END;
    cur := d^.syms^[cur].scope
  END
END ScopeItems;

PROCEDURE Complete (d: Doc; offset: CARDINAL; VAR out: Buf);
VAR
  t: CharPtr;
  ps, count, fs, k: CARDINAL;
  prefix: Name;
  names: Chain;
  cd, own: Doc;
  ct: INTEGER;
  first: BOOLEAN;
  bk: BKind;
  bname, bsig: ARRAY [0..79] OF CHAR;
  bdoc: ARRAY [0..127] OF CHAR;
  kw: ARRAY [0..15] OF CHAR;
BEGIN
  t := d^.text.data;
  first := TRUE;
  Add (out, '{"isIncomplete":true,"items":[');
  IF (offset > d^.text.len) OR (Context (t, d^.text.len, offset) # 0) THEN
    Add (out, ']}');
    RETURN
  END;
  ps := offset;
  WHILE (ps > 0) AND IsIdChar (t^[ps - 1]) DO DEC (ps) END;
  prefix[0] := 0C;
  IF offset > ps THEN
    FOR k := ps TO offset - 1 DO
      IF k - ps < NameLen - 1 THEN
        prefix[k - ps] := t^[k];
        prefix[k - ps + 1] := 0C
      END
    END
  END;
  IF (ps > 0) AND (t^[ps - 1] = '.') AND NOT ((ps > 1) AND (t^[ps - 2] = '.')) THEN
    IF ChainBefore (d, ps - 1, names, count, fs)
       AND ResolveChain (d, names, count, fs, cd, ct) THEN
      MemberItems (out, first, cd, ct, prefix)
    END
  ELSE
    ScopeItems (out, first, d, offset, prefix);
    k := d^.nsyms;
    WHILE k > 0 DO
      DEC (k);
      IF WithContainer (d, k, offset, cd, ct) THEN
        MemberItems (out, first, cd, ct, prefix)
      END
    END;
    IF NOT d^.isDef THEN
      own := Module (d, d^.modName);
      IF own # NIL THEN
        k := 0;
        WHILE k < own^.nsyms DO
          IF (own^.syms^[k].scope = -1) AND ExportedKind (own^.syms^[k].kind)
             AND HasPrefixCI (own^.syms^[k].name, prefix)
             AND (FindGlobal (d, own^.syms^[k].name) < 0) THEN
            SymItem (out, first, own, k)
          END;
          INC (k)
        END
      END
    END;
    FOR k := 1 TO Count () DO
      bk := Get (k - 1, bname, bsig, bdoc);
      IF HasPrefixCI (bname, prefix) THEN
        Sep (out, first);
        CASE bk OF
          bType: ItemHead (out, bname, 7) |
          bConst: ItemHead (out, bname, 21) |
          bProc: ItemHead (out, bname, 3)
        END;
        Add (out, ',"detail":'); AddJson (out, bsig);
        Add (out, ',"documentation":'); AddJson (out, bdoc);
        AddCh (out, '}')
      END
    END;
    FOR k := 1 TO KeywordCount () DO
      KeywordText (k - 1, kw);
      IF HasPrefixCI (kw, prefix) THEN
        Sep (out, first);
        ItemHead (out, kw, 14);
        AddCh (out, '}')
      END
    END
  END;
  Add (out, ']}')
END Complete;

(* ---- hover / definition ---- *)

PROCEDURE IdentAt (d: Doc; offset: CARDINAL; VAR s, e: CARDINAL): BOOLEAN;
VAR t: CharPtr;
BEGIN
  t := d^.text.data;
  IF offset > d^.text.len THEN RETURN FALSE END;
  s := offset; e := offset;
  WHILE (s > 0) AND IsIdChar (t^[s - 1]) DO DEC (s) END;
  WHILE (e < d^.text.len) AND IsIdChar (t^[e]) DO INC (e) END;
  RETURN e > s
END IdentAt;

(* Resolve the identifier at offset to a declaration: (td, ti), or a whole module (ti = -1). *)
PROCEDURE ResolveTarget (d: Doc; offset: CARDINAL; VAR td: Doc; VAR ti: INTEGER;
                         VAR s, e: CARDINAL): BOOLEAN;
VAR
  t: CharPtr;
  name: Name;
  names: Chain;
  count, fs: CARDINAL;
  cd, md: Doc;
  ct, i: INTEGER;
BEGIN
  IF NOT IdentAt (d, offset, s, e) THEN RETURN FALSE END;
  t := d^.text.data;
  IF Context (t, d^.text.len, offset) # 0 THEN RETURN FALSE END;
  Copy (name, "");
  FOR i := VAL (INTEGER, s) TO VAL (INTEGER, e) - 1 DO
    IF VAL (CARDINAL, i) - s < NameLen - 1 THEN
      name[VAL (CARDINAL, i) - s] := t^[i];
      name[VAL (CARDINAL, i) - s + 1] := 0C
    END
  END;
  (* the name being declared right here *)
  fs := 0;
  WHILE fs < d^.nsyms DO
    IF (d^.syms^[fs].kind # skWith) AND (d^.syms^[fs].kind # skImport)
       AND (d^.toks^[d^.syms^[fs].tok].start = s) THEN
      td := d; ti := VAL (INTEGER, fs);
      RETURN TRUE
    END;
    INC (fs)
  END;
  IF (s > 0) AND (t^[s - 1] = '.') AND NOT ((s > 1) AND (t^[s - 2] = '.')) THEN
    IF NOT ChainBefore (d, s - 1, names, count, fs) THEN RETURN FALSE END;
    IF NOT ResolveChain (d, names, count, fs, cd, ct) THEN RETURN FALSE END;
    IF ct = -1 THEN i := FindGlobal (cd, name) ELSE i := FindField (cd, ct, name) END;
    IF i < 0 THEN RETURN FALSE END;
    td := cd; ti := i;
    RETURN TRUE
  END;
  IF WithField (d, name, offset, cd, i) THEN
    td := cd; ti := i;
    RETURN TRUE
  END;
  i := Lookup (d, name, offset);
  IF i >= 0 THEN
    IF d^.syms^[i].kind = skImport THEN
      md := Module (d, d^.syms^[i].imp);
      IF md = NIL THEN RETURN FALSE END;
      IF Eq (d^.syms^[i].name, d^.syms^[i].imp) THEN
        td := md; ti := -1;
        RETURN TRUE
      END;
      ct := FindGlobal (md, name);
      IF ct < 0 THEN RETURN FALSE END;
      td := md; ti := ct;
      RETURN TRUE
    END;
    td := d; ti := i;
    RETURN TRUE
  END;
  md := Module (d, name);
  IF md # NIL THEN
    td := md; ti := -1;
    RETURN TRUE
  END;
  RETURN FALSE
END ResolveTarget;

PROCEDURE Hover (d: Doc; offset: CARDINAL; VAR out: Buf): BOOLEAN;
VAR
  td: Doc;
  ti: INTEGER;
  s, e, k, l1, c1, l2, c2: CARDINAL;
  md: Buf;
  name: Name;
  bk: BKind;
  bname, bsig: ARRAY [0..79] OF CHAR;
  bdoc: ARRAY [0..127] OF CHAR;
  kn: ARRAY [0..15] OF CHAR;
BEGIN
  Init (md);
  IF ResolveTarget (d, offset, td, ti, s, e) THEN
    Add (md, '```modula2'); AddCh (md, 12C);
    IF ti < 0 THEN
      Add (md, 'DEFINITION MODULE '); Add (md, td^.modName)
    ELSE
      Flat (md, td^.text.data, td^.syms^[ti].dFrom, td^.syms^[ti].dTo, 300)
    END;
    AddCh (md, 12C); Add (md, '```')
  ELSE
    IF NOT IdentAt (d, offset, s, e) THEN
      Release (md);
      RETURN FALSE
    END;
    FOR k := s TO e - 1 DO
      IF k - s < NameLen - 1 THEN
        name[k - s] := d^.text.data^[k];
        name[k - s + 1] := 0C
      END
    END;
    k := Find (name);
    IF k >= Count () THEN
      Release (md);
      RETURN FALSE
    END;
    bk := Get (k, bname, bsig, bdoc);
    Add (md, '```modula2'); AddCh (md, 12C);
    Add (md, bsig); AddCh (md, 12C); Add (md, '```');
    AddCh (md, 12C); AddCh (md, 12C); Add (md, bdoc)
  END;
  Add (out, '{"contents":{"kind":"markdown","value":');
  AddJsonRange (out, md.data, 0, md.len);
  Add (out, '},"range":{"start":');
  LineCol (d^.text.data, d^.text.len, s, l1, c1);
  LineCol (d^.text.data, d^.text.len, e, l2, c2);
  Position (out, l1, c1);
  Add (out, ',"end":');
  Position (out, l2, c2);
  Add (out, '}}');
  Release (md);
  RETURN TRUE
END Hover;

PROCEDURE Definition (d: Doc; VAR uri: Buf; offset: CARDINAL; VAR out: Buf): BOOLEAN;
VAR
  td: Doc;
  ti: INTEGER;
  s, e: CARDINAL;
  u: Buf;
BEGIN
  IF NOT ResolveTarget (d, offset, td, ti, s, e) THEN RETURN FALSE END;
  Add (out, '{"uri":');
  IF td = d THEN
    AddJsonRange (out, uri.data, 0, uri.len)
  ELSE
    Init (u);
    PathToUri (td^.path, u);
    AddJsonRange (out, u.data, 0, u.len);
    Release (u)
  END;
  Add (out, ',"range":');
  IF ti < 0 THEN
    Add (out, '{"start":{"line":0,"character":0},"end":{"line":0,"character":0}}')
  ELSE
    RangeOfTok (out, td, td^.syms^[ti].tok)
  END;
  AddCh (out, '}');
  RETURN TRUE
END Definition;

PROCEDURE DocumentSymbols (d: Doc; VAR uri: Buf; VAR out: Buf);
VAR
  k: CARDINAL;
  first, ok: BOOLEAN;
  sk: CARDINAL;
BEGIN
  first := TRUE;
  Add (out, '[');
  k := 0;
  WHILE k < d^.nsyms DO
    ok := FALSE;
    sk := 13;
    CASE d^.syms^[k].kind OF
      skProc: ok := TRUE; sk := 12 |
      skConst: ok := d^.syms^[k].scope = -1; sk := 14 |
      skType: ok := d^.syms^[k].scope = -1;
              IF d^.syms^[k].isRecord THEN sk := 23 ELSE sk := 5 END |
      skVar: ok := d^.syms^[k].scope = -1; sk := 13 |
      skModule: ok := TRUE; sk := 2
    ELSE
      ok := FALSE
    END;
    IF ok THEN
      Sep (out, first);
      Add (out, '{"name":'); AddJson (out, d^.syms^[k].name);
      Add (out, ',"kind":'); AddCard (out, sk);
      Add (out, ',"location":{"uri":'); AddJsonRange (out, uri.data, 0, uri.len);
      Add (out, ',"range":'); RangeOfTok (out, d, d^.syms^[k].tok);
      AddCh (out, '}');
      IF d^.syms^[k].scope >= 0 THEN
        Add (out, ',"containerName":');
        AddJson (out, d^.syms^[d^.syms^[k].scope].name)
      END;
      AddCh (out, '}')
    END;
    INC (k)
  END;
  Add (out, ']')
END DocumentSymbols;

END Nav.
