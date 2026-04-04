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

    @testset "set_model!" begin
        old_model = list_providers()["gemini"].model
        old_name = list_providers()["gemini"].name
        set_model!("gemini", "gemini-2.5-pro")
        @test list_providers()["gemini"].model == "gemini-2.5-pro"
        # Display name should update to reflect new model
        @test contains(list_providers()["gemini"].name, "gemini-2.5-pro")
        @test contains(list_providers()["gemini"].name, "Google")
        # Restore original
        set_model!("gemini", old_model)
        @test list_providers()["gemini"].model == old_model
        # Unknown provider should error
        @test_throws ErrorException set_model!("nonexistent", "some-model")
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
        @test rc.refereeing == false
        @test rc.acceptance_rate == (0.0, 0.0)
        @test isempty(rc.venue)
        @test rc.venue_type == :unspecified
    end

    @testset "Refereeing prompt selection" begin
        FeedBackAndForth._prompts_init()
        prompts = FeedBackAndForth.DEFAULT_PROMPTS

        # Default (no refereeing) — no verdict language
        rc = ReviewConfig()
        rp = FeedBackAndForth.get_review_prompt(prompts, rc)
        @test !contains(rp, "strong accept")
        @test !contains(rp, "verdict")
        @test contains(rp, "Do not provide an accept/reject")

        # With refereeing — verdict language present
        rc_ref = ReviewConfig(refereeing=true)
        rp_ref = FeedBackAndForth.get_review_prompt(prompts, rc_ref)
        @test contains(rp_ref, "strong accept")
        @test contains(rp_ref, "verdict")

        # Scores + no refereeing — scores present, no verdict
        rc_scores = ReviewConfig(request_scores=true)
        rp_scores = FeedBackAndForth.get_review_prompt(prompts, rc_scores)
        @test contains(rp_scores, "Novelty:")
        @test !contains(rp_scores, "strong accept")
        @test contains(rp_scores, "Do not provide an accept/reject")

        # Scores + refereeing — both present
        rc_both = ReviewConfig(request_scores=true, refereeing=true)
        rp_both = FeedBackAndForth.get_review_prompt(prompts, rc_both)
        @test contains(rp_both, "Novelty:")
        @test contains(rp_both, "strong accept")

        # Meta-review without refereeing — no "Overall recommendation" task
        mp = FeedBackAndForth.get_metareview_prompt(prompts, rc)
        @test !contains(mp, "Overall recommendation")
        @test contains(mp, "Do not provide an accept/reject")

        # Meta-review with refereeing — recommendation present
        mp_ref = FeedBackAndForth.get_metareview_prompt(prompts, rc_ref)
        @test contains(mp_ref, "Overall recommendation")

        # Author response prompts
        @test !contains(prompts["author_response_no_verdict"], "verdict")
        @test !contains(prompts["author_response_no_verdict"], "Final verdict")
        @test contains(prompts["author_response"], "verdict")
    end

    @testset "Detail level" begin
        FeedBackAndForth._prompts_init()
        prompts = FeedBackAndForth.DEFAULT_PROMPTS

        # Default detail=1 produces no extra instructions
        rc1 = ReviewConfig()
        @test rc1.detail == 1
        rp1 = FeedBackAndForth.get_review_prompt(prompts, rc1)
        @test !contains(rp1, "passage-level")
        @test !contains(rp1, "Quote a short excerpt")

        # Detail=2 adds concrete citation instructions
        rc2 = ReviewConfig(detail=2)
        rp2 = FeedBackAndForth.get_review_prompt(prompts, rc2)
        @test contains(rp2, "Cite the specific section")
        @test contains(rp2, "concrete improvement")
        dp2 = FeedBackAndForth.get_discussion_prompt(prompts, 2, rc2)
        @test contains(dp2, "cite specific sections")
        mp2 = FeedBackAndForth.get_metareview_prompt(prompts, rc2)
        @test contains(mp2, "actionable")

        # Detail=3 adds passage-level commentary
        rc3 = ReviewConfig(detail=3)
        rp3 = FeedBackAndForth.get_review_prompt(prompts, rc3)
        @test contains(rp3, "passage-level")
        @test contains(rp3, "Quote a short excerpt")
        dp3 = FeedBackAndForth.get_discussion_prompt(prompts, 2, rc3)
        @test contains(dp3, "passage-level commentary")
        mp3 = FeedBackAndForth.get_metareview_prompt(prompts, rc3)
        @test contains(mp3, "section-by-section")

        # Detail composes with other options (scores, venue)
        rc_combo = ReviewConfig(detail=3, request_scores=true,
                                venue="Mind", venue_type=:journal)
        rp_combo = FeedBackAndForth.get_review_prompt(prompts, rc_combo)
        @test contains(rp_combo, "Novelty:")       # scores
        @test contains(rp_combo, "Mind")            # venue
        @test contains(rp_combo, "passage-level")   # detail

        # Cost estimation scales with detail
        c1 = estimate_cost(10_000; n_providers=3, rounds=2, detail=1)
        c2 = estimate_cost(10_000; n_providers=3, rounds=2, detail=2)
        c3 = estimate_cost(10_000; n_providers=3, rounds=2, detail=3)
        @test c2 > c1
        @test c3 > c2
    end

    @testset "Selection prompts" begin
        FeedBackAndForth._prompts_init()
        prompts = FeedBackAndForth.DEFAULT_PROMPTS

        # Selection prompts should exist
        @test haskey(prompts, "selection_calibration")
        @test haskey(prompts, "selection_discussion")
        @test haskey(prompts, "selection_metareview")

        # Prompt substitution
        rc = ReviewConfig(accept=15)
        sp = FeedBackAndForth.get_selection_prompt(prompts, :calibration, rc, 50)
        @test contains(sp, "50")   # N_SUBMISSIONS
        @test contains(sp, "15")   # N_ACCEPT
        @test !contains(sp, "{N_SUBMISSIONS}")
        @test !contains(sp, "{N_ACCEPT}")

        # Discussion and metareview prompts also substitute
        dp = FeedBackAndForth.get_selection_prompt(prompts, :discussion, rc, 50)
        @test contains(dp, "50")
        mp = FeedBackAndForth.get_selection_prompt(prompts, :metareview, rc, 50)
        @test contains(mp, "15")

        # Venue context gets prepended
        rc_venue = ReviewConfig(accept=10, venue="EPSA 2026",
                                venue_type=:conference,
                                acceptance_rate=(0.20, 0.30))
        sp_venue = FeedBackAndForth.get_selection_prompt(prompts, :calibration,
                                                         rc_venue, 40)
        @test contains(sp_venue, "EPSA 2026")
        @test contains(sp_venue, "Read all submissions")  # still has calibration text

        # Detail levels for selection
        rc_d2 = ReviewConfig(accept=10, detail=2)
        sp_d2 = FeedBackAndForth.get_selection_prompt(prompts, :calibration,
                                                       rc_d2, 20)
        @test contains(sp_d2, "Cite specific")

        rc_d3 = ReviewConfig(accept=10, detail=3)
        sp_d3 = FeedBackAndForth.get_selection_prompt(prompts, :calibration,
                                                       rc_d3, 20)
        @test contains(sp_d3, "passage-level")
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
        @test rp_empty == prompts["review_no_verdict"]

        # Venue context with refereeing includes verdict calibration
        rc_ref = ReviewConfig(
            venue="Mind", venue_type=:journal,
            acceptance_rate=(0.05, 0.10), refereeing=true
        )
        ctx_ref = FeedBackAndForth._venue_context(rc_ref)
        @test contains(ctx_ref, "positive verdict")

        # Venue context without refereeing omits verdict calibration
        rc_noref = ReviewConfig(
            venue="Mind", venue_type=:journal,
            acceptance_rate=(0.05, 0.10), refereeing=false
        )
        ctx_noref = FeedBackAndForth._venue_context(rc_noref)
        @test !contains(ctx_noref, "positive verdict")
        @test contains(ctx_noref, "highly selective")
    end

end
