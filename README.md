# FeedBackAndForth.jl

A Julia package for multi-LLM iterative paper review. Assembles a diverse panel of large language models from different providers, has them independently review your paper, then orchestrates discussion rounds where they respond to each other's critiques. Produces a synthesized meta-review with consolidated feedback.

## Motivation

Getting feedback on a paper from a single LLM can be surprisingly useful. But just as human peer review benefits from multiple independent reviewers, LLM-based review benefits from *diverse* models — different providers have different training data, RLHF procedures, and architectural biases, producing less correlated critiques. FeedBackAndForth automates this process: independent reviews → cross-model discussion → meta-review synthesis.

The design draws on insights from the crowd wisdom literature, where aggregation benefits increase with the diversity and partial independence of individual judgments.

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/IgorDouven/FeedBackAndForth.jl")
```

## API Keys & Costs

FeedBackAndForth calls cloud LLM providers via their APIs. Most providers require a paid account with API credits. You will need API keys from **at least two** of the following:

| Provider | Sign up | Approximate cost per paper |
|----------|---------|---------------------------|
| [OpenAI](https://platform.openai.com) | Pay-as-you-go | ~$0.08 |
| [Anthropic](https://console.anthropic.com) | Pay-as-you-go | ~$0.07 |
| [Google Gemini](https://aistudio.google.com) | Free tier available | ~$0.002 |
| [DeepSeek](https://platform.deepseek.com) | Pay-as-you-go | ~$0.002 |
| [Mistral](https://console.mistral.ai) | Pay-as-you-go | ~$0.06 |

Costs shown are approximate, for a typical 8000-word paper with 2 rounds. A full panel of 5 providers costs roughly $0.20–0.30 per paper. Use `estimate_cost()` to get a projection before running.

**Budget-friendly option:** Gemini and DeepSeek are nearly free. Combined with a local model via Ollama (completely free), you can run a 3-model panel at essentially zero cost.

**Local models** (via Ollama, LM Studio, or vLLM) require no API key and no credits — see "Including Local Models" below.

Set your API keys as environment variables in your shell configuration (e.g., `~/.zshrc` or `~/.bashrc`):

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
export OPENAI_API_KEY="sk-..."
export GOOGLE_API_KEY="..."
export DEEPSEEK_API_KEY="sk-..."
export MISTRAL_API_KEY="..."
```

The package auto-detects which keys are available and uses only those providers.

## Quick Start

```julia
using FeedBackAndForth

# Run a review panel (auto-detects available providers)
panel = review("my_paper.tex")

# Calibrate to a specific venue
panel = review("my_paper.tex",
    venue = "Cognitive Science",
    venue_type = :journal,
    acceptance_rate = (0.15, 0.25)
)

# Save results
save_markdown(panel)           # auto-named Markdown file
save_json(panel)               # machine-readable JSON
```

## Usage

### Basic Review

```julia
# Specific providers, 3 rounds
panel = review("paper.tex",
    rounds = 3,
    providers = ["claude", "openai", "deepseek"]
)

# Request numerical scores alongside prose reviews
panel = review("paper.tex", scores=true)

# Include accept/reject recommendations (referee mode)
panel = review("paper.tex", refereeing=true)

# Custom meta-reviewer (from the panel)
# By default, the first provider in the list writes the meta-review.
panel = review("paper.tex", meta="deepseek")

# Independent meta-reviewer (not on the panel)
# This provider reads the paper and all discussion rounds fresh,
# without having committed to positions during the discussion —
# similar to an area chair in real peer review.
panel = review("paper.tex",
    providers = ["gemma", "phi", "qwen"],
    meta = "claude"
)
```

### Venue Calibration

Reviewers implicitly calibrate their standards to the venue — a paper that merits acceptance at a conference with a 60% acceptance rate may not pass muster at a journal that accepts 8%. FeedBackAndForth makes this explicit via the `acceptance_rate` and `venue` parameters:

```julia
# Highly selective philosophy journal
panel = review("paper.tex",
    venue = "Mind",
    venue_type = :journal,
    acceptance_rate = (0.05, 0.10)
)

# Selective interdisciplinary journal
panel = review("paper.tex",
    venue = "Cognitive Science",
    venue_type = :journal,
    acceptance_rate = (0.15, 0.25)
)

# Conference with moderate acceptance rate
panel = review("abstract.tex",
    venue = "EPSA 2025",
    venue_type = :conference,
    acceptance_rate = (0.55, 0.65)
)

# Workshop (high acceptance rate)
panel = review("abstract.tex",
    venue = "PhilML Workshop",
    venue_type = :workshop,
    acceptance_rate = (0.70, 0.80)
)
```

The acceptance rate is specified as a tuple of proportions `(lo, hi)` giving a range. The package translates this into calibration instructions for the reviewers: venues below 15% trigger highly rigorous standards, while venues above 50% prompt reviewers to focus on basic quality and clear contribution. The venue name and type (`:journal`, `:conference`, `:workshop`) are included in the reviewer instructions to provide additional context.

If no acceptance rate is specified, the reviewers default to a generic standard roughly corresponding to a mid-range journal.

### Refereeing Mode

By default, reviews focus on constructive feedback — strengths, weaknesses, questions — without accept/reject verdicts. To include accept/reject recommendations (as in a formal referee report), set `refereeing=true`:

```julia
# Full referee mode with venue calibration
panel = review("paper.tex",
    refereeing = true,
    venue = "Mind",
    venue_type = :journal,
    acceptance_rate = (0.05, 0.10)
)
```

When `refereeing=true`, each review includes an overall assessment verdict (strong accept / accept / weak accept / borderline / weak reject / reject), the meta-review includes an overall recommendation, and venue calibration guidance is phrased in terms of acceptance standards. When `refereeing=false` (the default), the same review structure is produced but without verdict language — useful when you want diagnostic feedback rather than a simulated editorial decision.

### Detail Levels

By default, reviews provide a high-level structured assessment. The `detail` option (1–3) asks reviewers to ground their feedback more concretely in the text of the paper:

```julia
# Standard review (default)
panel = review("paper.tex", detail=1)

# Detailed: reviewers cite specific sections, explain issues concretely,
# and suggest specific improvements
panel = review("paper.tex", detail=2)

# Passage-level: reviewers quote short excerpts from the paper and comment
# on each one, working through the paper section by section
panel = review("paper.tex", detail=3)
```

- **Level 1** (default): The standard structured review — summary, strengths, weaknesses, questions, and overall assessment.
- **Level 2**: Same structure, but reviewers are asked to cite specific sections/equations, explain each issue concretely, and suggest concrete improvements. Produces roughly 1.5–2× more output.
- **Level 3**: Adds a **passage-level commentary** section where reviewers quote short excerpts verbatim and comment on each, classified as `[strength]`, `[weakness]`, `[clarity]`, `[suggestion]`, or `[question]`. This aims for 10–25 individual passage-level comments, followed by the usual structured review. Produces roughly 2.5–3× more output.

Detail composes freely with all other options:

```julia
panel = review("paper.tex",
    detail = 3, scores = true, refereeing = true,
    venue = "Mind", venue_type = :journal,
    acceptance_rate = (0.05, 0.10)
)
```

**Token limits are scaled automatically**: at higher detail levels, the maximum output tokens sent to each provider are scaled up (1.8× for level 2, 3× for level 3) so that models have room to produce longer reviews without truncation. This applies to both cloud and local providers.

### Including Local Models

Any Ollama, LM Studio, vLLM, or llama.cpp server works out of the box — they all serve an OpenAI-compatible API:

```julia
# Ollama (default port 11434)
add_provider!("local_qwen",
    endpoint = "http://localhost:11434/v1/chat/completions",
    model = "qwen2.5:72b",
    name = "Qwen 2.5 72B (local)"
)

# LM Studio (default port 1234)
add_provider!("local_llama",
    endpoint = "http://localhost:1234/v1/chat/completions",
    model = "meta-llama-3.1-70b",
    name = "LLaMA 3.1 70B (local)"
)

# Now use them alongside cloud providers
panel = review("paper.tex",
    providers = ["claude", "openai", "local_qwen", "local_llama"]
)
```

Local models have zero API cost, which is useful for both budget-conscious reviews and for studying the cloud/local performance gap.

**Note on `max_tokens`**: Local providers default to `max_tokens=4096` (vs 8192 for cloud providers). The package automatically scales this up at higher detail levels, but if you find reviews are being truncated, you can set a higher base value when registering:

```julia
add_provider!("local_qwen",
    endpoint = "http://localhost:11434/v1/chat/completions",
    model = "qwen2.5:72b",
    name = "Qwen 2.5 72B (local)",
    max_tokens = 8192
)
```

### Author Response Cycle

After receiving feedback, write your response and let the panel evaluate it:

```julia
panel = review("paper.tex")
save_markdown(panel, "initial_review.md")

# ... write your response in response.txt ...

panel2 = review_and_respond(panel, "response.txt")
save_markdown(panel2, "after_response.md")
```

### Custom Prompts

Adapt the review criteria to your discipline via a TOML file:

```julia
panel = review("paper.tex",
    prompts_file = "prompts/philosophy_of_science.toml"
)
```

See `prompts/philosophy_of_science.toml` for the template.

### Cost Estimation

Before running, estimate the cost:

```julia
# For a 40,000-character paper with 3 providers and 2 rounds
estimate_cost(40_000; n_providers=3, rounds=2)  # returns USD

# Account for higher detail level
estimate_cost(40_000; n_providers=3, rounds=2, detail=3)

# After running, inspect actual usage
panel.cost  # shows per-provider token counts and costs
```

### Batch Processing

To review multiple papers (e.g., for an empirical evaluation):

```julia
using FeedBackAndForth

abstracts = readdir("abstracts"; join=true)
filter!(f -> endswith(f, ".tex"), abstracts)

for f in abstracts
    id = first(splitext(basename(f)))
    panel = review(f,
        acceptance_rate = (0.55, 0.65),
        venue = "EPSA 2025",
        venue_type = :conference,
        rounds = 2, scores = true
    )
    save_json(panel, "results/$(id).json")
    save_markdown(panel, "results/$(id).md")
end
```

## Pipeline

**Review** (`review()`):
```
Round 1:  Each LLM independently reviews the paper
   ↓
Round 2+: Each LLM reads all other reviews and responds
   ↓
  (...)   Additional discussion rounds (configurable)
   ↓
Meta:     One LLM synthesizes the full discussion
   ↓
Output:   Markdown transcript + JSON for analysis
```

**Batch Selection** (`select()`):
```
Phase 1:  Each LLM reads ALL submissions, tiers and ranks them
   ↓
Phase 2:  Committee members debate, focusing on borderline cases
   ↓
Phase 3:  Program chair produces the final accept/reject list
   ↓
Output:   Markdown transcript + JSON for analysis
```

## Supported Providers

| Key        | Provider        | Model (default)          | API format          |
|------------|-----------------|--------------------------|---------------------|
| `claude`   | Anthropic       | claude-sonnet-4-20250514 | Anthropic Messages  |
| `openai`   | OpenAI          | gpt-4o                   | OpenAI Chat         |
| `gemini`   | Google          | gemini-2.5-flash         | Google GenAI        |
| `deepseek` | DeepSeek        | deepseek-chat            | OpenAI-compatible   |
| `mistral`  | Mistral         | mistral-large-latest     | OpenAI-compatible   |
| *(custom)* | Ollama / vLLM / LM Studio / ... | any           | OpenAI-compatible   |

### Batch Selection

For conference organizers: `select()` evaluates a directory of submissions as a batch, rather than reviewing papers individually. The LLM panel first reads *all* submissions to calibrate to the overall quality level, then discusses and debates rankings, and finally produces a selection — mirroring how a real program committee works.

```julia
# Select submissions for a conference (specify target number of accepts)
panel = select("submissions/",
    accept = 50,
    venue = "EPSA 2026",
    venue_type = :conference
)

# Or derive the accept count from an acceptance rate
panel = select("submissions/",
    acceptance_rate = (0.20, 0.30),
    venue = "EPSA 2026",
    venue_type = :conference
)

# With specific providers and an independent program chair
panel = select("submissions/",
    accept = 50,
    providers = ["claude", "gemini"],
    meta = "openai",
    detail = 2
)

save_markdown(panel)
save_json(panel)
```

The three-phase pipeline:
1. **Calibration**: Each LLM reads all submissions, forms an overall quality impression, and assigns tiers (Strong Accept / Accept / Borderline / Reject / Strong Reject) with a ranked list.
2. **Discussion**: The committee members see each other's tierings, debate borderline cases, and revise their rankings.
3. **Final Selection**: The program chair (meta-reviewer) produces the definitive accept/reject list with justifications.

**Rate limits**: Because `select()` sends large payloads, some providers with low tokens-per-minute caps (e.g., OpenAI, Mistral) may return rate limit errors. Use `call_delay=60` to add a pause (in seconds) between provider calls:

```julia
panel = select("submissions/",
    accept = 20,
    providers = ["openai", "gemini", "deepseek"],
    call_delay = 60
)
```

The `call_delay` option also works with `review()`.

**Context window requirements**: All submissions are sent to each LLM in a single prompt. This works well for typical conference scenarios (e.g., 250 extended abstracts of ~800 words ≈ 200K tokens), but requires frontier models with large context windows (Claude, Gemini). Local models and smaller cloud models will likely not be able to handle large batches. For very large conferences (1000+ submissions), this approach is currently not feasible due to context window limits.

### Changing Models

To use a different model for any built-in provider, use `set_model!`:

```julia
# Switch Gemini to the Pro model
set_model!("gemini", "gemini-2.5-pro")

# Use a different Claude model
set_model!("claude", "claude-opus-4-20250514")

# Use a different OpenAI model
set_model!("openai", "gpt-4.1")
```

This keeps all other provider settings (endpoint, API key, pricing) intact. To see the current providers and their models, use `list_providers()`.

## Tips

- **PDF and LaTeX both work**: PDF files are automatically detected and converted to text via `pdftotext` (install with `brew install poppler` on macOS or via the appropriate package manager on Linux distributions). LaTeX source is often even better, since models can see `\cite{}` references, equation structure, and section labels. If your paper uses `\input{}`, flatten it first with `latexpand main.tex > paper.tex`. **Note:** When reviewing `.tex` files, the models see raw LaTeX source, so their reviews may quote LaTeX markup (e.g., `\emph{...}`, `\cite{...}`, equation environments). This is expected and generally useful — the LaTeX references make it easier to locate the passages being discussed. If you prefer cleaner output, consider converting your paper to plain text first.
- **Always specify the venue**: Without an acceptance rate, reviewers default to a generic mid-range journal standard, which may be too strict for conferences or too lenient for top journals.
- **Start with 2 rounds**: In our experience, verdicts stabilize quickly. Additional rounds add cost but may not change assessments substantially — though this is itself an empirical question worth studying.
- **Mix cloud and local**: Including local models is free and adds diversity. Even if a local model is weaker overall, it may catch issues that cloud models miss.

## Citation

If you use FeedBackAndForth in your research, please cite:

```bibtex
@software{feedbackandforth,
  author = {Douven, Igor},
  title = {FeedBackAndForth.jl: Multi-LLM Iterative Paper Review},
  year = {2026},
  url = {https://github.com/IgorDouven/FeedBackAndForth.jl}
}
```

## License

MIT
