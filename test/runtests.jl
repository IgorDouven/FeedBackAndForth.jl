using Test
using FeedBackAndForth

@testset "FeedBackAndForth.jl" begin

    @testset "Provider registry" begin
        provs = list_providers()
        @test haskey(provs, "claude")
        @test haskey(provs, "openai")
        @test haskey(provs, "gemini")
        @test haskey(provs, "deepseek")
        @test haskey(provs, "mistral")

        # All default providers should have pricing info
        for (_, p) in provs
            @test p.cost_per_1k_input >= 0
            @test p.cost_per_1k_output >= 0
        end
    end

    @testset "Custom provider registration" begin
        add_provider!("test_local",
            endpoint="http://localhost:11434/v1/chat/completions",
            model="test-model",
            name="Test Local Model")

        provs = list_providers()
        @test haskey(provs, "test_local")
        @test provs["test_local"].name == "Test Local Model"
        @test FeedBackAndForth.is_local(provs["test_local"])

        remove_provider!("test_local")
        @test !haskey(list_providers(), "test_local")
    end

    @testset "Cost estimation" begin
        # 10k char paper, 3 providers, 2 rounds
        cost = estimate_cost(10_000; n_providers=3, rounds=2)
        @test cost > 0
        @test cost < 5.0  # sanity check: shouldn't be more than a few dollars

        # More rounds = more cost
        cost2 = estimate_cost(10_000; n_providers=3, rounds=3)
        @test cost2 > cost

        # More providers = more cost
        cost3 = estimate_cost(10_000; n_providers=5, rounds=2)
        @test cost3 > cost
    end

    @testset "Cost tracker" begin
        ct = CostTracker()
        FeedBackAndForth.record!(ct, "claude", 1000, 500)
        FeedBackAndForth.record!(ct, "openai", 1200, 600)
        FeedBackAndForth.record!(ct, "claude", 800, 400)

        @test ct.total_input == 3000
        @test ct.total_output == 1500
        @test ct.total_calls == 3
        @test ct.usage["claude"].calls == 2
        @test ct.usage["openai"].calls == 1

        # Estimated cost should be positive
        @test FeedBackAndForth.estimated_cost(ct) > 0

        # Summary should be a string
        s = FeedBackAndForth.cost_summary(ct)
        @test contains(s, "Claude")
        @test contains(s, "GPT-4o")
    end

    @testset "Prompt management" begin
        FeedBackAndForth._prompts_init()
        prompts = FeedBackAndForth.DEFAULT_PROMPTS
        @test haskey(prompts, "review")
        @test haskey(prompts, "discussion")
        @test haskey(prompts, "metareview")
        @test haskey(prompts, "author_response")
        @test haskey(prompts, "review_with_scores")

        # Discussion prompt should substitute round number
        dp = FeedBackAndForth.get_discussion_prompt(prompts, 3, ReviewConfig())
        @test contains(dp, "round 3") || contains(dp, "Round 3")
    end

    @testset "ReviewConfig defaults" begin
        rc = ReviewConfig()
        @test rc.rounds == 2
        @test isempty(rc.providers)
        @test rc.verbose == true
        @test rc.request_scores == false
        @test rc.acceptance_rate == (0.0, 0.0)
        @test isempty(rc.venue)
        @test rc.venue_type == :unspecified
    end

    @testset "Venue context generation" begin
        # No venue info → empty string
        rc = ReviewConfig()
        ctx = FeedBackAndForth._venue_context(rc)
        @test isempty(ctx)

        # Highly selective journal
        rc = ReviewConfig(
            venue="Mind", venue_type=:journal,
            acceptance_rate=(0.05, 0.10)
        )
        ctx = FeedBackAndForth._venue_context(rc)
        @test contains(ctx, "Mind")
        @test contains(ctx, "journal")
        @test contains(ctx, "5–10%")
        @test contains(ctx, "highly selective")

        # Moderate conference
        rc = ReviewConfig(
            venue="EPSA 2025", venue_type=:conference,
            acceptance_rate=(0.55, 0.65)
        )
        ctx = FeedBackAndForth._venue_context(rc)
        @test contains(ctx, "EPSA 2025")
        @test contains(ctx, "conference")
        @test contains(ctx, "55–65%")
        @test contains(ctx, "high acceptance rate") || contains(ctx, "relatively high")

        # Acceptance rate only (no venue name)
        rc = ReviewConfig(acceptance_rate=(0.20, 0.30))
        ctx = FeedBackAndForth._venue_context(rc)
        @test contains(ctx, "20–30%")
        @test contains(ctx, "selective")

        # Venue context gets prepended to review prompt
        FeedBackAndForth._prompts_init()
        prompts = FeedBackAndForth.DEFAULT_PROMPTS
        rc = ReviewConfig(
            venue="Cognitive Science", venue_type=:journal,
            acceptance_rate=(0.15, 0.25)
        )
        rp = FeedBackAndForth.get_review_prompt(prompts, rc)
        @test contains(rp, "Cognitive Science")
        @test contains(rp, "Summary")  # still has the review instructions

        # No venue → prompt is unchanged
        rc_empty = ReviewConfig()
        rp_empty = FeedBackAndForth.get_review_prompt(prompts, rc_empty)
        @test rp_empty == prompts["review"]
    end

end
