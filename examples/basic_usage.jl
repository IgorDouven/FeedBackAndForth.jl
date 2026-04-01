#=
    basic_usage.jl — Example usage of FeedBackAndForth.jl

    Run from the package directory:
        julia --project=. examples/basic_usage.jl
    
    Or from the REPL:
        include("examples/basic_usage.jl")
=#

using FeedBackAndForth

# ─── Basic review ───
# Auto-detects all providers with available API keys
panel = review("my_paper.tex")
save_markdown(panel)
save_json(panel)

# ─── Calibrated to a specific venue ───
panel = review("my_paper.tex",
    venue = "Cognitive Science",
    venue_type = :journal,
    acceptance_rate = (0.15, 0.25),
    rounds = 2,
    scores = true
)
save_markdown(panel, "review_cogsci.md")

# ─── With refereeing (accept/reject verdicts) ───
panel = review("my_paper.tex",
    refereeing = true,
    venue = "Mind",
    venue_type = :journal,
    acceptance_rate = (0.05, 0.10)
)
save_markdown(panel, "review_mind.md")

# ─── With a local model via Ollama ───
add_provider!("local_qwen",
    endpoint = "http://localhost:11434/v1/chat/completions",
    model = "qwen2.5:72b",
    name = "Qwen 2.5 72B (local)"
)

panel = review("my_paper.tex",
    providers = ["claude", "openai", "local_qwen"],
    rounds = 3
)

# ─── Batch processing ───
failed = String[]
for f in readdir("abstracts"; join=true)
    endswith(f, ".pdf") || endswith(f, ".tex") || continue
    id = first(splitext(basename(f)))
    isfile("results/$(id).json") && continue  # skip already done
    try
        panel = review(f,
            acceptance_rate = (0.55, 0.65),
            venue = "EPSA 2025",
            venue_type = :conference,
            rounds = 2, scores = true
        )
        save_json(panel, "results/$(id).json")
        save_markdown(panel, "results/$(id).md")
    catch e
        @warn "Failed on $id" exception=e
        push!(failed, id)
    end
end

# ─── Author response cycle ───
panel = review("paper.tex")
save_markdown(panel, "initial_review.md")

# ... write your response in response.txt ...

panel2 = review_and_respond(panel, "response.txt")
save_markdown(panel2, "after_response.md")
