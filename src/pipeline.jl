# ─────────────────────────────────────────────────────────────────────
# Core Pipeline
# ─────────────────────────────────────────────────────────────────────

function _log(config::ReviewConfig, msg::String)
    config.verbose && println(msg)
end

# If call_delay > 0 and this is not the first call, pause between providers.
function _maybe_delay(config::ReviewConfig, i::Int)
    if config.call_delay > 0 && i > 1
        _log(config, "  ⏸  Waiting $(config.call_delay)s (rate limit delay)...")
        sleep(config.call_delay)
    end
end

"""
    _effective_max_tokens(provider, config) -> Int

Scale a provider's max_tokens based on the configured detail level.
Level 1 uses the provider default; level 2 scales by 1.8×; level 3 by 3×.
"""
function _effective_max_tokens(prov::Provider, config::ReviewConfig)
    factor = config.detail == 1 ? 1.0 : config.detail == 2 ? 1.8 : 3.0
    return round(Int, prov.max_tokens * factor)
end

"""
    _run_round1(paper, providers, prompts, config, cost) -> RoundResult

Each provider independently reviews the paper.
"""
function _run_round1(paper::String, providers::Vector{Tuple{String, Provider}},
                     prompts::Dict, config::ReviewConfig, cost::CostTracker)
    reviews = Dict{String, String}()
    timestamps = Dict{String, DateTime}()
    elapsed = Dict{String, Float64}()

    system = get_review_prompt(prompts, config)

    for (i, (key, prov)) in enumerate(providers)
        _maybe_delay(config, i)
        _log(config, "  ⏳ Requesting review from $(prov.name)...")
        t0 = time()
        try
            text, tokens = call_llm(prov, system, paper;
                                    max_tokens=_effective_max_tokens(prov, config))
            dt = round(time() - t0; digits=1)
            _log(config, "  ✅ $(prov.name) responded ($(dt)s, " *
                         "$(tokens.input)+$(tokens.output) tokens)")
            reviews[key] = text
            timestamps[key] = now()
            elapsed[key] = dt
            record!(cost, key, tokens.input, tokens.output)
        catch e
            dt = round(time() - t0; digits=1)
            @warn "$(prov.name) failed after $(dt)s" exception=e
            reviews[key] = "[ERROR: $(prov.name) did not respond — $(sprint(showerror, e))]"
            timestamps[key] = now()
            elapsed[key] = dt
        end
    end
    return RoundResult(1, reviews, timestamps, elapsed)
end

"""
Format all reviews except `exclude_key` for inclusion in a discussion prompt.
"""
function _format_other_reviews(reviews::Dict{String, String}, exclude_key::String)
    parts = String[]
    for (key, text) in reviews
        key == exclude_key && continue
        name = haskey(PROVIDER_REGISTRY, key) ? PROVIDER_REGISTRY[key].name : key
        push!(parts, "━━━ Review by $name ━━━\n$text")
    end
    return join(parts, "\n\n")
end

"""
    _run_discussion(paper, prev_reviews, providers, round_num, prompts, config, cost)

Each provider sees all other reviews and produces a revised assessment.
"""
function _run_discussion(paper::String, prev_reviews::Dict{String, String},
                         providers::Vector{Tuple{String, Provider}},
                         round_num::Int, prompts::Dict,
                         config::ReviewConfig, cost::CostTracker)
    reviews = Dict{String, String}()
    timestamps = Dict{String, DateTime}()
    elapsed = Dict{String, Float64}()

    system = get_discussion_prompt(prompts, round_num, config)

    for (i, (key, prov)) in enumerate(providers)
        _maybe_delay(config, i)
        others = _format_other_reviews(prev_reviews, key)
        own = get(prev_reviews, key, "")

        user_msg = """
## The Paper

$paper

## Your Previous Review

$own

## Reviews from Other Panelists

$others

---

Please provide your discussion response and updated assessment."""

        _log(config, "  ⏳ $(prov.name) deliberating (round $round_num)...")
        t0 = time()
        try
            text, tokens = call_llm(prov, system, user_msg;
                                    max_tokens=_effective_max_tokens(prov, config))
            dt = round(time() - t0; digits=1)
            _log(config, "  ✅ $(prov.name) responded ($(dt)s, " *
                         "$(tokens.input)+$(tokens.output) tokens)")
            reviews[key] = text
            timestamps[key] = now()
            elapsed[key] = dt
            record!(cost, key, tokens.input, tokens.output)
        catch e
            dt = round(time() - t0; digits=1)
            @warn "$(prov.name) failed in round $round_num" exception=e
            reviews[key] = prev_reviews[key]  # keep previous review
            timestamps[key] = now()
            elapsed[key] = dt
        end
    end
    return RoundResult(round_num, reviews, timestamps, elapsed)
end

"""
    _run_metareview(paper, all_rounds, providers, meta_prov, prompts, config, cost)

Produce a meta-review synthesizing all rounds.
"""
function _run_metareview(paper::String, all_rounds::Vector{RoundResult},
                         providers::Vector{Tuple{String, Provider}},
                         meta_prov::Tuple{String, Provider},
                         prompts::Dict, config::ReviewConfig, cost::CostTracker)
    parts = String[]
    for rr in all_rounds
        label = rr.round_num == 1 ? "Initial Reviews" : "Discussion Round $(rr.round_num - 1)"
        push!(parts, "═══════ $label ═══════\n")
        for (key, text) in rr.reviews
            name = haskey(PROVIDER_REGISTRY, key) ? PROVIDER_REGISTRY[key].name : key
            push!(parts, "── $name ──\n$text\n")
        end
    end
    history = join(parts, "\n")

    # Determine whether to include the paper text
    reports_only = !config.meta_reads_paper &&
                   !any(k == meta_prov[1] for (k, _) in providers)

    user_msg = if reports_only
        """
## Full Discussion History

$history

---

Please provide your meta-review based on the reviewers' reports above."""
    else
        """
## The Paper

$paper

## Full Discussion History

$history

---

Please provide your meta-review."""
    end

    key, prov = meta_prov
    if reports_only
        _log(config, "  📋 Meta-reviewer will not read the paper (reports-only mode)")
    end
    _log(config, "  ⏳ $(prov.name) writing meta-review...")
    t0 = time()
    try
        text, tokens = call_llm(prov, get_metareview_prompt(prompts, config;
                                                             reports_only=reports_only), user_msg;
                                max_tokens=_effective_max_tokens(prov, config))
        dt = round(time() - t0; digits=1)
        _log(config, "  ✅ Meta-review complete ($(dt)s, $(tokens.input)+$(tokens.output) tokens)")
        record!(cost, key, tokens.input, tokens.output)
        return text
    catch e
        dt = round(time() - t0; digits=1)
        @warn "$(prov.name) failed writing meta-review after $(dt)s" exception=e

        # Try fallback: use a different provider for the meta-review
        for (fkey, fprov) in providers
            fkey == key && continue
            _log(config, "  🔄 Falling back to $(fprov.name) for meta-review...")
            t0 = time()
            try
                text, tokens = call_llm(fprov, get_metareview_prompt(prompts, config;
                                                                    reports_only=reports_only), user_msg)
                dt = round(time() - t0; digits=1)
                _log(config, "  ✅ Meta-review complete via $(fprov.name) ($(dt)s)")
                record!(cost, fkey, tokens.input, tokens.output)
                return text
            catch e2
                @warn "$(fprov.name) also failed" exception=e2
                continue
            end
        end

        # All providers failed — return a placeholder
        @warn "All providers failed for meta-review. Returning placeholder."
        return "[META-REVIEW UNAVAILABLE: All providers failed. " *
               "Re-run with `review()` or try a different meta provider.]"
    end
end

"""
    _run_author_response(paper, all_rounds, metareview, response_text,
                         providers, prompts, config, cost) -> RoundResult

Authors respond to the panel; each reviewer evaluates the response.
"""
function _run_author_response(paper::String, all_rounds::Vector{RoundResult},
                              metareview::String, response_text::String,
                              providers::Vector{Tuple{String, Provider}},
                              prompts::Dict, config::ReviewConfig, cost::CostTracker)
    reviews = Dict{String, String}()
    timestamps = Dict{String, DateTime}()
    elapsed = Dict{String, Float64}()

    # Compile the last round's reviews for context
    last_reviews = all_rounds[end].reviews

    system = config.refereeing ? prompts["author_response"] : prompts["author_response_no_verdict"]

    for (i, (key, prov)) in enumerate(providers)
        _maybe_delay(config, i)
        own = get(last_reviews, key, "")

        user_msg = """
## The Paper

$paper

## Your Most Recent Review

$own

## Meta-Review Summary

$metareview

## Authors' Response

$response_text

---

Please evaluate the authors' response and provide your updated assessment."""

        _log(config, "  ⏳ $(prov.name) evaluating author response...")
        t0 = time()
        try
            text, tokens = call_llm(prov, system, user_msg;
                                    max_tokens=_effective_max_tokens(prov, config))
            dt = round(time() - t0; digits=1)
            _log(config, "  ✅ $(prov.name) responded ($(dt)s)")
            reviews[key] = text
            timestamps[key] = now()
            elapsed[key] = dt
            record!(cost, key, tokens.input, tokens.output)
        catch e
            @warn "$(prov.name) failed evaluating author response" exception=e
            reviews[key] = "[ERROR]"
            timestamps[key] = now()
            elapsed[key] = time() - t0
        end
    end

    round_num = length(all_rounds) + 1
    return RoundResult(round_num, reviews, timestamps, elapsed)
end

# ─────────────────────────────────────────────────────────────────────
# Selection (Batch) Pipeline
# ─────────────────────────────────────────────────────────────────────

"""
    _load_submissions(dir, config) -> (bundle, files, lengths)

Load all submissions from a directory, concatenate with clear labels.
Returns the bundle string, ordered filenames, and per-file character counts.
"""
function _load_submissions(dir::String, config::ReviewConfig)
    entries = sort(readdir(dir))
    valid_ext = (".tex", ".txt", ".md", ".pdf")
    entries = filter(f -> lowercase(last(splitext(f))) in valid_ext, entries)

    if isempty(entries)
        error("No submissions found in $dir (looked for .tex, .txt, .md, .pdf files)")
    end

    files = String[]
    lengths = Int[]
    parts = String[]

    for (i, fname) in enumerate(entries)
        path = joinpath(dir, fname)
        _log(config, "  📄 [$i/$(length(entries))] $fname")
        text = _load_paper(path, config)
        push!(files, fname)
        push!(lengths, length(text))
        push!(parts, "═══ Submission $i: $fname ═══\n\n$text")
    end

    bundle = join(parts, "\n\n")

    # Warn about context window size
    approx_tokens = length(bundle) ÷ 4
    if approx_tokens > 100_000
        @warn "Submission bundle is ~$(round(Int, approx_tokens/1000))k tokens. " *
              "This may exceed the context window of some models. " *
              "Consider using frontier models with large context windows."
    end

    return bundle, files, lengths
end

"""
    _run_calibration(bundle, providers, prompts, config, n_submissions, cost) -> RoundResult

Phase 1: Each provider reads all submissions and produces a calibration report.
"""
function _run_calibration(bundle::String, providers::Vector{Tuple{String, Provider}},
                          prompts::Dict, config::ReviewConfig, n_submissions::Int,
                          cost::CostTracker)
    reviews = Dict{String, String}()
    timestamps = Dict{String, DateTime}()
    elapsed = Dict{String, Float64}()

    system = get_selection_prompt(prompts, :calibration, config, n_submissions)

    for (i, (key, prov)) in enumerate(providers)
        _maybe_delay(config, i)
        _log(config, "  ⏳ $(prov.name) reading all submissions...")
        t0 = time()
        try
            text, tokens = call_llm(prov, system, bundle;
                                    max_tokens=_effective_max_tokens(prov, config))
            dt = round(time() - t0; digits=1)
            _log(config, "  ✅ $(prov.name) calibrated ($(dt)s, " *
                         "$(tokens.input)+$(tokens.output) tokens)")
            reviews[key] = text
            timestamps[key] = now()
            elapsed[key] = dt
            record!(cost, key, tokens.input, tokens.output)
        catch e
            dt = round(time() - t0; digits=1)
            @warn "$(prov.name) failed during calibration after $(dt)s" exception=e
            reviews[key] = "[ERROR: $(prov.name) did not respond — $(sprint(showerror, e))]"
            timestamps[key] = now()
            elapsed[key] = dt
        end
    end
    return RoundResult(1, reviews, timestamps, elapsed)
end

"""
    _run_selection_discussion(bundle, calibrations, providers, prompts, config,
                              n_submissions, cost) -> RoundResult

Phase 2: Each provider sees all other calibrations and debates rankings.
"""
function _run_selection_discussion(bundle::String, calibrations::Dict{String, String},
                                   providers::Vector{Tuple{String, Provider}},
                                   prompts::Dict, config::ReviewConfig,
                                   n_submissions::Int, cost::CostTracker)
    reviews = Dict{String, String}()
    timestamps = Dict{String, DateTime}()
    elapsed = Dict{String, Float64}()

    system = get_selection_prompt(prompts, :discussion, config, n_submissions)

    for (i, (key, prov)) in enumerate(providers)
        _maybe_delay(config, i)
        others = _format_other_reviews(calibrations, key)
        own = get(calibrations, key, "")

        user_msg = """
## All Submissions

$bundle

## Your Calibration Report

$own

## Other Committee Members' Reports

$others

---

Please provide your discussion response and updated ranking."""

        _log(config, "  ⏳ $(prov.name) discussing rankings...")
        t0 = time()
        try
            text, tokens = call_llm(prov, system, user_msg;
                                    max_tokens=_effective_max_tokens(prov, config))
            dt = round(time() - t0; digits=1)
            _log(config, "  ✅ $(prov.name) responded ($(dt)s, " *
                         "$(tokens.input)+$(tokens.output) tokens)")
            reviews[key] = text
            timestamps[key] = now()
            elapsed[key] = dt
            record!(cost, key, tokens.input, tokens.output)
        catch e
            dt = round(time() - t0; digits=1)
            @warn "$(prov.name) failed during discussion" exception=e
            reviews[key] = calibrations[key]  # fall back to calibration
            timestamps[key] = now()
            elapsed[key] = dt
        end
    end
    return RoundResult(2, reviews, timestamps, elapsed)
end

"""
    _run_selection_metareview(bundle, calibration, discussion, providers,
                              meta_prov, prompts, config, n_submissions, cost) -> String

Phase 3: The meta-reviewer produces the final selection.
"""
function _run_selection_metareview(bundle::String,
                                   calibration::RoundResult, discussion::RoundResult,
                                   providers::Vector{Tuple{String, Provider}},
                                   meta_prov::Tuple{String, Provider},
                                   prompts::Dict, config::ReviewConfig,
                                   n_submissions::Int, cost::CostTracker)
    parts = String[]
    push!(parts, "═══════ Calibration Reports ═══════\n")
    for (key, text) in calibration.reviews
        name = haskey(PROVIDER_REGISTRY, key) ? PROVIDER_REGISTRY[key].name : key
        push!(parts, "── $name ──\n$text\n")
    end
    push!(parts, "\n═══════ Discussion ═══════\n")
    for (key, text) in discussion.reviews
        name = haskey(PROVIDER_REGISTRY, key) ? PROVIDER_REGISTRY[key].name : key
        push!(parts, "── $name ──\n$text\n")
    end
    history = join(parts, "\n")

    # Determine whether to include the submissions
    reports_only = !config.meta_reads_paper &&
                   !any(k == meta_prov[1] for (k, _) in providers)

    user_msg = if reports_only
        """
## Committee Discussion

$history

---

Please provide your final selection based on the committee's reports above."""
    else
        """
## All Submissions

$bundle

## Committee Discussion

$history

---

Please provide your final selection."""
    end

    system = get_selection_prompt(prompts, :metareview, config, n_submissions;
                                  reports_only=reports_only)
    key, prov = meta_prov

    if reports_only
        _log(config, "  📋 Program chair will not read the submissions (reports-only mode)")
    end
    _log(config, "  ⏳ $(prov.name) making final selection...")
    t0 = time()
    try
        text, tokens = call_llm(prov, system, user_msg;
                                max_tokens=_effective_max_tokens(prov, config))
        dt = round(time() - t0; digits=1)
        _log(config, "  ✅ Final selection complete ($(dt)s, " *
                     "$(tokens.input)+$(tokens.output) tokens)")
        record!(cost, key, tokens.input, tokens.output)
        return text
    catch e
        dt = round(time() - t0; digits=1)
        @warn "$(prov.name) failed writing selection after $(dt)s" exception=e

        # Try fallback
        for (fkey, fprov) in providers
            fkey == key && continue
            _log(config, "  🔄 Falling back to $(fprov.name) for selection...")
            t0 = time()
            try
                text, tokens = call_llm(fprov, system, user_msg;
                                        max_tokens=_effective_max_tokens(fprov, config))
                dt = round(time() - t0; digits=1)
                _log(config, "  ✅ Selection complete via $(fprov.name) ($(dt)s)")
                record!(cost, fkey, tokens.input, tokens.output)
                return text
            catch e2
                @warn "$(fprov.name) also failed" exception=e2
                continue
            end
        end

        @warn "All providers failed for selection. Returning placeholder."
        return "[SELECTION UNAVAILABLE: All providers failed.]"
    end
end
