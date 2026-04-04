using Test
using HerbieMacros: @herbie, expr_to_fpcore, free_variables, to_fpcore_body,
    parse_sexp, extract_fpcore, sexp_to_julia_str, fpcore_to_julia,
    herbie_query

@testset "HerbieMacros" begin

    @testset "free_variables" begin
        @test free_variables(:(x + y)) == Set([:x, :y])
        @test free_variables(:(sqrt(x))) == Set([:x])
        @test free_variables(:(sin(x) + cos(y))) == Set([:x, :y])
        @test free_variables(:(x^2 + y^2)) == Set([:x, :y])
        @test free_variables(:(π * r^2)) == Set([:r])
        @test free_variables(:(1 + 2)) == Set{Symbol}()
    end

    @testset "to_fpcore_body" begin
        @test to_fpcore_body(:(x + y)) == "(+ x y)"
        @test to_fpcore_body(:(x * y)) == "(* x y)"
        @test to_fpcore_body(:(x^2)) == "(pow x 2)"
        @test to_fpcore_body(:(sqrt(x))) == "(sqrt x)"
        @test to_fpcore_body(:(sin(x) + cos(y))) == "(+ (sin x) (cos y))"
        @test to_fpcore_body(:(π)) == "PI"
        @test to_fpcore_body(3) == "3"
        @test to_fpcore_body(1.5) == "1.5"
    end

    @testset "expr_to_fpcore" begin
        @test expr_to_fpcore(:(sqrt(x^2 + y^2))) ==
            "(FPCore (x y) (sqrt (+ (pow x 2) (pow y 2))))"
        @test expr_to_fpcore(:(exp(x) - 1)) ==
            "(FPCore (x) (- (exp x) 1))"
        @test expr_to_fpcore(:(log(1 + x))) ==
            "(FPCore (x) (log (+ 1 x)))"
        @test expr_to_fpcore(:(π * r^2)) ==
            "(FPCore (r) (* PI (pow r 2)))"
    end

    @testset "parse_sexp" begin
        @test parse_sexp("x") == "x"
        @test parse_sexp("(+ x y)") == ["+", "x", "y"]
        @test parse_sexp("(sqrt (+ x y))") == ["sqrt", ["+", "x", "y"]]
        @test parse_sexp("(FPCore (x y) (hypot x y))") ==
            ["FPCore", ["x", "y"], ["hypot", "x", "y"]]
        # With properties
        @test parse_sexp("(FPCore (x) :name \"test\" (sqrt x))") ==
            ["FPCore", ["x"], ":name", "\"test\"", ["sqrt", "x"]]
        # With comments
        @test parse_sexp("; comment\n(+ 1 2)") == ["+", "1", "2"]
    end

    @testset "extract_fpcore" begin
        sexp = parse_sexp("(FPCore (x y) (hypot x y))")
        info = extract_fpcore(sexp)
        @test info.vars == ["x", "y"]
        @test isempty(info.props)
        @test info.body == ["hypot", "x", "y"]

        sexp2 = parse_sexp("(FPCore (x) :name \"test\" :pre (> x 0) (sqrt x))")
        info2 = extract_fpcore(sexp2)
        @test info2.vars == ["x"]
        @test info2.props[":name"] == "\"test\""
        @test info2.body == ["sqrt", "x"]
    end

    @testset "sexp_to_julia_str" begin
        # Simple atoms
        @test sexp_to_julia_str("x") == "x"
        @test sexp_to_julia_str("42") == "42"
        @test sexp_to_julia_str("PI") == "π"
        @test sexp_to_julia_str("E") == "ℯ"

        # Arithmetic
        @test sexp_to_julia_str(["+", "x", "y"]) == "(x + y)"
        @test sexp_to_julia_str(["*", "a", "b", "c"]) == "(a * b * c)"
        @test sexp_to_julia_str(["-", "x", "y"]) == "(x - y)"
        @test sexp_to_julia_str(["-", "x"]) == "(-x)"
        @test sexp_to_julia_str(["neg", "x"]) == "(-x)"
        @test sexp_to_julia_str(["/", "x", "y"]) == "(x / y)"

        # Power
        @test sexp_to_julia_str(["pow", "x", "2"]) == "(x ^ 2)"

        # Functions
        @test sexp_to_julia_str(["sqrt", "x"]) == "sqrt(x)"
        @test sexp_to_julia_str(["hypot", "x", "y"]) == "hypot(x, y)"
        @test sexp_to_julia_str(["fabs", "x"]) == "abs(x)"
        @test sexp_to_julia_str(["log1p", "x"]) == "log1p(x)"
        @test sexp_to_julia_str(["expm1", "x"]) == "expm1(x)"
        @test sexp_to_julia_str(["fma", "a", "b", "c"]) == "fma(a, b, c)"

        # Conditional
        @test sexp_to_julia_str(["if", ["<", "x", "0"], ["-", "x"], "x"]) ==
            "((x < 0) ? (-x) : x)"

        # Let
        @test sexp_to_julia_str(["let", [["t", ["+", "a", "b"]]], ["*", "t", "t"]]) ==
            "(let t = (a + b); (t * t) end)"

        # Boolean
        @test sexp_to_julia_str(["and", ["<", "x", "1"], [">", "x", "0"]]) ==
            "((x < 1) && (x > 0))"
    end

    @testset "fpcore_to_julia roundtrip" begin
        @test fpcore_to_julia("(FPCore (x y) (hypot x y))") == "hypot(x, y)"
        @test fpcore_to_julia("(FPCore (x) (log1p x))") == "log1p(x)"
        @test fpcore_to_julia("(FPCore (x) :name \"test\" (expm1 x))") == "expm1(x)"
    end

    @testset "@herbie macro expansion" begin
        # Macro should expand to a herbie_query call with the correct FPCore string
        ex = @macroexpand @herbie sqrt(x^2 + y^2)
        @test ex.head === :call
        @test ex.args[2] == "(FPCore (x y) (sqrt (+ (pow x 2) (pow y 2))))"

        ex2 = @macroexpand @herbie exp(x) - 1
        @test ex2.head === :call
        @test ex2.args[2] == "(FPCore (x) (- (exp x) 1))"

        ex3 = @macroexpand @herbie log(1 + x)
        @test ex3.head === :call
        @test ex3.args[2] == "(FPCore (x) (log (+ 1 x)))"
    end
end
