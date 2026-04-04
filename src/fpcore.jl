#=
Bidirectional conversion between Julia expressions and FPCore format.

Julia Expr → FPCore string  (used at macro expansion time)
FPCore string → Julia string (used at runtime to display Herbie's output)
=#

# --- Operator and constant mappings ---

const JULIA_TO_FPCORE = Dict{Symbol,String}(
    :+ => "+", :- => "-", :* => "*", :/ => "/",
    :^ => "pow",
    :sqrt => "sqrt", :cbrt => "cbrt",
    :abs => "fabs",
    :sin => "sin", :cos => "cos", :tan => "tan",
    :asin => "asin", :acos => "acos", :atan => "atan",
    :sinh => "sinh", :cosh => "cosh", :tanh => "tanh",
    :asinh => "asinh", :acosh => "acosh", :atanh => "atanh",
    :exp => "exp", :exp2 => "exp2",
    :log => "log", :log2 => "log2", :log10 => "log10",
    :log1p => "log1p", :expm1 => "expm1",
    :hypot => "hypot",
    :fma => "fma",
    :min => "fmin", :max => "fmax",
    :floor => "floor", :ceil => "ceil",
    :round => "nearbyint",
    :rem => "remainder", :mod => "fmod",
    :copysign => "copysign",
)

# Reverse mapping (FPCore name → Julia name)
const FPCORE_TO_JULIA = Dict{String,Symbol}(v => k for (k, v) in JULIA_TO_FPCORE)

const JULIA_CONST_TO_FPCORE = Dict{Symbol,String}(
    :π => "PI", :pi => "PI", :ℯ => "E",
)

const FPCORE_CONST_TO_JULIA = Dict{String,String}(
    "PI" => "π", "E" => "ℯ", "INFINITY" => "Inf", "NAN" => "NaN",
    "TRUE" => "true", "FALSE" => "false",
)

const KNOWN_FUNCTIONS = Set(keys(JULIA_TO_FPCORE))

# =====================================================================
# Julia Expr → FPCore
# =====================================================================

"""
    expr_to_fpcore(expr) -> String

Convert a Julia expression to an FPCore string.
"""
function expr_to_fpcore(expr)
    vars = sort!(collect(free_variables(expr)))
    body = to_fpcore_body(expr)
    "(FPCore ($(join(vars, " "))) $body)"
end

"""
    free_variables(expr) -> Set{Symbol}

Collect all free variable names in a Julia expression.
"""
function free_variables(expr)
    vars = Set{Symbol}()
    _collect_vars!(vars, expr)
    return vars
end

function _collect_vars!(vars::Set{Symbol}, expr::Expr)
    if expr.head === :call
        # args[1] is the function name — skip it
        for i in 2:length(expr.args)
            _collect_vars!(vars, expr.args[i])
        end
    else
        for arg in expr.args
            _collect_vars!(vars, arg)
        end
    end
end

function _collect_vars!(vars::Set{Symbol}, s::Symbol)
    if s ∉ KNOWN_FUNCTIONS && !haskey(JULIA_CONST_TO_FPCORE, s)
        push!(vars, s)
    end
end

_collect_vars!(::Set{Symbol}, ::Any) = nothing

"""
    to_fpcore_body(expr) -> String

Recursively convert a Julia expression to an FPCore body string.
"""
function to_fpcore_body(expr::Expr)
    if expr.head === :call
        fname = expr.args[1]::Symbol
        fpname = get(JULIA_TO_FPCORE, fname, nothing)
        fpname === nothing && error("Unsupported function in FPCore conversion: $fname")
        args = join((to_fpcore_body(a) for a in expr.args[2:end]), " ")
        return "($fpname $args)"
    end
    error("Unsupported expression head: $(expr.head) in $(expr)")
end

function to_fpcore_body(s::Symbol)
    return get(JULIA_CONST_TO_FPCORE, s, string(s))
end

function to_fpcore_body(n::Number)
    return string(n)
end

# =====================================================================
# S-expression tokenizer and parser
# =====================================================================

"""
    tokenize_sexp(s) -> Vector{String}

Tokenize an S-expression string into a flat list of tokens.
"""
function tokenize_sexp(s::AbstractString)
    tokens = String[]
    i = 1
    n = ncodeunits(s)
    while i <= n
        c = s[i]
        if c == '('
            push!(tokens, "(")
            i += 1
        elseif c == ')'
            push!(tokens, ")")
            i += 1
        elseif c in (' ', '\t', '\n', '\r')
            i += 1
        elseif c == ';'
            # Line comment — skip to end of line
            while i <= n && s[i] != '\n'
                i += 1
            end
        elseif c == '"'
            # String literal
            j = i + 1
            while j <= n
                if s[j] == '\\' && j < n
                    j += 2
                elseif s[j] == '"'
                    break
                else
                    j += 1
                end
            end
            push!(tokens, s[i:j])
            i = j + 1
        else
            # Atom (symbol, number, keyword)
            j = i
            while j <= n && s[j] ∉ (' ', '\t', '\n', '\r', '(', ')', '"')
                j += 1
            end
            push!(tokens, s[i:j-1])
            i = j
        end
    end
    return tokens
end

"""
    parse_sexp(s) -> Any

Parse the first S-expression from string `s`.
Returns nested `Vector{Any}` for lists, `String` for atoms.
"""
function parse_sexp(s::AbstractString)
    tokens = tokenize_sexp(s)
    isempty(tokens) && error("Empty S-expression")
    result, _ = _parse_sexp_tokens(tokens, 1)
    return result
end

function _parse_sexp_tokens(tokens::Vector{String}, i::Int)
    if tokens[i] == "("
        list = Any[]
        i += 1
        while i <= length(tokens) && tokens[i] != ")"
            elem, i = _parse_sexp_tokens(tokens, i)
            push!(list, elem)
        end
        i <= length(tokens) || error("Unmatched '(' in S-expression")
        return list, i + 1  # skip ")"
    elseif tokens[i] == ")"
        error("Unexpected ')' in S-expression")
    else
        return tokens[i], i + 1
    end
end

# =====================================================================
# FPCore → Julia string
# =====================================================================

"""
    extract_fpcore(sexp) -> NamedTuple

Extract variables, properties, and body from a parsed FPCore expression.
"""
function extract_fpcore(sexp::Vector)
    length(sexp) >= 3 || error("FPCore expression too short")
    sexp[1] == "FPCore" || error("Expected FPCore, got: $(sexp[1])")

    vars = sexp[2]
    props = Dict{String,Any}()
    i = 3
    while i < length(sexp) && sexp[i] isa String && startswith(sexp[i], ":")
        props[sexp[i]] = sexp[i + 1]
        i += 2
    end
    body = sexp[end]
    return (; vars, props, body)
end

"""
    fpcore_to_julia(s) -> String

Parse an FPCore string and return the equivalent Julia expression as a string.
"""
function fpcore_to_julia(s::AbstractString)
    sexp = parse_sexp(s)
    info = extract_fpcore(sexp)
    return sexp_to_julia_str(info.body)
end

"""
    sexp_to_julia_str(sexp) -> String

Convert a parsed FPCore body to a Julia expression string.
"""
function sexp_to_julia_str(sexp)
    sexp isa String && return _atom_to_julia(sexp)

    sexp isa Vector || error("Unexpected S-expression type: $(typeof(sexp))")
    isempty(sexp) && error("Empty S-expression list")

    head = sexp[1]::String
    nargs = length(sexp) - 1

    # Infix binary/n-ary arithmetic
    if head in ("+", "*") && nargs >= 2
        args = [sexp_to_julia_str(a) for a in sexp[2:end]]
        return "(" * join(args, " $head ") * ")"
    end
    if head == "-"
        if nargs == 1
            return "(-$(sexp_to_julia_str(sexp[2])))"
        else
            args = [sexp_to_julia_str(a) for a in sexp[2:end]]
            return "(" * join(args, " - ") * ")"
        end
    end
    if head == "/" && nargs == 2
        return "($(sexp_to_julia_str(sexp[2])) / $(sexp_to_julia_str(sexp[3])))"
    end

    # Negation
    if head == "neg"
        return "(-$(sexp_to_julia_str(sexp[2])))"
    end

    # Power → infix ^
    if head == "pow" && nargs == 2
        return "($(sexp_to_julia_str(sexp[2])) ^ $(sexp_to_julia_str(sexp[3])))"
    end

    # Conditional → ternary
    if head == "if" && nargs == 3
        c = sexp_to_julia_str(sexp[2])
        t = sexp_to_julia_str(sexp[3])
        f = sexp_to_julia_str(sexp[4])
        return "($c ? $t : $f)"
    end

    # Let bindings
    if head in ("let", "let*") && nargs == 2
        bindings = sexp[2]::Vector
        body = sexp_to_julia_str(sexp[3])
        binds = join(("$(b[1]) = $(sexp_to_julia_str(b[2]))" for b in bindings), ", ")
        return "(let $binds; $body end)"
    end

    # Boolean operators
    if head == "and"
        args = [sexp_to_julia_str(a) for a in sexp[2:end]]
        return "(" * join(args, " && ") * ")"
    end
    if head == "or"
        args = [sexp_to_julia_str(a) for a in sexp[2:end]]
        return "(" * join(args, " || ") * ")"
    end
    if head == "not" && nargs == 1
        return "(!$(sexp_to_julia_str(sexp[2])))"
    end

    # Comparison operators
    if head in ("<", ">", "<=", ">=", "==", "!=")
        args = [sexp_to_julia_str(a) for a in sexp[2:end]]
        return "(" * join(args, " $head ") * ")"
    end

    # Named functions
    julia_name = get(FPCORE_TO_JULIA, head, nothing)
    fname = julia_name !== nothing ? string(julia_name) : head
    args = [sexp_to_julia_str(a) for a in sexp[2:end]]
    return "$fname($(join(args, ", ")))"
end

function _atom_to_julia(s::String)
    haskey(FPCORE_CONST_TO_JULIA, s) && return FPCORE_CONST_TO_JULIA[s]
    return s  # variable name or numeric literal
end
