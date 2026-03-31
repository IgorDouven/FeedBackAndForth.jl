# ─────────────────────────────────────────────────────────────────────
# Prompt Management
# ─────────────────────────────────────────────────────────────────────

const DEFAULT_PROMPTS = Dict{String, String}()

function _init_default_prompts!()
    DEFAULT_PROMPTS["review"] = """
You are a rigorous but constructive academic reviewer. You have deep expertise \
across the sciences, formal methods, philosophy, and computational approaches. \
Provide a thorough, structured review of the paper you are given. Cover:

1. **Summary**: A concise summary of the paper's main contribution(s).
2. **Strengths**: What the paper does well (novelty, methodology, clarity, etc.).
3. **Weaknesses**: Substantive issues, gaps, or unclear points.
4. **Minor issues**: Writing, notation, presentational suggestions.
5. **Questions for the authors**: Specific points you'd like clarified.
6. **Overall assessment**: A brief verdict (e.g., strong accept / accept / \
weak accept / borderline / weak reject / reject) with justification.

Be specific: cite sections, equations, or page numbers where possible. \
Be honest but collegial."""

    DEFAULT_PROMPTS["review_with_scores"] = """
You are a rigorous but constructive academic reviewer. You have deep expertise \
across the sciences, formal methods, philosophy, and computational approaches. \
Provide a thorough, structured review of the paper you are given. Cover:

1. **Summary**: A concise summary of the paper's main contribution(s).
2. **Strengths**: What the paper does well (novelty, methodology, clarity, etc.).
3. **Weaknesses**: Substantive issues, gaps, or unclear points.
4. **Minor issues**: Writing, notation, presentational suggestions.
5. **Questions for the authors**: Specific points you'd like clarified.
6. **Scores** (rate each on a scale of 1–10):
   - Novelty: [score]
   - Methodology: [score]
   - Clarity: [score]
   - Significance: [score]
   - Overall: [score]
7. **Overall assessment**: A brief verdict (e.g., strong accept / accept / \
weak accept / borderline / weak reject / reject) with justification.

Be specific: cite sections, equations, or page numbers where possible. \
Be honest but collegial."""

    DEFAULT_PROMPTS["discussion"] = """
You are participating in round {ROUND} of a multi-reviewer discussion \
panel for an academic paper. You have already submitted your initial review, \
and you have now received the reviews of other panelists (who are other AI \
models from different providers).

Your task:
1. **Respond to the other reviews**: Do you agree or disagree with specific \
points? Are there issues they raised that you missed, or vice versa?
2. **Revise your assessment**: Based on the discussion, update your own review. \
You may strengthen, weaken, or refine your earlier points.
3. **Identify consensus and disagreement**: Note where the panel agrees and \
where genuine disagreements remain.
4. **Rate the other reviews**: Briefly note which reviews you found most \
insightful and why.

Be specific and substantive. Avoid generic agreement — engage with the \
actual arguments. If you change your mind on something, say so explicitly."""

    DEFAULT_PROMPTS["metareview"] = """
You are the meta-reviewer (area chair) for this paper. You have access to the \
paper itself and to the full discussion among the review panel (multiple AI \
models from different providers). Your task:

1. **Synthesize**: Summarize the key points of agreement and disagreement.
2. **Adjudicate**: Where reviewers disagree, give your own assessment of who \
has the stronger argument.
3. **Consolidate feedback**: Produce a single, prioritized list of the most \
important issues the authors should address.
4. **Overall recommendation**: Give a final recommendation with justification, \
weighing the panel's collective input.
5. **Meta-observations**: Note if certain models contributed distinctive \
insights that others missed — this is useful for understanding model diversity.

Be concise but thorough. The goal is an actionable summary for the authors."""

    DEFAULT_PROMPTS["author_response"] = """
You are participating in a follow-up round of a multi-reviewer discussion \
panel. The authors have now responded to the panel's feedback. Your task:

1. **Evaluate the response**: Did the authors adequately address your concerns \
and those of the other reviewers?
2. **Identify remaining issues**: Are there concerns that were deflected or \
inadequately addressed?
3. **Update your assessment**: Based on the authors' response, would you \
change your recommendation? State explicitly if your verdict changes.
4. **Final verdict**: Provide your updated recommendation with justification.

Be fair but rigorous. Give credit where authors have addressed issues \
substantively, but flag unresolved problems clearly."""
end

"""
    load_prompts(path::String) -> Dict{String, String}

Load custom prompts from a TOML file. The file should have keys matching
the default prompt names: `review`, `discussion`, `metareview`, `author_response`.

Any keys not present in the file will fall back to defaults.

# Example TOML file

```toml
[prompts]
review = \"\"\"
You are reviewing a paper in experimental psychology.
Focus especially on statistical methodology and effect sizes.
...
\"\"\"
```
"""
function load_prompts(path::String)
    if !isfile(path)
        error("Prompts file not found: $path")
    end
    data = TOML.parsefile(path)
    prompts = copy(DEFAULT_PROMPTS)
    if haskey(data, "prompts")
        for (k, v) in data["prompts"]
            prompts[string(k)] = string(v)
        end
    end
    return prompts
end

"""
    get_prompts(config::ReviewConfig) -> Dict{String, String}

Return the active prompt set based on the configuration.
"""
function get_prompts(config::ReviewConfig)
    if !isempty(config.prompts_file)
        return load_prompts(config.prompts_file)
    else
        return copy(DEFAULT_PROMPTS)
    end
end

function get_review_prompt(prompts::Dict, config::ReviewConfig)
    base = config.request_scores ? prompts["review_with_scores"] : prompts["review"]
    ctx = _venue_context(config)
    return isempty(ctx) ? base : ctx * "\n\n" * base
end

function get_discussion_prompt(prompts::Dict, round_num::Int, config::ReviewConfig)
    base = replace(prompts["discussion"], "{ROUND}" => string(round_num))
    ctx = _venue_context(config)
    return isempty(ctx) ? base : ctx * "\n\n" * base
end

function get_metareview_prompt(prompts::Dict, config::ReviewConfig)
    base = prompts["metareview"]
    ctx = _venue_context(config)
    return isempty(ctx) ? base : ctx * "\n\n" * base
end

"""
    _venue_context(config) -> String

Build a preamble paragraph describing the venue, acceptance rate, and
what this implies for the reviewing standard. Returns "" if no venue
info is configured.
"""
function _venue_context(config::ReviewConfig)
    parts = String[]

    # Venue description
    if !isempty(config.venue)
        vtype = config.venue_type == :journal    ? "journal" :
                config.venue_type == :conference  ? "conference" :
                config.venue_type == :workshop    ? "workshop" : "venue"
        push!(parts, "You are reviewing for $(config.venue) (a $vtype).")
    end

    # Acceptance rate
    lo, hi = config.acceptance_rate
    if lo > 0 || hi > 0
        lo_pct = round(Int, lo * 100)
        hi_pct = round(Int, hi * 100)
        if lo_pct == hi_pct || hi == 0
            rate_str = "approximately $(max(lo_pct, hi_pct))%"
        else
            rate_str = "approximately $(lo_pct)–$(hi_pct)%"
        end
        push!(parts, "The acceptance rate for this venue is $rate_str.")

        # Calibration guidance
        if hi <= 0.15
            push!(parts, "This is a highly selective venue. Apply rigorous standards: " *
                         "only papers making a clear, significant contribution should " *
                         "receive a positive verdict. Acceptable papers must demonstrate " *
                         "novelty, methodological soundness, and substantial significance.")
        elseif hi <= 0.30
            push!(parts, "This is a selective venue. Papers should demonstrate clear " *
                         "merit in terms of novelty and execution to warrant acceptance.")
        elseif hi <= 0.50
            push!(parts, "This venue has a moderate acceptance rate. Sound papers with " *
                         "a clear contribution should be accepted, but raise concerns " *
                         "about any significant weaknesses.")
        elseif hi <= 0.70
            push!(parts, "This venue has a relatively high acceptance rate. Focus your " *
                         "review on whether the paper meets basic standards of quality " *
                         "and makes a reasonable contribution to the field.")
        else
            push!(parts, "This venue has a high acceptance rate. Focus on identifying " *
                         "fundamental flaws; papers meeting basic quality standards " *
                         "should generally be accepted.")
        end
    end

    return join(parts, " ")
end

# Initialize on load
function _prompts_init()
    _init_default_prompts!()
end
