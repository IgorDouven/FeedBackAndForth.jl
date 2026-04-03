# ─────────────────────────────────────────────────────────────────────
# Output Formatting
# ─────────────────────────────────────────────────────────────────────

"""
    save_markdown(panel::ReviewPanel, path::String="") -> String

Write the full panel transcript to a Markdown file. Returns the path.
If `path` is empty, auto-generates a filename.
"""
function save_markdown(panel::ReviewPanel, path::String="")
    if isempty(path)
        bn = first(splitext(basename(panel.paper_path)))
        path = "review_panel_$(bn)_$(Dates.format(now(), "yyyymmdd_HHMM")).md"
    end

    io = IOBuffer()

    # Header
    println(io, "# LLM Review Panel — $(Dates.format(now(), "yyyy-mm-dd HH:MM"))\n")
    names = [p.name for (_, p) in panel.providers_used]
    println(io, "**Panelists**: $(join(names, ", "))\n")
    println(io, "**Rounds**: $(length(panel.rounds))\n")
    if panel.config.detail > 1
        detail_label = panel.config.detail == 2 ? "Detailed" : "Passage-level"
        println(io, "**Detail level**: $(panel.config.detail) ($detail_label)\n")
    end
    if !isempty(panel.config.venue)
        println(io, "**Venue**: $(panel.config.venue)\n")
    end
    lo, hi = panel.config.acceptance_rate
    if lo > 0 || hi > 0
        lo_pct = round(Int, lo * 100)
        hi_pct = round(Int, hi * 100)
        rate = lo_pct == hi_pct ? "$(lo_pct)%" : "$(lo_pct)–$(hi_pct)%"
        println(io, "**Acceptance rate**: $rate\n")
    end
    println(io, "---\n")

    # Rounds
    for rr in panel.rounds
        if rr.round_num == 1
            println(io, "## Round 1: Independent Reviews\n")
        else
            println(io, "## Round $(rr.round_num): Discussion\n")
        end
        for (key, text) in rr.reviews
            name = haskey(PROVIDER_REGISTRY, key) ? PROVIDER_REGISTRY[key].name : key
            println(io, "### $name\n")
            println(io, text)
            println(io, "\n---\n")
        end
    end

    # Meta-review
    if !isempty(panel.metareview)
        println(io, "## Meta-Review\n")
        println(io, panel.metareview)
        println(io)
    end

    # Cost summary
    println(io, "\n---\n")
    println(io, "## Session Info\n")
    println(io, "```")
    println(io, cost_summary(panel.cost))
    println(io, "Total wall-clock time: $(round(panel.total_elapsed; digits=1))s")
    println(io, "```")

    content = String(take!(io))
    write(path, content)
    return path
end

"""
    save_json(panel::ReviewPanel, path::String="") -> String

Save a machine-readable JSON representation of the panel results.
Useful for downstream analysis (e.g., comparing across papers or rounds).
"""
function save_json(panel::ReviewPanel, path::String="")
    if isempty(path)
        bn = first(splitext(basename(panel.paper_path)))
        path = "review_panel_$(bn)_$(Dates.format(now(), "yyyymmdd_HHMM")).json"
    end

    data = Dict(
        "timestamp" => Dates.format(now(), "yyyy-mm-ddTHH:MM:SS"),
        "paper_path" => panel.paper_path,
        "paper_length_chars" => panel.paper_length,
        "config" => Dict(
            "rounds" => panel.config.rounds,
            "request_scores" => panel.config.request_scores,
            "detail" => panel.config.detail,
            "acceptance_rate" => [panel.config.acceptance_rate...],
            "venue" => panel.config.venue,
            "venue_type" => string(panel.config.venue_type),
        ),
        "providers" => Dict(
            key => Dict("name" => p.name, "model" => p.model,
                        "is_local" => is_local(p))
            for (key, p) in panel.providers_used
        ),
        "rounds" => [
            Dict(
                "round_num" => rr.round_num,
                "reviews" => Dict(
                    key => Dict(
                        "text" => text,
                        "timestamp" => Dates.format(
                            get(rr.timestamps, key, now()), "yyyy-mm-ddTHH:MM:SS"),
                        "elapsed_s" => get(rr.elapsed, key, 0.0)
                    )
                    for (key, text) in rr.reviews
                )
            )
            for rr in panel.rounds
        ],
        "metareview" => Dict(
            "text" => panel.metareview,
            "provider" => panel.meta_provider_key,
        ),
        "costs" => Dict(
            "by_provider" => Dict(
                key => Dict("input_tokens" => u.input,
                            "output_tokens" => u.output,
                            "calls" => u.calls)
                for (key, u) in panel.cost.usage
            ),
            "total_input_tokens" => panel.cost.total_input,
            "total_output_tokens" => panel.cost.total_output,
            "estimated_usd" => round(estimated_cost(panel.cost); digits=4),
        ),
        "total_elapsed_s" => round(panel.total_elapsed; digits=1),
    )

    write(path, JSON3.write(data))
    return path
end

# ─────────────────────────────────────────────────────────────────────
# Selection Output
# ─────────────────────────────────────────────────────────────────────

"""
    save_markdown(panel::SelectionPanel, path::String="") -> String

Write the full selection transcript to a Markdown file. Returns the path.
"""
function save_markdown(panel::SelectionPanel, path::String="")
    if isempty(path)
        dn = basename(rstrip(panel.submission_dir, '/'))
        path = "selection_$(dn)_$(Dates.format(now(), "yyyymmdd_HHMM")).md"
    end

    io = IOBuffer()

    # Header
    println(io, "# LLM Selection Panel — $(Dates.format(now(), "yyyy-mm-dd HH:MM"))\n")
    names = [p.name for (_, p) in panel.providers_used]
    println(io, "**Committee**: $(join(names, ", "))\n")
    println(io, "**Submissions**: $(length(panel.submission_files))\n")
    println(io, "**Target accepts**: $(panel.n_accept)\n")
    if panel.config.detail > 1
        detail_label = panel.config.detail == 2 ? "Detailed" : "Passage-level"
        println(io, "**Detail level**: $(panel.config.detail) ($detail_label)\n")
    end
    if !isempty(panel.config.venue)
        println(io, "**Venue**: $(panel.config.venue)\n")
    end
    println(io, "---\n")

    # Phase 1: Calibration
    println(io, "## Phase 1: Calibration\n")
    for (key, text) in panel.calibration.reviews
        name = haskey(PROVIDER_REGISTRY, key) ? PROVIDER_REGISTRY[key].name : key
        println(io, "### $name\n")
        println(io, text)
        println(io, "\n---\n")
    end

    # Phase 2: Discussion
    println(io, "## Phase 2: Committee Discussion\n")
    for (key, text) in panel.discussion.reviews
        name = haskey(PROVIDER_REGISTRY, key) ? PROVIDER_REGISTRY[key].name : key
        println(io, "### $name\n")
        println(io, text)
        println(io, "\n---\n")
    end

    # Phase 3: Final Selection
    if !isempty(panel.selection)
        println(io, "## Final Selection\n")
        println(io, panel.selection)
        println(io)
    end

    # Submission index
    println(io, "\n---\n")
    println(io, "## Submissions\n")
    println(io, "| # | File | Chars |")
    println(io, "|---|------|-------|")
    for (i, (f, l)) in enumerate(zip(panel.submission_files, panel.submission_lengths))
        println(io, "| $i | $f | $l |")
    end

    # Cost summary
    println(io, "\n---\n")
    println(io, "## Session Info\n")
    println(io, "```")
    println(io, cost_summary(panel.cost))
    println(io, "Total wall-clock time: $(round(panel.total_elapsed; digits=1))s")
    println(io, "```")

    content = String(take!(io))
    write(path, content)
    return path
end

"""
    save_json(panel::SelectionPanel, path::String="") -> String

Save a machine-readable JSON representation of the selection results.
"""
function save_json(panel::SelectionPanel, path::String="")
    if isempty(path)
        dn = basename(rstrip(panel.submission_dir, '/'))
        path = "selection_$(dn)_$(Dates.format(now(), "yyyymmdd_HHMM")).json"
    end

    data = Dict(
        "timestamp" => Dates.format(now(), "yyyy-mm-ddTHH:MM:SS"),
        "submission_dir" => panel.submission_dir,
        "n_submissions" => length(panel.submission_files),
        "n_accept" => panel.n_accept,
        "submissions" => [
            Dict("file" => f, "chars" => l)
            for (f, l) in zip(panel.submission_files, panel.submission_lengths)
        ],
        "config" => Dict(
            "detail" => panel.config.detail,
            "acceptance_rate" => [panel.config.acceptance_rate...],
            "venue" => panel.config.venue,
            "venue_type" => string(panel.config.venue_type),
        ),
        "providers" => Dict(
            key => Dict("name" => p.name, "model" => p.model,
                        "is_local" => is_local(p))
            for (key, p) in panel.providers_used
        ),
        "calibration" => Dict(
            key => Dict(
                "text" => text,
                "timestamp" => Dates.format(
                    get(panel.calibration.timestamps, key, now()), "yyyy-mm-ddTHH:MM:SS"),
                "elapsed_s" => get(panel.calibration.elapsed, key, 0.0)
            )
            for (key, text) in panel.calibration.reviews
        ),
        "discussion" => Dict(
            key => Dict(
                "text" => text,
                "timestamp" => Dates.format(
                    get(panel.discussion.timestamps, key, now()), "yyyy-mm-ddTHH:MM:SS"),
                "elapsed_s" => get(panel.discussion.elapsed, key, 0.0)
            )
            for (key, text) in panel.discussion.reviews
        ),
        "selection" => Dict(
            "text" => panel.selection,
            "provider" => panel.meta_provider_key,
        ),
        "costs" => Dict(
            "by_provider" => Dict(
                key => Dict("input_tokens" => u.input,
                            "output_tokens" => u.output,
                            "calls" => u.calls)
                for (key, u) in panel.cost.usage
            ),
            "total_input_tokens" => panel.cost.total_input,
            "total_output_tokens" => panel.cost.total_output,
            "estimated_usd" => round(estimated_cost(panel.cost); digits=4),
        ),
        "total_elapsed_s" => round(panel.total_elapsed; digits=1),
    )

    write(path, JSON3.write(data))
    return path
end

function Base.show(io::IO, panel::SelectionPanel)
    n_sub = length(panel.submission_files)
    n_prov = length(panel.providers_used)
    print(io, "SelectionPanel($n_sub submissions, $n_prov providers, " *
              "accept=$(panel.n_accept), " *
              "≈\$$(round(estimated_cost(panel.cost); digits=3)))")
end

function Base.show(io::IO, ::MIME"text/plain", panel::SelectionPanel)
    names = join([p.name for (_, p) in panel.providers_used], ", ")
    println(io, "LLM Selection Panel")
    println(io, "  Submissions: $(length(panel.submission_files)) from $(panel.submission_dir)")
    println(io, "  Target accepts: $(panel.n_accept)")
    println(io, "  Committee: $names")
    println(io, "  Program chair: $(panel.meta_provider_key)")
    println(io, "  Time: $(round(panel.total_elapsed; digits=1))s")
    print(io, "  Est. cost: \$$(round(estimated_cost(panel.cost); digits=4))")
end

function Base.show(io::IO, panel::ReviewPanel)
    n_rounds = length(panel.rounds)
    n_providers = length(panel.providers_used)
    names = join([p.name for (_, p) in panel.providers_used], ", ")
    print(io, "ReviewPanel($(n_providers) providers, $(n_rounds) rounds, " *
              "≈\$$(round(estimated_cost(panel.cost); digits=3)))")
end

function Base.show(io::IO, ::MIME"text/plain", panel::ReviewPanel)
    names = join([p.name for (_, p) in panel.providers_used], ", ")
    println(io, "LLM Review Panel")
    println(io, "  Paper: $(panel.paper_path) ($(panel.paper_length) chars)")
    println(io, "  Panelists: $names")
    println(io, "  Rounds: $(length(panel.rounds))")
    println(io, "  Meta-reviewer: $(panel.meta_provider_key)")
    println(io, "  Time: $(round(panel.total_elapsed; digits=1))s")
    print(io, "  Est. cost: \$$(round(estimated_cost(panel.cost); digits=4))")
end
