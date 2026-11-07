MODULE More;

TYPE
  Token = RECORD
            pos: CARDINAL;
            CASE kind: CARDINAL OF
              0: num: INTEGER; neg: BOOLEAN |
              1, 2: text: CARDINAL |
              3..5: (* nothing *)
            ELSE
              other: CHAR
            END;
            tail: CARDINAL
          END;

PROCEDURE Work;
TYPE
  Local = RECORD
            alpha, beta: INTEGER
          END;
  LocalPtr = POINTER TO Local;
VAR
  lp: LocalPtr;
  tk: Token;
BEGIN
  lp^.alpha := 1;
  tk.num := 2
END Work;

CONST
  Limit = 16;
VAR
  small: RECORD a: INTEGER END;

BEGIN
END More.
