defmodule MeaningGame.Chronicle do
  @moduledoc """
  The record of everything played, written once and never rewritten.

  A Page arrives here when it closes, as the whole thing at once: the authored
  document, every attempt in order, what each Seat wrote on each, and what the
  Assayer said about each pair. Nothing here updates a row and nothing deletes
  one — the log is the version history (ADR-0003), which is why the couple
  correcting the record later will be another row rather than an edit to this
  one.

  Rows reference Seats and never Accounts. A Seat is permanent and claimable, so
  a history written against one comes with it whenever an Account claims it
  (ADR-0007).

  There is no repository seam under this. Tests run against real Postgres
  through the Ecto sandbox, because a Chronicle that only ever wrote to a fake
  would prove nothing about the thing the couple are going to read.
  """

  import Ecto.Query

  alias MeaningGame.Chronicle.Attempt
  alias MeaningGame.Chronicle.Bridge
  alias MeaningGame.Chronicle.Page
  alias MeaningGame.Chronicle.Verdict
  alias MeaningGame.Repo

  @doc """
  Writes one closed Page, with its attempts, its Bridges and its verdicts.

  `entry` is what `MeaningGame.Game` describes when a Page closes, and
  `opened_at` is when the Room dealt it — the Game keeps no clock, so the time a
  Page began is the Room's to remember.

  One transaction, and every insert is a bang: a Page half in the Chronicle is
  worse than a Page that is not in it, so a row that will not go in takes the
  whole write down rather than leaving a torn record behind.
  """
  @spec write(Ecto.UUID.t(), map(), DateTime.t()) :: {:ok, Page.t()}
  def write(room_id, entry, opened_at) do
    Repo.transaction(fn ->
      page = insert_page(room_id, entry, opened_at)

      Enum.each(entry.attempts, &insert_attempt(page, &1))

      page
    end)
  end

  @doc """
  Every closed Page in one Room, oldest first, with its attempts, Bridges and
  verdicts loaded.

  The book (and the Markdown export under it) is a view computed from these rows
  rather than a second copy of them.
  """
  @spec pages(Ecto.UUID.t()) :: [Page.t()]
  def pages(room_id) do
    from(p in Page, where: p.room_id == ^room_id, order_by: [asc: p.closed_at, asc: p.id])
    |> Repo.all()
    |> Repo.preload(attempts: [:bridges, :verdicts])
  end

  defp insert_page(room_id, entry, opened_at) do
    %Page{}
    |> Page.changeset(%{
      room_id: room_id,
      document: entry.page,
      closed_because: to_string(entry.closed_because),
      melded: entry.melded?,
      closeness: entry.closeness,
      opened_at: opened_at,
      closed_at: DateTime.utc_now()
    })
    |> Repo.insert!()
  end

  defp insert_attempt(page, attempt) do
    row =
      %Attempt{}
      |> Attempt.changeset(%{
        page_id: page.id,
        number: attempt.number,
        anchors: attempt.anchors,
        closeness: attempt.closeness,
        melded: attempt.melded?
      })
      |> Repo.insert!()

    # The position is the order the players were shown, and it is written down
    # rather than inferred: rows inserted inside one transaction share a
    # timestamp closely enough that reading them back by it is a coin toss.
    attempt.bridges |> Enum.with_index() |> Enum.each(&insert_bridge(row, &1))
    attempt.verdicts |> Enum.with_index() |> Enum.each(&insert_verdict(row, &1))
  end

  defp insert_bridge(attempt, {bridge, position}) do
    %Bridge{}
    |> Bridge.changeset(%{
      attempt_id: attempt.id,
      seat_id: bridge.seat_id,
      bridge: bridge.bridge,
      position: position
    })
    |> Repo.insert!()
  end

  defp insert_verdict(attempt, {verdict, position}) do
    meta = verdict.meta

    %Verdict{}
    |> Verdict.changeset(%{
      attempt_id: attempt.id,
      seat_ids: verdict.seat_ids,
      bridges: verdict.bridges,
      graded: verdict.graded?,
      closeness: verdict.closeness,
      band: verdict.band && to_string(verdict.band),
      reasoning: verdict.reasoning,
      quip: verdict.quip,
      model: meta[:model],
      prompt_version: meta[:prompt_version],
      latency_ms: meta[:latency_ms],
      cost_usd: meta[:cost_usd],
      forward: meta[:forward],
      reverse: meta[:reverse],
      reasoning_reverse: meta[:reasoning_reverse],
      position: position
    })
    |> Repo.insert!()
  end
end
