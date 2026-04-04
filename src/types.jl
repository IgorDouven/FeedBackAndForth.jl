# ─────────────────────────────────────────────────────────────────────
# Type Definitions
# ─────────────────────────────────────────────────────────────────────

"""
    Provider

Configuration for a single LLM provider.

# Fields
- `name::String`: Human-readable name (e.g., "Claude (Anthropic)")
- `api_key_env::String`: Environment variable name for the API key
- `endpoint::String`: API endpoint URL
- `model::String`: Model identifier string
- `format::Symbol`: API format — `:anthropic`, `:openai`, or `:google`
- `max_tokens::Int`: Maximum tokens in the response
- `cost_per_1k_input::Float64`: Cost per 1000 input tokens (USD)
- `cost_per_1k_output::Float64`: Cost per 1000 output tokens (USD)
"""
struct Provider
    name::String
    api_key_env::String
    endpoint::String
    model::String
    format::Symbol
    max_tokens::Int
    cost_per_1k_input::Float64
    cost_per_1k_output::Float64
end

# Convenience constructor without cost info
function Provider(name, api_key_env, endpoint, model, format, max_tokens)
    Provider(name, api_key_env, endpoint, model, format, max_tokens, 0.0, 0.0)
end

"""
    ReviewConfig

Configuration for a review panel session.

# Fields
- `rounds::Int`: Total number of rounds (1 = independent only)
- `providers::Vector{String}`: Provider keys to use (empty = auto-detect)
- `meta_provider::String`: Which provider writes the meta-review
- `request_scores::Bool`: Whether to ask for structured numerical scores
- `prompts_file::String`: Path to a custom TOML prompts file
- `verbose::Bool`: Print progress messages
- `acceptance_rate::Tuple{Float64,Float64}`: Expected acceptance rate range,
   e.g. `(0.10, 0.15)` for 10–15%. `(0.0, 0.0)` means unspecified.
- `venue::String`: Description of the venue (journal, conference, etc.)
- `venue_type::Symbol`: `:journal`, `:conference`, `:workshop`, or `:unspecified`
- `refereeing::Bool`: Whether to include accept/reject recommendations (default: false)
- `detail::Int`: Level of detail in reviews (1 = standard, 2 = detailed, 3 = passage-level)
- `accept::Int`: Number of submissions to accept (used by `select()`, 0 = derive from acceptance_rate)
- `call_delay::Int`: Seconds to wait between provider API calls (default: 0). Useful for
   avoiding rate limits, especially with large payloads in `select()`.
- `meta_reads_paper::Bool`: Whether the meta-reviewer reads the paper (default: true).
   When `false`, the meta-reviewer only sees the panel's reviews/discussion — like
   a handling editor who bases their verdict on the referee reports. Ignored when
   the meta-reviewer is on the panel (since they already read the paper).
"""
Base.@kwdef mutable struct ReviewConfig
    rounds::Int = 2
    providers::Vector{String} = String[]
    meta_provider::String = ""
    request_scores::Bool = false
    prompts_file::String = ""
    verbose::Bool = true
    acceptance_rate::Tuple{Float64, Float64} = (0.0, 0.0)
    venue::String = ""
    venue_type::Symbol = :unspecified
    refereeing::Bool = false
    detail::Int = 1
    accept::Int = 0
    call_delay::Int = 0
    meta_reads_paper::Bool = true
end

"""
    RoundResult

Stores one round's reviews from all panelists.
"""
struct RoundResult
    round_num::Int
    reviews::Dict{String, String}
    timestamps::Dict{String, DateTime}
    elapsed::Dict{String, Float64}   # seconds per provider
end

"""
    ReviewPanel

Complete results from a review panel session.

# Fields
- `paper_path::String`: Path to the reviewed paper
- `paper_length::Int`: Character count of the paper
- `config::ReviewConfig`: Configuration used
- `providers_used::Vector{Tuple{String, Provider}}`: Active providers
- `rounds::Vector{RoundResult}`: All round results
- `metareview::String`: The synthesized meta-review
- `meta_provider_key::String`: Which provider wrote the meta-review
- `total_elapsed::Float64`: Total wall-clock time (seconds)
- `cost::CostTracker`: Token usage and cost estimates
"""
mutable struct ReviewPanel
    paper_path::String
    paper_length::Int
    config::ReviewConfig
    providers_used::Vector{Tuple{String, Provider}}
    rounds::Vector{RoundResult}
    metareview::String
    meta_provider_key::String
    total_elapsed::Float64
    cost::Any  # CostTracker, defined in costs.jl
end

"""
    SelectionPanel

Complete results from a batch selection session.

# Fields
- `submission_dir::String`: Directory containing the submissions
- `submission_files::Vector{String}`: Ordered list of submission filenames
- `submission_lengths::Vector{Int}`: Character counts per submission
- `n_accept::Int`: Target number of acceptances
- `config::ReviewConfig`: Configuration used
- `providers_used::Vector{Tuple{String, Provider}}`: Active providers
- `calibration::RoundResult`: Phase 1 — independent calibration reports
- `discussion::RoundResult`: Phase 2 — panel discussion on rankings
- `selection::String`: Phase 3 — final selection meta-review
- `meta_provider_key::String`: Which provider wrote the final selection
- `total_elapsed::Float64`: Total wall-clock time (seconds)
- `cost::Any`: CostTracker
"""
mutable struct SelectionPanel
    submission_dir::String
    submission_files::Vector{String}
    submission_lengths::Vector{Int}
    n_accept::Int
    config::ReviewConfig
    providers_used::Vector{Tuple{String, Provider}}
    calibration::RoundResult
    discussion::RoundResult
    selection::String
    meta_provider_key::String
    total_elapsed::Float64
    cost::Any  # CostTracker
end
