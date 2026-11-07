MODULE Cases;

TYPE
  Kind = (Circle, Square, Triangle, Hexagon);
  Shape = RECORD
            CASE kind: Kind OF
              Circle: r: CARDINAL |
              Square, Triangle: side: CARDINAL
            ELSE
              n: CARDINAL
            END
          END;

VAR
  s: Shape;
  k: Kind;
  n: CARDINAL;

PROCEDURE Area (VAR sh: Shape): CARDINAL;
BEGIN
  CASE sh.kind OF
    Circle: RETURN 1 |
    Square: RETURN 2 |
    Triangle: RETURN 3
  END;
  RETURN 0
END Area;

BEGIN
  CASE k OF
    Circle..Hexagon: n := 1
  END;
  CASE k OF
    Circle: n := 1
  ELSE
    n := 2
  END;
  CASE k OF
    Circle: n := 1 |
    Square:
      CASE s.kind OF
        Circle: n := 1 |
        Square..Hexagon: n := 2
      END
  END;
  CASE n OF
    1: n := 2
  END
END Cases.
