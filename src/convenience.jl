# ─────────────────────────────────────────────────────────────────────
# Convenience Functions (Main User-Facing API)
# ─────────────────────────────────────────────────────────────────────

# Ensure prompts are initialized
function _ensure_init()
    isempty(DEFAULT_PROMPTS) && _prompts_init()
end

"""
    _load_paper(path, config) -> String

Load a paper from disk. For `.pdf` files, automatically extracts text
using `pdftotext` (from poppler-utils). All other files are read as text.
"""
function _load_paper(path::String, config::ReviewConfig)
    ext = lowercase(last(splitext(path)))

    if ext == ".pdf"
        return _extract_pdf_text(path, config)
    else
        return read(path, String)
    end
end

"""
    _extract_pdf_text(path, config) -> String

Extract text from a PDF. Tries, in order:
1. `pdftotext` (poppler-utils) — fast, works on text-based PDFs
2. `pdfminer.six` (Python) — handles some PDFs that pdftotext misses
3. OCR via `pdftoppm` + `tesseract` — handles scanned/image-based PDFs
"""
function _extract_pdf_text(path::String, config::ReviewConfig)
    # Try pdftotext first (most robust for text-based PDFs)
    if _has_command("pdftotext")
        _log(config, "   Extracting text from PDF via pdftotext...")
        txt = read(`pdftotext -layout $path -`, String)
        if !isempty(strip(txt))
            return txt
        end
        @warn "pdftotext returned empty output — PDF may be image-based (scanned)."
    end

    # Try python pdfminer.six as fallback
    if _has_command("python3")
        py_script = """
import sys
try:
    from pdfminer.high_level import extract_text
    print(extract_text(sys.argv[1]))
except ImportError:
    sys.exit(1)
"""
        try
            txt = read(`python3 -c $py_script $path`, String)
            if !isempty(strip(txt))
                _log(config, "   Extracted text from PDF via pdfminer.")
                return txt
            end
        catch
            # pdfminer not installed, fall through
        end
    end

    # Try OCR via pdftoppm + tesseract (for scanned PDFs)
    if _has_command("tesseract") && _has_command("pdftoppm")
        _log(config, "   Attempting OCR via tesseract (scanned PDF)...")
        try
            txt = _ocr_pdf(path)
            if !isempty(strip(txt))
                _log(config, "   OCR extracted $(length(txt)) characters.")
                return txt
            end
        catch e
            @warn "OCR failed" exception=e
        end
    end

    error("""
    Cannot extract text from PDF: $path

    This PDF appears to be image-based (scanned). Install OCR tools:
      • tesseract + poppler:  brew install tesseract poppler   (macOS)
                               apt install tesseract-ocr poppler-utils (Linux)

    Or convert the PDF to text manually:
      pdftotext -layout $path $(first(splitext(path))).txt
    """)
end

"""
    _ocr_pdf(path) -> String

OCR a PDF by converting pages to images via `pdftoppm`, then running
`tesseract` on each page. Returns concatenated text.
"""
function _ocr_pdf(path::String)
    mktempdir() do tmpdir
        # Convert PDF pages to PNG images
        run(`pdftoppm -png -r 300 $path $(joinpath(tmpdir, "page"))`)

        # OCR each page image
        pages = sort(filter(f -> endswith(f, ".png"), readdir(tmpdir; join=true)))
        texts = String[]
        for img in pages
            txt = read(`tesseract $img stdout -l eng --psm 6`, String)
            push!(texts, txt)
        end
        return join(texts, "\n\n")
    end
end

function _has_command(cmd::String)
    try
        success(`which $cmd`)
    catch
        false
    end
end

"""
    review(paper_path; rounds=2, providers=String[], meta="",
           scores=false, refereeing=false, detail=1,
           prompts_file="", output="", call_delay=0,
           verbose=true, acceptance_rate=(0.0, 0.0), venue="",
           venue_type=:unspecified) -> ReviewPanel

Run a full review panel session on a paper.

# Arguments
- `paper_path`: Path to the paper (`.tex`, `.txt`, `.md`, etc.)
- `rounds`: Total rounds (1 = independent only, 2 = reviews + 1 discussion, etc.)
- `providers`: Provider keys to use (default: all with available API keys)
- `meta`: Which provider writes the meta-review (default: first in `providers`).
   Can be a provider that is not in `providers`, in which case it acts as an
   independent meta-reviewer that did not participate in the discussion rounds.
- `scores`: Request structured numerical scores alongside prose
- `refereeing`: Include accept/reject recommendations (default: false)
- `detail`: Level of detail (1 = standard, 2 = detailed with concrete citations,
   3 = passage-level commentary). Default: 1
- `call_delay`: Seconds to wait between provider API calls (default: 0). Helps
   avoid rate limits with providers that have low tokens-per-minute caps.
- `prompts_file`: Path to a TOML file with custom prompts
- `output`: Output file path (empty = auto-generate)
- `verbose`: Print progress messages
- `acceptance_rate`: Tuple `(lo, hi)` expressing the venue's acceptance rate
   as proportions, e.g. `(0.10, 0.15)` for 10–15%. Calibrates reviewer strictness.
- `venue`: Name/description of the target venue
- `venue_type`: `:journal`, `:conference`, `:workshop`, or `:unspecified`

# Examples

```julia
using FeedBackAndForth

# Basic usage — auto-detects available providers
panel = review("paper.tex")

# Specific providers, 3 rounds, with scores and refereeing
panel = review("paper.tex", rounds=3,
               providers=["claude", "openai", "deepseek"],
               scores=true, refereeing=true)

# Passage-level detailed review
panel = review("paper.tex", detail=3)

# Calibrated to a selective philosophy journal
panel = review("paper.tex",
    acceptance_rate = (0.05, 0.10),
    venue = "Mind",
    venue_type = :journal
)

# Calibrated to a conference with higher acceptance
panel = review("abstract.tex",
    acceptance_rate = (0.55, 0.65),
    venue = "EPSA 2025",
    venue_type = :conference
)

# With a local model
add_provider!("local_qwen",
    endpoint="http://localhost:11434/v1/chat/completions",
    model="qwen2.5:72b", name="Qwen 2.5 72B (local)")

panel = review("paper.tex", providers=["claude", "openai", "local_qwen"])

# Save results
save_markdown(panel)                   # auto-named .md
save_markdown(panel, "my_review.md")   # custom path
save_json(panel)                       # machine-readable JSON
```
"""
function review(paper_path::AbstractString;
                rounds::Int=2,
                providers::Vector{String}=String[],
                meta::AbstractString="",
                scores::Bool=false,
                refereeing::Bool=false,
                detail::Int=1,
                call_delay::Int=0,
                prompts_file::AbstractString="",
                output::AbstractString="",
                verbose::Bool=true,
                acceptance_rate::Tuple{Real, Real}=(0.0, 0.0),
                venue::AbstractString="",
                venue_type::Symbol=:unspecified)

    _ensure_init()
    t_start = time()

    detail in 1:3 || error("detail must be 1, 2, or 3 (got $detail)")

    config = ReviewConfig(
        rounds=rounds, providers=providers, meta_provider=string(meta),
        request_scores=scores, refereeing=refereeing, detail=detail,
        call_delay=call_delay,
        prompts_file=string(prompts_file),
        verbose=verbose,
        acceptance_rate=Float64.(acceptance_rate),
        venue=string(venue), venue_type=venue_type
    )

    # Load paper
    paper_path = string(paper_path)
    if !isfile(paper_path)
        error("File not found: $paper_path")
    end
    _log(config, "📄 Loading paper: $paper_path")
    paper_text = _load_paper(paper_path, config)
    _log(config, "   $(length(paper_text)) chars, ~$(length(split(paper_text))) words\n")

    # Detect providers
    provs = available_providers(config.providers)
    if length(provs) < 2
        error("Need at least 2 providers with valid API keys. Found: $(length(provs)). " *
              "Set API key environment variables or add local providers with add_provider!().")
    end
    _log(config, "🤖 Panel: $(join([p.name for (_, p) in provs], ", "))\n")

    # Choose meta-reviewer (may be a non-participating provider)
    meta_key = config.meta_provider
    meta_prov = if !isempty(meta_key)
        if any(k == meta_key for (k, _) in provs)
            # Meta-reviewer is one of the panelists
            first(filter(x -> x[1] == meta_key, provs))
        elseif haskey(PROVIDER_REGISTRY, meta_key)
            # Meta-reviewer is a registered but non-participating provider
            p = PROVIDER_REGISTRY[meta_key]
            if !is_local(p) && isempty(get(ENV, p.api_key_env, ""))
                error("Meta-reviewer '$meta_key' requires API key ($(p.api_key_env) not set).")
            end
            _log(config, "📋 Independent meta-reviewer: $(p.name) (not on the panel)\n")
            (meta_key, p)
        else
            error("Unknown meta-reviewer provider '$meta_key'. " *
                  "Register it first with add_provider!().")
        end
    else
        provs[1]
    end

    # Get prompts
    prompts = get_prompts(config)
    cost = CostTracker()
    all_rounds = RoundResult[]

    # Round 1
    _log(config, "═══ Round 1: Independent Reviews ═══")
    rr1 = _run_round1(paper_text, provs, prompts, config, cost)
    push!(all_rounds, rr1)

    # Discussion rounds
    prev_reviews = rr1.reviews
    for r in 2:rounds
        _log(config, "\n═══ Round $r: Discussion ═══")
        rr = _run_discussion(paper_text, prev_reviews, provs, r, prompts, config, cost)
        push!(all_rounds, rr)
        prev_reviews = rr.reviews
    end

    # Meta-review
    _log(config, "\n═══ Meta-Review (by $(meta_prov[2].name)) ═══")
    metareview = _run_metareview(paper_text, all_rounds, provs, meta_prov,
                                 prompts, config, cost)

    total_elapsed = time() - t_start

    panel = ReviewPanel(
        paper_path, length(paper_text), config, provs,
        all_rounds, metareview, meta_prov[1],
        total_elapsed, cost
    )

    # Auto-save if output specified
    if !isempty(output)
        save_markdown(panel, string(output))
        _log(config, "\n📝 Saved to: $output")
    end

    _log(config, "\n" * cost_summary(cost))
    _log(config, "⏱  Total time: $(round(total_elapsed; digits=1))s")

    return panel
end

"""
    review_and_respond(panel::ReviewPanel, response_path::AbstractString;
                       output="", verbose=true) -> ReviewPanel

After running `review()`, feed in your author response and let the
panel evaluate whether you've addressed their concerns.

# Example

```julia
panel = review("paper.tex")
save_markdown(panel, "round1.md")

# ... you write your response in response.txt ...

panel2 = review_and_respond(panel, "response.txt")
save_markdown(panel2, "after_response.md")
```
"""
function review_and_respond(panel::ReviewPanel, response_path::AbstractString;
                            output::AbstractString="", verbose::Bool=true)
    _ensure_init()

    config = deepcopy(panel.config)
    config.verbose = verbose

    if !isfile(response_path)
        error("Response file not found: $response_path")
    end
    response_text = read(string(response_path), String)
    _log(config, "📄 Author response: $(length(response_text)) chars\n")

    paper_text = read(panel.paper_path, String)
    prompts = get_prompts(config)
    cost = deepcopy(panel.cost)

    _log(config, "═══ Author Response Evaluation ═══")
    rr = _run_author_response(paper_text, panel.rounds, panel.metareview,
                               response_text, panel.providers_used,
                               prompts, config, cost)

    # Build updated panel
    all_rounds = vcat(panel.rounds, [rr])

    # New meta-review incorporating the response
    meta_prov = first(filter(x -> x[1] == panel.meta_provider_key,
                              panel.providers_used))
    _log(config, "\n═══ Updated Meta-Review ═══")
    metareview = _run_metareview(paper_text, all_rounds, panel.providers_used,
                                 meta_prov, prompts, config, cost)

    new_panel = ReviewPanel(
        panel.paper_path, panel.paper_length, config, panel.providers_used,
        all_rounds, metareview, panel.meta_provider_key,
        panel.total_elapsed + (time() - time()),  # approximate
        cost
    )

    if !isempty(output)
        save_markdown(new_panel, string(output))
        _log(config, "\n📝 Saved to: $output")
    end

    return new_panel
end

"""
    select(submissions_dir; accept=0, providers=String[], meta="",
           detail=1, prompts_file="", output="", verbose=true,
           acceptance_rate=(0.0, 0.0), venue="", venue_type=:unspecified)
           -> SelectionPanel

Run a batch selection process on a directory of submissions.

A panel of LLMs reads all submissions, calibrates to the overall quality
level, discusses and debates rankings, and produces a final selection.
This mirrors how a real program committee works: read the whole batch first,
then decide.

# Arguments
- `submissions_dir`: Directory containing submissions (`.tex`, `.txt`, `.md`, `.pdf`)
- `accept`: Number of submissions to accept. If 0, derived from `acceptance_rate`.
- `providers`: Provider keys to use (default: all with available API keys)
- `meta`: Which provider makes the final selection (default: first in `providers`).
   Can be a non-participating provider (independent program chair).
- `detail`: Level of detail (1–3) in calibration reports
- `call_delay`: Seconds to wait between provider API calls (default: 0). Recommended
   for `select()` since the large payloads can trigger rate limits.
- `prompts_file`: Path to a TOML file with custom prompts
- `output`: Output file path (empty = auto-generate)
- `verbose`: Print progress messages
- `acceptance_rate`: Tuple `(lo, hi)` as proportions; used to derive `accept` if not set
- `venue`: Name/description of the event
- `venue_type`: `:journal`, `:conference`, `:workshop`, or `:unspecified`

# Examples

```julia
using FeedBackAndForth

# Select 20 submissions for a conference
panel = select("submissions/",
    accept = 20,
    venue = "EPSA 2026",
    venue_type = :conference
)

# Derive accept count from acceptance rate
panel = select("submissions/",
    acceptance_rate = (0.20, 0.30),
    venue = "EPSA 2026",
    venue_type = :conference
)

# With specific providers and an independent program chair
panel = select("submissions/",
    accept = 20,
    providers = ["claude", "gemini"],
    meta = "openai",
    detail = 2
)

save_markdown(panel)
save_json(panel)
```

!!! note "Context window requirements"
    All submissions are sent to each LLM in a single prompt. For large batches
    (e.g., 250 abstracts of 800 words ≈ 200K tokens), use frontier models with
    large context windows (Claude, Gemini). Smaller or local models may not be
    able to handle the full batch.
"""
function select(submissions_dir::AbstractString;
                accept::Int=0,
                providers::Vector{String}=String[],
                meta::AbstractString="",
                detail::Int=1,
                call_delay::Int=0,
                prompts_file::AbstractString="",
                output::AbstractString="",
                verbose::Bool=true,
                acceptance_rate::Tuple{Real, Real}=(0.0, 0.0),
                venue::AbstractString="",
                venue_type::Symbol=:unspecified)

    _ensure_init()
    t_start = time()

    detail in 1:3 || error("detail must be 1, 2, or 3 (got $detail)")
    submissions_dir = string(submissions_dir)
    isdir(submissions_dir) || error("Directory not found: $submissions_dir")

    config = ReviewConfig(
        rounds=2, providers=providers, meta_provider=string(meta),
        request_scores=false, refereeing=true, detail=detail,
        call_delay=call_delay,
        prompts_file=string(prompts_file),
        verbose=verbose,
        acceptance_rate=Float64.(acceptance_rate),
        venue=string(venue), venue_type=venue_type,
        accept=accept
    )

    # Load submissions
    _log(config, "📂 Loading submissions from: $submissions_dir")
    bundle, files, lengths = _load_submissions(submissions_dir, config)
    n_sub = length(files)
    total_chars = sum(lengths)
    _log(config, "   $n_sub submissions, $(total_chars) chars total, " *
                 "~$(total_chars ÷ 4) tokens\n")

    # Determine accept count
    if config.accept <= 0
        lo, hi = config.acceptance_rate
        if lo > 0 || hi > 0
            rate = (lo + hi) / 2
            config.accept = max(1, round(Int, rate * n_sub))
            _log(config, "📊 Target accepts: $(config.accept) " *
                         "($(round(Int, rate*100))% of $n_sub)\n")
        else
            error("Must specify either `accept` (number of submissions to accept) " *
                  "or `acceptance_rate`.")
        end
    else
        _log(config, "📊 Target accepts: $(config.accept) of $n_sub\n")
    end

    # Detect providers
    provs = available_providers(config.providers)
    if length(provs) < 2
        error("Need at least 2 providers. Found: $(length(provs)).")
    end
    _log(config, "🤖 Committee: $(join([p.name for (_, p) in provs], ", "))\n")

    # Choose meta-reviewer (program chair) — same logic as review()
    meta_key = config.meta_provider
    meta_prov = if !isempty(meta_key)
        if any(k == meta_key for (k, _) in provs)
            first(filter(x -> x[1] == meta_key, provs))
        elseif haskey(PROVIDER_REGISTRY, meta_key)
            p = PROVIDER_REGISTRY[meta_key]
            if !is_local(p) && isempty(get(ENV, p.api_key_env, ""))
                error("Program chair '$meta_key' requires API key ($(p.api_key_env) not set).")
            end
            _log(config, "📋 Independent program chair: $(p.name) (not on the committee)\n")
            (meta_key, p)
        else
            error("Unknown provider '$meta_key'. Register it first with add_provider!().")
        end
    else
        provs[1]
    end

    prompts = get_prompts(config)
    cost = CostTracker()

    # Phase 1: Calibration
    _log(config, "═══ Phase 1: Calibration ═══")
    calibration = _run_calibration(bundle, provs, prompts, config, n_sub, cost)

    # Phase 2: Discussion
    _log(config, "\n═══ Phase 2: Committee Discussion ═══")
    discussion = _run_selection_discussion(bundle, calibration.reviews, provs,
                                           prompts, config, n_sub, cost)

    # Phase 3: Final Selection
    _log(config, "\n═══ Phase 3: Final Selection (by $(meta_prov[2].name)) ═══")
    selection = _run_selection_metareview(bundle, calibration, discussion, provs,
                                          meta_prov, prompts, config, n_sub, cost)

    total_elapsed = time() - t_start

    panel = SelectionPanel(
        submissions_dir, files, lengths, config.accept, config, provs,
        calibration, discussion, selection, meta_prov[1],
        total_elapsed, cost
    )

    if !isempty(output)
        save_markdown(panel, string(output))
        _log(config, "\n📝 Saved to: $output")
    end

    _log(config, "\n" * cost_summary(cost))
    _log(config, "⏱  Total time: $(round(total_elapsed; digits=1))s")

    return panel
end
