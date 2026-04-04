#=
Run the Herbie CLI (`racket -l herbie improve`) on FPCore expressions.
=#

"""
    herbie_query(fpcore::String) -> String

Send an FPCore expression to Herbie via the CLI and return the improved Julia expression.
"""
function herbie_query(fpcore::String)
    (; racket, env) = ensure_herbie()

    input_path  = tempname() * ".fpcore"
    output_path = tempname() * ".fpcore"
    stderr_path = tempname() * ".log"

    try
        Base.write(input_path, fpcore * "\n")

        cmd = setenv(`$racket -l herbie improve $input_path $output_path`, env)
        @info "Running Herbie…"
        run(pipeline(cmd; stdout = devnull, stderr = stderr_path))

        isfile(output_path) || error("Herbie did not produce an output file")
        output = strip(Base.read(output_path, String))
        isempty(output) && error("Herbie returned empty output")

        # Parse the improved FPCore and convert to Julia
        sexp = parse_sexp(output)
        info = extract_fpcore(sexp)
        julia_str = sexp_to_julia_str(info.body)

        println(julia_str)

        # Show error improvement if Herbie included it
        err_in  = get(info.props, ":herbie-error-input",  nothing)
        err_out = get(info.props, ":herbie-error-output", nothing)
        if err_in !== nothing && err_out !== nothing
            println("  (error: $err_in → $err_out bits)")
        end

        return julia_str
    catch e
        if e isa ProcessFailedException
            msg = isfile(stderr_path) ? strip(Base.read(stderr_path, String)) : ""
            error("Herbie command failed." * (isempty(msg) ? "" : "\n$msg"))
        end
        rethrow()
    finally
        rm(input_path;  force = true)
        rm(output_path; force = true)
        rm(stderr_path; force = true)
    end
end
