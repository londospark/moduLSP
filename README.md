# moduLSP (`m2lsp`)

A small Language Server for **GNU Modula-2**, written in GNU Modula-2.

| Feature | How |
|---|---|
| Diagnostics | runs `gm2 -fsyntax-only` on a scratch copy of the buffer when a file is opened or saved |
| Completion | keywords, builtins (with docs), symbols visible at the cursor, imported names, `Module.` members from `.def` files, `record.` / `ptr^.` fields |
| Hover | declaration text of the identifier under the cursor |
| Go to definition | local declarations, and into `.def` files (next to the file, `M2LSP_INCLUDE`, or gm2's library dirs) |
| Document symbols | procedures, module-level consts/types/vars |

## Build and install

    make            # needs gm2 (GCC's Modula-2 front end)
    make install    # copies m2lsp to ~/.local/bin

## Configuration (environment variables)

* `M2LSP_FLAGS`   extra gm2 flags for diagnostics, e.g. `-fiso`, `-fpim4`, `-fextended-opaque`
* `M2LSP_INCLUDE` colon-separated extra directories, used for `-I` and for finding `.def` files

## Sublime Text (LSP package)

Install the [LSP](https://packagecontrol.io/packages/LSP) package, make sure `m2lsp` is on your `PATH`, and add:

In `Packages/User/LSP.sublime-settings`:

    {
      "clients": {
        "m2lsp": {
          "enabled": true,
          "command": ["m2lsp"],
          "selector": "source.modula2",
          "env": { "M2LSP_FLAGS": "" }
        }
      }
    }

## Limits

* Diagnostics come from gm2, which usually stops at the first few errors. They refresh on save, not per keystroke.
* The scanner is a declaration scanner, not a full parser. It resolves named and anonymous records (including variant parts), pointers to them, procedure-local types, `WITH` statements and call results (`f(x).field`). Types that need real expression typing (for example a field whose type is an anonymous record inside a `POINTER TO RECORD ... END`) are not followed.
* Positions are byte columns. Clients that support the `utf-8` position encoding (LSP 3.17) get exact columns; others are off only on lines with non-ASCII characters before the cursor.
* Only `.def` files are indexed for other modules, not the `.mod` files.

## Tests

    python3 tests/smoke.py ./m2lsp
    python3 tests/robust.py ./m2lsp
    python3 tests/limits.py ./m2lsp   # anonymous records, WITH, call results
    python3 tests/more.py ./m2lsp     # variants, local types, hover text

## Credits

The pervasive-identifier table (`Pervasive.mod`) adapts signatures and descriptions from
[catink123/adw-modula2-lsp](https://github.com/catink123/adw-modula2-lsp) (MIT, Copyright (c) 2026 Matsvei Radzevich),
and the overall shape (lexer, declaration scan, `.def` resolution) follows the same design.
