defmodule Keeper.Adapter.Together do
  @moduledoc """
  Together AI serverless (OpenAI-compatible), streaming. Model id `moonshotai/Kimi-K3` is from Together's own
  serverless-models page (2026-09-02); confirm live with `GET https://api.together.xyz/v1/models` before the first run.
  Kimi K3 always reasons; top-level `reasoning_effort` takes low / high / max (default max); thoughts are billed as output.
  Needs TOGETHER_AI_API_KEY in the environment (it was not in the vaulted-agent manifest when this was written).
  """
  @behaviour Keeper.Adapter

  @impl true
  def complete(req, opts \\ []) do
    Keeper.Adapter.ChatCompletions.complete(req, "https://api.together.xyz/v1", System.fetch_env!("TOGETHER_AI_API_KEY"), :together, opts)
  end
end
