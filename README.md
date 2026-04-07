# HerbieMacros.jl

[![CI](https://github.com/cossio/HerbieMacros.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/cossio/HerbieMacros.jl/actions/workflows/ci.yml)

HerbieMacros.jl provides a Julia `@herbie` macro that sends floating-point expressions to [Herbie](https://herbie.uwplse.org/), prints a numerically improved Julia expression, and returns that suggestion as a `String`.

On first use, the package automatically finds or installs Racket, installs Herbie, and then runs the Herbie CLI for you.

## Installation

```julia
using Pkg
Pkg.add("HerbieMacros")
```

## Usage

```julia
using HerbieMacros

@herbie sqrt(x^2 + y^2)
# hypot(x, y)
```

The macro expands your Julia expression into [FPCore](https://fpbench.org/), asks Herbie to improve it, prints the resulting Julia expression, and returns that printed suggestion as a `String`. When Herbie reports error metrics, those are printed too.

## First-run requirements

The first runtime call may take a while because the package needs to prepare Herbie.

- Internet access is required to download Racket or install Herbie if they are not already available.
- Rust is typically required because Herbie's installation can build Rust dependencies.
- Installed tools are stored under the first Julia depot (typically `~/.julia/herbie_macros/`).
- A cached installation is reused on later runs.

If Racket is already available on your system, the package will use it instead of downloading its own copy.

## How it works

The package has two main phases:

1. **Compile time**: `@herbie expr` converts the Julia expression into an FPCore program.
2. **Runtime**: the generated FPCore is passed to `racket -l herbie improve`, then the improved result is converted back to Julia syntax.

Supported expression conversion includes common arithmetic, powers, roots, trigonometric functions, exponentials, logs, `hypot`, `fma`, `min`/`max`, rounding functions, boolean operators, comparisons, and `let` / conditional forms on the return path from Herbie.

## Development

Run the package tests with:

```bash
julia --project=test -e 'using Pkg; Pkg.instantiate(); Pkg.test("HerbieMacros")'
```

For a quick direct test run, you can also use:

```bash
julia --project=test test/runtests.jl
```

The test suite covers the Julia ↔ FPCore conversion logic and macro expansion. It does not require Herbie or Racket.
