# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

HerbieMacros.jl provides a Julia `@herbie` macro that sends floating-point expressions to [Herbie](https://herbie.uwplse.org/) for numerical improvement. It auto-downloads Racket and installs Herbie on first use.

## Commands

```bash
# Run tests (no Herbie/Racket needed — tests only exercise conversion logic)
julia --project=test -e 'using Pkg; Pkg.instantiate(); Pkg.test()'

# Quick test run (after first instantiate)
julia --project=test test/runtests.jl

# Resolve after changing Project.toml deps
julia --project=test -e 'using Pkg; Pkg.resolve(); Pkg.instantiate()'
```

## Architecture

The macro works in two phases:

1. **Compile time** (`fpcore.jl`): `@herbie expr` converts the Julia `Expr` AST to an [FPCore](https://fpbench.org/) string via `expr_to_fpcore`. This walks the expression tree, collects free variables, and maps Julia operators/functions to FPCore equivalents (e.g. `^` → `pow`, `abs` → `fabs`).

2. **Runtime** (`herbie.jl`): `herbie_query(fpcore_string)` writes the FPCore to a temp file, runs `racket -l herbie improve input output`, then parses the improved FPCore output back to a Julia expression string via `sexp_to_julia_str`.

The auto-install system (`install.jl`) is triggered by `ensure_herbie()` on first runtime call. It stores Racket and Herbie in `~/.julia/herbie_macros/` and uses a `.herbie_ready_v1` flag file to skip reinstallation. Platform handling: `.sh` installer on Linux, `.dmg` + `hdiutil` on macOS. `PLTUSERHOME` is set to scope Herbie's Racket packages to the depot directory.

## Key design details

- `JULIA_TO_FPCORE` / `FPCORE_TO_JULIA` dicts in `fpcore.jl` define the operator mappings. The reverse dict is auto-generated. To add a new function, add one entry to `JULIA_TO_FPCORE`.
- FPCore variables are sorted alphabetically for deterministic output.
- The S-expression parser (`tokenize_sexp` + `_parse_sexp_tokens`) handles comments (`;`), string literals, and nested lists. `extract_fpcore` skips `:keyword value` property pairs to find the body.
- `sexp_to_julia_str` handles special forms: infix `+−*/`, `pow` → `^`, `if` → ternary, `let`/`let*` → Julia `let`, `and`/`or`/`not` → `&&`/`||`/`!`, comparison operators, and named function calls.
- Test environment uses workspace (root `[workspace] projects = ["test"]`). The test `Project.toml` gets `HerbieMacros` via `Pkg.develop(path=".")`, not manual `[sources]`.
- Tests are pure unit tests of the conversion pipeline — they never call Herbie, so CI needs no Racket/Rust.
