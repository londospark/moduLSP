IMPLEMENTATION MODULE Files;

FROM SYSTEM IMPORT ADDRESS, ADR, CSIZE_T;
FROM libc IMPORT open, close, read, write;
FROM Text IMPORT Buf, Reserve, AddCh, Add, Len, Copy, Append, IsDigit;

PROCEDURE ReadFile (path: ARRAY OF CHAR; VAR b: Buf): BOOLEAN;
VAR
  fd, n: INTEGER;
BEGIN
  fd := open (ADR (path), 0, 0);
  IF fd < 0 THEN RETURN FALSE END;
  LOOP
    Reserve (b, 65536);
    n := VAL (INTEGER, read (fd, ADDRESS (b.data) + VAL (ADDRESS, b.len), VAL (CSIZE_T, 65536)));
    IF n <= 0 THEN EXIT END;
    INC (b.len, VAL (CARDINAL, n))
  END;
  b.data^[b.len] := 0C;
  fd := close (fd);
  RETURN TRUE
END ReadFile;

PROCEDURE WriteFile (path: ARRAY OF CHAR; VAR b: Buf): BOOLEAN;
VAR
  fd, n: INTEGER;
  done: CARDINAL;
BEGIN
  fd := open (ADR (path), 577, 420);
  IF fd < 0 THEN RETURN FALSE END;
  done := 0;
  WHILE done < b.len DO
    n := VAL (INTEGER, write (fd, ADDRESS (b.data) + VAL (ADDRESS, done), VAL (CSIZE_T, b.len - done)));
    IF n <= 0 THEN
      fd := close (fd);
      RETURN FALSE
    END;
    INC (done, VAL (CARDINAL, n))
  END;
  fd := close (fd);
  RETURN TRUE
END WriteFile;

PROCEDURE Exists (path: ARRAY OF CHAR): BOOLEAN;
VAR fd: INTEGER;
BEGIN
  fd := open (ADR (path), 0, 0);
  IF fd < 0 THEN RETURN FALSE END;
  fd := close (fd);
  RETURN TRUE
END Exists;

PROCEDURE LastSlash (path: ARRAY OF CHAR): INTEGER;
VAR i, n: CARDINAL; r: INTEGER;
BEGIN
  n := Len (path);
  r := -1;
  FOR i := 1 TO n DO
    IF path[i - 1] = '/' THEN r := VAL (INTEGER, i - 1) END
  END;
  RETURN r
END LastSlash;

PROCEDURE DirName (path: ARRAY OF CHAR; VAR dir: ARRAY OF CHAR);
VAR k: INTEGER; i: CARDINAL;
BEGIN
  k := LastSlash (path);
  IF k < 0 THEN
    Copy (dir, '.')
  ELSIF k = 0 THEN
    Copy (dir, '/')
  ELSE
    i := 0;
    WHILE (i < VAL (CARDINAL, k)) AND (i < HIGH (dir)) DO
      dir[i] := path[i]; INC (i)
    END;
    dir[i] := 0C
  END
END DirName;

PROCEDURE BaseName (path: ARRAY OF CHAR; VAR base: ARRAY OF CHAR);
VAR k: INTEGER; i, j: CARDINAL;
BEGIN
  k := LastSlash (path);
  i := VAL (CARDINAL, k + 1);
  j := 0;
  WHILE (i < Len (path)) AND (j < HIGH (base)) DO
    base[j] := path[i]; INC (i); INC (j)
  END;
  base[j] := 0C
END BaseName;

PROCEDURE Stem (path: ARRAY OF CHAR; VAR stem: ARRAY OF CHAR);
VAR i, dot: CARDINAL;
BEGIN
  BaseName (path, stem);
  dot := Len (stem);
  FOR i := 1 TO Len (stem) DO
    IF stem[i - 1] = '.' THEN dot := i - 1 END
  END;
  stem[dot] := 0C
END Stem;

PROCEDURE HasExt (path: ARRAY OF CHAR; ext: ARRAY OF CHAR): BOOLEAN;
VAR n, e, i: CARDINAL;
BEGIN
  n := Len (path); e := Len (ext);
  IF n < e THEN RETURN FALSE END;
  FOR i := 1 TO e DO
    IF path[n - e + i - 1] # ext[i - 1] THEN RETURN FALSE END
  END;
  RETURN TRUE
END HasExt;

PROCEDURE HexVal (c: CHAR): INTEGER;
BEGIN
  IF IsDigit (c) THEN RETURN VAL (INTEGER, ORD (c) - ORD ('0')) END;
  IF (c >= 'a') AND (c <= 'f') THEN RETURN VAL (INTEGER, ORD (c) - ORD ('a') + 10) END;
  IF (c >= 'A') AND (c <= 'F') THEN RETURN VAL (INTEGER, ORD (c) - ORD ('A') + 10) END;
  RETURN -1
END HexVal;

PROCEDURE UriToPath (VAR uri: Buf; VAR path: ARRAY OF CHAR);
VAR i, j: CARDINAL; h1, h2: INTEGER;
BEGIN
  i := 0; j := 0;
  IF (uri.len >= 7) AND (uri.data^[0] = 'f') AND (uri.data^[4] = ':') THEN i := 7 END;
  WHILE (i < uri.len) AND (j < HIGH (path)) DO
    IF (uri.data^[i] = '%') AND (i + 2 < uri.len) THEN
      h1 := HexVal (uri.data^[i + 1]);
      h2 := HexVal (uri.data^[i + 2]);
      IF (h1 >= 0) AND (h2 >= 0) THEN
        path[j] := CHR (VAL (CARDINAL, h1 * 16 + h2));
        INC (i, 3)
      ELSE
        path[j] := '%'; INC (i)
      END
    ELSE
      path[j] := uri.data^[i]; INC (i)
    END;
    INC (j)
  END;
  path[j] := 0C
END UriToPath;

PROCEDURE PathToUri (path: ARRAY OF CHAR; VAR uri: Buf);
VAR i: CARDINAL; c: CHAR; hex: ARRAY [0..15] OF CHAR;
BEGIN
  Copy (hex, '0123456789ABCDEF');
  Add (uri, 'file://');
  FOR i := 1 TO Len (path) DO
    c := path[i - 1];
    IF ((c >= 'a') AND (c <= 'z')) OR ((c >= 'A') AND (c <= 'Z')) OR IsDigit (c)
       OR (c = '/') OR (c = '-') OR (c = '_') OR (c = '.') OR (c = '~') THEN
      AddCh (uri, c)
    ELSE
      AddCh (uri, '%');
      AddCh (uri, hex[ORD (c) DIV 16]);
      AddCh (uri, hex[ORD (c) MOD 16])
    END
  END
END PathToUri;

PROCEDURE ShellQuote (s: ARRAY OF CHAR; VAR out: ARRAY OF CHAR);
VAR i, j: CARDINAL;
BEGIN
  j := 0;
  out[j] := "'"; INC (j);
  FOR i := 1 TO Len (s) DO
    IF j + 6 < HIGH (out) THEN
      IF s[i - 1] = "'" THEN
        out[j] := "'"; out[j + 1] := '\'; out[j + 2] := "'"; out[j + 3] := "'";
        INC (j, 4)
      ELSE
        out[j] := s[i - 1]; INC (j)
      END
    END
  END;
  out[j] := "'"; INC (j);
  out[j] := 0C
END ShellQuote;

END Files.
