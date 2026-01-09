# %%
# Sessions.jl Demo Notebook
# This is an example notebook showing basic Julia features

# %%
# Simple arithmetic
x = 1 + 1

# %%
# Define a function
function greet(name)
    "Hello, $name!"
end

# %%
# Call the function
greet("Sessions.jl")

# %%
# Arrays and comprehensions
squares = [i^2 for i in 1:10]

# %%
# Sum the squares
sum(squares)

# %%
# Define a struct
struct Point
    x::Float64
    y::Float64
end

# %%
# Create some points
p1 = Point(0.0, 0.0)
p2 = Point(3.0, 4.0)

# %%
# Calculate distance
function distance(a::Point, b::Point)
    sqrt((b.x - a.x)^2 + (b.y - a.y)^2)
end

distance(p1, p2)

# %%
# Fibonacci sequence
function fib(n)
    n <= 1 && return n
    fib(n-1) + fib(n-2)
end

[fib(i) for i in 0:10]

# %%
# That's it! This notebook demonstrates basic Julia features.
# In the full Sessions.jl IDE, you would see:
# - Syntax highlighting
# - Reactive updates
# - Rich output rendering
println("Demo complete!")
