# A simple Julia script — NOT a notebook
# This is a plain .jl file for testing the file editor

function greet(name::String)
    println("Hello, $name!")
    return "greeted $name"
end

function fibonacci(n::Int)
    n <= 0 && return 0
    n == 1 && return 1
    a, b = 0, 1
    for _ in 2:n
        a, b = b, a + b
    end
    return b
end

# Constants
const PI_APPROX = 3.14159265358979
const GOLDEN_RATIO = (1 + sqrt(5)) / 2

# Data structures
struct Point2D
    x::Float64
    y::Float64
end

distance(a::Point2D, b::Point2D) = sqrt((a.x - b.x)^2 + (a.y - b.y)^2)

# Array operations
function matrix_ops()
    A = rand(5, 5)
    B = A' * A  # symmetric positive definite
    eigenvalues = eigvals(B)
    return eigenvalues
end

# String processing
function word_count(text::String)
    words = split(text)
    counts = Dict{String, Int}()
    for w in words
        w_lower = lowercase(w)
        counts[w_lower] = get(counts, w_lower, 0) + 1
    end
    return counts
end

# Main
if abspath(PROGRAM_FILE) == @__FILE__
    greet("World")
    println("fib(10) = ", fibonacci(10))
    p1 = Point2D(0.0, 0.0)
    p2 = Point2D(3.0, 4.0)
    println("distance = ", distance(p1, p2))
end
