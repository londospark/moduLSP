MODULE Dump;
(* debugging aid: print the symbol table of a file *)
FROM Symbols IMPORT Doc, NewDoc, LoadFile, SymKind;
FROM Args IMPORT GetArg;
FROM StrIO IMPORT WriteString, WriteLn;
FROM NumberIO IMPORT WriteInt, WriteCard;
VAR
  d: Doc;
  path: ARRAY [0..1023] OF CHAR;
  k: CARDINAL;
BEGIN
  IF GetArg (path, 1) THEN
    d := NewDoc (path);
    IF LoadFile (d) THEN
      k := 0;
      WHILE k < d^.nsyms DO
        WriteCard (k, 3); WriteString (' ');
        WriteString (d^.syms^[k].name); WriteString (' kind=');
        WriteCard (ORD (d^.syms^[k].kind), 0);
        WriteString (' scope='); WriteInt (d^.syms^[k].scope, 0);
        WriteString (' owner='); WriteInt (d^.syms^[k].owner, 0);
        WriteString (' type='); WriteString (d^.syms^[k].typeName);
        WriteString (' rec='); WriteCard (ORD (d^.syms^[k].isRecord), 0);
        WriteString (' end='); WriteCard (d^.syms^[k].bodyEnd, 0);
        WriteLn;
        INC (k)
      END
    END
  END
END Dump.
