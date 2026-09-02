defmodule Keeper.Adapter.Baseten do
  @moduledoc "Baseten Model APIs (OpenAI-compatible) over raw HTTP, streaming. Model ids confirmed via GET /v1/models on 2026-09-02."
  @behaviour Keeper.Adapter

  @impl true
  def complete(req, opts \\ []) do
    Keeper.Adapter.ChatCompletions.complete(req, "https://inference.baseten.co/v1", System.fetch_env!("BASETEN_API_KEY"), :baseten, opts)
  end
end
