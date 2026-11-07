IMPLEMENTATION MODULE Pervasive;

FROM Text IMPORT Copy, Eq;

CONST
  Max = 80;

TYPE
  Entry = RECORD
            kind: BKind;
            name: ARRAY [0..23] OF CHAR;
            sig: ARRAY [0..79] OF CHAR;
            doc: ARRAY [0..127] OF CHAR
          END;

VAR
  tab: ARRAY [0..Max - 1] OF Entry;
  n: CARDINAL;

PROCEDURE Def (k: BKind; name, sig, doc: ARRAY OF CHAR);
BEGIN
  IF n < Max THEN
    tab[n].kind := k;
    Copy (tab[n].name, name);
    Copy (tab[n].sig, sig);
    Copy (tab[n].doc, doc);
    INC (n)
  END
END Def;

PROCEDURE Count (): CARDINAL;
BEGIN
  RETURN n
END Count;

PROCEDURE Get (i: CARDINAL; VAR name, sig, doc: ARRAY OF CHAR): BKind;
BEGIN
  Copy (name, tab[i].name);
  Copy (sig, tab[i].sig);
  Copy (doc, tab[i].doc);
  RETURN tab[i].kind
END Get;

PROCEDURE Find (name: ARRAY OF CHAR): CARDINAL;
VAR i: CARDINAL;
BEGIN
  i := 0;
  WHILE i < n DO
    IF Eq (tab[i].name, name) THEN RETURN i END;
    INC (i)
  END;
  RETURN n
END Find;

BEGIN
  n := 0;
  Def (bType, 'BOOLEAN', 'BOOLEAN', 'Boolean type: FALSE, TRUE.');
  Def (bType, 'CHAR', 'CHAR', 'Character type.');
  Def (bType, 'INTEGER', 'INTEGER', 'Signed integer of the natural machine size.');
  Def (bType, 'CARDINAL', 'CARDINAL', 'Unsigned integer of the natural machine size.');
  Def (bType, 'LONGINT', 'LONGINT', 'Long signed integer.');
  Def (bType, 'LONGCARD', 'LONGCARD', 'Long unsigned integer.');
  Def (bType, 'SHORTINT', 'SHORTINT', 'Short signed integer.');
  Def (bType, 'SHORTCARD', 'SHORTCARD', 'Short unsigned integer.');
  Def (bType, 'REAL', 'REAL', 'Single precision floating point.');
  Def (bType, 'LONGREAL', 'LONGREAL', 'Double precision floating point.');
  Def (bType, 'SHORTREAL', 'SHORTREAL', 'Short floating point.');
  Def (bType, 'COMPLEX', 'COMPLEX', 'Complex number of REAL components.');
  Def (bType, 'LONGCOMPLEX', 'LONGCOMPLEX', 'Complex number of LONGREAL components.');
  Def (bType, 'SHORTCOMPLEX', 'SHORTCOMPLEX', 'Complex number of SHORTREAL components.');
  Def (bType, 'BITSET', 'BITSET', 'Set of 0 .. word size - 1.');
  Def (bType, 'PROC', 'PROC', 'Parameterless procedure type.');
  Def (bConst, 'TRUE', 'TRUE', 'Boolean true.');
  Def (bConst, 'FALSE', 'FALSE', 'Boolean false.');
  Def (bConst, 'NIL', 'NIL', 'Null pointer value, compatible with all pointer types.');
  Def (bProc, 'ABS', 'ABS(x) : <type of x>', 'Absolute value.');
  Def (bProc, 'CAP', 'CAP(ch : CHAR) : CHAR', 'Upper case of a letter.');
  Def (bProc, 'CHR', 'CHR(x : CARDINAL) : CHAR', 'Character with ordinal x.');
  Def (bProc, 'CMPLX', 'CMPLX(re, im : REAL) : COMPLEX', 'Construct a complex number.');
  Def (bProc, 'DEC', 'DEC(VAR v [; n])', 'v := v - n (n defaults to 1).');
  Def (bProc, 'DISPOSE', 'DISPOSE(VAR p)', 'Release storage of p (calls DEALLOCATE).');
  Def (bProc, 'EXCL', 'EXCL(VAR s; e)', 's := s - {e}.');
  Def (bProc, 'FLOAT', 'FLOAT(x) : REAL', 'Convert to REAL.');
  Def (bProc, 'HALT', 'HALT[(status)]', 'Terminate the program.');
  Def (bProc, 'HIGH', 'HIGH(a) : CARDINAL', 'Highest index of an (open) array.');
  Def (bProc, 'IM', 'IM(z) : REAL', 'Imaginary part.');
  Def (bProc, 'INC', 'INC(VAR v [; n])', 'v := v + n (n defaults to 1).');
  Def (bProc, 'INCL', 'INCL(VAR s; e)', 's := s + {e}.');
  Def (bProc, 'INT', 'INT(x) : INTEGER', 'Convert to INTEGER.');
  Def (bProc, 'LENGTH', 'LENGTH(s : ARRAY OF CHAR) : CARDINAL', 'Length of a string.');
  Def (bProc, 'LFLOAT', 'LFLOAT(x) : LONGREAL', 'Convert to LONGREAL.');
  Def (bProc, 'LONG', 'LONG(x)', 'Widen a value to its long type.');
  Def (bProc, 'MAX', 'MAX(T) : T', 'Largest value of type T.');
  Def (bProc, 'MIN', 'MIN(T) : T', 'Smallest value of type T.');
  Def (bProc, 'NEW', 'NEW(VAR p)', 'Allocate storage for p^ (calls ALLOCATE).');
  Def (bProc, 'ODD', 'ODD(x) : BOOLEAN', 'x is odd.');
  Def (bProc, 'ORD', 'ORD(x) : CARDINAL', 'Ordinal number of x.');
  Def (bProc, 'RE', 'RE(z) : REAL', 'Real part.');
  Def (bProc, 'SHORT', 'SHORT(x)', 'Narrow a value to its short type.');
  Def (bProc, 'SIZE', 'SIZE(v | T) : CARDINAL', 'Storage size of a variable or type.');
  Def (bProc, 'TRUNC', 'TRUNC(r) : CARDINAL', 'Truncate a real number.');
  Def (bProc, 'VAL', 'VAL(T, x) : T', 'Convert x to type T.')
END Pervasive.
