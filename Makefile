# m2lsp - Language Server for GNU Modula-2, written in GNU Modula-2
MODS   = Text Json Lexer Files Symbols Pervasive Units Nav Gm2
OBJS   = $(addsuffix .o,$(MODS))
GM2    = gm2 -O2 -fpim4 -I.
PREFIX ?= $(HOME)/.local

m2lsp: m2lsp.mod $(OBJS)
	$(GM2) -o $@ m2lsp.mod $(OBJS)

%.o: %.mod %.def
	$(GM2) -fno-scaffold-main -c -o $@ $<

Symbols.o: Text.def Lexer.def Files.def
Nav.o: Symbols.def Units.def Pervasive.def Lexer.def Files.def
Units.o: Symbols.def Files.def
Gm2.o: Symbols.def Units.def Files.def Lexer.def

install: m2lsp
	install -Dm755 m2lsp $(PREFIX)/bin/m2lsp

clean:
	rm -f m2lsp *.o

.PHONY: install clean
