IMPLEMENTATION MODULE Json;

FROM Text IMPORT CharPtr, Buf, AddCh, AddUtf8, IsDigit;

CONST
  BS = 134C;

PROCEDURE SkipWs (src: CharPtr; len, p: CARDINAL): CARDINAL;
BEGIN
  WHILE (p < len) AND ((src^[p] = ' ') OR (src^[p] = 12C) OR (src^[p] = 15C) OR (src^[p] = 11C)) DO
    INC (p)
  END;
  RETURN p
END SkipWs;

PROCEDURE SkipString (src: CharPtr; len, p: CARDINAL): CARDINAL;
BEGIN
  INC (p);
  WHILE p < len DO
    IF src^[p] = BS THEN
      INC (p, 2)
    ELSIF src^[p] = '"' THEN
      RETURN p + 1
    ELSE
      INC (p)
    END
  END;
  RETURN len
END SkipString;

PROCEDURE SkipValue (src: CharPtr; len, pos: CARDINAL): CARDINAL;
VAR p, depth: CARDINAL;
BEGIN
  p := SkipWs (src, len, pos);
  IF p >= len THEN RETURN len END;
  IF src^[p] = '"' THEN
    RETURN SkipString (src, len, p)
  ELSIF (src^[p] = '{') OR (src^[p] = '[') THEN
    depth := 0;
    LOOP
      IF p >= len THEN RETURN len END;
      IF src^[p] = '"' THEN
        p := SkipString (src, len, p)
      ELSIF (src^[p] = '{') OR (src^[p] = '[') THEN
        INC (depth); INC (p)
      ELSIF (src^[p] = '}') OR (src^[p] = ']') THEN
        DEC (depth); INC (p);
        IF depth = 0 THEN RETURN p END
      ELSE
        INC (p)
      END
    END
  ELSE
    WHILE (p < len) AND (src^[p] # ',') AND (src^[p] # '}') AND (src^[p] # ']')
          AND (src^[p] # ' ') AND (src^[p] # 12C) AND (src^[p] # 15C) DO
      INC (p)
    END;
    RETURN p
  END
END SkipValue;

PROCEDURE Find (src: CharPtr; len: CARDINAL; path: ARRAY OF CHAR; VAR pos: CARDINAL): BOOLEAN;
VAR
  p, i, j, ks, ke, k, idx: CARDINAL;
  match: BOOLEAN;
BEGIN
  p := 0; i := 0;
  LOOP
    p := SkipWs (src, len, p);
    IF (i > HIGH (path)) OR (path[i] = 0C) THEN
      pos := p;
      RETURN p < len
    END;
    j := i;
    WHILE (j <= HIGH (path)) AND (path[j] # 0C) AND (path[j] # '.') DO INC (j) END;
    IF IsDigit (path[i]) THEN
      IF (p >= len) OR (src^[p] # '[') THEN RETURN FALSE END;
      idx := 0; k := i;
      WHILE k < j DO
        idx := idx * 10 + (ORD (path[k]) - ORD ('0'));
        INC (k)
      END;
      p := SkipWs (src, len, p + 1);
      IF (p < len) AND (src^[p] = ']') THEN RETURN FALSE END;
      k := 0;
      WHILE k < idx DO
        p := SkipWs (src, len, SkipValue (src, len, p));
        IF (p < len) AND (src^[p] = ',') THEN
          p := SkipWs (src, len, p + 1)
        ELSE
          RETURN FALSE
        END;
        INC (k)
      END
    ELSE
      IF (p >= len) OR (src^[p] # '{') THEN RETURN FALSE END;
      INC (p);
      LOOP
        p := SkipWs (src, len, p);
        IF (p >= len) OR (src^[p] # '"') THEN RETURN FALSE END;
        ks := p + 1;
        p := SkipString (src, len, p);
        ke := p - 1;
        p := SkipWs (src, len, p);
        IF (p >= len) OR (src^[p] # ':') THEN RETURN FALSE END;
        p := SkipWs (src, len, p + 1);
        match := (ke >= ks) AND (ke - ks = j - i);
        k := 0;
        WHILE match AND (k < j - i) DO
          IF src^[ks + k] # path[i + k] THEN match := FALSE END;
          INC (k)
        END;
        IF match THEN EXIT END;
        p := SkipWs (src, len, SkipValue (src, len, p));
        IF (p < len) AND (src^[p] = ',') THEN INC (p) ELSE RETURN FALSE END
      END
    END;
    i := j;
    IF (i <= HIGH (path)) AND (path[i] = '.') THEN INC (i) END
  END
END Find;

PROCEDURE Hex4 (src: CharPtr; len, p: CARDINAL): CARDINAL;
VAR
  k, v, d: CARDINAL;
  c: CHAR;
BEGIN
  v := 0;
  FOR k := 0 TO 3 DO
    IF p + k < len THEN c := src^[p + k] ELSE c := '0' END;
    IF IsDigit (c) THEN
      d := ORD (c) - ORD ('0')
    ELSIF (c >= 'a') AND (c <= 'f') THEN
      d := ORD (c) - ORD ('a') + 10
    ELSIF (c >= 'A') AND (c <= 'F') THEN
      d := ORD (c) - ORD ('A') + 10
    ELSE
      d := 0
    END;
    v := v * 16 + d
  END;
  RETURN v
END Hex4;

PROCEDURE GetString (src: CharPtr; len, pos: CARDINAL; VAR out: Buf): BOOLEAN;
VAR
  p, cp, lo: CARDINAL;
  c: CHAR;
BEGIN
  p := SkipWs (src, len, pos);
  IF (p >= len) OR (src^[p] # '"') THEN RETURN FALSE END;
  INC (p);
  WHILE (p < len) AND (src^[p] # '"') DO
    c := src^[p];
    IF (c = BS) AND (p + 1 < len) THEN
      INC (p);
      c := src^[p];
      IF c = 'n' THEN AddCh (out, 12C)
      ELSIF c = 't' THEN AddCh (out, 11C)
      ELSIF c = 'r' THEN AddCh (out, 15C)
      ELSIF c = 'b' THEN AddCh (out, 10C)
      ELSIF c = 'f' THEN AddCh (out, 14C)
      ELSIF c = 'u' THEN
        cp := Hex4 (src, len, p + 1);
        INC (p, 4);
        IF (cp >= 0D800H) AND (cp < 0DC00H) AND (p + 6 < len)
           AND (src^[p + 1] = BS) AND (src^[p + 2] = 'u') THEN
          lo := Hex4 (src, len, p + 3);
          cp := 10000H + (cp - 0D800H) * 400H + (lo - 0DC00H);
          INC (p, 6)
        END;
        AddUtf8 (out, cp)
      ELSE
        AddCh (out, c)
      END
    ELSE
      AddCh (out, c)
    END;
    INC (p)
  END;
  RETURN TRUE
END GetString;

PROCEDURE GetCard (src: CharPtr; len, pos: CARDINAL; VAR n: CARDINAL): BOOLEAN;
VAR p: CARDINAL;
BEGIN
  p := SkipWs (src, len, pos);
  IF (p >= len) OR NOT IsDigit (src^[p]) THEN RETURN FALSE END;
  n := 0;
  WHILE (p < len) AND IsDigit (src^[p]) DO
    n := n * 10 + (ORD (src^[p]) - ORD ('0'));
    INC (p)
  END;
  RETURN TRUE
END GetCard;

END Json.
