defmodule Keeper.Adapter do
  @moduledoc """
  The internal seam between the Keeper and any language-model provider.

  A request is provider-neutral:
    %{role, model, system, user, schema, schema_name, max_tokens, effort, fallbacks}
  A result is provider-neutral too:
    %{text, json, usage, timings: %{ttft_ms, total_ms}, model, stop_reason, cost, meta}
  """

  @type request :: map()
  @type result :: map()

  @callback complete(request, keyword) :: {:ok, result} | {:error, term}

  @doc "Shared tail for every adapter: decode JSON, price the call, print the one-line summary, record it."
  def finish(req, st) do
    text = IO.iodata_to_binary(st.text)
    usage = st.usage
    model = st.model || req.model
    cost = Keeper.Config.cost(model, usage)

    json =
      if req[:schema] && text != "" do
        case Jason.decode(text) do
          {:ok, map} when is_map(map) -> map
          _ -> nil
        end
      end

    result = %{
      text: text,
      json: json,
      usage: usage,
      timings: %{ttft_ms: st.ttft_ms, total_ms: st.total_ms},
      model: model,
      stop_reason: st.stop_reason,
      cost: cost,
      meta: Map.drop(st, [:text, :usage, :model, :stop_reason, :ttft_ms, :total_ms, :t0, :raw, :sse_buf])
    }

    Keeper.Ledger.record(req, result)
    result
  end

  def put_if(map, _key, nil), do: map
  def put_if(map, _key, false), do: map
  def put_if(map, key, value), do: Map.put(map, key, value)
end
