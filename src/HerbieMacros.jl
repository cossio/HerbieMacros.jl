module HerbieMacros

export @herbie

include("fpcore.jl")
include("install.jl")
include("herbie.jl")

"""
    @herbie expr

Query Herbie for a numerically improved version of `expr`.

On first use, Racket and Herbie are downloaded automatically
(requires an internet connection and Rust for building Herbie).

# Example

```julia
julia> @herbie sqrt(x^2 + y^2)
hypot(x, y)
```
"""
macro herbie(expr)
    fpcore = expr_to_fpcore(expr)
    return :(herbie_query($fpcore))
end

end # module HerbieMacros
