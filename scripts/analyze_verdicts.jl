#!/usr/bin/env julia
#=
    analyze_verdicts.jl — Compare FeedBackAndForth panel verdicts with ground truth

    Usage (from the Julia REPL, in the package directory):
        include("scripts/analyze_verdicts.jl")
        analyze("/path/to/results", "/path/to/verdicts.txt")

    The verdicts.txt file should have one line per submission:
        110 ACCEPT
        151 REJECT
        ...
=#

# ─── Verdict Scale ───
# Maps textual verdicts to a numerical score.
# Higher = more positive. Scale: 1 (strong reject) to 7 (strong accept).

const VERDICT_MAP = Dict(
    "strong reject"      => 1,
    "reject"             => 2,
    "borderline reject"  => 3,
    "borderline"         => 3.5,
    "weak reject"        => 3,
    "borderline accept"  => 4,
    "weak accept"        => 5,
    "accept"             => 6,
    "strong accept"      => 7,
)

# Threshold: panel verdicts at or above this score count as ACCEPT
const ACCEPT_THRESHOLD = 4.0

"""
    extract_meta_verdict(md_text) -> (verdict_string, score)

Extract the overall recommendation from the Meta-Review section of a
FeedBackAndForth markdown file.
"""
function extract_meta_verdict(md_text::String)
    # Find the Meta-Review section
    meta_start = findlast("## Meta-Review", md_text)
    if isnothing(meta_start)
        return ("not found", missing)
    end
    meta_section = md_text[first(meta_start):end]

    # Stop at Session Info if present
    session_idx = findfirst("## Session Info", meta_section)
    if !isnothing(session_idx)
        meta_section = meta_section[1:first(session_idx)-1]
    end

    meta_lower = lowercase(meta_section)

    # Strategy 1: Look for explicit "Verdict: <X>" or "Recommendation: <X>" lines,
    # then search the captured text for known verdict phrases
    for pattern in [
        r"(?:overall\s+)?verdict[s]?[:\s]*\*{0,2}\s*(.{3,60})"i,
        r"(?:overall\s+)?recommendation[:\s]*\*{0,2}\s*(.{3,60})"i,
        r"(?:final\s+)?(?:verdict|assessment)[:\s]*\*{0,2}\s*(.{3,60})"i,
    ]
        for m in eachmatch(pattern, meta_lower)
            captured = strip(m.captures[1])
            for (phrase, score) in sort(collect(VERDICT_MAP); by=x -> -length(x.first))
                if contains(captured, phrase)
                    return (phrase, score)
                end
            end
        end
    end

    # Strategy 2: Scan the entire meta-review for known verdict phrases,
    # prioritizing longer (more specific) matches
    for (phrase, score) in sort(collect(VERDICT_MAP); by=x -> -length(x.first))
        if contains(meta_lower, phrase)
            return (phrase, score)
        end
    end

    return ("unclear", missing)
end

"""
    extract_individual_verdicts(md_text) -> Dict{String, Vector{Tuple{String, Float64}}}

Extract per-provider verdicts from each round.
Returns a dict: round_label => [(provider, score), ...]
"""
function extract_individual_verdicts(md_text::String)
    results = Dict{String, Vector{Tuple{String, Union{Float64, Missing}}}}()

    # Split into rounds
    round_chunks = split(md_text, r"## Round \d+:")
    for chunk in round_chunks
        # Identify provider sections
        provider_sections = split(chunk, "### ")
        for psection in provider_sections[2:end]  # skip pre-header text
            lines = split(psection, "\n"; limit=2)
            provider = strip(lines[1])
            isempty(provider) && continue

            text = length(lines) > 1 ? lowercase(lines[2]) : ""

            # Look for verdict
            for pattern in [
                r"verdict[:\s]*\*{0,2}\s*([^*\n]+)",
                r"overall assessment[:\s]*\*{0,2}\s*([^*\n]+)",
                r"final recommendation[:\s]*\*{0,2}\s*([^*\n]+)",
            ]
                m = match(pattern, text)
                if !isnothing(m)
                    vstr, vscore = _parse_verdict(strip(m.captures[1]))
                    key = "individual"
                    if !haskey(results, key)
                        results[key] = Tuple{String, Union{Float64, Missing}}[]
                    end
                    push!(results[key], (provider, vscore))
                    break
                end
            end
        end
    end
    return results
end

function _parse_verdict(s::AbstractString)
    s = lowercase(strip(s))
    # Remove trailing punctuation, parentheticals
    s = replace(s, r"\s*\(.*\)\s*$" => "")
    s = replace(s, r"[.!,;]+$" => "")
    s = strip(s)

    # Direct match
    if haskey(VERDICT_MAP, s)
        return (s, VERDICT_MAP[s])
    end

    # Fuzzy match: check if any known verdict is a substring
    for (phrase, score) in sort(collect(VERDICT_MAP); by=x -> -length(x.first))
        if contains(s, phrase)
            return (phrase, score)
        end
    end

    return (s, missing)
end

"""
    load_ground_truth(path) -> Dict{Int, Symbol}

Load ground truth verdicts from a text file.
Expects one verdict per line (ACCEPT or REJECT), ordered by submission number.
Returns a dict mapping submission number to :accept or :reject.

The file format should be like:
    110 ACCEPT
    151 REJECT
or just:
    ACCEPT
    REJECT
(in which case line numbers are inferred from ordering context)
"""
function load_ground_truth(path::String)
    lines = filter(!isempty, strip.(readlines(path)))
    verdicts = Dict{Int, Symbol}()

    for line in lines
        parts = split(strip(line))
        if length(parts) >= 2
            # Format: "N VERDICT" or "EPSA25_full_N VERDICT"
            id_str = parts[1]
            verdict_str = uppercase(parts[end])

            # Extract number from id
            m = match(r"(\d+)", id_str)
            if !isnothing(m)
                num = parse(Int, m.captures[1])
                verdict = verdict_str == "ACCEPT" ? :accept : :reject
                verdicts[num] = verdict
            end
        elseif length(parts) == 1 && uppercase(parts[1]) in ("ACCEPT", "REJECT")
            # Just verdicts, no numbers — we'll handle this separately
            # Store with line index as key (will need re-mapping)
            idx = length(verdicts) + 1
            verdicts[idx] = uppercase(parts[1]) == "ACCEPT" ? :accept : :reject
        end
    end
    return verdicts
end

"""
    extract_submission_number(filename) -> Int

Extract the submission number N from filenames like EPSA25_full_N.md
"""
function extract_submission_number(filename::String)
    bn = basename(filename)
    # Try "full_N" pattern first (e.g., EPSA25_full_110.md)
    m = match(r"full_(\d+)", bn)
    if !isnothing(m)
        return parse(Int, m.captures[1])
    end
    # Fallback: last number in the filename
    m = match(r"(\d+)\.[^.]+$", bn)
    if !isnothing(m)
        return parse(Int, m.captures[1])
    end
    # Last resort: any number
    m = match(r"(\d+)", bn)
    isnothing(m) && error("Cannot extract number from: $bn")
    return parse(Int, m.captures[1])
end

# ─── Main Analysis ───

"""
    analyze(results_dir, verdicts_path; threshold=$ACCEPT_THRESHOLD)

Compare FeedBackAndForth panel verdicts with ground truth.

# Arguments
- `results_dir`: Directory containing the .md result files
- `verdicts_path`: Path to the ground truth verdicts file
- `threshold`: Score at or above which the panel verdict counts as ACCEPT
"""
function analyze(results_dir::String, verdicts_path::String;
                 threshold::Float64=ACCEPT_THRESHOLD)

    # Load ground truth
    gt = load_ground_truth(verdicts_path)
    println("📋 Loaded $(length(gt)) ground truth verdicts\n")

    # Find and process result files
    md_files = filter(f -> endswith(f, ".md"), readdir(results_dir; join=true))
    sort!(md_files; by=f -> extract_submission_number(f))

    # Collect results
    results = NamedTuple{
        (:id, :num, :meta_verdict, :meta_score, :gt_verdict, :match),
        Tuple{String, Int, String, Union{Float64, Missing}, Symbol, Union{Bool, Missing}}
    }[]

    for f in md_files
        num = extract_submission_number(f)
        id = "EPSA25_full_$num"
        md_text = read(f, String)

        verdict_str, verdict_score = extract_meta_verdict(md_text)

        gt_verdict = get(gt, num, :unknown)
        if gt_verdict == :unknown
            @warn "No ground truth for submission $num"
            continue
        end

        # Determine match
        if ismissing(verdict_score)
            is_match = missing
        else
            panel_accept = verdict_score >= threshold
            gt_accept = gt_verdict == :accept
            is_match = panel_accept == gt_accept
        end

        push!(results, (
            id = id, num = num,
            meta_verdict = verdict_str, meta_score = verdict_score,
            gt_verdict = gt_verdict, match = is_match
        ))
    end

    # ─── Display Results ───
    println("="^80)
    println("  VERDICT COMPARISON")
    println("="^80)
    println()

    # Header
    println(rpad("Submission", 20),
            rpad("Ground Truth", 15),
            rpad("Panel Verdict", 22),
            rpad("Score", 8),
            "Match")
    println("─"^80)

    for r in results
        gt_str = r.gt_verdict == :accept ? "ACCEPT" : "REJECT"
        score_str = ismissing(r.meta_score) ? "?" : string(r.meta_score)
        match_str = ismissing(r.match) ? "?" :
                    r.match ? "✅" : "❌"
        println(rpad(r.id, 20),
                rpad(gt_str, 15),
                rpad(r.meta_verdict, 22),
                rpad(score_str, 8),
                match_str)
    end
    println("─"^80)

    # ─── Summary Statistics ───
    valid = filter(r -> !ismissing(r.match), results)
    n_total = length(valid)
    n_correct = count(r -> r.match === true, valid)
    n_accept_gt = count(r -> r.gt_verdict == :accept, valid)
    n_reject_gt = count(r -> r.gt_verdict == :reject, valid)

    # True positives, false positives, etc.
    tp = count(r -> r.gt_verdict == :accept && r.meta_score >= threshold, valid)
    tn = count(r -> r.gt_verdict == :reject && r.meta_score < threshold, valid)
    fp = count(r -> r.gt_verdict == :reject && r.meta_score >= threshold, valid)
    fn = count(r -> r.gt_verdict == :accept && r.meta_score < threshold, valid)

    accuracy = n_total > 0 ? n_correct / n_total : 0.0
    precision_val = (tp + fp) > 0 ? tp / (tp + fp) : 0.0
    recall = (tp + fn) > 0 ? tp / (tp + fn) : 0.0
    f1 = (precision_val + recall) > 0 ?
         2 * precision_val * recall / (precision_val + recall) : 0.0

    println()
    println("="^80)
    println("  SUMMARY")
    println("="^80)
    println()
    println("  Papers analyzed:     $n_total")
    println("  Ground truth:        $n_accept_gt accept, $n_reject_gt reject")
    println("  Threshold:           $(threshold) (≥ counts as ACCEPT)")
    println()
    println("  Accuracy:            $(round(accuracy; digits=3))  ($n_correct / $n_total)")
    println("  Precision (accept):  $(round(precision_val; digits=3))  (TP=$tp, FP=$fp)")
    println("  Recall (accept):     $(round(recall; digits=3))  (TP=$tp, FN=$fn)")
    println("  F1 score:            $(round(f1; digits=3))")
    println()

    # Confusion matrix
    println("  Confusion Matrix:")
    println("                    Panel: ACCEPT   Panel: REJECT")
    println("  GT: ACCEPT        $(lpad(tp, 6))          $(lpad(fn, 6))")
    println("  GT: REJECT        $(lpad(fp, 6))          $(lpad(tn, 6))")
    println()

    # ─── Ordinal Analysis ───
    # How well do the scores track the accept/reject distinction?
    accept_scores = [r.meta_score for r in valid if r.gt_verdict == :accept && !ismissing(r.meta_score)]
    reject_scores = [r.meta_score for r in valid if r.gt_verdict == :reject && !ismissing(r.meta_score)]

    if !isempty(accept_scores) && !isempty(reject_scores)
        println("  Score distribution:")
        println("    Accepted papers:  mean=$(round(mean(accept_scores); digits=2)), " *
                "range=[$(minimum(accept_scores)), $(maximum(accept_scores))]")
        println("    Rejected papers:  mean=$(round(mean(reject_scores); digits=2)), " *
                "range=[$(minimum(reject_scores)), $(maximum(reject_scores))]")

        # Rank-biserial correlation (effect size for ordinal vs binary)
        # = (mean_accept - mean_reject) / pooled range, simplified
        # Or use Mann-Whitney U statistic
        u = 0
        for a in accept_scores, r in reject_scores
            u += (a > r) + 0.5 * (a == r)
        end
        n1, n2 = length(accept_scores), length(reject_scores)
        auc = u / (n1 * n2)
        println("    AUC (accept vs reject): $(round(auc; digits=3))")
        println("    (1.0 = perfect separation, 0.5 = chance)")
    end

    println()
    println("="^80)

    return nothing
end

# Simple mean
mean(x) = sum(x) / length(x)
