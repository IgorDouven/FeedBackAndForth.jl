module FeedBackAndForth

using HTTP, JSON3, Dates, TOML, UUIDs

# ─── Source files ───
include("types.jl")
include("providers.jl")
include("api.jl")
include("costs.jl")
include("prompts.jl")
include("pipeline.jl")
include("output.jl")
include("convenience.jl")

# ─── Public API ───
export
    # Main entry points
    review,
    review_and_respond,
    select,
    # Provider management
    Provider,
    add_provider!,
    remove_provider!,
    set_model!,
    list_providers,
    available_providers,
    # Configuration
    ReviewConfig,
    load_prompts,
    # Output
    ReviewPanel,
    SelectionPanel,
    save_markdown,
    save_json,
    # Cost tracking
    estimate_cost,
    CostTracker

end # module
