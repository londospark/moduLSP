IMPLEMENTATION MODULE Units;

FROM Symbols IMPORT Doc, NewDoc, FreeDoc, LoadFile, PathLen;
FROM Text IMPORT Eq, Copy, Append;
FROM Files IMPORT Exists;

CONST
  MaxDirs = 24;
  MaxUnits = 96;

VAR
  dirs: ARRAY [0..MaxDirs - 1] OF ARRAY [0..PathLen - 1] OF CHAR;
  ndirs: CARDINAL;
  units: ARRAY [0..MaxUnits - 1] OF Doc;
  nunits: CARDINAL;
  next: CARDINAL;

PROCEDURE AddDir (dir: ARRAY OF CHAR);
VAR i: CARDINAL;
BEGIN
  FOR i := 1 TO ndirs DO
    IF Eq (dirs[i - 1], dir) THEN RETURN END
  END;
  IF ndirs < MaxDirs THEN
    Copy (dirs[ndirs], dir);
    INC (ndirs)
  END
END AddDir;

PROCEDURE Cached (path: ARRAY OF CHAR): Doc;
VAR i: CARDINAL;
BEGIN
  FOR i := 1 TO nunits DO
    IF (units[i - 1] # NIL) AND Eq (units[i - 1]^.path, path) THEN RETURN units[i - 1] END
  END;
  RETURN NIL
END Cached;

PROCEDURE Load (path: ARRAY OF CHAR): Doc;
VAR d: Doc;
BEGIN
  d := Cached (path);
  IF d # NIL THEN RETURN d END;
  d := NewDoc (path);
  IF NOT LoadFile (d) THEN
    FreeDoc (d);
    RETURN NIL
  END;
  IF nunits < MaxUnits THEN
    units[nunits] := d;
    INC (nunits)
  ELSE
    (* cache full: recycle slots round-robin *)
    FreeDoc (units[next]);
    units[next] := d;
    next := (next + 1) MOD MaxUnits
  END;
  RETURN d
END Load;

PROCEDURE Find (module, localDir: ARRAY OF CHAR): Doc;
VAR
  path: ARRAY [0..PathLen - 1] OF CHAR;
  i: CARDINAL;
BEGIN
  Copy (path, localDir);
  Append (path, '/');
  Append (path, module);
  Append (path, '.def');
  IF Exists (path) THEN RETURN Load (path) END;
  FOR i := 1 TO ndirs DO
    Copy (path, dirs[i - 1]);
    Append (path, '/');
    Append (path, module);
    Append (path, '.def');
    IF Exists (path) THEN RETURN Load (path) END
  END;
  RETURN NIL
END Find;

PROCEDURE Invalidate (path: ARRAY OF CHAR);
VAR i: CARDINAL;
BEGIN
  FOR i := 1 TO nunits DO
    IF (units[i - 1] # NIL) AND Eq (units[i - 1]^.path, path) THEN
      FreeDoc (units[i - 1])
    END
  END
END Invalidate;

BEGIN
  ndirs := 0;
  nunits := 0;
  next := 0
END Units.
