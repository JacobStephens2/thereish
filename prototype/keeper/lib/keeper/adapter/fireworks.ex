defmodule Keeper.Adapter.Fireworks do
  @moduledoc """
  Fireworks serverless inference (OpenAI-compatible), streaming. Model id confirmed via GET /inference/v1/models on
  2026-09-02. `reasoning_effort` accepts none / low / max on DeepSeek V4 Flash 0731 (probed); thoughts stream in
  `delta.reasoning_content` and are counted in `completion_tokens` (`completion_tokens_details.reasoning_tokens`).
  """
  @behaviour Keeper.Adapter

  @impl true
  def complete(req, opts \\ []) do
    Keeper.Adapter.ChatCompletions.complete(req, "https://api.fireworks.ai/inference/v1", System.fetch_env!("FIREWORKS_API_KEY"), :fireworks, opts)
  end
end
