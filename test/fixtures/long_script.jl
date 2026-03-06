# A longer Julia script to test scrolling and navigation
# 100+ lines to exercise file editor scrolling

module LongScript

using LinearAlgebra

# ── Type hierarchy ──────────────────────────────────────────────────

abstract type Shape end

struct Circle <: Shape
    radius::Float64
end

struct Rectangle <: Shape
    width::Float64
    height::Float64
end

struct Triangle <: Shape
    a::Float64
    b::Float64
    c::Float64
end

# ── Area calculations ───────────────────────────────────────────────

area(c::Circle) = π * c.radius^2
area(r::Rectangle) = r.width * r.height

function area(t::Triangle)
    s = (t.a + t.b + t.c) / 2
    return sqrt(s * (s - t.a) * (s - t.b) * (s - t.c))
end

# ── Perimeter calculations ──────────────────────────────────────────

perimeter(c::Circle) = 2π * c.radius
perimeter(r::Rectangle) = 2 * (r.width + r.height)
perimeter(t::Triangle) = t.a + t.b + t.c

# ── Sorting algorithms ──────────────────────────────────────────────

function bubble_sort!(arr::Vector{T}) where T
    n = length(arr)
    for i in 1:n-1
        swapped = false
        for j in 1:n-i
            if arr[j] > arr[j+1]
                arr[j], arr[j+1] = arr[j+1], arr[j]
                swapped = true
            end
        end
        !swapped && break
    end
    return arr
end

function merge_sort(arr::Vector{T}) where T
    length(arr) <= 1 && return arr
    mid = div(length(arr), 2)
    left = merge_sort(arr[1:mid])
    right = merge_sort(arr[mid+1:end])
    return _merge(left, right)
end

function _merge(left::Vector{T}, right::Vector{T}) where T
    result = T[]
    i, j = 1, 1
    while i <= length(left) && j <= length(right)
        if left[i] <= right[j]
            push!(result, left[i])
            i += 1
        else
            push!(result, right[j])
            j += 1
        end
    end
    append!(result, left[i:end])
    append!(result, right[j:end])
    return result
end

# ── Matrix utilities ────────────────────────────────────────────────

function create_rotation_matrix(θ::Float64)
    return [cos(θ) -sin(θ);
            sin(θ)  cos(θ)]
end

function matrix_power(A::Matrix, n::Int)
    n == 0 && return I(size(A, 1))
    n == 1 && return A
    if iseven(n)
        half = matrix_power(A, div(n, 2))
        return half * half
    else
        return A * matrix_power(A, n - 1)
    end
end

# ── String utilities ────────────────────────────────────────────────

function caesar_cipher(text::String, shift::Int)
    chars = Char[]
    for c in text
        if 'a' <= c <= 'z'
            push!(chars, 'a' + mod(c - 'a' + shift, 26))
        elseif 'A' <= c <= 'Z'
            push!(chars, 'A' + mod(c - 'A' + shift, 26))
        else
            push!(chars, c)
        end
    end
    return String(chars)
end

function is_palindrome(s::String)
    cleaned = filter(isalpha, lowercase(s))
    return cleaned == reverse(cleaned)
end

function levenshtein(s1::String, s2::String)
    m, n = length(s1), length(s2)
    d = zeros(Int, m + 1, n + 1)
    for i in 0:m; d[i+1, 1] = i; end
    for j in 0:n; d[1, j+1] = j; end
    for j in 1:n, i in 1:m
        cost = s1[i] == s2[j] ? 0 : 1
        d[i+1, j+1] = min(
            d[i, j+1] + 1,      # deletion
            d[i+1, j] + 1,      # insertion
            d[i, j] + cost       # substitution
        )
    end
    return d[m+1, n+1]
end

# ── Number theory ───────────────────────────────────────────────────

function is_prime(n::Int)
    n < 2 && return false
    n < 4 && return true
    (n % 2 == 0 || n % 3 == 0) && return false
    i = 5
    while i * i <= n
        (n % i == 0 || n % (i + 2) == 0) && return false
        i += 6
    end
    return true
end

function prime_factors(n::Int)
    factors = Int[]
    d = 2
    while d * d <= n
        while n % d == 0
            push!(factors, d)
            n = div(n, d)
        end
        d += 1
    end
    n > 1 && push!(factors, n)
    return factors
end

function gcd_extended(a::Int, b::Int)
    if a == 0
        return b, 0, 1
    end
    g, x, y = gcd_extended(b % a, a)
    return g, y - div(b, a) * x, x
end

end # module LongScript
