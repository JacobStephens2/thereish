defmodule Keeper.Bench do
  @moduledoc "One Assayer call, measured. Used by the assay and bench tasks; no retries so latency numbers stay honest."

  alias Keeper.{Hedge, Prompts, Schema}

  def call(cfg, item, order, hedge \\ 1) do
    {p1, p2} = if order == :forward, do: {item.a, item.b}, else: {item.b, item.a}
    req = Prompts.assay(item.anchors, p1, p2)
    t0 = System.monotonic_time(:millisecond)

    outcome =
      try do
        Hedge.race(hedge, fn -> Schema.generate(cfg, req, &Prompts.check_verdict/1, 0) end)
      rescue
        e -> {:error, {:transport, Exception.message(e)}, []}
      end

    case outcome do
      {:ok, r, _} ->
        %{ok: true, ttft: r.timings.ttft_ms, total: r.timings.total_ms, out: r.usage[:output_tokens] || 0, closeness: r.json["closeness"], reasoning: r.json["reasoning"], cost: r.cost, wall: System.monotonic_time(:millisecond) - t0}

      {:error, why, _} ->
        %{ok: false, why: inspect(why) |> String.slice(0, 300), wall: System.monotonic_time(:millisecond) - t0}
    end
  end

  def parse_candidates(nil), do: Map.keys(Keeper.Config.candidates()) |> Enum.sort()
  def parse_candidates(str), do: str |> String.split(",", trim: true) |> Enum.map(&String.to_atom(String.trim(&1)))

  def cfg(name, fake?) do
    c = Keeper.Config.candidate(name)
    if fake?, do: Keeper.Config.fake(c), else: c
  end

  def fmt(nil), do: "n/a"
  def fmt(v) when is_float(v), do: :erlang.float_to_binary(v, decimals: 1)
  def fmt(v), do: to_string(v)
end
