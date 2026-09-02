defmodule Keeper.Adapter.OpenAI do
  @moduledoc "OpenAI chat completions over raw HTTP, streaming."
  @behaviour Keeper.Adapter

  @impl true
  def complete(req, opts \\ []) do
    Keeper.Adapter.ChatCompletions.complete(req, "https://api.openai.com/v1", System.fetch_env!("OPENAI_API_KEY"), :openai, opts)
  end
end
