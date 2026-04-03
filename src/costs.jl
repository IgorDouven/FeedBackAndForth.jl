# ─────────────────────────────────────────────────────────────────────
# Cost Tracking
# ─────────────────────────────────────────────────────────────────────

"""
    CostTracker

Tracks token usage and estimated costs across all API calls in a session.
"""
mutable struct CostTracker
    # Per-provider totals: key => (input_tokens, output_tokens, n_calls)
    usage::Dict{String, @NamedTuple{input::Int, output::Int, calls::Int}}
    total_input::Int
    total_output::Int
    total_calls::Int
end

CostTracker() = CostTracker(
    Dict{String, @NamedTuple{input::Int, output::Int, calls::Int}}(),
    0, 0, 0
)

function record!(ct::CostTracker, key::String, input_tokens::Int, output_tokens::Int)
    if haskey(ct.usage, key)
        old = ct.usage[key]
        ct.usage[key] = (input=old.input + input_tokens,
                         output=old.output + output_tokens,
                         calls=old.calls + 1)
    else
        ct.usage[key] = (input=input_tokens, output=output_tokens, calls=1)
    end
    ct.total_input += input_tokens
    ct.total_output += output_tokens
    ct.total_calls += 1
end

"""
    estimated_cost(ct::CostTracker) -> Float64

Return total estimated cost in USD based on registered provider pricing.
"""
function estimated_cost(ct::CostTracker)
    total = 0.0
    for (key, usage) in ct.usage
        if haskey(PROVIDER_REGISTRY, key)
            p = PROVIDER_REGISTRY[key]
            total += (usage.input / 1000) * p.cost_per_1k_input
            total += (usage.output / 1000) * p.cost_per_1k_output
        end
    end
    return total
end

"""
    cost_summary(ct::CostTracker) -> String

Return a formatted summary of token usage and costs.
"""
function cost_summary(ct::CostTracker)
    lines = String[]
    push!(lines, "Token Usage & Cost Estimates")
    push!(lines, "─" ^ 60)

    for (key, usage) in sort(collect(ct.usage); by=first)
        name = haskey(PROVIDER_REGISTRY, key) ? PROVIDER_REGISTRY[key].name : key
        cost = 0.0
        if haskey(PROVIDER_REGISTRY, key)
            p = PROVIDER_REGISTRY[key]
            cost = (usage.input / 1000) * p.cost_per_1k_input +
                   (usage.output / 1000) * p.cost_per_1k_output
        end
        push!(lines, "  $(name): $(usage.input) in / $(usage.output) out " *
                     "($(usage.calls) calls) ≈ \$$(round(cost; digits=4))")
    end

    push!(lines, "─" ^ 60)
    push!(lines, "  Total: $(ct.total_input) in / $(ct.total_output) out " *
                 "($(ct.total_calls) calls) ≈ \$$(round(estimated_cost(ct); digits=4))")
    return join(lines, "\n")
end

"""
    estimate_cost(paper_chars::Int; n_providers=3, rounds=2, with_meta=true, detail=1) -> Float64

Rough a priori cost estimate in USD for a review session.
Uses average provider pricing. Useful for budgeting before running.
`detail` (1–3) scales expected output length: level 2 ≈ 1.8×, level 3 ≈ 3×.
"""
function estimate_cost(paper_chars::Int; n_providers::Int=3, rounds::Int=2,
                       with_meta::Bool=true, detail::Int=1)
    paper_tokens = paper_chars ÷ 4  # rough char-to-token ratio
    detail_factor = detail == 1 ? 1.0 : detail == 2 ? 1.8 : 3.0
    review_output = round(Int, 2000 * detail_factor)  # estimated tokens per review

    # Round 1: each provider sees the paper
    r1_input = paper_tokens * n_providers
    r1_output = review_output * n_providers

    # Subsequent rounds: paper + all other reviews
    other_reviews_tokens = review_output * (n_providers - 1)
    rn_input = (paper_tokens + review_output + other_reviews_tokens) * n_providers
    rn_output = review_output * n_providers

    total_input = r1_input + (rounds - 1) * rn_input
    total_output = r1_output + (rounds - 1) * rn_output

    if with_meta
        all_reviews = review_output * n_providers * rounds
        total_input += paper_tokens + all_reviews
        total_output += 3000  # meta-review tends to be longer
    end

    # Use average of common provider pricing (rough)
    avg_input_cost = 0.002   # $/1k tokens
    avg_output_cost = 0.008  # $/1k tokens

    return (total_input / 1000) * avg_input_cost +
           (total_output / 1000) * avg_output_cost
end

function Base.show(io::IO, ct::CostTracker)
    print(io, cost_summary(ct))
end
