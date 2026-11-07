IMPLEMENTATION MODULE Lexer;

FROM Text IMPORT CharPtr, IsIdStart, IsIdChar, IsDigit, Eq, Copy;
FROM SYSTEM IMPORT ADDRESS, CSIZE_T;
FROM libc IMPORT realloc, free;

CONST
  NumKw = 40;
  LF = 12C;

VAR
  kwText: ARRAY [1..NumKw] OF ARRAY [0..15] OF CHAR;

PROCEDURE DefKw (k: Kw; s: ARRAY OF CHAR);
BEGIN
  Copy (kwText[ORD (k)], s)
END DefKw;

PROCEDURE InitKeywords;
BEGIN
  DefKw (kwAND, 'AND'); DefKw (kwARRAY, 'ARRAY'); DefKw (kwBEGIN, 'BEGIN');
  DefKw (kwBY, 'BY'); DefKw (kwCASE, 'CASE'); DefKw (kwCONST, 'CONST');
  DefKw (kwDEFINITION, 'DEFINITION'); DefKw (kwDIV, 'DIV'); DefKw (kwDO, 'DO');
  DefKw (kwELSE, 'ELSE'); DefKw (kwELSIF, 'ELSIF'); DefKw (kwEND, 'END');
  DefKw (kwEXIT, 'EXIT'); DefKw (kwEXPORT, 'EXPORT'); DefKw (kwFOR, 'FOR');
  DefKw (kwFROM, 'FROM'); DefKw (kwIF, 'IF'); DefKw (kwIMPLEMENTATION, 'IMPLEMENTATION');
  DefKw (kwIMPORT, 'IMPORT'); DefKw (kwIN, 'IN'); DefKw (kwLOOP, 'LOOP');
  DefKw (kwMOD, 'MOD'); DefKw (kwMODULE, 'MODULE'); DefKw (kwNOT, 'NOT');
  DefKw (kwOF, 'OF'); DefKw (kwOR, 'OR'); DefKw (kwPOINTER, 'POINTER');
  DefKw (kwPROCEDURE, 'PROCEDURE'); DefKw (kwQUALIFIED, 'QUALIFIED');
  DefKw (kwRECORD, 'RECORD'); DefKw (kwREPEAT, 'REPEAT'); DefKw (kwRETURN, 'RETURN');
  DefKw (kwSET, 'SET'); DefKw (kwTHEN, 'THEN'); DefKw (kwTO, 'TO');
  DefKw (kwTYPE, 'TYPE'); DefKw (kwUNTIL, 'UNTIL'); DefKw (kwVAR, 'VAR');
  DefKw (kwWHILE, 'WHILE'); DefKw (kwWITH, 'WITH')
END InitKeywords;

PROCEDURE KeywordCount (): CARDINAL;
BEGIN
  RETURN NumKw
END KeywordCount;

PROCEDURE KeywordText (i: CARDINAL; VAR s: ARRAY OF CHAR);
BEGIN
  Copy (s, kwText[i + 1])
END KeywordText;

PROCEDURE LookupKw (src: CharPtr; lo, hi: CARDINAL): Kw;
VAR
  k: CARDINAL;
  i: CARDINAL;
  ok: BOOLEAN;
BEGIN
  IF (hi - lo > 14) OR (src^[lo] < 'A') OR (src^[lo] > 'Z') THEN RETURN kwNone END;
  FOR k := 1 TO NumKw DO
    ok := TRUE;
    i := 0;
    WHILE ok AND (lo + i < hi) DO
      IF kwText[k][i] # src^[lo + i] THEN ok := FALSE END;
      INC (i)
    END;
    IF ok AND (kwText[k][i] = 0C) THEN RETURN VAL (Kw, k) END
  END;
  RETURN kwNone
END LookupKw;

PROCEDURE Tokenize (src: CharPtr; len: CARDINAL; VAR toks: TokPtr; VAR n: CARDINAL);
VAR
  cap, p, lineStart, line, q, depth, st: CARDINAL;
  c, c2: CHAR;
  kw: Kw;
  tk: Token;
  mem: ADDRESS;

  PROCEDURE Push (kind: TokKind; lo, hi: CARDINAL; a, b: CHAR);
  BEGIN
    IF n >= cap THEN
      cap := cap * 2;
      mem := realloc (toks, VAL (CSIZE_T, cap * SIZE (Token)));
      toks := mem
    END;
    toks^[n].kind := kind;
    toks^[n].kw := kwNone;
    toks^[n].start := lo;
    toks^[n].stop := hi;
    toks^[n].line := line;
    toks^[n].col := lo - lineStart;
    toks^[n].c1 := a;
    toks^[n].c2 := b;
    INC (n)
  END Push;

BEGIN
  cap := 1024;
  mem := realloc (NIL, VAL (CSIZE_T, cap * SIZE (Token)));
  toks := mem;
  n := 0; p := 0; line := 0; lineStart := 0;
  WHILE p < len DO
    c := src^[p];
    IF c = LF THEN
      INC (line); INC (p); lineStart := p
    ELSIF (c = ' ') OR (c = 11C) OR (c = 15C) THEN
      INC (p)
    ELSIF (c = '(') AND (p + 1 < len) AND (src^[p + 1] = '*') THEN
      depth := 1; INC (p, 2);
      WHILE (p < len) AND (depth > 0) DO
        IF (src^[p] = '(') AND (p + 1 < len) AND (src^[p + 1] = '*') THEN
          INC (depth); INC (p, 2)
        ELSIF (src^[p] = '*') AND (p + 1 < len) AND (src^[p + 1] = ')') THEN
          DEC (depth); INC (p, 2)
        ELSE
          IF src^[p] = LF THEN INC (line); lineStart := p + 1 END;
          INC (p)
        END
      END
    ELSIF IsIdStart (c) THEN
      st := p;
      WHILE (p < len) AND IsIdChar (src^[p]) DO INC (p) END;
      kw := LookupKw (src, st, p);
      IF kw = kwNone THEN
        Push (tkIdent, st, p, 0C, 0C)
      ELSE
        Push (tkKeyword, st, p, 0C, 0C);
        toks^[n - 1].kw := kw
      END
    ELSIF IsDigit (c) THEN
      st := p;
      WHILE (p < len) AND IsIdChar (src^[p]) DO INC (p) END;
      IF (p + 1 < len) AND (src^[p] = '.') AND (src^[p + 1] # '.') THEN
        INC (p);
        WHILE (p < len) AND IsIdChar (src^[p]) DO INC (p) END;
        IF (src^[p - 1] = 'E') AND (p < len) AND ((src^[p] = '+') OR (src^[p] = '-')) THEN
          INC (p);
          WHILE (p < len) AND IsDigit (src^[p]) DO INC (p) END
        END
      END;
      Push (tkNumber, st, p, 0C, 0C)
    ELSIF (c = "'") OR (c = '"') THEN
      st := p; INC (p);
      WHILE (p < len) AND (src^[p] # c) AND (src^[p] # LF) DO INC (p) END;
      IF (p < len) AND (src^[p] = c) THEN INC (p) END;
      Push (tkString, st, p, 0C, 0C)
    ELSE
      c2 := 0C;
      IF p + 1 < len THEN
        q := ORD (src^[p + 1]);
        IF ((c = ':') AND (q = ORD ('='))) OR ((c = '<') AND ((q = ORD ('=')) OR (q = ORD ('>'))))
           OR ((c = '>') AND (q = ORD ('='))) OR ((c = '.') AND (q = ORD ('.'))) THEN
          c2 := src^[p + 1]
        END
      END;
      IF c2 # 0C THEN
        Push (tkSym, p, p + 2, c, c2); INC (p, 2)
      ELSE
        Push (tkSym, p, p + 1, c, 0C); INC (p)
      END
    END
  END
END Tokenize;

PROCEDURE FreeTokens (VAR toks: TokPtr);
BEGIN
  IF toks # NIL THEN free (toks) END;
  toks := NIL
END FreeTokens;

PROCEDURE Context (src: CharPtr; len, offset: CARDINAL): CARDINAL;
VAR
  i, depth, j: CARDINAL;
  q: CHAR;
BEGIN
  i := 0; depth := 0;
  WHILE (i < offset) AND (i < len) DO
    IF depth > 0 THEN
      IF (src^[i] = '(') AND (i + 1 < len) AND (src^[i + 1] = '*') THEN
        INC (depth); INC (i, 2)
      ELSIF (src^[i] = '*') AND (i + 1 < len) AND (src^[i + 1] = ')') THEN
        DEC (depth); INC (i, 2)
      ELSE
        INC (i)
      END
    ELSIF (src^[i] = "'") OR (src^[i] = '"') THEN
      q := src^[i];
      j := i + 1;
      WHILE (j < len) AND (src^[j] # q) AND (src^[j] # LF) DO INC (j) END;
      IF (offset > i) AND (offset <= j) THEN RETURN 2 END;
      i := j + 1
    ELSIF (src^[i] = '(') AND (i + 1 < len) AND (src^[i + 1] = '*') THEN
      depth := 1; INC (i, 2)
    ELSE
      INC (i)
    END
  END;
  IF depth > 0 THEN RETURN 1 END;
  RETURN 0
END Context;

PROCEDURE OffsetOf (src: CharPtr; len, line, col: CARDINAL): CARDINAL;
VAR p, l: CARDINAL;
BEGIN
  p := 0; l := 0;
  WHILE (l < line) AND (p < len) DO
    IF src^[p] = LF THEN INC (l) END;
    INC (p)
  END;
  WHILE (col > 0) AND (p < len) AND (src^[p] # LF) DO
    INC (p); DEC (col)
  END;
  RETURN p
END OffsetOf;

PROCEDURE LineCol (src: CharPtr; len, offset: CARDINAL; VAR line, col: CARDINAL);
VAR p, ls: CARDINAL;
BEGIN
  line := 0; ls := 0; p := 0;
  WHILE (p < offset) AND (p < len) DO
    IF src^[p] = LF THEN INC (line); ls := p + 1 END;
    INC (p)
  END;
  col := offset - ls
END LineCol;

PROCEDURE LineEnd (src: CharPtr; len, offset: CARDINAL): CARDINAL;
BEGIN
  WHILE (offset < len) AND (src^[offset] # LF) DO INC (offset) END;
  RETURN offset
END LineEnd;

BEGIN
  InitKeywords
END Lexer.
