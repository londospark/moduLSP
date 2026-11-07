MODULE m2lsp;
(* A small Language Server for GNU Modula-2, written in GNU Modula-2.

   stdio JSON-RPC with Content-Length framing. Features:
     diagnostics     real compiler output (gm2 -fsyntax-only) on open and save
     completion      keywords, builtins, scope symbols, imports, Module.member, record.field
     hover           declaration text of the identifier under the cursor
     definition      across .def files found next to the file or in gm2's library dirs
     documentSymbol  outline

   Environment:  M2LSP_FLAGS    extra gm2 flags, e.g. "-fiso" or "-fpim4"
                 M2LSP_INCLUDE  colon separated extra directories (-I and .def search) *)

FROM SYSTEM IMPORT ADDRESS, ADR, CSIZE_T;
FROM libc IMPORT read, write, exit;
FROM Text IMPORT Buf, CharPtr, Init, Release, Clear, Reserve, Add, AddCh, AddBuf, AddRange, AddCard,
                 AddJsonRange, Eq, Len, BufEqStr;
FROM Json IMPORT Find, SkipValue, GetString, GetCard;
FROM Files IMPORT UriToPath;
FROM Lexer IMPORT OffsetOf;
FROM Symbols IMPORT Doc, NewDoc, FreeDoc, SetText, PathLen;
IMPORT Units, Nav, Gm2, Lint;

CONST
  MaxDocs = 64;

TYPE
  Slot = RECORD
           used: BOOLEAN;
           uri: Buf;
           doc: Doc
         END;

VAR
  slots: ARRAY [0..MaxDocs - 1] OF Slot;
  ibuf: ARRAY [0..65535] OF CHAR;
  ipos, ilen: CARDINAL;
  msg: Buf;           (* current request body *)
  reply: Buf;         (* outgoing body under construction *)
  result: Buf;
  shutdownSeen: BOOLEAN;

(* ---- transport ---- *)

PROCEDURE GetByte (VAR c: CHAR): BOOLEAN;
VAR n: INTEGER;
BEGIN
  IF ipos >= ilen THEN
    n := VAL (INTEGER, read (0, ADR (ibuf), VAL (CSIZE_T, 65536)));
    IF n <= 0 THEN RETURN FALSE END;
    ilen := VAL (CARDINAL, n);
    ipos := 0
  END;
  c := ibuf[ipos];
  INC (ipos);
  RETURN TRUE
END GetByte;

PROCEDURE ReadMessage (VAR body: Buf): BOOLEAN;
VAR
  c: CHAR;
  line: ARRAY [0..255] OF CHAR;
  ll, i, len: CARDINAL;
BEGIN
  len := 0;
  LOOP
    ll := 0;
    LOOP
      IF NOT GetByte (c) THEN RETURN FALSE END;
      IF c = 12C THEN EXIT END;
      IF (c # 15C) AND (ll < 255) THEN line[ll] := c; INC (ll) END
    END;
    line[ll] := 0C;
    IF ll = 0 THEN EXIT END;
    IF (ll > 15) AND (line[0] = 'C') AND (line[7] = '-') AND (line[14] = ':') THEN
      i := 15;
      WHILE (i < ll) AND (line[i] = ' ') DO INC (i) END;
      len := 0;
      WHILE (i < ll) AND (line[i] >= '0') AND (line[i] <= '9') DO
        len := len * 10 + (ORD (line[i]) - ORD ('0'));
        INC (i)
      END
    END
  END;
  Clear (body);
  Reserve (body, len);
  i := 0;
  WHILE i < len DO
    IF NOT GetByte (c) THEN RETURN FALSE END;
    AddCh (body, c);
    INC (i)
  END;
  RETURN TRUE
END ReadMessage;

PROCEDURE WriteAll (p: CharPtr; n: CARDINAL);
VAR
  done: CARDINAL;
  w: INTEGER;
BEGIN
  done := 0;
  WHILE done < n DO
    w := VAL (INTEGER, write (1, ADDRESS (p) + VAL (ADDRESS, done), VAL (CSIZE_T, n - done)));
    IF w <= 0 THEN exit (1) END;
    INC (done, VAL (CARDINAL, w))
  END
END WriteAll;

PROCEDURE Send (VAR b: Buf);
VAR h: Buf;
BEGIN
  Init (h);
  Add (h, 'Content-Length: ');
  AddCard (h, b.len);
  AddCh (h, 15C); AddCh (h, 12C); AddCh (h, 15C); AddCh (h, 12C);
  WriteAll (h.data, h.len);
  WriteAll (b.data, b.len);
  Release (h)
END Send;

(* ---- documents ---- *)

PROCEDURE SameBuf (VAR a, b: Buf): BOOLEAN;
VAR i: CARDINAL;
BEGIN
  IF a.len # b.len THEN RETURN FALSE END;
  FOR i := 1 TO a.len DO
    IF a.data^[i - 1] # b.data^[i - 1] THEN RETURN FALSE END
  END;
  RETURN TRUE
END SameBuf;

PROCEDURE FindSlot (VAR uri: Buf): INTEGER;
VAR i: CARDINAL;
BEGIN
  FOR i := 1 TO MaxDocs DO
    IF slots[i - 1].used AND SameBuf (slots[i - 1].uri, uri) THEN RETURN VAL (INTEGER, i - 1) END
  END;
  RETURN -1
END FindSlot;

(* read params.textDocument.uri into uri *)
PROCEDURE ReadUri (VAR uri: Buf): BOOLEAN;
VAR pos: CARDINAL;
BEGIN
  Clear (uri);
  RETURN Find (msg.data, msg.len, 'params.textDocument.uri', pos)
         AND GetString (msg.data, msg.len, pos, uri)
END ReadUri;

PROCEDURE OpenSlot (VAR uri: Buf): INTEGER;
VAR
  i: CARDINAL;
  path: ARRAY [0..PathLen - 1] OF CHAR;
BEGIN
  FOR i := 1 TO MaxDocs DO
    IF NOT slots[i - 1].used THEN
      slots[i - 1].used := TRUE;
      Init (slots[i - 1].uri);
      AddBuf (slots[i - 1].uri, uri);
      UriToPath (uri, path);
      slots[i - 1].doc := NewDoc (path);
      RETURN VAL (INTEGER, i - 1)
    END
  END;
  RETURN -1
END OpenSlot;

PROCEDURE CloseSlot (i: INTEGER);
BEGIN
  slots[i].used := FALSE;
  Release (slots[i].uri);
  FreeDoc (slots[i].doc)
END CloseSlot;

(* ---- replies ---- *)

PROCEDURE BeginReply;
VAR pos, e: CARDINAL;
BEGIN
  Clear (reply);
  Add (reply, '{"jsonrpc":"2.0","id":');
  IF Find (msg.data, msg.len, 'id', pos) THEN
    e := SkipValue (msg.data, msg.len, pos);
    AddRange (reply, msg.data, pos, e)
  ELSE
    Add (reply, 'null')
  END
END BeginReply;

PROCEDURE SendResult;
BEGIN
  BeginReply;
  Add (reply, ',"result":');
  AddBuf (reply, result);
  AddCh (reply, '}');
  Send (reply)
END SendResult;

PROCEDURE SendNullResult;
BEGIN
  Clear (result);
  Add (result, 'null');
  SendResult
END SendNullResult;

PROCEDURE SendError (code: CARDINAL; text: ARRAY OF CHAR);
BEGIN
  BeginReply;
  Add (reply, ',"error":{"code":-');
  AddCard (reply, code);
  Add (reply, ',"message":"');
  Add (reply, text);
  Add (reply, '"}}');
  Send (reply)
END SendError;

PROCEDURE PublishDiagnostics (s: INTEGER);
VAR
  n: Buf;
  first: BOOLEAN;
BEGIN
  first := TRUE;
  Init (n);
  Add (n, '{"jsonrpc":"2.0","method":"textDocument/publishDiagnostics","params":{"uri":');
  AddJsonRange (n, slots[s].uri.data, 0, slots[s].uri.len);
  Add (n, ',"diagnostics":');
  AddCh (n, '[');
  Gm2.Check (slots[s].doc, n, first);
  Lint.Check (slots[s].doc, n, first);
  AddCh (n, ']');
  Add (n, '}}');
  Send (n);
  Release (n)
END PublishDiagnostics;

(* ---- handlers ---- *)

(* LSP positions count UTF-16 units by default; we count bytes, so ask for utf-8 when the
   client offers it. *)
PROCEDURE ClientOffersUtf8 (): BOOLEAN;
VAR
  pos, e, i, k: CARDINAL;
  want: ARRAY [0..7] OF CHAR;
  ok: BOOLEAN;
BEGIN
  IF NOT Find (msg.data, msg.len, 'params.capabilities.general.positionEncodings', pos) THEN
    RETURN FALSE
  END;
  e := SkipValue (msg.data, msg.len, pos);
  want := '"utf-8"';
  i := pos;
  WHILE i + 7 <= e DO
    ok := TRUE; k := 0;
    WHILE ok AND (k < 7) DO
      IF msg.data^[i + k] # want[k] THEN ok := FALSE END;
      INC (k)
    END;
    IF ok THEN RETURN TRUE END;
    INC (i)
  END;
  RETURN FALSE
END ClientOffersUtf8;

PROCEDURE Initialize;
BEGIN
  Clear (result);
  Add (result, '{"capabilities":{');
  IF ClientOffersUtf8 () THEN Add (result, '"positionEncoding":"utf-8",') END;
  Add (result, '"textDocumentSync":{"openClose":true,"change":1,"save":{"includeText":false}},');
  Add (result, '"completionProvider":{"triggerCharacters":["."]},');
  Add (result, '"hoverProvider":true,"definitionProvider":true,"documentSymbolProvider":true},');
  Add (result, '"serverInfo":{"name":"m2lsp","version":"0.1.0"}}');
  SendResult
END Initialize;

PROCEDURE UpdateText (s: INTEGER; path: ARRAY OF CHAR): BOOLEAN;
VAR
  pos: CARDINAL;
  txt: Buf;
  ok: BOOLEAN;
BEGIN
  Init (txt);
  ok := Find (msg.data, msg.len, path, pos) AND GetString (msg.data, msg.len, pos, txt);
  IF ok THEN SetText (slots[s].doc, txt.data, txt.len) END;
  Release (txt);
  RETURN ok
END UpdateText;

PROCEDURE DidOpen;
VAR
  uri: Buf;
  s: INTEGER;
BEGIN
  Init (uri);
  IF ReadUri (uri) THEN
    s := FindSlot (uri);
    IF s < 0 THEN s := OpenSlot (uri) END;
    IF (s >= 0) AND UpdateText (s, 'params.textDocument.text') THEN
      PublishDiagnostics (s)
    END
  END;
  Release (uri)
END DidOpen;

PROCEDURE DidChange;
VAR
  uri: Buf;
  s: INTEGER;
  ok: BOOLEAN;
BEGIN
  Init (uri);
  IF ReadUri (uri) THEN
    s := FindSlot (uri);
    IF s >= 0 THEN ok := UpdateText (s, 'params.contentChanges.0.text') END
  END;
  Release (uri)
END DidChange;

PROCEDURE DidSave;
VAR
  uri: Buf;
  s: INTEGER;
BEGIN
  Init (uri);
  IF ReadUri (uri) THEN
    s := FindSlot (uri);
    IF s >= 0 THEN
      Units.Invalidate (slots[s].doc^.path);
      PublishDiagnostics (s)
    END
  END;
  Release (uri)
END DidSave;

PROCEDURE DidClose;
VAR
  uri: Buf;
  s: INTEGER;
  n: Buf;
BEGIN
  Init (uri);
  IF ReadUri (uri) THEN
    s := FindSlot (uri);
    IF s >= 0 THEN
      Init (n);
      Add (n, '{"jsonrpc":"2.0","method":"textDocument/publishDiagnostics","params":{"uri":');
      AddJsonRange (n, uri.data, 0, uri.len);
      Add (n, ',"diagnostics":[]}}');
      Send (n);
      Release (n);
      CloseSlot (s)
    END
  END;
  Release (uri)
END DidClose;

(* Locate the document and the cursor offset for position based requests. *)
PROCEDURE CursorRequest (VAR s: INTEGER; VAR offset: CARDINAL): BOOLEAN;
VAR
  uri: Buf;
  pos, line, col: CARDINAL;
  ok: BOOLEAN;
BEGIN
  Init (uri);
  ok := FALSE;
  IF ReadUri (uri) THEN
    s := FindSlot (uri);
    IF (s >= 0) AND Find (msg.data, msg.len, 'params.position.line', pos)
       AND GetCard (msg.data, msg.len, pos, line)
       AND Find (msg.data, msg.len, 'params.position.character', pos)
       AND GetCard (msg.data, msg.len, pos, col) THEN
      offset := OffsetOf (slots[s].doc^.text.data, slots[s].doc^.text.len, line, col);
      ok := TRUE
    END
  END;
  Release (uri);
  RETURN ok
END CursorRequest;

PROCEDURE Completion;
VAR
  s: INTEGER;
  offset: CARDINAL;
BEGIN
  Clear (result);
  IF CursorRequest (s, offset) THEN
    Nav.Complete (slots[s].doc, offset, result);
    SendResult
  ELSE
    SendNullResult
  END
END Completion;

PROCEDURE HoverReq;
VAR
  s: INTEGER;
  offset: CARDINAL;
BEGIN
  Clear (result);
  IF CursorRequest (s, offset) AND Nav.Hover (slots[s].doc, offset, result) THEN
    SendResult
  ELSE
    SendNullResult
  END
END HoverReq;

PROCEDURE DefinitionReq;
VAR
  s: INTEGER;
  offset: CARDINAL;
BEGIN
  Clear (result);
  IF CursorRequest (s, offset) AND Nav.Definition (slots[s].doc, slots[s].uri, offset, result) THEN
    SendResult
  ELSE
    SendNullResult
  END
END DefinitionReq;

PROCEDURE SymbolsReq;
VAR
  uri: Buf;
  s: INTEGER;
BEGIN
  Clear (result);
  Init (uri);
  IF ReadUri (uri) THEN
    s := FindSlot (uri);
    IF s >= 0 THEN
      Nav.DocumentSymbols (slots[s].doc, slots[s].uri, result);
      Release (uri);
      SendResult;
      RETURN
    END
  END;
  Release (uri);
  SendNullResult
END SymbolsReq;

PROCEDURE Dispatch;
VAR
  pos: CARDINAL;
  method: Buf;
  hasId: BOOLEAN;
BEGIN
  Init (method);
  IF Find (msg.data, msg.len, 'method', pos) AND GetString (msg.data, msg.len, pos, method) THEN
    hasId := Find (msg.data, msg.len, 'id', pos);
    IF BufEqStr (method, 'initialize') THEN Initialize
    ELSIF BufEqStr (method, 'shutdown') THEN shutdownSeen := TRUE; SendNullResult
    ELSIF BufEqStr (method, 'exit') THEN
      IF shutdownSeen THEN exit (0) ELSE exit (1) END
    ELSIF BufEqStr (method, 'textDocument/didOpen') THEN DidOpen
    ELSIF BufEqStr (method, 'textDocument/didChange') THEN DidChange
    ELSIF BufEqStr (method, 'textDocument/didSave') THEN DidSave
    ELSIF BufEqStr (method, 'textDocument/didClose') THEN DidClose
    ELSIF BufEqStr (method, 'textDocument/completion') THEN Completion
    ELSIF BufEqStr (method, 'textDocument/hover') THEN HoverReq
    ELSIF BufEqStr (method, 'textDocument/definition') THEN DefinitionReq
    ELSIF BufEqStr (method, 'textDocument/documentSymbol') THEN SymbolsReq
    ELSIF hasId THEN
      SendError (32601, 'method not found')
    END
  END;
  Release (method)
END Dispatch;

VAR
  i: CARDINAL;
BEGIN
  ipos := 0; ilen := 0;
  shutdownSeen := FALSE;
  FOR i := 1 TO MaxDocs DO slots[i - 1].used := FALSE END;
  Init (msg); Init (reply); Init (result);
  Gm2.Setup;
  WHILE ReadMessage (msg) DO
    Dispatch
  END;
  exit (0)
END m2lsp.
