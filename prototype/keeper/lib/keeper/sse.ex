defmodule Keeper.SSE do
  @moduledoc "Incremental Server-Sent Events parser. Feed chunks, get complete events back plus the leftover buffer."

  @doc "feed(buffer, chunk) -> {events, rest}. An event is %{event: name | nil, data: joined data lines}."
  def feed(buffer, chunk) do
    parts = String.split(buffer <> chunk, ~r/\r?\n\r?\n/)
    {complete, [rest]} = Enum.split(parts, -1)
    events = complete |> Enum.map(&parse/1) |> Enum.reject(&is_nil/1)
    {events, rest}
  end

  defp parse(block) do
    block
    |> String.split(~r/\r?\n/)
    |> Enum.reduce(%{event: nil, data: []}, fn line, acc ->
      cond do
        String.starts_with?(line, ":") -> acc
        String.starts_with?(line, "event:") -> %{acc | event: line |> String.replace_prefix("event:", "") |> String.trim()}
        String.starts_with?(line, "data:") -> %{acc | data: acc.data ++ [line |> String.replace_prefix("data:", "") |> String.trim_leading()]}
        true -> acc
      end
    end)
    |> case do
      %{data: []} -> nil
      %{event: ev, data: data} -> %{event: ev, data: Enum.join(data, "\n")}
    end
  end
end
