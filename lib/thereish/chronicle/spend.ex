defmodule Thereish.Chronicle.Spend do
  @moduledoc """
  What the Steward's calls cost, read back from the Chronicle's rows by role and
  model, and never stored as a total (ticket 09).

  The Steward records each call's cost on the row the call produced: the
  Author's on its Page, the Assayer's on its Verdict, the Scribe's on its Recap,
  Foley's on the Page's Track and Vamp and on the Verdict's voice, the Limner's
  on the Page's Masks. This module owns the narrow reads of those rows, decodes
  each into calls, and tallies them.

  The seam is `tally/1`, pure over a list of `t:call/0` facts, so every rule
  about money (totals, unpriced counts, grouping) can be tested without a
  database. The Room answer and the all-Rooms answer come from the same tally.
  """

  import Ecto.Query

  alias Thereish.Chronicle.Attempt
  alias Thereish.Chronicle.Page
  alias Thereish.Chronicle.Recap
  alias Thereish.Chronicle.Verdict
  alias Thereish.Foley.Track
  alias Thereish.Foley.Vamp
  alias Thereish.Mask
  alias Thereish.Repo
  alias Thereish.Rooms.Room

  @roles [
    {"Author", :author},
    {"Assayer", :assayer},
    {"Scribe", :scribe},
    {"Foley", :foley},
    {"Limner", :limner}
  ]

  @type role :: :author | :assayer | :scribe | :foley | :limner

  @typedoc "One call the Steward made. A nil cost is an unpriced call."
  @type call :: %{role: role(), model: String.t(), cost: Decimal.t() | nil}

  @type stats :: %{
          total_usd: Decimal.t(),
          calls_count: non_neg_integer(),
          unpriced_count: non_neg_integer()
        }

  @type role_stats :: %{
          total_usd: Decimal.t(),
          calls_count: non_neg_integer(),
          unpriced_count: non_neg_integer(),
          by_model: %{String.t() => stats()}
        }

  @type tally :: %{
          total_usd: Decimal.t(),
          calls_count: non_neg_integer(),
          unpriced_count: non_neg_integer(),
          by_role: %{role() => role_stats()},
          by_model: %{String.t() => stats()}
        }

  @typedoc "One Room's tally, with the Room it belongs to."
  @type room_spend :: %{
          required(:room_id) => Ecto.UUID.t(),
          required(:slug) => String.t(),
          required(:opened_at) => NaiveDateTime.t() | DateTime.t() | nil,
          required(:total_usd) => Decimal.t(),
          required(:calls_count) => non_neg_integer(),
          required(:unpriced_count) => non_neg_integer(),
          required(:by_role) => %{role() => role_stats()},
          required(:by_model) => %{String.t() => stats()}
        }

  @typedoc "Every call in every Room, plus each Room's own tally ordered by slug."
  @type all_spend :: %{
          required(:total_usd) => Decimal.t(),
          required(:calls_count) => non_neg_integer(),
          required(:unpriced_count) => non_neg_integer(),
          required(:by_role) => %{role() => role_stats()},
          required(:by_model) => %{String.t() => stats()},
          required(:rooms) => [room_spend()]
        }

  @doc "The Steward's roles in display order, as name and key."
  @spec roles() :: [{String.t(), role()}]
  def roles, do: @roles

  @doc "Spend for one Room."
  @spec room(Ecto.UUID.t()) :: room_spend()
  def room(room_id) do
    room = Repo.get!(Room, room_id)
    calls = Enum.map(calls(room.id), &elem(&1, 1))

    room_spend(room, calls)
  end

  @doc "Spend for every Room, with each Room's breakdown."
  @spec all() :: all_spend()
  def all do
    rooms = Repo.all(from(r in Room, order_by: [asc: r.slug]))
    calls = calls(:all)
    calls_by_room = Enum.group_by(calls, &elem(&1, 0), &elem(&1, 1))

    calls
    |> Enum.map(&elem(&1, 1))
    |> tally()
    |> Map.put(:rooms, Enum.map(rooms, &room_spend(&1, Map.get(calls_by_room, &1.id, []))))
  end

  @doc """
  Tallies calls into totals, by role and by model, counting the unpriced ones.
  Every role is present, at zero when it made no call.
  """
  @spec tally([call()]) :: tally()
  def tally(calls) do
    zero_tally =
      zero()
      |> Map.put(:by_role, Map.new(@roles, fn {_name, role} -> {role, zero_role()} end))
      |> Map.put(:by_model, %{})

    Enum.reduce(calls, zero_tally, fn %{role: role, model: model, cost: cost}, acc ->
      acc
      |> add(cost)
      |> Map.update!(:by_role, fn by_role ->
        Map.update!(by_role, role, fn role_stats ->
          role_stats
          |> add(cost)
          |> Map.update!(:by_model, &add_model(&1, model, cost))
        end)
      end)
      |> Map.update!(:by_model, &add_model(&1, model, cost))
    end)
  end

  @doc """
  Formats the spend line for display in the book view and Markdown export.
  """
  @spec line(tally()) :: String.t()
  def line(spend) do
    calls_word = if spend.calls_count == 1, do: "call", else: "calls"

    unpriced_str =
      if spend.unpriced_count > 0, do: " (#{spend.unpriced_count} unpriced)", else: ""

    roles_summary =
      Enum.map_join(@roles, ", ", fn {name, role} -> role_line(name, spend.by_role[role]) end)

    "Spend: #{format_usd(spend.total_usd)} across #{spend.calls_count} #{calls_word}#{unpriced_str} (#{roles_summary})"
  end

  @doc """
  Formats a dollar decimal or float as a 4-decimal currency string (e.g. "$0.0042").
  """
  @spec format_usd(Decimal.t() | number() | binary() | nil) :: String.t()
  def format_usd(nil), do: "$0.0000"

  def format_usd(%Decimal{} = dec) do
    rounded = Decimal.round(dec, 4)
    "$" <> Decimal.to_string(rounded, :normal)
  end

  def format_usd(val) when is_number(val) or is_binary(val) do
    case to_decimal(val) do
      nil -> "$0.0000"
      dec -> format_usd(dec)
    end
  end

  defp role_line(name, role_stats) do
    cond do
      role_stats.calls_count == 0 ->
        "#{name} $0.0000"

      role_stats.unpriced_count == role_stats.calls_count ->
        "#{name} unpriced"

      role_stats.unpriced_count > 0 ->
        "#{name} #{format_usd(role_stats.total_usd)} (#{role_stats.unpriced_count} unpriced)"

      true ->
        "#{name} #{format_usd(role_stats.total_usd)}"
    end
  end

  defp room_spend(room, calls) do
    calls
    |> tally()
    |> Map.merge(%{room_id: room.id, slug: room.slug, opened_at: room.inserted_at})
  end

  defp zero, do: %{total_usd: Decimal.new(0), calls_count: 0, unpriced_count: 0}

  defp zero_role, do: Map.put(zero(), :by_model, %{})

  defp add(stats, nil),
    do: %{stats | calls_count: stats.calls_count + 1, unpriced_count: stats.unpriced_count + 1}

  defp add(stats, %Decimal{} = cost),
    do: %{
      stats
      | total_usd: Decimal.add(stats.total_usd, cost),
        calls_count: stats.calls_count + 1
    }

  defp add_model(by_model, model, cost),
    do: Map.update(by_model, model, add(zero(), cost), &add(&1, cost))

  # Every call in scope (one Room's id, or :all), each paired with its Room's id.
  defp calls(scope) do
    pages =
      from(p in Page,
        as: :owner,
        select: %{
          room_id: p.room_id,
          author_meta: p.author_meta,
          music_meta: p.music_meta,
          vamp_meta: p.vamp_meta,
          masks_meta: p.masks_meta
        }
      )

    verdicts =
      from(v in Verdict,
        join: a in Attempt,
        on: a.id == v.attempt_id,
        join: p in Page,
        as: :owner,
        on: p.id == a.page_id,
        select: %{
          room_id: p.room_id,
          model: v.model,
          cost_usd: v.cost_usd,
          voice_meta: v.voice_meta
        }
      )

    recaps =
      from(r in Recap,
        as: :owner,
        select: %{room_id: r.room_id, model: r.model, cost_usd: r.cost_usd}
      )

    Enum.flat_map(read(pages, scope), &with_room(&1, page_calls(&1))) ++
      Enum.flat_map(read(verdicts, scope), &with_room(&1, verdict_calls(&1))) ++
      Enum.flat_map(read(recaps, scope), &with_room(&1, [call(:scribe, &1.model, &1.cost_usd)]))
  end

  defp read(query, :all), do: Repo.all(query)
  defp read(query, room_id), do: Repo.all(where(query, [owner: o], o.room_id == ^room_id))

  defp with_room(row, calls), do: Enum.map(calls, &{row.room_id, &1})

  defp page_calls(page) do
    author_calls(page.author_meta) ++
      foley_calls(page.music_meta) ++
      foley_calls(page.vamp_meta) ++
      limner_calls(page.masks_meta)
  end

  defp author_calls(meta) when is_map(meta) and map_size(meta) > 0,
    do: [call(:author, meta["model"] || meta[:model], meta["cost_usd"] || meta[:cost_usd])]

  defp author_calls(_meta), do: []

  # A Track, failed or kept, or a Vamp is one Foley call; a failure costs $0.
  defp foley_calls(nil), do: []

  defp foley_calls(%{meta: meta} = record)
       when is_struct(record, Track) or is_struct(record, Vamp),
       do: [call(:foley, meta["model"] || meta["provider"], meta["cost_usd"])]

  # A dot instead of a Mask is no call.
  defp limner_calls(masks) when is_map(masks) do
    for {_seat_id, %Mask{meta: meta}} <- masks,
        do: call(:limner, meta["model"], meta["cost_usd"])
  end

  defp limner_calls(_masks), do: []

  defp verdict_calls(verdict),
    do: [call(:assayer, verdict.model, verdict.cost_usd) | voice_calls(verdict.voice_meta)]

  # Older Verdict rows name the voice's model and cost under any of these keys.
  defp voice_calls(meta) when is_map(meta) and map_size(meta) > 0 do
    model =
      meta["model"] || meta[:model] ||
        meta["voice"] || meta[:voice] ||
        meta["voice_id"] || meta[:voice_id] ||
        meta["provider"] || meta[:provider]

    [call(:foley, model, meta["cost_usd"] || meta[:cost_usd] || meta["cost"] || meta[:cost])]
  end

  defp voice_calls(_meta), do: []

  defp call(role, model, cost),
    do: %{role: role, model: to_string(model || "unknown"), cost: to_decimal(cost)}

  defp to_decimal(nil), do: nil
  defp to_decimal(%Decimal{} = d), do: d
  defp to_decimal(f) when is_float(f), do: Decimal.from_float(f)
  defp to_decimal(i) when is_integer(i), do: Decimal.new(i)

  defp to_decimal(s) when is_binary(s) do
    case Decimal.parse(s) do
      {d, ""} -> d
      _ -> nil
    end
  end

  defp to_decimal(_), do: nil
end
