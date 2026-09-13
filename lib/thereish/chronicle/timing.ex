defmodule Thereish.Chronicle.Timing do
  @moduledoc """
  Interprets recorded Page occurrence times into a duration breakdown.

  Exact totals end at the final reveal. Legacy Pages that only have
  opened-to-closed times are estimates; missing phase boundaries stay
  unavailable rather than being inferred from insert timestamps.
  """

  alias Thereish.Chronicle.Page

  @type phase :: %{kind: :exact | :unavailable, ms: integer() | nil}

  @type t :: %{
          id: Ecto.UUID.t(),
          room_slug: String.t() | nil,
          opened_at: DateTime.t(),
          closed_at: DateTime.t(),
          revealed_at: DateTime.t() | nil,
          attempts_count: non_neg_integer(),
          melded?: boolean(),
          closed_because: String.t(),
          outcome: :early_meld | :fifth_attempt_meld | :exhausted,
          kind: :exact | :estimate,
          total_ms: integer() | nil,
          phases: %{
            give_entry: phase(),
            generation: phase(),
            bridge_writing: phase(),
            assayer_beat: phase(),
            reveal_pauses: phase()
          }
        }

  @doc "A duration readout for one closed Page."
  @spec view(Page.t()) :: t()
  def view(%Page{} = page) do
    attempts = Enum.sort_by(page.attempts || [], & &1.number)
    gives = Enum.sort_by(page.gives || [], & &1.order)
    revealed_at = page.revealed_at || last_revealed(attempts)
    kind = if revealed_at, do: :exact, else: :estimate
    end_at = revealed_at || page.closed_at

    %{
      id: page.id,
      room_slug: page.room && page.room.slug,
      opened_at: page.opened_at,
      closed_at: page.closed_at,
      revealed_at: revealed_at,
      attempts_count: length(attempts),
      melded?: page.melded,
      closed_because: page.closed_because,
      outcome: outcome(page, attempts),
      kind: kind,
      total_ms: diff_ms(page.opened_at, end_at),
      phases: %{
        give_entry: give_entry(page, gives),
        generation: generation(gives, attempts),
        bridge_writing: span_sum(attempts, :started_at, :assaying_started_at),
        assayer_beat: span_sum(attempts, :assaying_started_at, :revealed_at),
        reveal_pauses: reveal_pauses(attempts)
      }
    }
  end

  @doc "The last Attempt reveal among recorded occurrence times."
  @spec last_revealed([map()]) :: DateTime.t() | nil
  def last_revealed(attempts) when is_list(attempts) do
    attempts
    |> Enum.map(&revealed_at/1)
    |> Enum.filter(&match?(%DateTime{}, &1))
    |> List.last()
  end

  defp revealed_at(%{revealed_at: time}), do: time
  defp revealed_at(%{"revealed_at" => time}), do: time
  defp revealed_at(_), do: nil

  @doc "A short label for how the Page ended."
  @spec outcome_label(t()) :: String.t()
  def outcome_label(%{outcome: :early_meld, attempts_count: n}), do: "Meld on attempt #{n}"
  def outcome_label(%{outcome: :fifth_attempt_meld}), do: "Meld on attempt 5"
  def outcome_label(%{outcome: :exhausted, attempts_count: n}), do: "#{n} attempts, unmelded"
  def outcome_label(%{outcome: :exhausted}), do: "Attempts exhausted"

  @doc "Formats a millisecond duration for the operator readout."
  @spec format_ms(integer() | nil) :: String.t()
  def format_ms(nil), do: "unavailable"
  def format_ms(ms) when is_integer(ms) and ms < 0, do: "unavailable"

  def format_ms(ms) when is_integer(ms) and ms < 1_000 do
    "#{ms}ms"
  end

  def format_ms(ms) when is_integer(ms) and ms < 60_000 do
    seconds = ms / 1_000

    if seconds == trunc(seconds) do
      "#{trunc(seconds)}s"
    else
      :erlang.float_to_binary(seconds, decimals: 1) <> "s"
    end
  end

  def format_ms(ms) when is_integer(ms) do
    minutes = div(ms, 60_000)
    seconds = rem(div(ms, 1_000), 60)
    "#{minutes}m #{seconds}s"
  end

  defp outcome(page, attempts) do
    reached_five? = Enum.any?(attempts, &(&1.number >= 5)) or length(attempts) >= 5

    cond do
      page.melded and reached_five? -> :fifth_attempt_meld
      page.melded -> :early_meld
      true -> :exhausted
    end
  end

  defp give_entry(page, gives) do
    arrivals = Enum.map(gives, & &1.arrived_at)

    if gives != [] and Enum.all?(arrivals, &match?(%DateTime{}, &1)) do
      last = Enum.max(arrivals, DateTime)
      phase(diff_ms(page.opened_at, last))
    else
      unavailable()
    end
  end

  defp generation(gives, attempts) do
    arrivals = Enum.map(gives, & &1.arrived_at)
    first_start = Enum.find_value(attempts, &datetime(&1.started_at))

    if gives != [] and Enum.all?(arrivals, &match?(%DateTime{}, &1)) and first_start do
      last = Enum.max(arrivals, DateTime)
      phase(diff_ms(last, first_start))
    else
      unavailable()
    end
  end

  defp span_sum([], _from, _to), do: unavailable()

  defp span_sum(attempts, from_field, to_field) do
    spans =
      Enum.map(attempts, fn attempt ->
        diff_ms(Map.get(attempt, from_field), Map.get(attempt, to_field))
      end)

    if Enum.any?(spans, &is_nil/1) do
      unavailable()
    else
      phase(Enum.sum(spans))
    end
  end

  defp reveal_pauses([]), do: unavailable()

  defp reveal_pauses([only]) do
    if match?(%DateTime{}, only.revealed_at), do: phase(0), else: unavailable()
  end

  defp reveal_pauses(attempts) do
    spans =
      attempts
      |> Enum.drop(-1)
      |> Enum.map(&diff_ms(&1.revealed_at, &1.advanced_at))

    if Enum.any?(spans, &is_nil/1) do
      unavailable()
    else
      phase(Enum.sum(spans))
    end
  end

  defp phase(nil), do: unavailable()
  defp phase(ms) when is_integer(ms), do: %{kind: :exact, ms: max(ms, 0)}
  defp unavailable, do: %{kind: :unavailable, ms: nil}

  defp datetime(%DateTime{} = time), do: time
  defp datetime(_), do: nil

  defp diff_ms(%DateTime{} = from, %DateTime{} = to) do
    DateTime.diff(to, from, :millisecond)
  end

  defp diff_ms(_, _), do: nil
end
