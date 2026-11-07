IMPLEMENTATION MODULE Text;

FROM SYSTEM IMPORT ADDRESS, CSIZE_T;
FROM libc IMPORT realloc, free, memcpy;

CONST
  BS = 134C;

PROCEDURE Init (VAR b: Buf);
BEGIN
  b.data := NIL;
  b.len := 0;
  b.cap := 0
END Init;

PROCEDURE Release (VAR b: Buf);
BEGIN
  IF b.data # NIL THEN free (b.data) END;
  Init (b)
END Release;

PROCEDURE Clear (VAR b: Buf);
BEGIN
  b.len := 0;
  IF b.data # NIL THEN b.data^[0] := 0C END
END Clear;

PROCEDURE Reserve (VAR b: Buf; extra: CARDINAL);
VAR
  need, ncap: CARDINAL;
  p: ADDRESS;
BEGIN
  need := b.len + extra + 1;
  IF need > b.cap THEN
    ncap := b.cap * 2;
    IF ncap < 256 THEN ncap := 256 END;
    WHILE ncap < need DO ncap := ncap * 2 END;
    p := realloc (b.data, VAL (CSIZE_T, ncap));
    b.data := p;
    b.cap := ncap
  END
END Reserve;

PROCEDURE AddCh (VAR b: Buf; c: CHAR);
BEGIN
  Reserve (b, 1);
  b.data^[b.len] := c;
  INC (b.len);
  b.data^[b.len] := 0C
END AddCh;

PROCEDURE Add (VAR b: Buf; s: ARRAY OF CHAR);
VAR i: CARDINAL;
BEGIN
  i := 0;
  WHILE (i <= HIGH (s)) AND (s[i] # 0C) DO
    AddCh (b, s[i]);
    INC (i)
  END
END Add;

PROCEDURE AddBuf (VAR b: Buf; VAR src: Buf);
BEGIN
  IF src.len > 0 THEN AddRange (b, src.data, 0, src.len) END
END AddBuf;

PROCEDURE AddRange (VAR b: Buf; p: CharPtr; lo, hi: CARDINAL);
VAR r: ADDRESS;
BEGIN
  IF hi > lo THEN
    Reserve (b, hi - lo);
    r := memcpy (ADDRESS (b.data) + VAL (ADDRESS, b.len), ADDRESS (p) + VAL (ADDRESS, lo), VAL (CSIZE_T, hi - lo));
    INC (b.len, hi - lo);
    b.data^[b.len] := 0C
  END
END AddRange;

PROCEDURE AddCard (VAR b: Buf; n: CARDINAL);
VAR
  tmp: ARRAY [0..15] OF CHAR;
  i: CARDINAL;
BEGIN
  IF n = 0 THEN
    AddCh (b, '0')
  ELSE
    i := 0;
    WHILE n > 0 DO
      tmp[i] := CHR (ORD ('0') + (n MOD 10));
      n := n DIV 10;
      INC (i)
    END;
    WHILE i > 0 DO
      DEC (i);
      AddCh (b, tmp[i])
    END
  END
END AddCard;

PROCEDURE AddInt (VAR b: Buf; n: INTEGER);
BEGIN
  IF n < 0 THEN
    AddCh (b, '-');
    AddCard (b, VAL (CARDINAL, -n))
  ELSE
    AddCard (b, VAL (CARDINAL, n))
  END
END AddInt;

PROCEDURE AddUtf8 (VAR b: Buf; cp: CARDINAL);
BEGIN
  IF cp < 80H THEN
    AddCh (b, CHR (cp))
  ELSIF cp < 800H THEN
    AddCh (b, CHR (0C0H + cp DIV 40H));
    AddCh (b, CHR (80H + cp MOD 40H))
  ELSIF cp < 10000H THEN
    AddCh (b, CHR (0E0H + cp DIV 1000H));
    AddCh (b, CHR (80H + (cp DIV 40H) MOD 40H));
    AddCh (b, CHR (80H + cp MOD 40H))
  ELSE
    AddCh (b, CHR (0F0H + cp DIV 40000H));
    AddCh (b, CHR (80H + (cp DIV 1000H) MOD 40H));
    AddCh (b, CHR (80H + (cp DIV 40H) MOD 40H));
    AddCh (b, CHR (80H + cp MOD 40H))
  END
END AddUtf8;

PROCEDURE HexDigit (n: CARDINAL): CHAR;
BEGIN
  IF n < 10 THEN RETURN CHR (ORD ('0') + n) END;
  RETURN CHR (ORD ('a') + n - 10)
END HexDigit;

PROCEDURE EscCh (VAR b: Buf; c: CHAR);
BEGIN
  IF c = '"' THEN
    AddCh (b, BS); AddCh (b, '"')
  ELSIF c = BS THEN
    AddCh (b, BS); AddCh (b, BS)
  ELSIF c = 12C THEN
    AddCh (b, BS); AddCh (b, 'n')
  ELSIF c = 15C THEN
    AddCh (b, BS); AddCh (b, 'r')
  ELSIF c = 11C THEN
    AddCh (b, BS); AddCh (b, 't')
  ELSIF c < ' ' THEN
    AddCh (b, BS); AddCh (b, 'u'); AddCh (b, '0'); AddCh (b, '0');
    AddCh (b, HexDigit (ORD (c) DIV 16));
    AddCh (b, HexDigit (ORD (c) MOD 16))
  ELSE
    AddCh (b, c)
  END
END EscCh;

PROCEDURE AddJson (VAR b: Buf; s: ARRAY OF CHAR);
VAR i: CARDINAL;
BEGIN
  AddCh (b, '"');
  i := 0;
  WHILE (i <= HIGH (s)) AND (s[i] # 0C) DO
    EscCh (b, s[i]);
    INC (i)
  END;
  AddCh (b, '"')
END AddJson;

PROCEDURE AddJsonRange (VAR b: Buf; p: CharPtr; lo, hi: CARDINAL);
VAR i: CARDINAL;
BEGIN
  AddCh (b, '"');
  i := lo;
  WHILE i < hi DO
    EscCh (b, p^[i]);
    INC (i)
  END;
  AddCh (b, '"')
END AddJsonRange;

PROCEDURE AddJsonFlat (VAR b: Buf; p: CharPtr; lo, hi, limit: CARDINAL);
VAR
  i, n: CARDINAL;
  space: BOOLEAN;
BEGIN
  AddCh (b, '"');
  i := lo; n := 0; space := TRUE;
  WHILE (i < hi) AND (n < limit) DO
    IF IsSpace (p^[i]) THEN
      IF NOT space THEN AddCh (b, ' '); INC (n) END;
      space := TRUE
    ELSE
      EscCh (b, p^[i]);
      INC (n);
      space := FALSE
    END;
    INC (i)
  END;
  AddCh (b, '"')
END AddJsonFlat;

PROCEDURE SetStr (VAR b: Buf; s: ARRAY OF CHAR);
BEGIN
  Clear (b);
  Add (b, s)
END SetStr;

PROCEDURE Len (a: ARRAY OF CHAR): CARDINAL;
VAR i: CARDINAL;
BEGIN
  i := 0;
  WHILE (i <= HIGH (a)) AND (a[i] # 0C) DO INC (i) END;
  RETURN i
END Len;

PROCEDURE Eq (a, b: ARRAY OF CHAR): BOOLEAN;
VAR i: CARDINAL;
BEGIN
  i := 0;
  LOOP
    IF (i > HIGH (a)) OR (a[i] = 0C) THEN
      RETURN (i > HIGH (b)) OR (b[i] = 0C)
    END;
    IF (i > HIGH (b)) OR (b[i] # a[i]) THEN RETURN FALSE END;
    INC (i)
  END
END Eq;

PROCEDURE Copy (VAR dst: ARRAY OF CHAR; src: ARRAY OF CHAR);
VAR i: CARDINAL;
BEGIN
  i := 0;
  WHILE (i <= HIGH (src)) AND (i < HIGH (dst)) AND (src[i] # 0C) DO
    dst[i] := src[i];
    INC (i)
  END;
  dst[i] := 0C
END Copy;

PROCEDURE CopyRange (VAR dst: ARRAY OF CHAR; p: CharPtr; lo, hi: CARDINAL);
VAR i: CARDINAL;
BEGIN
  i := 0;
  WHILE (lo + i < hi) AND (i < HIGH (dst)) DO
    dst[i] := p^[lo + i];
    INC (i)
  END;
  dst[i] := 0C
END CopyRange;

PROCEDURE Append (VAR dst: ARRAY OF CHAR; src: ARRAY OF CHAR);
VAR i, j: CARDINAL;
BEGIN
  i := Len (dst);
  j := 0;
  WHILE (j <= HIGH (src)) AND (i < HIGH (dst)) AND (src[j] # 0C) DO
    dst[i] := src[j];
    INC (i); INC (j)
  END;
  dst[i] := 0C
END Append;

PROCEDURE UpCh (c: CHAR): CHAR;
BEGIN
  IF (c >= 'a') AND (c <= 'z') THEN RETURN CHR (ORD (c) - 32) END;
  RETURN c
END UpCh;

PROCEDURE IsDigit (c: CHAR): BOOLEAN;
BEGIN
  RETURN (c >= '0') AND (c <= '9')
END IsDigit;

PROCEDURE IsIdStart (c: CHAR): BOOLEAN;
BEGIN
  RETURN ((c >= 'a') AND (c <= 'z')) OR ((c >= 'A') AND (c <= 'Z')) OR (c = '_')
END IsIdStart;

PROCEDURE IsIdChar (c: CHAR): BOOLEAN;
BEGIN
  RETURN IsIdStart (c) OR IsDigit (c)
END IsIdChar;

PROCEDURE IsSpace (c: CHAR): BOOLEAN;
BEGIN
  RETURN (c = ' ') OR (c = 11C) OR (c = 12C) OR (c = 15C)
END IsSpace;

PROCEDURE HasPrefixCI (name, prefix: ARRAY OF CHAR): BOOLEAN;
VAR i: CARDINAL;
BEGIN
  i := 0;
  WHILE (i <= HIGH (prefix)) AND (prefix[i] # 0C) DO
    IF (i > HIGH (name)) OR (UpCh (name[i]) # UpCh (prefix[i])) THEN RETURN FALSE END;
    INC (i)
  END;
  RETURN TRUE
END HasPrefixCI;

PROCEDURE BufEqStr (VAR b: Buf; s: ARRAY OF CHAR): BOOLEAN;
VAR i: CARDINAL;
BEGIN
  IF b.len # Len (s) THEN RETURN FALSE END;
  i := 0;
  WHILE i < b.len DO
    IF b.data^[i] # s[i] THEN RETURN FALSE END;
    INC (i)
  END;
  RETURN TRUE
END BufEqStr;

END Text.
