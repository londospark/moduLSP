MODULE Demo;

FROM Shapes IMPORT Shape, Point, Kind, NewShape, Area;
IMPORT Shapes;
FROM STextIO IMPORT WriteString, WriteLn;

VAR
  s: Shape;
  p: Point;
  total: CARDINAL;

PROCEDURE Describe (sh: Shape; verbose: BOOLEAN);
VAR
  local: CARDINAL;
BEGIN
  local := Area (sh);
  sh^.origin.x := 1;
  total := total + local
END Describe;

BEGIN
  p.x := 1;
  s := NewShape (Circle, p, 3);
  Describe (s, TRUE);
  Shapes.count := 2;
  undefinedThing := 4
END Demo.
