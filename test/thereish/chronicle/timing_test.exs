defmodule Thereish.Chronicle.TimingTest do
  @moduledoc """
  Duration interpretation at the Timing seam (ticket 10).
  """
  use ExUnit.Case, async: true

  alias Thereish.Chronicle.Attempt
  alias Thereish.Chronicle.Document
  alias Thereish.Chronicle.Give
  alias Thereish.Chronicle.Page
  alias Thereish.Chronicle.Timing

  @opened ~U[2026-09-12 12:00:00.000000Z]

  test "an early Meld's exact total ends at the final reveal, not at close" do
    view =
      Timing.view(
        page(
          melded: true,
          closed_because: "meld",
          revealed_at: at(20),
          closed_at: at(60),
          gives: [give(1, 4), give(2, 8)],
          attempts: [attempt(1, started: 11, assaying: 18, revealed: 20)]
        )
      )

    assert view.kind == :exact
    assert view.outcome == :early_meld
    assert view.total_ms == 20_000
    assert view.phases.give_entry == %{kind: :exact, ms: 8_000}
    assert view.phases.generation == %{kind: :exact, ms: 3_000}
    assert view.phases.bridge_writing == %{kind: :exact, ms: 7_000}
    assert view.phases.assayer_beat == %{kind: :exact, ms: 2_000}
    assert view.phases.reveal_pauses == %{kind: :exact, ms: 0}
  end

  test "a fifth-Attempt Meld is distinct from an earlier Meld and from exhaustion" do
    attempts = [
      attempt(1, started: 11, assaying: 12, revealed: 13, advanced: 15),
      attempt(2, started: 15, assaying: 16, revealed: 17, advanced: 19),
      attempt(3, started: 19, assaying: 20, revealed: 21, advanced: 23),
      attempt(4, started: 23, assaying: 24, revealed: 25, advanced: 27),
      attempt(5, started: 27, assaying: 28, revealed: 30)
    ]

    melded =
      Timing.view(
        page(
          melded: true,
          closed_because: "meld",
          revealed_at: at(30),
          gives: [give(1, 4), give(2, 8)],
          attempts: attempts
        )
      )

    assert melded.outcome == :fifth_attempt_meld
    assert melded.kind == :exact
    assert melded.total_ms == 30_000
    assert melded.phases.reveal_pauses == %{kind: :exact, ms: 8_000}

    spent =
      Timing.view(
        page(
          melded: false,
          closed_because: "attempts_spent",
          revealed_at: at(30),
          gives: [give(1, 4), give(2, 8)],
          attempts: attempts
        )
      )

    assert spent.outcome == :exhausted
    assert spent.kind == :exact
  end

  test "legacy opened-to-closed duration is an estimate and the breakdown is unavailable" do
    view =
      Timing.view(
        page(
          melded: true,
          closed_because: "meld",
          revealed_at: nil,
          closed_at: at(45),
          gives: [%Give{order: 1, arrived_at: nil}],
          attempts: [%Attempt{number: 1, melded: true, bookends: ["lantern", "harbour"]}]
        )
      )

    assert view.kind == :estimate
    assert view.total_ms == 45_000
    assert view.phases.give_entry == %{kind: :unavailable, ms: nil}
    assert view.phases.generation == %{kind: :unavailable, ms: nil}
    assert view.phases.bridge_writing == %{kind: :unavailable, ms: nil}
    assert view.phases.assayer_beat == %{kind: :unavailable, ms: nil}
    assert view.phases.reveal_pauses == %{kind: :unavailable, ms: nil}
  end

  defp page(attrs) do
    attrs = Map.new(attrs)

    %Page{
      id: Ecto.UUID.generate(),
      document: %Document{},
      opened_at: @opened,
      closed_at: attrs[:closed_at] || at(60),
      revealed_at: attrs[:revealed_at],
      melded: attrs[:melded],
      closed_because: attrs[:closed_because],
      gives: attrs[:gives] || [],
      attempts: attrs[:attempts] || [],
      room: %{slug: "dust"}
    }
  end

  defp give(order, seconds) do
    %Give{order: order, arrived_at: at(seconds)}
  end

  defp attempt(number, times) do
    times = Map.new(times)

    %Attempt{
      number: number,
      bookends: ["lantern", "harbour"],
      melded: false,
      started_at: at(times[:started]),
      assaying_started_at: at(times[:assaying]),
      revealed_at: at(times[:revealed]),
      advanced_at: at(times[:advanced])
    }
  end

  defp at(nil), do: nil
  defp at(seconds), do: DateTime.add(@opened, seconds, :second)
end
