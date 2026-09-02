defmodule Keeper.Config do
  @moduledoc """
  PROTOTYPE. One map decides which model plays which role; swapping a role is one line.
  Prices are $ per million tokens {input, output}, from each provider's pricing page on 2026-09-02.
  """

  alias Keeper.Adapter.{Anthropic, Baseten, Fake, Fireworks, Gemini, OpenAI, Together}

  @roles %{
    # Author: frontier tier, unattended, latency irrelevant (design law 13).
    # 32_000 was not enough: at "max" the clover Page thinks past the cap (see REPORT.md Q1), so 100_000.
    author: %{adapter: Anthropic, model: "claude-fable-5-1", effort: "max", max_tokens: 100_000, fallbacks: true},
    # A/B arm for the Author: OpenAI's top effort for this model is "xhigh" (no "max"; verified 2026-09-02).
    author_b: %{adapter: OpenAI, model: "gpt-5.6-sol", effort: "xhigh", max_tokens: 32_000},
    # Assayer: the model policy's v1 pick; thinking cannot be disabled on GLM 5.3, "low" is the floor.
    assayer: %{adapter: Baseten, model: "zai-org/GLM-5.3-Flash", effort: "low", max_tokens: 160},
    # Scribe: same as the Author.
    scribe: %{adapter: Anthropic, model: "claude-fable-5-1", effort: "max", max_tokens: 8_000, fallbacks: true}
  }

  # The Assayer bench compares these. Anthropic max_tokens leaves room for adaptive thinking at "low".
  @assayer_candidates %{
    glm: %{adapter: Baseten, model: "zai-org/GLM-5.3-Flash", effort: "low", max_tokens: 160},
    sonnet: %{adapter: Anthropic, model: "claude-sonnet-5", effort: "low", max_tokens: 400},
    opus: %{adapter: Anthropic, model: "claude-opus-5", effort: "low", max_tokens: 400},
    luna: %{adapter: OpenAI, model: "gpt-5.6-luna", effort: "low", max_tokens: 400},
    # Added 2026-09-02 at Jacob's suggestion; thinking floor is "low" on both.
    gemini37: %{adapter: Gemini, model: "gemini-3.7-flash", effort: "low", max_tokens: 400},
    gemini38: %{adapter: Gemini, model: "gemini-3.8-flash", effort: "low", max_tokens: 400},
    # Added 2026-09-02 at Jacob's suggestion ("DeepSeek V4 Flash 0731 (max)"); the low and none arms are for comparison.
    # Reasoning tokens count against max_tokens, so the max arm gets room to think.
    deepseek_max: %{adapter: Fireworks, model: "accounts/fireworks/models/deepseek-v4-flash-0731", effort: "max", max_tokens: 4_000},
    deepseek_low: %{adapter: Fireworks, model: "accounts/fireworks/models/deepseek-v4-flash-0731", effort: "low", max_tokens: 1_000},
    deepseek_none: %{adapter: Fireworks, model: "accounts/fireworks/models/deepseek-v4-flash-0731", effort: "none", max_tokens: 400},
    # Jacob's ask (2026-09-02): "Kimi K3 max". Not yet run: TOGETHER_AI_API_KEY was not injected into the session.
    kimi_max: %{adapter: Together, model: "moonshotai/Kimi-K3", effort: "max", max_tokens: 8_000},
    kimi_low: %{adapter: Together, model: "moonshotai/Kimi-K3", effort: "low", max_tokens: 2_000}
  }

  @prices %{
    "claude-fable-5-1" => {10.0, 50.0},
    "claude-opus-5" => {5.0, 25.0},
    "claude-opus-4-8" => {5.0, 25.0},
    "claude-sonnet-5" => {2.0, 10.0},
    "zai-org/GLM-5.3-Flash" => {0.15, 0.50},
    "gpt-5.6-sol" => {4.0, 20.0},
    "gpt-5.6-luna" => {0.20, 1.20},
    # Google's promotional rate through 2026-12-31 ($1.50 / $7.50 after); output includes thinking tokens.
    "gemini-3.7-flash" => {0.75, 3.75},
    "gemini-3.8-flash" => {0.75, 3.75},
    # Fireworks serverless standard tier; reasoning tokens are in completion_tokens.
    "accounts/fireworks/models/deepseek-v4-flash-0731" => {0.22, 0.66},
    # Together serverless; thinking billed as output.
    "moonshotai/Kimi-K3" => {3.0, 15.0},
    "fake" => {0.0, 0.0}
  }

  def role(name), do: Map.fetch!(@roles, name)
  def candidates, do: @assayer_candidates
  def candidate(name), do: Map.fetch!(@assayer_candidates, name)
  def fake(cfg), do: %{cfg | adapter: Fake, model: "fake"}

  def price(model), do: Map.get(@prices, model, {0.0, 0.0})

  @doc "Dollar cost of one call from its usage map."
  def cost(model, usage) do
    {pin, pout} = price(model)
    input = Map.get(usage, :input_tokens, 0) || 0
    output = Map.get(usage, :output_tokens, 0) || 0
    input / 1.0e6 * pin + output / 1.0e6 * pout
  end
end
