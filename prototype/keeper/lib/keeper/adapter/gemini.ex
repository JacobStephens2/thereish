defmodule Keeper.Adapter.Gemini do
  @moduledoc """
  Gemini through Google's OpenAI-compatible endpoint, streaming. Model ids confirmed via GET /v1beta/models on
  2026-09-02. Thinking cannot be turned off on 3.7/3.8 Flash; `reasoning_effort: "low"` is the floor
  (`thinking_level: minimal` is rejected natively). Usage: `completion_tokens` excludes thoughts, `total_tokens`
  includes them, so output is priced as total − prompt.
  """
  @behaviour Keeper.Adapter

  @impl true
  def complete(req, opts \\ []) do
    Keeper.Adapter.ChatCompletions.complete(
      req,
      "https://generativelanguage.googleapis.com/v1beta/openai",
      System.fetch_env!("GEMINI_API_KEY"),
      :gemini,
      opts
    )
  end
end
