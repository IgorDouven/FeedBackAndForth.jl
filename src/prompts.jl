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

    DEFAULT_PROMPTS["review_no_verdict"] = """
You are a rigorous but constructive academic reviewer. You have deep expertise \
across the sciences, formal methods, philosophy, and computational approaches. \
Provide a thorough, structured review of the paper you are given. Cover:

1. **Summary**: A concise summary of the paper's main contribution(s).
2. **Strengths**: What the paper does well (novelty, methodology, clarity, etc.).
3. **Weaknesses**: Substantive issues, gaps, or unclear points.
4. **Minor issues**: Writing, notation, presentational suggestions.
5. **Questions for the authors**: Specific points you'd like clarified.

Be specific: cite sections, equations, or page numbers where possible. \
Be honest but collegial. Do not provide an accept/reject recommendation."""

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

    DEFAULT_PROMPTS["review_with_scores_no_verdict"] = """
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

Be specific: cite sections, equations, or page numbers where possible. \
Be honest but collegial. Do not provide an accept/reject recommendation."""

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

    DEFAULT_PROMPTS["metareview_no_verdict"] = """
You are the meta-reviewer for this paper. You have access to the paper itself \
and to the full discussion among the review panel (multiple AI models from \
different providers). Your task:

1. **Synthesize**: Summarize the key points of agreement and disagreement.
2. **Adjudicate**: Where reviewers disagree, give your own assessment of who \
has the stronger argument.
3. **Consolidate feedback**: Produce a single, prioritized list of the most \
important issues the authors should address.
4. **Meta-observations**: Note if certain models contributed distinctive \
insights that others missed — this is useful for understanding model diversity.

Be concise but thorough. The goal is an actionable summary for the authors. \
Do not provide an accept/reject recommendation."""

    DEFAULT_PROMPTS["metareview_reports_only"] = """
You are the meta-reviewer (area chair) for this paper. You have NOT read the \
paper itself — you are basing your assessment entirely on the review panel's \
reports and discussion (from multiple AI models from different providers), \
much like a handling editor who relies on referee reports. Your task:

1. **Synthesize**: Summarize the key points of agreement and disagreement \
among the reviewers.
2. **Adjudicate**: Where reviewers disagree, assess who has the stronger \
argument based on the reasoning and evidence presented in their reports.
3. **Consolidate feedback**: Produce a single, prioritized list of the most \
important issues the authors should address, as reported by the reviewers.
4. **Overall recommendation**: Give a final recommendation with justification, \
weighing the panel's collective input.
5. **Meta-observations**: Note if certain models contributed distinctive \
insights that others missed — this is useful for understanding model diversity.

Be concise but thorough. The goal is an actionable summary for the authors. \
Since you have not read the paper, ground your synthesis in what the reviewers \
report rather than making independent claims about the paper's content."""

    DEFAULT_PROMPTS["metareview_reports_only_no_verdict"] = """
You are the meta-reviewer for this paper. You have NOT read the paper itself — \
you are basing your assessment entirely on the review panel's reports and \
discussion (from multiple AI models from different providers), much like a \
handling editor who relies on referee reports. Your task:

1. **Synthesize**: Summarize the key points of agreement and disagreement \
among the reviewers.
2. **Adjudicate**: Where reviewers disagree, assess who has the stronger \
argument based on the reasoning and evidence presented in their reports.
3. **Consolidate feedback**: Produce a single, prioritized list of the most \
important issues the authors should address, as reported by the reviewers.
4. **Meta-observations**: Note if certain models contributed distinctive \
insights that others missed — this is useful for understanding model diversity.

Be concise but thorough. The goal is an actionable summary for the authors. \
Since you have not read the paper, ground your synthesis in what the reviewers \
report rather than making independent claims about the paper's content. \
Do not provide an accept/reject recommendation."""

    DEFAULT_PROMPTS["selection_metareview_reports_only"] = """
You are the program chair making the final selection. You have NOT read the \
submissions yourself — you are basing your decisions entirely on the committee \
members' calibration reports and discussion (from multiple AI models). \
Approximately {N_ACCEPT} submissions can be accepted.

Your task:
1. **Final selection**: List every submission with a clear **Accept** or \
**Reject** decision.
2. **Brief justification**: For each submission, provide a 2–3 sentence \
justification based on what the committee members reported.
3. **Borderline commentary**: For submissions near the boundary, explain \
what tipped the decision and note any dissent among committee members.
4. **Summary**: Provide a brief overall summary of the selection \
(common strengths of accepted submissions, common weaknesses of \
rejected ones, and any themes or observations about the batch).

Present the accepted submissions first (ranked by strength), then the \
rejected submissions. Be decisive, fair, and transparent. Ground your \
reasoning in the committee's reports rather than making independent claims \
about the submissions."""

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

    DEFAULT_PROMPTS["author_response_no_verdict"] = """
You are participating in a follow-up round of a multi-reviewer discussion \
panel. The authors have now responded to the panel's feedback. Your task:

1. **Evaluate the response**: Did the authors adequately address your concerns \
and those of the other reviewers?
2. **Identify remaining issues**: Are there concerns that were deflected or \
inadequately addressed?
3. **Update your assessment**: Based on the authors' response, has your \
overall evaluation of the paper changed? Explain how and why.

Be fair but rigorous. Give credit where authors have addressed issues \
substantively, but flag unresolved problems clearly. \
Do not provide an accept/reject recommendation."""

    # ── Selection (batch) prompts ──

    DEFAULT_PROMPTS["selection_calibration"] = """
You are a program committee member tasked with selecting submissions for \
an academic event. You will read {N_SUBMISSIONS} submissions. \
Approximately {N_ACCEPT} can be accepted.

Your task:
1. **Read all submissions carefully** and form an overall impression of \
the batch: the average quality level, the spread in quality, and any \
clusters of topics or approaches.
2. **Tier every submission** into one of: **Strong Accept**, **Accept**, \
**Borderline**, **Reject**, **Strong Reject**.
3. **Provide a brief rationale** (2–3 sentences) for each submission's tier.
4. **Rank all submissions** from strongest to weakest.

Reference submissions by their label (e.g., "Submission 1: filename"). \
Be calibrated: your accept tiers should roughly match the target number \
of acceptances. Be fair, constructive, and specific."""

    DEFAULT_PROMPTS["selection_discussion"] = """
You are participating in a program committee discussion. You have already \
read all {N_SUBMISSIONS} submissions and produced your own tiering. You \
have now received the tierings and rankings of the other committee members \
(who are other AI models from different providers).

Your task:
1. **Compare rankings**: Where do you agree and disagree with other \
committee members? Focus especially on submissions where tierings differ.
2. **Debate borderline cases**: For submissions near the accept/reject \
boundary, make your case — why should a particular submission be included \
or excluded?
3. **Revise your ranking**: Based on the discussion, update your tier \
assignments and overall ranking.
4. **Identify consensus**: Note which submissions everyone agrees on \
(clear accepts and clear rejects) and which remain contentious.

Be specific and substantive. Reference submissions by label. Engage with \
the actual arguments rather than deferring generically."""

    DEFAULT_PROMPTS["selection_metareview"] = """
You are the program chair making the final selection. You have access to \
all {N_SUBMISSIONS} submissions and to the full committee discussion \
(calibration reports and debate from multiple AI models). \
Approximately {N_ACCEPT} submissions can be accepted.

Your task:
1. **Final selection**: List every submission with a clear **Accept** or \
**Reject** decision.
2. **Brief justification**: For each submission, provide a 2–3 sentence \
justification for your decision.
3. **Borderline commentary**: For submissions near the boundary, explain \
what tipped the decision and note any dissent among committee members.
4. **Summary**: Provide a brief overall summary of the selection \
(common strengths of accepted submissions, common weaknesses of \
rejected ones, and any themes or observations about the batch).

Present the accepted submissions first (ranked by strength), then the \
rejected submissions. Be decisive, fair, and transparent."""
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
    key = if config.request_scores
        config.refereeing ? "review_with_scores" : "review_with_scores_no_verdict"
    else
        config.refereeing ? "review" : "review_no_verdict"
    end
    base = prompts[key]
    ctx = _venue_context(config)
    detail = _detail_instructions(config.detail, :review)
    prompt = isempty(ctx) ? base : ctx * "\n\n" * base
    return isempty(detail) ? prompt : prompt * detail
end

function get_discussion_prompt(prompts::Dict, round_num::Int, config::ReviewConfig)
    base = replace(prompts["discussion"], "{ROUND}" => string(round_num))
    ctx = _venue_context(config)
    detail = _detail_instructions(config.detail, :discussion)
    prompt = isempty(ctx) ? base : ctx * "\n\n" * base
    return isempty(detail) ? prompt : prompt * "\n\n" * detail
end

function get_metareview_prompt(prompts::Dict, config::ReviewConfig;
                               reports_only::Bool=false)
    key = if reports_only
        config.refereeing ? "metareview_reports_only" : "metareview_reports_only_no_verdict"
    else
        config.refereeing ? "metareview" : "metareview_no_verdict"
    end
    base = prompts[key]
    ctx = _venue_context(config)
    phase = reports_only ? :metareview_reports_only : :metareview
    detail = _detail_instructions(config.detail, phase)
    prompt = isempty(ctx) ? base : ctx * "\n\n" * base
    return isempty(detail) ? prompt : prompt * "\n\n" * detail
end

function get_selection_prompt(prompts::Dict, phase::Symbol,
                              config::ReviewConfig, n_submissions::Int;
                              reports_only::Bool=false)
    key = phase == :calibration ? "selection_calibration" :
          phase == :discussion  ? "selection_discussion" :
          reports_only          ? "selection_metareview_reports_only" :
                                  "selection_metareview"
    base = replace(replace(prompts[key],
                   "{N_SUBMISSIONS}" => string(n_submissions)),
                   "{N_ACCEPT}" => string(config.accept))
    ctx = _venue_context(config)
    detail_phase = phase == :calibration ? :selection_calibration :
                   phase == :discussion  ? :selection_discussion :
                                           :selection_metareview
    detail = _detail_instructions(config.detail, detail_phase)
    prompt = isempty(ctx) ? base : ctx * "\n\n" * base
    return isempty(detail) ? prompt : prompt * "\n\n" * detail
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

        # Calibration guidance (only when refereeing)
        if config.refereeing
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
        else
            if hi <= 0.15
                push!(parts, "This is a highly selective venue. Apply rigorous standards " *
                             "and evaluate the paper's novelty, methodology, and significance " *
                             "accordingly.")
            elseif hi <= 0.30
                push!(parts, "This is a selective venue. Evaluate the paper with high " *
                             "expectations for novelty and execution.")
            elseif hi <= 0.50
                push!(parts, "This venue has a moderate acceptance rate. Evaluate the paper " *
                             "for clear contributions while noting any significant weaknesses.")
            elseif hi <= 0.70
                push!(parts, "This venue has a relatively high acceptance rate. Focus your " *
                             "review on whether the paper meets basic standards of quality " *
                             "and makes a reasonable contribution to the field.")
            else
                push!(parts, "This venue has a high acceptance rate. Focus on identifying " *
                             "fundamental flaws rather than minor issues.")
            end
        end
    end

    return join(parts, " ")
end

"""
    _detail_instructions(detail::Int, phase::Symbol) -> String

Return additional prompt instructions for the given detail level and phase.
`phase` is one of `:review`, `:discussion`, or `:metareview`.
Level 1 returns "" (the default behavior). Levels 2 and 3 add progressively
more specific instructions asking reviewers to ground their feedback in the
text of the paper.
"""
function _detail_instructions(detail::Int, phase::Symbol)
    detail <= 1 && return ""

    if phase == :review
        if detail == 2
            return """

## Additional instructions — detailed feedback

Go beyond high-level observations. For every strength or weakness you identify:
- **Cite the specific section, theorem, figure, or equation** you are referring to.
- **Explain concretely** what the issue is (e.g., an unstated assumption, a gap in \
the argument, an ambiguous definition) rather than giving a generic label.
- **Suggest a concrete improvement** where possible (e.g., "Theorem 2 would benefit \
from an explicit statement of the regularity conditions" rather than "some assumptions \
are missing").
- For clarity issues, give an example of a sentence or passage that confused you \
and explain why.

Aim for a review that the authors can act on point-by-point."""
        else  # detail == 3
            return """

## Additional instructions — passage-level commentary

Provide **passage-level feedback**: work through the paper from beginning to end and \
comment on specific passages where you see issues or noteworthy contributions. For each:
- **Quote a short excerpt** (one or two sentences) from the paper verbatim.
- **Comment** on that excerpt: explain the problem, the strength, the ambiguity, \
or the suggestion.
- **Classify** each comment as one of: [strength], [weakness], [clarity], [suggestion], \
[question].

After the passage-level commentary, provide your usual structured review (summary, \
strengths, weaknesses, questions, assessment). The passage-level section should come \
first and constitute the bulk of the review.

Aim to cover every major section of the paper. Be thorough: a good passage-level \
review typically produces 10–25 individual comments depending on paper length."""
        end

    elseif phase == :discussion
        if detail == 2
            return """

When responding to other reviews and updating your assessment, remain concrete: \
cite specific sections, equations, or passages from the paper. If you agree or \
disagree with another reviewer's point, explain *why* with reference to the text."""
        else  # detail == 3
            return """

When responding to other reviews and updating your assessment, continue to provide \
passage-level commentary where relevant. If another reviewer's point draws your \
attention to a passage you overlooked, quote the passage and give your own assessment. \
If you disagree with another reviewer's reading of a specific passage, quote it and \
explain your interpretation."""
        end

    elseif phase == :metareview
        if detail == 2
            return """

When synthesizing the panel's feedback, be concrete: reference specific sections \
and issues from the paper, not just the reviewers' labels. The consolidated feedback \
list should be actionable at the level of specific passages or results."""
        else  # detail == 3
            return """

When synthesizing the panel's feedback, organize the consolidated feedback around \
specific passages and sections of the paper. Where multiple reviewers commented on \
the same passage, note the convergence or divergence. Quote key passages that were \
points of contention. The goal is a meta-review the authors can use as a \
section-by-section revision guide."""
        end

    elseif phase == :metareview_reports_only
        if detail == 2
            return """

When synthesizing the panel's feedback, be concrete: reference specific sections \
and issues as described by the reviewers. The consolidated feedback \
list should be actionable based on what the reviewers report."""
        else  # detail == 3
            return """

When synthesizing the panel's feedback, organize the consolidated feedback around \
specific passages and sections as cited by the reviewers. Where multiple reviewers \
commented on the same aspect, note the convergence or divergence. Quote key excerpts \
from the reviews that highlight points of contention. The goal is a meta-review the \
authors can use as a revision guide, grounded in the reviewers' reports."""
        end

    # ── Selection (batch) phases ──

    elseif phase == :selection_calibration
        if detail == 2
            return """

For each submission, go beyond a generic assessment. Cite specific claims, \
results, or methodological choices that justify your tier assignment. Where \
a submission has weaknesses, identify them concretely (e.g., "the argument \
in Section 2 relies on an unstated assumption")."""
        else  # detail == 3
            return """

For each submission, provide passage-level notes: quote a key sentence or \
two and comment on what makes it strong or weak. Your rationale for each \
tier assignment should reference specific text from the submission. Aim \
for 3–5 passage-level comments per submission."""
        end

    elseif phase == :selection_discussion
        if detail == 2
            return """

When debating borderline cases, cite specific passages or claims from the \
submissions to support your argument. If you disagree with another committee \
member's assessment, explain why with reference to the text."""
        else  # detail == 3
            return """

When debating borderline cases, quote specific passages from the submissions \
and provide your reading of them. If another committee member's assessment \
hinges on a particular passage, quote it and give your own interpretation."""
        end

    elseif phase == :selection_metareview
        if detail == 2
            return """

In your justifications, reference specific strengths or weaknesses from \
the submissions rather than giving generic assessments. For borderline \
decisions, cite the specific factors that tipped the balance."""
        else  # detail == 3
            return """

For each submission, quote a key passage that exemplifies its main strength \
or weakness. For borderline decisions, quote the specific passages that were \
points of contention among committee members and explain how you weighed them."""
        end

    else
        return ""
    end
end

# Initialize on load
function _prompts_init()
    _init_default_prompts!()
end
