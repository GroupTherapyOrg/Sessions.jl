# A plain Julia file (no notebook markers) — opens in the file editor pane.
# Demonstrates Sessions.jl's file-explorer + file-editor flow alongside
# its notebook editor. Tiny self-contained module: Money conversion.

module Money

export Currency, USD, EUR, JPY, convert_to

"""
    Currency(code, rate_to_usd)

A minimal currency type. `rate_to_usd` is "1 unit of this currency = N USD"
on some imaginary day in 2026.
"""
struct Currency
    code::Symbol
    rate_to_usd::Float64
end

const USD = Currency(:USD, 1.000)
const EUR = Currency(:EUR, 1.087)
const JPY = Currency(:JPY, 0.0064)
const GBP = Currency(:GBP, 1.283)

"""
    convert_to(amount, from::Currency, to::Currency) -> Float64

Convert `amount` from one currency to another via the USD-relative rates.
"""
function convert_to(amount::Real, from::Currency, to::Currency)
    usd = amount * from.rate_to_usd
    return usd / to.rate_to_usd
end

# Quick smoke test
let breakfast_yen = 850
    breakfast_usd = round(convert_to(breakfast_yen, JPY, USD); digits=2)
    println("¥$breakfast_yen  ≈  \$", breakfast_usd)
end

end # module Money
