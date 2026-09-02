defmodule Keeper.Ledger do
  @moduledoc "Every model call in one place: one printed line each (never the key), a running tally, and an append-only PROTOTYPE-calls.log."

  @log "PROTOTYPE-calls.log"

  def start do
    case Process.whereis(__MODULE__) do
      nil ->
        {:ok, _} = Agent.start(fn -> [] end, name: __MODULE__)
        :ok

      _ ->
        :ok
    end
  end

  def record(req, result) do
    line =
      "[#{req[:role] || :call}] #{result.model} ttft=#{ms(result.timings.ttft_ms)} total=#{ms(result.timings.total_ms)} " <>
        "in=#{result.usage[:input_tokens]} out=#{result.usage[:output_tokens]} $#{usd(result.cost)} stop=#{result.stop_reason}"

    unless Process.get(:keeper_quiet), do: IO.puts(line)
    File.write(@log, "#{DateTime.to_iso8601(DateTime.utc_now())} #{line}\n", [:append])

    if Process.whereis(__MODULE__) do
      Agent.update(__MODULE__, &[%{role: req[:role], model: result.model, cost: result.cost, usage: result.usage} | &1])
    end

    :ok
  end

  def calls, do: if(Process.whereis(__MODULE__), do: Agent.get(__MODULE__, & &1), else: [])

  def summary do
    calls = calls()

    by_model =
      calls
      |> Enum.group_by(& &1.model)
      |> Enum.map(fn {m, cs} -> {m, length(cs), Enum.sum(Enum.map(cs, & &1.cost))} end)
      |> Enum.sort_by(fn {_, _, c} -> -c end)

    IO.puts("\n== spend this run: $#{usd(Enum.sum(Enum.map(calls, & &1.cost)))} over #{length(calls)} calls ==")
    for {m, n, c} <- by_model, do: IO.puts("   #{String.pad_trailing(m, 24)} #{String.pad_leading(to_string(n), 4)} calls  $#{usd(c)}")
    :ok
  end

  def ms(nil), do: "n/a"
  def ms(v), do: "#{v}ms"
  def usd(v), do: :erlang.float_to_binary(v / 1, decimals: 5)
end
