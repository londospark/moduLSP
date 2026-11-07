IMPLEMENTATION MODULE Symbols;

FROM SYSTEM IMPORT ADDRESS, CSIZE_T;
FROM libc IMPORT malloc, realloc, free;
FROM Text IMPORT Buf, CharPtr, Init, Release, Clear, AddRange, Eq, Copy, CopyRange, Len, Append;
FROM Lexer IMPORT Kw, TokKind, Tokenize, FreeTokens, LineEnd;
FROM Files IMPORT ReadFile, Stem;

CONST
  MaxCard = 4294967295;
  MaxStack = 255;

TYPE
  OpenKind = (opOther, opProc, opRec, opModule, opWith, opVariant, opCase);
  Opener = RECORD
             kind: OpenKind;
             sym: INTEGER
           END;
  Section = (secNone, secConst, secType, secVar);

VAR
  sd: Doc;                          (* document currently being scanned *)
  stack: ARRAY [0..MaxStack] OF Opener;
  sp: CARDINAL;
  section: Section;
  declAt: CARDINAL;
  pd: CARDINAL;
  pendingOwner: INTEGER;
  labelMode: BOOLEAN;               (* inside the labels of a record variant *)

(* ---- document management ---- *)

PROCEDURE NewDoc (path: ARRAY OF CHAR): Doc;
VAR
  d: Doc;
  m: ADDRESS;
BEGIN
  m := malloc (VAL (CSIZE_T, SIZE (DocRec)));
  d := m;
  Copy (d^.path, path);
  Stem (path, d^.modName);
  d^.isDef := FALSE;
  Init (d^.text);
  d^.toks := NIL;
  d^.ntoks := 0;
  d^.syms := NIL;
  d^.nsyms := 0;
  d^.scap := 0;
  RETURN d
END NewDoc;

PROCEDURE FreeDoc (VAR d: Doc);
BEGIN
  IF d # NIL THEN
    Release (d^.text);
    FreeTokens (d^.toks);
    IF d^.syms # NIL THEN free (d^.syms) END;
    free (d);
    d := NIL
  END
END FreeDoc;

(* ---- token helpers ---- *)

PROCEDURE IsKw (i: CARDINAL; k: Kw): BOOLEAN;
BEGIN
  RETURN (i < sd^.ntoks) AND (sd^.toks^[i].kind = tkKeyword) AND (sd^.toks^[i].kw = k)
END IsKw;

PROCEDURE IsIdent (i: CARDINAL): BOOLEAN;
BEGIN
  RETURN (i < sd^.ntoks) AND (sd^.toks^[i].kind = tkIdent)
END IsIdent;

PROCEDURE IsSym (i: CARDINAL; c: CHAR): BOOLEAN;
BEGIN
  RETURN (i < sd^.ntoks) AND (sd^.toks^[i].kind = tkSym) AND (sd^.toks^[i].c1 = c)
        AND (sd^.toks^[i].c2 = 0C)
END IsSym;

PROCEDURE TokName (i: CARDINAL; VAR n: Name);
BEGIN
  CopyRange (n, sd^.text.data, sd^.toks^[i].start, sd^.toks^[i].stop)
END TokName;

PROCEDURE IsIdentText (i: CARDINAL; s: ARRAY OF CHAR): BOOLEAN;
VAR n: Name;
BEGIN
  IF NOT IsIdent (i) THEN RETURN FALSE END;
  TokName (i, n);
  RETURN Eq (n, s)
END IsIdentText;

PROCEDURE CurProc (): INTEGER;
VAR k: CARDINAL;
BEGIN
  k := sp;
  WHILE k > 0 DO
    DEC (k);
    IF stack[k].kind = opProc THEN RETURN stack[k].sym END
  END;
  RETURN -1
END CurProc;

PROCEDURE InRecord (): BOOLEAN;
BEGIN
  RETURN (sp > 0) AND ((stack[sp - 1].kind = opRec) OR (stack[sp - 1].kind = opVariant))
END InRecord;

PROCEDURE Push (k: OpenKind; s: INTEGER);
BEGIN
  IF sp <= MaxStack THEN
    stack[sp].kind := k;
    stack[sp].sym := s;
    INC (sp)
  END
END Push;

PROCEDURE AddSym (tok: CARDINAL; kind: SymKind; scope, owner: INTEGER): CARDINAL;
VAR
  d: Doc;
  idx: CARDINAL;
  m: ADDRESS;
BEGIN
  d := sd;
  IF d^.nsyms >= d^.scap THEN
    IF d^.scap = 0 THEN d^.scap := 64 ELSE d^.scap := d^.scap * 2 END;
    m := realloc (d^.syms, VAL (CSIZE_T, d^.scap * SIZE (Sym)));
    d^.syms := m
  END;
  idx := d^.nsyms;
  INC (d^.nsyms);
  TokName (tok, d^.syms^[idx].name);
  d^.syms^[idx].kind := kind;
  d^.syms^[idx].tok := tok;
  d^.syms^[idx].scope := scope;
  d^.syms^[idx].owner := owner;
  d^.syms^[idx].typeName[0] := 0C;
  d^.syms^[idx].typeMod[0] := 0C;
  d^.syms^[idx].imp[0] := 0C;
  d^.syms^[idx].isRecord := FALSE;
  d^.syms^[idx].anonOwner := -1;
  d^.syms^[idx].hasElse := FALSE;
  d^.syms^[idx].opaque := FALSE;
  d^.syms^[idx].dFrom := d^.toks^[tok].start;
  d^.syms^[idx].dTo := d^.toks^[tok].stop;
  d^.syms^[idx].bodyEnd := 0;
  RETURN idx
END AddSym;

(* Capture the head of a type designator starting at token j: strips ARRAY..OF,
   POINTER TO and SET OF, then takes [Module.]Name. Returns the next token. *)
PROCEDURE TypeHead (j: CARDINAL; VAR tn, tm: Name): CARDINAL;
VAR depth: CARDINAL;
BEGIN
  tn[0] := 0C;
  tm[0] := 0C;
  LOOP
    IF IsKw (j, kwARRAY) THEN
      depth := 0;
      INC (j);
      WHILE (j < sd^.ntoks) AND NOT ((depth = 0) AND IsKw (j, kwOF)) DO
        IF IsSym (j, '[') OR IsSym (j, '(') THEN INC (depth)
        ELSIF (IsSym (j, ']') OR IsSym (j, ')')) AND (depth > 0) THEN DEC (depth)
        ELSIF IsSym (j, ';') OR IsSym (j, ')') THEN RETURN j END;
        INC (j)
      END;
      INC (j)
    ELSIF IsKw (j, kwPOINTER) THEN
      INC (j);
      IF IsKw (j, kwTO) THEN INC (j) END
    ELSIF IsKw (j, kwSET) THEN
      INC (j);
      IF IsKw (j, kwOF) THEN INC (j) END
    ELSE
      EXIT
    END
  END;
  IF IsIdent (j) THEN
    TokName (j, tn);
    INC (j);
    IF IsSym (j, '.') AND IsIdent (j + 1) THEN
      Copy (tm, tn);
      TokName (j + 1, tn);
      INC (j, 2)
    END
  END;
  RETURN j
END TypeHead;

PROCEDURE SetTypes (first, last: CARDINAL; VAR tn, tm: Name);
VAR k: CARDINAL;
BEGIN
  IF last >= first THEN
    FOR k := first TO last DO
      Copy (sd^.syms^[k].typeName, tn);
      Copy (sd^.syms^[k].typeMod, tm)
    END
  END
END SetTypes;

PROCEDURE SetRanges (first, last, startTok, endTok: CARDINAL);
VAR k, from, to: CARDINAL;
BEGIN
  from := sd^.toks^[startTok].start;
  IF endTok >= sd^.ntoks THEN endTok := sd^.ntoks - 1 END;
  to := sd^.toks^[endTok].stop;
  IF last >= first THEN
    FOR k := first TO last DO
      sd^.syms^[k].dFrom := from;
      sd^.syms^[k].dTo := to
    END
  END
END SetRanges;

(* Last token to show for a declaration whose head ends at token e: keep going on the same
   line up to ';' / END, and stop after RECORD so that records show as "T = RECORD". *)
PROCEDURE HeadEnd (e: CARDINAL): CARDINAL;
VAR k: CARDINAL;
BEGIN
  IF e >= sd^.ntoks THEN RETURN sd^.ntoks - 1 END;
  k := e + 1;
  WHILE (k < sd^.ntoks) AND (sd^.toks^[k].line = sd^.toks^[e].line)
        AND NOT IsSym (k, ';') AND NOT IsKw (k, kwEND) DO
    e := k;
    IF IsKw (k, kwRECORD) THEN RETURN e END;
    INC (k)
  END;
  RETURN e
END HeadEnd;

(* ---- declarations ---- *)

PROCEDURE ParseDecl (i: CARDINAL): CARDINAL;
VAR
  j, first, last, k: CARDINAL;
  kind: SymKind;
  scope, owner: INTEGER;
  tn, tm: Name;
  isType, ownerSet: BOOLEAN;
BEGIN
  isType := FALSE;
  owner := -1;
  IF InRecord () THEN
    kind := skField; scope := -2; owner := stack[sp - 1].sym
  ELSE
    scope := CurProc ();
    CASE section OF
      secConst: kind := skConst |
      secType: kind := skType; isType := TRUE |
      secVar: kind := skVar
    ELSE
      kind := skVar
    END
  END;
  j := i;
  first := sd^.nsyms;
  LOOP
    IF NOT IsIdent (j) THEN EXIT END;
    k := AddSym (j, kind, scope, owner);
    INC (j);
    IF IsSym (j, '*') OR IsSym (j, '-') THEN INC (j) END;
    IF IsSym (j, ',') THEN INC (j) ELSE EXIT END
  END;
  last := sd^.nsyms - 1;
  IF sd^.nsyms = first THEN RETURN i + 1 END;
  IF (kind = skVar) OR (kind = skField) THEN
    IF IsSym (j, ':') THEN
      INC (j);
      j := TypeHead (j, tn, tm);
      SetTypes (first, last, tn, tm);
      IF IsKw (j, kwRECORD) THEN
        (* anonymous record type: its fields belong to the first name of the list *)
        FOR k := first TO last DO
          sd^.syms^[k].isRecord := TRUE;
          sd^.syms^[k].anonOwner := VAL (INTEGER, first)
        END;
        pendingOwner := VAL (INTEGER, first)
      END
    END
  ELSIF kind = skConst THEN
    IF IsSym (j, '=') THEN INC (j) END
  ELSE
    IF IsSym (j, '=') THEN
      INC (j);
      IF IsKw (j, kwRECORD) THEN
        sd^.syms^[first].isRecord := TRUE;
        pendingOwner := VAL (INTEGER, first)
      ELSIF IsSym (j, '(') THEN
        INC (j);
        WHILE IsIdent (j) DO
          k := AddSym (j, skEnum, scope, VAL (INTEGER, first));
          INC (j);
          IF IsSym (j, ',') THEN INC (j) END
        END;
        IF IsSym (j, ')') THEN INC (j) END
      ELSE
        j := TypeHead (j, tn, tm);
        SetTypes (first, first, tn, tm)
      END
    END
  END;
  IF j <= i THEN j := i + 1 END;
  SetRanges (first, last, i, HeadEnd (j - 1));
  RETURN j
END ParseDecl;

PROCEDURE ParseParams (j: CARDINAL; s: CARDINAL): CARDINAL;
VAR
  first, k, depth: CARDINAL;
  tn, tm: Name;
BEGIN
  INC (j);
  LOOP
    IF j >= sd^.ntoks THEN RETURN j END;
    IF IsSym (j, ')') THEN RETURN j + 1 END;
    IF IsKw (j, kwVAR) THEN INC (j) END;
    first := sd^.nsyms;
    WHILE IsIdent (j) DO
      k := AddSym (j, skParam, VAL (INTEGER, s), -1);
      INC (j);
      IF IsSym (j, ',') THEN INC (j) END
    END;
    IF IsSym (j, ':') THEN
      INC (j);
      j := TypeHead (j, tn, tm);
      IF sd^.nsyms > first THEN SetTypes (first, sd^.nsyms - 1, tn, tm) END
    END;
    depth := 0;
    WHILE (j < sd^.ntoks) AND NOT ((depth = 0) AND (IsSym (j, ';') OR IsSym (j, ')'))) DO
      IF IsSym (j, '(') THEN INC (depth)
      ELSIF IsSym (j, ')') THEN DEC (depth) END;
      INC (j)
    END;
    IF IsSym (j, ';') THEN INC (j) END
  END
END ParseParams;

PROCEDURE ParseProc (i: CARDINAL): CARDINAL;
VAR
  s, j: CARDINAL;
  tn, tm: Name;
BEGIN
  IF NOT IsIdent (i + 1) THEN RETURN i + 1 END;
  s := AddSym (i + 1, skProc, CurProc (), -1);
  j := i + 2;
  IF IsSym (j, '(') THEN j := ParseParams (j, s) END;
  IF IsSym (j, ':') THEN
    INC (j);
    j := TypeHead (j, tn, tm);
    Copy (sd^.syms^[s].typeName, tn);
    Copy (sd^.syms^[s].typeMod, tm)
  END;
  WHILE (j < sd^.ntoks) AND NOT IsSym (j, ';') DO INC (j) END;
  IF j < sd^.ntoks THEN
    sd^.syms^[s].dFrom := sd^.toks^[i].start;
    sd^.syms^[s].dTo := sd^.toks^[j].stop
  END;
  INC (j);
  IF sd^.isDef THEN
    (* heading only *)
  ELSIF IsIdentText (j, 'FORWARD') THEN
    INC (j);
    IF IsSym (j, ';') THEN INC (j) END
  ELSE
    Push (opProc, VAL (INTEGER, s));
    section := secNone;
    declAt := MaxCard
  END;
  RETURN j
END ParseProc;

PROCEDURE ParseImport (i: CARDINAL): CARDINAL;
VAR
  j, k: CARDINAL;
  m: Name;
  scope: INTEGER;
BEGIN
  scope := CurProc ();
  IF IsKw (i, kwFROM) THEN
    IF NOT IsIdent (i + 1) THEN RETURN i + 1 END;
    TokName (i + 1, m);
    j := i + 2;
    IF IsKw (j, kwIMPORT) THEN INC (j) END;
    WHILE IsIdent (j) DO
      k := AddSym (j, skImport, scope, -1);
      Copy (sd^.syms^[k].imp, m);
      INC (j);
      IF IsSym (j, ',') THEN INC (j) END
    END
  ELSE
    j := i + 1;
    WHILE IsIdent (j) DO
      k := AddSym (j, skImport, scope, -1);
      TokName (j, sd^.syms^[k].imp);
      INC (j);
      IF IsSym (j, ',') THEN INC (j) END
    END
  END;
  WHILE (j < sd^.ntoks) AND NOT IsSym (j, ';') DO INC (j) END;
  RETURN j + 1
END ParseImport;

(* Dotted text of the designator starting at token j, up to DO / OF. [..] and ^ are dropped;
   bad is set when anything else (calls, operators, numbers) shows up. *)
PROCEDURE BuildDesignator (j: CARDINAL; VAR out: Name; VAR bad: BOOLEAN): CARDINAL;
VAR
  depth: CARDINAL;
  nm: Name;
BEGIN
  out[0] := 0C;
  bad := FALSE;
  WHILE (j < sd^.ntoks) AND NOT IsKw (j, kwDO) AND NOT IsKw (j, kwOF) DO
    IF IsIdent (j) THEN
      TokName (j, nm);
      Append (out, nm)
    ELSIF IsSym (j, '.') THEN
      Append (out, '.')
    ELSIF IsSym (j, '^') THEN
      (* dereference *)
    ELSIF IsSym (j, '[') THEN
      depth := 0;
      REPEAT
        IF IsSym (j, '[') THEN INC (depth) ELSIF IsSym (j, ']') THEN DEC (depth) END;
        INC (j)
      UNTIL (depth = 0) OR (j >= sd^.ntoks);
      DEC (j)
    ELSE
      bad := TRUE
    END;
    INC (j)
  END;
  RETURN j
END BuildDesignator;

(* WITH designator DO: remember the designator (dotted) and where the body starts. *)
PROCEDURE AddWith (i: CARDINAL): INTEGER;
VAR
  j, s: CARDINAL;
  bad: BOOLEAN;
BEGIN
  IF NOT IsIdent (i + 1) THEN RETURN -1 END;
  s := AddSym (i + 1, skWith, -3, -1);
  j := BuildDesignator (i + 1, sd^.syms^[s].imp, bad);
  IF j < sd^.ntoks THEN
    sd^.syms^[s].dFrom := sd^.toks^[j].stop
  ELSE
    sd^.syms^[s].dFrom := sd^.text.len
  END;
  sd^.syms^[s].dTo := sd^.syms^[s].dFrom;
  sd^.syms^[s].bodyEnd := sd^.text.len;
  RETURN VAL (INTEGER, s)
END AddWith;

(* CASE selector OF: remember the selector, labels follow as skLabel symbols. *)
PROCEDURE AddCase (i: CARDINAL): INTEGER;
VAR
  s, j: CARDINAL;
  bad: BOOLEAN;
BEGIN
  s := AddSym (i, skCase, -3, -1);
  j := BuildDesignator (i + 1, sd^.syms^[s].imp, bad);
  sd^.syms^[s].opaque := bad OR (sd^.syms^[s].imp[0] = 0C);
  RETURN VAL (INTEGER, s)
END AddCase;

PROCEDURE IsDots (i: CARDINAL): BOOLEAN;
BEGIN
  RETURN (i < sd^.ntoks) AND (sd^.toks^[i].kind = tkSym) AND (sd^.toks^[i].c1 = '.')
         AND (sd^.toks^[i].c2 = '.')
END IsDots;

PROCEDURE TopIs (k: OpenKind): BOOLEAN;
BEGIN
  RETURN (sp > 0) AND (stack[sp - 1].kind = k)
END TopIs;

PROCEDURE HandleKw (i: CARDINAL): CARDINAL;
VAR
  s: CARDINAL;
  kw: Kw;
BEGIN
  kw := sd^.toks^[i].kw;
  CASE kw OF
    kwMODULE:
      IF IsIdent (i + 1) THEN
        s := AddSym (i + 1, skModule, CurProc (), -1);
        Push (opModule, VAL (INTEGER, s))
      ELSE
        Push (opModule, -1)
      END;
      section := secNone;
      RETURN i + 1 |
    kwPROCEDURE:
      IF pd > 0 THEN RETURN i + 1 END;
      RETURN ParseProc (i) |
    kwCONST, kwTYPE, kwVAR:
      IF pd = 0 THEN
        IF kw = kwCONST THEN section := secConst
        ELSIF kw = kwTYPE THEN section := secType
        ELSE section := secVar END;
        declAt := i + 1
      END;
      RETURN i + 1 |
    kwBEGIN:
      section := secNone;
      RETURN i + 1 |
    kwWITH:
      Push (opWith, AddWith (i));
      IF NOT InRecord () THEN section := secNone END;
      RETURN i + 1 |
    kwCASE:
      IF InRecord () THEN
        (* record variant: CASE [tag :] Type OF label : fields | label : fields [ELSE fields] END *)
        Push (opVariant, stack[sp - 1].sym);
        labelMode := FALSE;
        declAt := MaxCard;
        IF IsIdent (i + 1) AND IsSym (i + 2, ':') THEN declAt := i + 1 END
      ELSE
        Push (opCase, AddCase (i));
        labelMode := FALSE;
        section := secNone
      END;
      RETURN i + 1 |
    kwOF:
      IF TopIs (opVariant) OR TopIs (opCase) THEN
        labelMode := TRUE;
        declAt := MaxCard
      END;
      RETURN i + 1 |
    kwELSE:
      IF TopIs (opVariant) THEN
        labelMode := FALSE;
        declAt := i + 1
      ELSIF TopIs (opCase) THEN
        labelMode := FALSE;
        IF stack[sp - 1].sym >= 0 THEN sd^.syms^[stack[sp - 1].sym].hasElse := TRUE END
      END;
      RETURN i + 1 |
    kwIF, kwWHILE, kwFOR, kwLOOP:
      Push (opOther, -1);
      IF NOT InRecord () THEN section := secNone END;
      RETURN i + 1 |
    kwRECORD:
      Push (opRec, pendingOwner);
      pendingOwner := -1;
      declAt := i + 1;
      RETURN i + 1 |
    kwEND:
      IF sp > 0 THEN
        DEC (sp);
        IF (stack[sp].kind = opProc) AND (stack[sp].sym >= 0) THEN
          sd^.syms^[stack[sp].sym].bodyEnd := sd^.toks^[i].start;
          section := secNone
        ELSIF (stack[sp].kind = opWith) AND (stack[sp].sym >= 0) THEN
          sd^.syms^[stack[sp].sym].bodyEnd := sd^.toks^[i].start
        ELSIF stack[sp].kind = opModule THEN
          section := secNone
        END
      END;
      RETURN i + 1 |
    kwFROM, kwIMPORT:
      RETURN ParseImport (i) |
    kwEXPORT:
      WHILE (i < sd^.ntoks) AND NOT IsSym (i, ';') DO INC (i) END;
      RETURN i + 1
  ELSE
    RETURN i + 1
  END
END HandleKw;

PROCEDURE Scan (d: Doc);
VAR
  i, k: CARDINAL;
BEGIN
  sd := d;
  sp := 0;
  section := secNone;
  declAt := MaxCard;
  pd := 0;
  pendingOwner := -1;
  labelMode := FALSE;
  d^.nsyms := 0;
  i := 0;
  WHILE i < d^.ntoks DO
    IF ((section # secNone) OR InRecord ()) AND (i = declAt) AND (pd = 0) AND IsIdent (i) THEN
      i := ParseDecl (i)
    ELSIF d^.toks^[i].kind = tkKeyword THEN
      i := HandleKw (i)
    ELSE
      IF labelMode AND TopIs (opCase) AND (pd = 0) THEN
        IF IsIdent (i) AND NOT IsSym (i + 1, '.') THEN
          k := AddSym (i, skLabel, -3, stack[sp - 1].sym)
        ELSIF IsDots (i) AND (d^.nsyms > 0) AND (d^.syms^[d^.nsyms - 1].kind = skLabel) THEN
          d^.syms^[d^.nsyms - 1].isRecord := TRUE
        END
      END;
      IF IsSym (i, '(') THEN
        INC (pd)
      ELSIF IsSym (i, ')') THEN
        IF pd > 0 THEN DEC (pd) END
      ELSIF IsSym (i, ';') AND (pd = 0) THEN
        IF (section # secNone) OR InRecord () THEN declAt := i + 1 END
      ELSIF IsSym (i, '|') AND (TopIs (opVariant) OR TopIs (opCase)) THEN
        labelMode := TRUE;
        declAt := MaxCard
      ELSIF IsSym (i, ':') AND labelMode AND (pd = 0) THEN
        labelMode := FALSE;
        declAt := i + 1
      END;
      INC (i)
    END
  END;
  (* procedures left open (code still being typed) extend to the end of the text *)
  WHILE sp > 0 DO
    DEC (sp);
    IF (stack[sp].kind = opProc) AND (stack[sp].sym >= 0) THEN
      d^.syms^[stack[sp].sym].bodyEnd := d^.text.len
    END
  END
END Scan;

PROCEDURE SetText (d: Doc; p: CharPtr; len: CARDINAL);
BEGIN
  Clear (d^.text);
  AddRange (d^.text, p, 0, len);
  FreeTokens (d^.toks);
  Tokenize (d^.text.data, d^.text.len, d^.toks, d^.ntoks);
  d^.isDef := FALSE;
  (* DEFINITION MODULE ? *)
  sd := d;
  IF IsKw (0, kwDEFINITION) THEN d^.isDef := TRUE END;
  Scan (d)
END SetText;

PROCEDURE LoadFile (d: Doc): BOOLEAN;
VAR b: Buf;
BEGIN
  Init (b);
  IF NOT ReadFile (d^.path, b) THEN
    Release (b);
    RETURN FALSE
  END;
  SetText (d, b.data, b.len);
  Release (b);
  RETURN TRUE
END LoadFile;

(* ---- queries ---- *)

PROCEDURE EnclosingProc (d: Doc; offset: CARDINAL): INTEGER;
VAR
  k: CARDINAL;
  best: INTEGER;
BEGIN
  best := -1;
  k := 0;
  WHILE k < d^.nsyms DO
    IF (d^.syms^[k].kind = skProc) AND (d^.syms^[k].bodyEnd > 0)
       AND (d^.syms^[k].dFrom <= offset) AND (offset <= d^.syms^[k].bodyEnd) THEN
      IF (best < 0) OR (d^.syms^[k].dFrom >= d^.syms^[best].dFrom) THEN
        best := VAL (INTEGER, k)
      END
    END;
    INC (k)
  END;
  RETURN best
END EnclosingProc;

PROCEDURE Lookup (d: Doc; name: ARRAY OF CHAR; offset: CARDINAL): INTEGER;
VAR
  cur: INTEGER;
  k: CARDINAL;
BEGIN
  cur := EnclosingProc (d, offset);
  LOOP
    k := 0;
    WHILE k < d^.nsyms DO
      IF (d^.syms^[k].scope = cur) AND (d^.syms^[k].kind # skField) AND Eq (d^.syms^[k].name, name) THEN
        RETURN VAL (INTEGER, k)
      END;
      INC (k)
    END;
    IF cur < 0 THEN EXIT END;
    cur := d^.syms^[cur].scope
  END;
  RETURN -1
END Lookup;

PROCEDURE LookupType (d: Doc; name: ARRAY OF CHAR; offset: CARDINAL): INTEGER;
VAR
  cur: INTEGER;
  k: CARDINAL;
BEGIN
  cur := EnclosingProc (d, offset);
  LOOP
    k := 0;
    WHILE k < d^.nsyms DO
      IF (d^.syms^[k].scope = cur) AND ((d^.syms^[k].kind = skType) OR (d^.syms^[k].kind = skImport))
         AND Eq (d^.syms^[k].name, name) THEN
        RETURN VAL (INTEGER, k)
      END;
      INC (k)
    END;
    IF cur < 0 THEN EXIT END;
    cur := d^.syms^[cur].scope
  END;
  RETURN -1
END LookupType;

PROCEDURE FindGlobal (d: Doc; name: ARRAY OF CHAR): INTEGER;
VAR k: CARDINAL;
BEGIN
  k := 0;
  WHILE k < d^.nsyms DO
    IF (d^.syms^[k].scope = -1) AND Eq (d^.syms^[k].name, name) THEN RETURN VAL (INTEGER, k) END;
    INC (k)
  END;
  RETURN -1
END FindGlobal;

PROCEDURE FindTypeGlobal (d: Doc; name: ARRAY OF CHAR): INTEGER;
VAR k: CARDINAL;
BEGIN
  k := 0;
  WHILE k < d^.nsyms DO
    IF (d^.syms^[k].scope = -1) AND (d^.syms^[k].kind = skType) AND Eq (d^.syms^[k].name, name) THEN
      RETURN VAL (INTEGER, k)
    END;
    INC (k)
  END;
  RETURN -1
END FindTypeGlobal;

PROCEDURE FindField (d: Doc; owner: INTEGER; name: ARRAY OF CHAR): INTEGER;
VAR k: CARDINAL;
BEGIN
  k := 0;
  WHILE k < d^.nsyms DO
    IF (d^.syms^[k].kind = skField) AND (d^.syms^[k].owner = owner) AND Eq (d^.syms^[k].name, name) THEN
      RETURN VAL (INTEGER, k)
    END;
    INC (k)
  END;
  RETURN -1
END FindField;

PROCEDURE KindName (k: SymKind; VAR s: ARRAY OF CHAR);
BEGIN
  CASE k OF
    skModule: Copy (s, 'module') |
    skConst: Copy (s, 'const') |
    skType: Copy (s, 'type') |
    skVar: Copy (s, 'var') |
    skField: Copy (s, 'field') |
    skParam: Copy (s, 'param') |
    skProc: Copy (s, 'procedure') |
    skEnum: Copy (s, 'enum member') |
    skImport: Copy (s, 'import') |
    skWith: Copy (s, 'with') |
    skCase: Copy (s, 'case') |
    skLabel: Copy (s, 'label')
  END
END KindName;

END Symbols.
