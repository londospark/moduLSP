MODULE Limits;

FROM Shapes IMPORT Shape, Point, NewShape;

VAR
  grid: ARRAY [0..3] OF RECORD
                          cell: Point;
                          tag: CARDINAL
                        END;
  cfg: RECORD
         name: CARDINAL;
         inner: RECORD depth: INTEGER END
       END;
  sh: Shape;

PROCEDURE Current (): Shape;
BEGIN
  RETURN sh
END Current;

BEGIN
  grid[1].tag := 1;
  cfg.inner.depth := 2;
  Current ().size := 3;
  NewShape (Circle, grid[0].cell, 2)^.origin.x := 1;
  WITH cfg DO
    name := 1;
    WITH inner DO
      depth := 3
    END
  END;
  WITH sh^ DO
    kind := Circle
  END
END Limits.
