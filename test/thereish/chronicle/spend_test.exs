defmodule Thereish.Chronicle.SpendTest do
  @moduledoc """
  What the Steward's calls cost. The tally and the spend line are pinned from
  call facts built in memory; the reads are pinned against real Postgres only
  for what crosses them: that every row kind reaches the tally, and that the
  all-Rooms answer breaks down by Room.
  """
  use Thereish.DataCase, async: false

  import Thereish.EntryFixtures
  import Thereish.RoomFixtures

  alias Thereish.Chronicle
  alias Thereish.Chronicle.Spend
  alias Thereish.Foley.Track
  alias Thereish.Foley.Vamp
  alias Thereish.Mask
  alias Thereish.Rooms
  alias Thereish.Rooms.Room

  defp call(role, model, cost),
    do: %{role: role, model: model, cost: cost && Decimal.new(cost)}

  describe "tally/1" do
    test "no calls is zero everywhere, with every role present" do
      spend = Spend.tally([])

      assert Decimal.equal?(spend.total_usd, 0)
      assert spend.calls_count == 0
      assert spend.unpriced_count == 0
      assert spend.by_model == %{}

      for {_name, role} <- Spend.roles() do
        assert %{calls_count: 0, unpriced_count: 0, by_model: by_model} = spend.by_role[role]
        assert Decimal.equal?(spend.by_role[role].total_usd, 0)
        assert by_model == %{}
      end

      assert Spend.line(spend) ==
               "Spend: $0.0000 across 0 calls (Author $0.0000, Assayer $0.0000, " <>
                 "Scribe $0.0000, Foley $0.0000, Limner $0.0000)"
    end

    test "an unpriced call counts as a call and as unpriced, and costs nothing" do
      spend =
        Spend.tally([
          call(:assayer, "gemini-3.8-flash", "0.0015"),
          call(:assayer, "gemini-3.8-flash", nil)
        ])

      assert Decimal.equal?(spend.total_usd, Decimal.new("0.0015"))
      assert spend.calls_count == 2
      assert spend.unpriced_count == 1
      assert spend.by_role.assayer.calls_count == 2
      assert spend.by_role.assayer.unpriced_count == 1
      assert spend.by_model["gemini-3.8-flash"].unpriced_count == 1
    end

    test "groups by role and by model, and a model on two roles is one model" do
      spend =
        Spend.tally([
          call(:author, "gemini-3.8-flash", "0.0002"),
          call(:assayer, "gemini-3.8-flash", "0.0015"),
          call(:scribe, "claude-fable-5-1", "0.0025"),
          call(:foley, "mureka-v1", "0.0400")
        ])

      assert Decimal.equal?(spend.total_usd, Decimal.new("0.0442"))
      assert spend.calls_count == 4

      assert Decimal.equal?(spend.by_role.author.total_usd, Decimal.new("0.0002"))
      assert spend.by_role.author.by_model["gemini-3.8-flash"].calls_count == 1
      assert Decimal.equal?(spend.by_role.assayer.total_usd, Decimal.new("0.0015"))
      assert spend.by_role.assayer.by_model["gemini-3.8-flash"].calls_count == 1
      assert spend.by_role.scribe.by_model["claude-fable-5-1"].calls_count == 1
      assert spend.by_role.foley.by_model["mureka-v1"].calls_count == 1
      assert spend.by_role.limner.calls_count == 0

      assert spend.by_model["gemini-3.8-flash"].calls_count == 2
      assert Decimal.equal?(spend.by_model["gemini-3.8-flash"].total_usd, Decimal.new("0.0017"))

      assert Map.keys(spend.by_model) |> Enum.sort() == [
               "claude-fable-5-1",
               "gemini-3.8-flash",
               "mureka-v1"
             ]
    end
  end

  describe "line/1" do
    test "names a role all unpriced as unpriced and a role some unpriced with its count" do
      spend =
        Spend.tally([
          call(:author, "gemini-3.8-flash", nil),
          call(:assayer, "gemini-3.8-flash", "0.0015"),
          call(:assayer, "gemini-3.8-flash", nil),
          call(:scribe, "claude-fable-5-1", "0.0025")
        ])

      assert Spend.line(spend) ==
               "Spend: $0.0040 across 4 calls (2 unpriced) (Author unpriced, " <>
                 "Assayer $0.0015 (1 unpriced), Scribe $0.0025, Foley $0.0000, Limner $0.0000)"
    end

    test "one call is a call" do
      assert Spend.line(Spend.tally([call(:limner, "imagen-3", "0.04")])) =~
               "Spend: $0.0400 across 1 call (Author"
    end
  end

  describe "reading the Chronicle's rows" do
    setup do
      slug = open_room()
      {:ok, melissa} = Rooms.join(slug, "Melissa", device_token())
      {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())

      %{room: Repo.get_by!(Room, slug: slug), melissa: melissa, jacob: jacob}
    end

    defp verdict(seats, bridge, meta, voice_meta \\ nil) do
      %{
        seat_ids: Enum.map(seats, & &1.id),
        bridges: [bridge, bridge],
        meta: meta,
        voice_meta: voice_meta
      }
    end

    defp attempt(seats, bridge, verdicts) do
      %{bridges: Enum.map(seats, &%{seat_id: &1.id, bridge: bridge}), verdicts: verdicts}
    end

    test "every row kind reaches the Room's tally", ctx do
      seats = [ctx.melissa, ctx.jacob]

      entry =
        entry(
          author_meta: %{model: "gemini-3.8-flash", cost_usd: 0.0002},
          music_meta: %Track{
            path: "/media/tracks/a.mp3",
            meta: %{"provider" => "mureka", "model" => "mureka-v1", "cost_usd" => 0.0400}
          },
          vamp_meta: %Vamp{
            path: "/media/vamps/oasis-vamp.mp3",
            meta: %{"model" => "eleven_text_to_sound_v2", "cost_usd" => 0.0120}
          },
          masks: %{
            ctx.melissa.id => %Mask{
              url: "/media/masks/mask-melissa.png",
              meta: %{model: "imagen-3", cost_usd: 0.04}
            },
            ctx.jacob.id => :dot
          },
          attempts: [
            attempt(seats, "water", [
              verdict(seats, "water", %{model: "gemini-3.8-flash", cost_usd: 0.0015}, %{
                "provider" => "fake",
                "voice" => "fake-voice",
                "cost_usd" => 0.0,
                "failure" => "voice_unavailable"
              }),
              verdict(seats, "water", %{model: "gemini-3.8-flash", cost_usd: nil})
            ])
          ]
        )

      assert {:ok, page} = Chronicle.write(ctx.room.id, entry)

      {:ok, _recap} =
        Chronicle.record_recap(ctx.room.id, %{
          page_id: page.id,
          recap: "A trek through dunes to an oasis.",
          model: "claude-fable-5-1",
          cost_usd: 0.0025
        })

      spend = Spend.room(ctx.room.id)

      assert spend.room_id == ctx.room.id
      assert spend.slug == ctx.room.slug
      assert spend.calls_count == 8
      assert spend.unpriced_count == 1
      assert Decimal.equal?(spend.total_usd, Decimal.new("0.0962"))

      assert spend.by_role.author.by_model["gemini-3.8-flash"].calls_count == 1
      assert spend.by_role.assayer.calls_count == 2
      assert spend.by_role.assayer.unpriced_count == 1
      assert spend.by_role.scribe.by_model["claude-fable-5-1"].calls_count == 1
      assert spend.by_role.limner.by_model["imagen-3"].calls_count == 1

      assert Map.keys(spend.by_role.foley.by_model) |> Enum.sort() ==
               ["eleven_text_to_sound_v2", "fake-voice", "mureka-v1"]

      assert Decimal.equal?(spend.by_role.foley.total_usd, Decimal.new("0.0520"))
      assert spend.by_role.foley.unpriced_count == 0
    end

    test "a Page without author meta is no Author call", ctx do
      assert {:ok, _page} = Chronicle.write(ctx.room.id, entry(attempts: []))

      assert Spend.room(ctx.room.id).calls_count == 0
    end

    test "every Room's calls, totalled and broken down by Room", ctx do
      seats = [ctx.melissa, ctx.jacob]

      entry1 =
        entry(
          author_meta: %{model: "gemini-3.8-flash", cost_usd: 0.0002},
          attempts: [
            attempt(seats, "water", [
              verdict(seats, "water", %{model: "gemini-3.8-flash", cost_usd: 0.0010})
            ])
          ]
        )

      assert {:ok, page1} = Chronicle.write(ctx.room.id, entry1)

      {:ok, _recap1} =
        Chronicle.record_recap(ctx.room.id, %{
          page_id: page1.id,
          recap: "A trek through dunes to an oasis.",
          model: "claude-fable-5-1",
          cost_usd: 0.0030
        })

      slug2 = open_room()
      room2 = Repo.get_by!(Room, slug: slug2)
      {:ok, seat_a} = Rooms.join(slug2, "Alice", device_token())
      {:ok, seat_b} = Rooms.join(slug2, "Bob", device_token())

      entry2 =
        entry(
          author_meta: %{model: "gemini-3.8-flash", cost_usd: nil},
          attempts: [
            attempt([seat_a, seat_b], "sky", [
              verdict([seat_a, seat_b], "sky", %{model: "gemini-3.8-flash", cost_usd: 0.0005})
            ])
          ]
        )

      assert {:ok, _page2} = Chronicle.write(room2.id, entry2)

      all = Spend.all()

      assert Decimal.equal?(all.total_usd, Decimal.new("0.0047"))
      assert all.calls_count == 5
      assert all.unpriced_count == 1
      assert all.by_role.author.calls_count == 2
      assert all.by_role.author.unpriced_count == 1

      assert Enum.map(all.rooms, & &1.slug) == Enum.sort([ctx.room.slug, slug2])

      room1_spend = Enum.find(all.rooms, &(&1.room_id == ctx.room.id))
      room2_spend = Enum.find(all.rooms, &(&1.room_id == room2.id))

      assert Decimal.equal?(room1_spend.total_usd, Decimal.new("0.0042"))
      assert room1_spend.calls_count == 3
      assert room1_spend.unpriced_count == 0

      assert Decimal.equal?(room2_spend.total_usd, Decimal.new("0.0005"))
      assert room2_spend.calls_count == 2
      assert room2_spend.unpriced_count == 1
      assert room2_spend.opened_at == room2.inserted_at
    end
  end
end
