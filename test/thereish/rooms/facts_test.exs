defmodule Thereish.Rooms.FactsTest do
  @moduledoc """
  The Room's facts, driven command by command through the module's interface
  and asserted on the facts, attributes and effects it answers. No Room
  process, database or PubSub is involved.
  """
  use ExUnit.Case, async: true

  alias Thereish.Foley.Prologue
  alias Thereish.Rooms.Facts
  alias Thereish.Rooms.Room

  defp facts(attrs \\ %{}), do: Facts.new(struct!(%Room{slug: "facts", seat_limit: 8}, attrs))

  defp run!(facts, command) do
    {:ok, facts, attrs, effects} = Facts.apply(facts, command)
    {facts, attrs, effects}
  end

  describe "new/1" do
    test "holds the Room's persisted facts and no Prologue take" do
      facts =
        facts(%{
          speaker: "a",
          quips: false,
          full_table: false,
          split_readings: false,
          nudges: false,
          music: "house",
          prologue_skipped: true,
          quip: "a Code's Quip"
        })

      view = Facts.view(facts, "a")

      assert view.speaker? == true
      assert view.quips == false
      assert view.full_table == false
      assert view.split_readings == false
      assert view.nudges_enabled? == false
      assert view.music == "house"
      assert view.prologue_skipped == true
      assert view.quip == "a Code's Quip"
      assert is_nil(view.prologue)
    end
  end

  describe "the Speaker" do
    test "claiming from a free Room takes the Speaker and tells Voice" do
      assert {facts, %{speaker: "a"}, [:speaker_claimed]} = run!(facts(), {:claim_speaker, "a"})
      assert Facts.holds_speaker?(facts, "a")
      assert Facts.speaker_claimed?(facts)
    end

    test "claiming from a second device takes the Speaker" do
      held = facts(%{speaker: "a"})

      assert {facts, %{speaker: "b"}, [:speaker_claimed]} = run!(held, {:claim_speaker, "b"})
      assert Facts.holds_speaker?(facts, "b")
      refute Facts.holds_speaker?(facts, "a")
    end

    test "claiming again from the holder changes nothing" do
      held = facts(%{speaker: "a"})

      assert {^held, attrs, []} = run!(held, {:claim_speaker, "a"})
      assert attrs == %{}
    end

    test "a device with no token cannot claim the Speaker" do
      held = facts(%{speaker: "a"})

      for token <- [nil, "", "  "] do
        assert {^held, attrs, []} = run!(held, {:claim_speaker, token})
        assert attrs == %{}
      end
    end

    test "a release from another device changes nothing" do
      held = facts(%{speaker: "a"})

      assert {^held, attrs, []} = run!(held, {:release_speaker, "b"})
      assert attrs == %{}
    end

    test "a release from the holder, or from nobody in particular, frees the Speaker" do
      held = facts(%{speaker: "a"})

      for token <- ["a", nil] do
        assert {facts, %{speaker: nil}, []} = run!(held, {:release_speaker, token})
        refute Facts.speaker_claimed?(facts)
      end
    end

    test "releasing a free Speaker changes nothing" do
      free = facts()

      assert {^free, attrs, []} = run!(free, {:release_speaker, nil})
      assert attrs == %{}
    end

    test "a nil or blank Speaker is unclaimed and held by no device" do
      for speaker <- [nil, "", "   "] do
        facts = facts(%{speaker: speaker})

        refute Facts.speaker_claimed?(facts)
        refute Facts.holds_speaker?(facts, speaker)
        refute Facts.holds_speaker?(facts, nil)
      end
    end
  end

  describe "start sound and the Prologue rule" do
    test "the Stage's first tap claims the Speaker and draws a take in a Room with no Chronicle" do
      assert {facts, %{speaker: "stage"}, [:speaker_claimed]} =
               run!(facts(), {:start_sound, "stage", false})

      assert Facts.holds_speaker?(facts, "stage")
      assert %{reading: reading, text: text} = Facts.view(facts, "stage").prologue
      assert reading in Prologue.readings()
      assert text == Prologue.script()
    end

    test "a Room with a Chronicle draws no take" do
      {facts, _attrs, _effects} = run!(facts(), {:start_sound, "stage", true})
      assert is_nil(Facts.view(facts, "stage").prologue)
    end

    test "a Room that skipped the Prologue draws no take" do
      {facts, _attrs, _effects} =
        run!(facts(%{prologue_skipped: true}), {:start_sound, "stage", false})

      assert is_nil(Facts.view(facts, "stage").prologue)
    end

    test "a tap from a device with no token changes nothing and tells nobody" do
      held = facts(%{speaker: "a"})

      for token <- [nil, "", "  "] do
        assert {^held, attrs, []} = run!(held, {:start_sound, token, false})
        assert attrs == %{}
      end
    end

    test "a take already playing is not drawn again" do
      {playing, _attrs, _effects} = run!(facts(), :play_prologue)
      take = Facts.view(playing, nil).prologue

      {facts, _attrs, _effects} = run!(playing, {:start_sound, "stage", false})
      assert Facts.view(facts, "stage").prologue == take
    end

    test "a tap from the device already holding the Speaker writes nothing but still tells Voice" do
      held = facts(%{speaker: "stage", prologue_skipped: true})

      assert {^held, attrs, [:speaker_claimed]} = run!(held, {:start_sound, "stage", true})
      assert attrs == %{}
    end

    test "play Prologue draws a new take, even after a skip, and writes nothing" do
      {facts, attrs, []} = run!(facts(%{prologue_skipped: true}), :play_prologue)

      assert attrs == %{}
      assert Facts.view(facts, nil).prologue.reading in Prologue.readings()
    end

    test "skip Prologue clears the take and records the skip" do
      {playing, _attrs, _effects} = run!(facts(), :play_prologue)

      assert {facts, %{prologue_skipped: true}, []} = run!(playing, :skip_prologue)
      view = Facts.view(facts, nil)
      assert is_nil(view.prologue)
      assert view.prologue_skipped == true
    end

    test "skipping a Prologue already skipped and silent changes nothing" do
      skipped = facts(%{prologue_skipped: true})

      assert {^skipped, attrs, []} = run!(skipped, :skip_prologue)
      assert attrs == %{}
    end
  end

  describe "Quips, Full table, Split readings and Nudges" do
    test "setting Quips persists the new value" do
      assert {facts, %{quips: false}, []} = run!(facts(), {:set, :quips, false})
      assert Facts.view(facts, nil).quips == false
    end

    test "setting Full table persists the new value and tells the Game" do
      assert {facts, %{full_table: false}, [{:full_table_changed, false}]} =
               run!(facts(), {:set, :full_table, false})

      assert Facts.view(facts, nil).full_table == false
    end

    test "setting either to the value it has changes nothing" do
      start = facts()

      for fact <- [:quips, :full_table, :split_readings, :nudges] do
        assert {^start, attrs, []} = run!(start, {:set, fact, true})
        assert attrs == %{}
      end
    end

    test "setting Split readings persists the new value and tells nobody" do
      assert {facts, %{split_readings: false}, []} =
               run!(facts(), {:set, :split_readings, false})

      assert Facts.view(facts, nil).split_readings == false
    end

    test "Nudges default to on and toggling persists without immediate effects" do
      assert Facts.view(facts(), nil).nudges_enabled? == true

      assert {off, %{nudges: false}, []} = run!(facts(), {:toggle, :nudges})
      assert Facts.view(off, nil).nudges_enabled? == false

      assert {on, %{nudges: true}, []} = run!(off, {:toggle, :nudges})
      assert Facts.view(on, nil).nudges_enabled? == true
    end

    test "toggling flips the Room's own value" do
      assert {_facts, %{quips: false}, []} = run!(facts(), {:toggle, :quips})

      assert {_facts, %{full_table: true}, [{:full_table_changed, true}]} =
               run!(facts(%{full_table: false}), {:toggle, :full_table})
    end

    test "toggling twice returns to the start" do
      start = facts()

      for fact <- [:quips, :full_table, :split_readings, :nudges] do
        {once, _attrs, _effects} = run!(start, {:toggle, fact})
        {twice, attrs, _effects} = run!(once, {:toggle, fact})

        assert twice == start
        assert attrs == %{fact => true}
      end
    end
  end

  describe "music" do
    test "a music mode persists and tells Occupancy" do
      assert {facts, %{music: "off"}, [{:music_changed, "off"}]} =
               run!(facts(), {:set_music, "off"})

      assert Facts.view(facts, nil).music == "off"
    end

    test "a music mode may be named by an atom" do
      assert {_facts, %{music: "house"}, [{:music_changed, "house"}]} =
               run!(facts(), {:set_music, :house})
    end

    test "the music mode the Room already has writes nothing but still tells Occupancy" do
      start = facts()

      assert {^start, attrs, [{:music_changed, "page"}]} = run!(start, {:set_music, "page"})
      assert attrs == %{}
    end

    test "a bad music setting is refused" do
      for music <- ["loud", :loud, nil, 3] do
        assert {:error, :bad_music_setting} = Facts.apply(facts(), {:set_music, music})
      end
    end
  end

  describe "view/2" do
    test "answers the Room-fact keys for one device" do
      facts = facts(%{speaker: "a"})

      assert Facts.view(facts, "a").speaker? == true
      assert Facts.view(facts, "b").speaker? == false
      assert Facts.view(facts, nil).speaker? == false

      for token <- ["a", "b", nil] do
        view = Facts.view(facts, token)

        assert view.speaker_claimed? == true

        assert Map.keys(view) |> Enum.sort() ==
                 Enum.sort([
                   :speaker?,
                   :speaker_claimed?,
                   :quips,
                   :full_table,
                   :split_readings,
                   :nudges_enabled?,
                   :music,
                   :quip,
                   :prologue_skipped,
                   :prologue,
                   :prologue_script
                 ])

        assert view.prologue_script == Prologue.script()
      end
    end

    test "the view never exposes the device token" do
      token = "device-token-#{System.unique_integer([:positive])}"
      {facts, _attrs, _effects} = run!(facts(), {:start_sound, token, false})

      for viewer <- [token, "other", nil] do
        view = Facts.view(facts, viewer)

        refute Map.has_key?(view, :speaker)
        refute Map.has_key?(view, :device_token)
        refute Jason.encode!(view) =~ token
      end
    end
  end
end
