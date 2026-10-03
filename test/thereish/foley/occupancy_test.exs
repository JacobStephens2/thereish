defmodule Thereish.Foley.OccupancyTest do
  @moduledoc """
  What the Speaker plays, driven as a list of things that happen to a Room and
  asserted on the view it presents and the effects it asks the Room to perform.

  Everything here goes through the interface. No test reads a struct field: the
  view and the effects are all the Room has to work with.
  """
  use ExUnit.Case, async: true

  alias Thereish.Foley.Occupancy

  @gives ["harbour", "lantern"]
  @draw %{name: "Dusk", title: "Dusk", path: "/loops/dusk.mp3"}
  @other %{name: "Tide", title: "Tide", path: "/loops/tide.mp3"}
  @third %{name: "Ember", title: "Ember", path: "/loops/ember.mp3"}
  @members [@draw, @other]
  @vamp %{path: "/media/vamp.mp3", duration: 30, format: "mp3", meta: %{cost_usd: 0.01}}
  @track %{path: "/media/track.mp3", meta: %{provider: "fake", cost_usd: 0.5}}
  @cached %{path: "/media/cached.mp3", title: "Harbour Lights", meta: %{provider: "fake"}}

  defp table(overrides \\ %{}), do: Map.merge(%{music: "page", closed?: false}, overrides)

  # An Occupancy whose one eligible member, and so its draw, is @draw.
  defp occupancy(members \\ [@draw]), do: Occupancy.new(members)

  # A Page opened under "page" on a cache miss, with the effects it asked for.
  defp opened(ref, occ \\ occupancy(), cached \\ nil, mode \\ "page") do
    Occupancy.page_opened(occ, ref, @gives, cached, 1_000, mode)
  end

  defp arrive(occ, ref, result, closed? \\ false) do
    {occ, _effects} = Occupancy.arrived(occ, ref, result, closed?)
    occ
  end

  defp kinds(effects), do: Enum.map(effects, &elem(&1, 0))

  defp logged(effects) do
    for {:log, _ref, event, _landed_at} <- effects, do: event
  end

  describe "a Page opens" do
    test "a cache hit plays the cached Track at once and starts no Vamp, Track or title work" do
      ref = make_ref()
      {occ, effects} = opened(ref, occupancy(), @cached)

      assert kinds(effects) == [:log]
      assert logged(effects) == ["cache hit"]

      view = Occupancy.view(occ, table())
      assert view.track == @cached
      assert view.vamp == nil
      assert view.playing == %{path: @cached.path, title: "Harbour Lights", kind: "track"}
      assert view.music_meta.title == "Harbour Lights"
      assert view.music_meta["path"] == @cached.path
      assert view.music_meta.title_cost_usd == 0.0
      assert view.music_meta.provider == "fake"
    end

    test "a cache row with no title is a miss" do
      {_occ, effects} = opened(make_ref(), occupancy(), Map.put(@cached, :title, nil))
      assert :enqueue_track in kinds(effects)
    end

    test "a cache miss asks for a Vamp, the Track and a title, and plays the draw meanwhile" do
      ref = make_ref()
      {occ, effects} = opened(ref)

      assert {:start_vamp, ref, @gives} in effects
      assert {:enqueue_track, ref, @gives, 1_000} in effects
      assert {:start_title, ref, @gives} in effects
      assert logged(effects) == ["cache miss", "vamp started", "score queued"]

      view = Occupancy.view(occ, table())
      assert view.playing == %{path: @draw.path, title: "Dusk", kind: "repertoire"}
      assert view.track == nil
      assert view.vamp == nil
    end

    test "under house or off, nothing is looked for and nothing is started" do
      for mode <- ["house", "off"] do
        {_occ, effects} = opened(make_ref(), occupancy(), @cached, mode)
        assert effects == []
      end
    end
  end

  describe "results arriving" do
    test "a Vamp plays while the Track is made, then the Track replaces it" do
      ref = make_ref()
      {occ, _} = opened(ref)

      {occ, effects} = Occupancy.arrived(occ, ref, {:vamp, {:ok, @vamp}}, false)

      assert [{:persist_vamp_meta, ^ref, vamp_meta}] =
               Enum.filter(effects, &(elem(&1, 0) != :log))

      assert vamp_meta.path == @vamp.path
      assert vamp_meta["loop"] == true
      assert logged(effects) == ["vamp landed"]

      view = Occupancy.view(occ, table())
      assert view.vamp == @vamp
      assert view.playing == %{path: @vamp.path, title: nil, kind: "vamp"}

      {occ, effects} = Occupancy.arrived(occ, ref, {:track, {:ok, @track}}, false)
      assert logged(effects) == ["track landed"]
      assert {:persist_music_meta, ^ref, meta} = List.keyfind(effects, :persist_music_meta, 0)
      assert meta.path == @track.path

      assert {:cache_track, @gives, %{path: "/media/track.mp3"}} =
               List.keyfind(effects, :cache_track, 0)

      view = Occupancy.view(occ, table())
      assert view.vamp == nil
      assert view.track.path == @track.path
      assert view.playing == %{path: @track.path, title: "Track", kind: "track"}
      assert view.music_meta.provider == "fake"
    end

    test "a Vamp landing after its Track is no longer being made is kept but not played" do
      ref = make_ref()
      {occ, _} = opened(ref)
      occ = arrive(occ, ref, {:track, {:ok, @track}})

      {occ, effects} = Occupancy.arrived(occ, ref, {:vamp, {:ok, @vamp}}, false)
      assert :persist_vamp_meta in kinds(effects)
      assert Occupancy.view(occ, table()).vamp == nil
      assert Occupancy.view(occ, table()).playing.kind == "track"
      assert Occupancy.chronicle_meta(occ, "page").vamp_meta.path == @vamp.path
    end

    test "a Vamp landing after its Page closed is persisted to that Page, not played" do
      ref = make_ref()
      {occ, _} = opened(ref)

      {occ, effects} = Occupancy.arrived(occ, ref, {:vamp, {:ok, @vamp}}, true)

      assert {:persist_vamp_meta, ^ref, %{path: "/media/vamp.mp3"}} =
               List.keyfind(effects, :persist_vamp_meta, 0)

      view = Occupancy.view(occ, table(%{closed?: true}))
      assert view.vamp == nil
      assert view.playing.kind == "repertoire"
    end

    test "a Track landing after its Page closed is persisted to that Page, not played" do
      ref = make_ref()
      {occ, _} = opened(ref)

      {occ, effects} = Occupancy.arrived(occ, ref, {:track, {:ok, @track}}, true)

      assert {:persist_music_meta, ^ref, %{path: "/media/track.mp3"}} =
               List.keyfind(effects, :persist_music_meta, 0)

      refute :cache_track in kinds(effects)

      view = Occupancy.view(occ, table(%{closed?: true}))
      assert view.track == nil
      assert view.playing.kind == "repertoire"
    end

    test "results for a superseded Page are persisted to it and leave the current Page untouched" do
      old = make_ref()
      new = make_ref()
      {occ, _} = opened(old)
      occ = Occupancy.page_turned(occ, [@draw])
      {occ, _} = opened(new, occ)
      before = Occupancy.view(occ, table())

      {occ, effects} = Occupancy.arrived(occ, old, {:vamp, {:ok, @vamp}}, false)
      assert [{:persist_vamp_meta, ^old, _}] = effects

      {occ, effects} =
        Occupancy.arrived(occ, old, {:track, {:ok, Map.put(@track, :title, "Old")}}, false)

      assert [{:persist_music_meta, ^old, meta}] = effects
      assert meta.title == "Old"

      {occ, effects} = Occupancy.arrived(occ, old, {:title, {:ok, %{title: "Late"}}}, false)
      assert effects == []

      {occ, effects} = Occupancy.arrived(occ, old, {:track, {:error, :timeout}}, false)
      assert effects == []

      assert Occupancy.view(occ, table()) == before
    end

    test "a title arriving before its Track is kept and applied when the Track lands" do
      ref = make_ref()
      {occ, _} = opened(ref)

      {occ, effects} =
        Occupancy.arrived(
          occ,
          ref,
          {:title, {:ok, %{title: "Salt Road", meta: %{cost_usd: 0.002}}}},
          false
        )

      assert effects == []

      {occ, effects} = Occupancy.arrived(occ, ref, {:track, {:ok, @track}}, false)
      assert {:persist_music_meta, ^ref, meta} = List.keyfind(effects, :persist_music_meta, 0)
      assert meta.title == "Salt Road"
      assert meta.title_cost_usd == 0.002

      assert {:cache_track, @gives, %{title: "Salt Road"}} =
               List.keyfind(effects, :cache_track, 0)

      view = Occupancy.view(occ, table())
      assert view.playing.title == "Salt Road"
      assert view.track.title == "Salt Road"
      assert view.music_meta["title"] == "Salt Road"
    end

    test "a title arriving after its Track renames it and caches the titled Track" do
      ref = make_ref()
      {occ, _} = opened(ref)
      occ = arrive(occ, ref, {:track, {:ok, @track}})

      {occ, effects} =
        Occupancy.arrived(
          occ,
          ref,
          {:title, {:ok, %{title: "Salt Road", meta: %{cost_usd: 0.002}}}},
          false
        )

      assert [{:cache_track, @gives, %{title: "Salt Road", path: "/media/track.mp3"}}] = effects

      view = Occupancy.view(occ, table())
      assert view.playing.title == "Salt Road"
      assert view.music_meta.title == "Salt Road"
      assert view.music_meta.title_cost_usd == 0.002
      assert view.music_meta.provider == "fake"
    end

    test "a title arriving after its Page closed changes nothing" do
      ref = make_ref()
      {occ, _} = opened(ref)
      occ = arrive(occ, ref, {:track, {:ok, @track}})

      {occ, effects} = Occupancy.arrived(occ, ref, {:title, {:ok, %{title: "Late"}}}, true)
      assert effects == []
      assert Occupancy.view(occ, table(%{closed?: true})).playing.title == "Track"
    end

    test "a failed title is logged and the Track keeps its own name" do
      ref = make_ref()
      {occ, _} = opened(ref)

      {occ, effects} = Occupancy.arrived(occ, ref, {:title, {:error, :refused}}, false)
      assert logged(effects) == [{:title_failure, :refused}]

      occ = arrive(occ, ref, {:track, {:ok, Map.put(@track, :title, "Own Name")}})
      assert Occupancy.view(occ, table()).playing.title == "Own Name"
    end

    test "a failed Track clears the Vamp and records failure meta for the Chronicle" do
      ref = make_ref()
      {occ, _} = opened(ref)
      occ = arrive(occ, ref, {:vamp, {:ok, @vamp}})

      {occ, effects} = Occupancy.arrived(occ, ref, {:track, {:error, :timeout}}, false)
      assert logged(effects) == [{:failure, :timeout}]

      view = Occupancy.view(occ, table())
      assert view.vamp == nil
      assert view.track == nil
      assert view.playing.kind == "repertoire"
      assert view.music_meta.failure == "timeout"
      assert Occupancy.chronicle_meta(occ, "page").music_meta.failure == "timeout"
    end

    test "a Track that succeeds after a failure replaces the failure meta" do
      ref = make_ref()
      {occ, _} = opened(ref)
      occ = arrive(occ, ref, {:track, {:error, :timeout}})
      occ = arrive(occ, ref, {:track, {:ok, @track}})

      meta = Occupancy.chronicle_meta(occ, "page").music_meta
      refute Map.has_key?(meta, :failure)
      assert meta.path == @track.path
    end

    test "a failed Vamp is logged and the draw keeps playing" do
      ref = make_ref()
      {occ, _} = opened(ref)

      {occ, effects} = Occupancy.arrived(occ, ref, {:vamp, {:error, :refused}}, false)
      assert logged(effects) == [{:vamp_failure, :refused}]
      assert Occupancy.view(occ, table()).playing.kind == "repertoire"
    end
  end

  describe "holdover" do
    setup do
      ref = make_ref()
      {occ, _} = opened(ref)
      %{occ: arrive(occ, ref, {:track, {:ok, Map.put(@track, :title, "Salt Road")}})}
    end

    test "a closed Page's Track is still on the Speaker, as a holdover", %{occ: occ} do
      assert Occupancy.view(occ, table(%{closed?: true})).playing ==
               %{path: @track.path, title: "Salt Road", kind: "holdover"}
    end

    test "on page_turned the Track holds over until the next Page's Vamp, then its Track", %{
      occ: occ
    } do
      occ = Occupancy.page_turned(occ, [@draw])
      assert Occupancy.view(occ, table()).playing.kind == "holdover"

      ref = make_ref()
      {occ, _} = opened(ref, occ)
      assert Occupancy.view(occ, table()).playing.kind == "holdover"
      assert Occupancy.view(occ, table()).track.title == "Salt Road"

      occ = arrive(occ, ref, {:vamp, {:ok, @vamp}})
      assert Occupancy.view(occ, table()).playing.kind == "vamp"

      occ = arrive(occ, ref, {:track, {:ok, Map.put(@track, :path, "/media/next.mp3")}})

      assert Occupancy.view(occ, table()).playing == %{
               path: "/media/next.mp3",
               title: "Track",
               kind: "track"
             }
    end

    test "gives_reset forgets the Page's Vamp, title and work but keeps a held-over Track", %{
      occ: occ
    } do
      occ = Occupancy.page_turned(occ, [@draw])
      ref = make_ref()
      {occ, _} = opened(ref, occ)
      occ = arrive(occ, ref, {:vamp, {:ok, @vamp}})
      occ = arrive(occ, ref, {:title, {:ok, %{title: "Forgotten"}}})

      occ = Occupancy.gives_reset(occ)
      view = Occupancy.view(occ, table())
      assert view.playing == %{path: @track.path, title: "Salt Road", kind: "holdover"}
      assert view.vamp == nil
      assert view.music_meta == nil

      {occ, effects} = Occupancy.arrived(occ, ref, {:track, {:ok, @track}}, false)
      assert [{:persist_music_meta, ^ref, _}] = effects
      assert Occupancy.view(occ, table()).playing.kind == "holdover"
    end
  end

  describe "the music setting changing mid-Page" do
    test "to page asks for the TrackCache, then starts Track work on a miss" do
      ref = make_ref()
      {occ, effects} = opened(ref, occupancy(), nil, "house")
      assert effects == []

      {occ, effects} = Occupancy.music_changed(occ, "page")
      assert effects == [{:look_up_track, ref, @gives}]

      {occ, effects} = Occupancy.track_looked_up(occ, ref, nil)
      assert {:enqueue_track, ref, @gives, 1_000} in effects
      assert {:start_vamp, ref, @gives} in effects

      assert {_occ, []} = Occupancy.music_changed(occ, "page")
    end

    test "to page plays a Track the TrackCache holds by then" do
      ref = make_ref()
      {occ, _} = opened(ref, occupancy(), nil, "off")

      {occ, [{:look_up_track, ^ref, @gives}]} = Occupancy.music_changed(occ, "page")
      {occ, effects} = Occupancy.track_looked_up(occ, ref, @cached)
      assert logged(effects) == ["cache hit"]
      assert Occupancy.view(occ, table()).playing.kind == "track"
    end

    test "to page starts nothing while the Page's Track work is already running" do
      {occ, _} = opened(make_ref())
      assert {_occ, []} = Occupancy.music_changed(occ, "page")
    end

    test "to page starts nothing once this Page's Track has landed" do
      ref = make_ref()
      {occ, _} = opened(ref)
      occ = arrive(occ, ref, {:track, {:ok, @track}})

      assert {_occ, []} = Occupancy.music_changed(occ, "page")
    end

    test "to page starts nothing with no Page open" do
      assert {_occ, []} = Occupancy.music_changed(occupancy(), "page")
    end

    test "a TrackCache answer for a Page no longer current starts nothing" do
      ref = make_ref()
      {occ, _} = opened(ref, occupancy(), nil, "house")
      {occ, _} = Occupancy.music_changed(occ, "page")
      occ = Occupancy.gives_reset(occ)

      assert {_occ, []} = Occupancy.track_looked_up(occ, ref, nil)
    end

    test "to house or off starts nothing" do
      {occ, _} = opened(make_ref(), occupancy(), nil, "house")
      assert {_occ, []} = Occupancy.music_changed(occ, "off")
      assert {_occ, []} = Occupancy.music_changed(occ, "house")
    end
  end

  describe "view/2" do
    setup do
      ref = make_ref()
      {occ, _} = opened(ref)
      %{occ: arrive(occ, ref, {:track, {:ok, @track}})}
    end

    test "off plays nothing and shows no Track or loop", %{occ: occ} do
      view = Occupancy.view(occ, table(%{music: "off"}))
      assert view.playing == nil
      assert view.track == nil
      assert view.vamp == nil
      assert view.loop == nil
      refute view.next?
      refute view.never?
    end

    test "house plays the Repertoire draw whatever Track exists" do
      ref = make_ref()
      {occ, _} = opened(ref, occupancy(@members))
      occ = arrive(occ, ref, {:track, {:ok, @track}})

      view = Occupancy.view(occ, table(%{music: "house"}))
      assert view.loop in @members
      assert view.playing == %{path: view.loop.path, title: view.loop.title, kind: "repertoire"}
      assert view.track == nil
      assert view.next?
      assert view.never?
    end

    test "page plays this Page's Track, which Next will not skip", %{occ: occ} do
      view = Occupancy.view(occ, table())
      assert view.playing.kind == "track"
      assert view.loop == @draw
      refute view.next?
      assert view.never?
    end

    test "the last remaining member is neither skipped nor refused" do
      view = Occupancy.view(occupancy(), table())
      assert view.playing.kind == "repertoire"
      refute view.next?
      refute view.never?
    end
  end

  describe "the Repertoire draw" do
    test "a new Occupancy plays a draw from the members it was given" do
      view = Occupancy.view(occupancy(@members), table())
      assert view.playing.kind == "repertoire"
      assert view.loop in @members
    end

    test "page_turned draws afresh from the members passed in, not repeating the last draw" do
      occ = occupancy(@members)
      before = Occupancy.view(occ, table()).loop

      occ = Occupancy.page_turned(occ, @members)
      refute Occupancy.view(occ, table()).loop == before

      occ = Occupancy.page_turned(occ, [@third])
      assert Occupancy.view(occ, table()).loop == @third
    end
  end

  describe "Next" do
    test "is refused on this Page's Track" do
      ref = make_ref()
      {occ, _} = opened(ref, occupancy(@members))
      occ = arrive(occ, ref, {:track, {:ok, @track}})

      refute Occupancy.view(occ, table()).next?
      assert Occupancy.next(occ, table()) == {:error, :refused}
    end

    test "is refused with only one member" do
      refute Occupancy.view(occupancy(), table()).next?
      assert Occupancy.next(occupancy(), table()) == {:error, :refused}
    end

    test "is refused under off" do
      assert Occupancy.next(occupancy(@members), table(%{music: "off"})) == {:error, :refused}
    end

    test "on a Repertoire draw moves to another member" do
      occ = occupancy(@members)
      before = Occupancy.view(occ, table()).playing

      assert {:ok, occ, []} = Occupancy.next(occ, table())
      after_next = Occupancy.view(occ, table()).playing
      assert after_next.kind == "repertoire"
      refute after_next.path == before.path
    end

    test "on a holdover drops the held-over Track for a Repertoire draw" do
      ref = make_ref()
      {occ, _} = opened(ref, occupancy(@members))
      occ = arrive(occ, ref, {:track, {:ok, @track}})
      occ = Occupancy.page_turned(occ, @members)
      assert Occupancy.view(occ, table()).next?

      assert {:ok, occ, []} = Occupancy.next(occ, table())
      view = Occupancy.view(occ, table())
      assert view.playing.kind == "repertoire"
      assert view.track == nil
      assert Occupancy.view(occ, table(%{closed?: true})).playing.kind == "repertoire"

      next_ref = make_ref()
      {occ, _} = opened(next_ref, occ)
      occ = arrive(occ, next_ref, {:track, {:ok, Map.put(@track, :path, "/media/next.mp3")}})
      assert Occupancy.view(occ, table()).playing.path == "/media/next.mp3"
      assert Occupancy.view(occ, table()).playing.kind == "track"
    end

    test "moves through the deal without repeating, then reshuffles when it runs out" do
      occ = occupancy([@draw, @other, @third])
      first = Occupancy.view(occ, table()).playing.path

      {:ok, occ, []} = Occupancy.next(occ, table())
      second = Occupancy.view(occ, table()).playing.path
      {:ok, occ, []} = Occupancy.next(occ, table())
      third = Occupancy.view(occ, table()).playing.path

      assert Enum.sort([first, second, third]) ==
               Enum.sort([@draw.path, @other.path, @third.path])

      {:ok, occ, []} = Occupancy.next(occ, table())
      reshuffled = Occupancy.view(occ, table()).playing
      assert reshuffled.kind == "repertoire"
      refute reshuffled.path == third
    end
  end

  describe "Never" do
    test "removes the playing member, asks for the Never to be recorded, and moves on" do
      occ = occupancy([@draw, @other, @third])
      nevered = Occupancy.view(occ, table()).playing.path

      assert {:ok, occ, [{:record_never, ^nevered}]} = Occupancy.never(occ, table())
      refute Occupancy.view(occ, table()).playing.path == nevered

      Enum.reduce(1..6, occ, fn _, occ ->
        {:ok, occ, []} = Occupancy.next(occ, table())
        refute Occupancy.view(occ, table()).playing.path == nevered
        occ
      end)
    end

    test "is refused on the last remaining member" do
      refute Occupancy.view(occupancy(), table()).never?
      assert Occupancy.never(occupancy(), table()) == {:error, :refused}

      {:ok, occ, _} = Occupancy.never(occupancy(@members), table())
      refute Occupancy.view(occ, table()).never?
      refute Occupancy.view(occ, table()).next?
      assert Occupancy.never(occ, table()) == {:error, :refused}
    end

    test "on this Page's Track clears it from the Speaker, so it does not hold over" do
      ref = make_ref()
      {occ, _} = opened(ref, occupancy(@members))
      occ = arrive(occ, ref, {:track, {:ok, @track}})
      assert Occupancy.view(occ, table()).never?

      assert {:ok, occ, [{:record_never, path}]} = Occupancy.never(occ, table())
      assert path == @track.path
      assert Occupancy.view(occ, table()).playing.kind == "repertoire"
      assert Occupancy.view(occ, table()).track == nil

      occ = Occupancy.page_turned(occ, @members)
      assert Occupancy.view(occ, table()).playing.kind == "repertoire"
    end

    test "on a holdover clears it from the Speaker" do
      ref = make_ref()
      {occ, _} = opened(ref, occupancy(@members))
      occ = arrive(occ, ref, {:track, {:ok, @track}})
      occ = Occupancy.page_turned(occ, @members)

      assert {:ok, occ, [{:record_never, path}]} = Occupancy.never(occ, table())
      assert path == @track.path
      view = Occupancy.view(occ, table())
      assert view.playing.kind == "repertoire"
      assert view.track == nil

      next_ref = make_ref()
      {occ, _} = opened(next_ref, occ)
      occ = arrive(occ, next_ref, {:track, {:ok, Map.put(@track, :path, "/media/next.mp3")}})
      assert Occupancy.view(occ, table()).playing.path == "/media/next.mp3"
      assert Occupancy.view(occ, table()).playing.kind == "track"
    end
  end

  describe "next? and never?" do
    test "agree with what next and never would do" do
      ref = make_ref()
      {opened_occ, _} = opened(ref, occupancy(@members))
      vamping = arrive(opened_occ, ref, {:vamp, {:ok, @vamp}})
      tracked = arrive(opened_occ, ref, {:track, {:ok, @track}})
      held_over = Occupancy.page_turned(tracked, @members)
      {:ok, last_left, _} = Occupancy.never(occupancy(@members), table())

      cases =
        for occ <- [occupancy(), occupancy(@members), vamping, tracked, held_over, last_left],
            music <- ["page", "house", "off"],
            closed? <- [false, true],
            do: {occ, table(%{music: music, closed?: closed?})}

      for {occ, table} <- cases do
        view = Occupancy.view(occ, table)
        assert view.next? == match?({:ok, _, _}, Occupancy.next(occ, table))
        assert view.never? == match?({:ok, _, _}, Occupancy.never(occ, table))
      end
    end
  end

  describe "chronicle_meta/2" do
    test "a Page closing with its Track unfinished records an unfinished failure" do
      ref = make_ref()
      {occ, _} = opened(ref)
      occ = arrive(occ, ref, {:vamp, {:ok, @vamp}})

      meta = Occupancy.chronicle_meta(occ, "page")
      assert meta.music_meta.failure == "unfinished"
      assert meta.vamp_meta.path == @vamp.path
    end

    test "a Page closing under house or off records no music" do
      ref = make_ref()
      {occ, _} = opened(ref)
      occ = arrive(occ, ref, {:track, {:ok, @track}})

      assert Occupancy.chronicle_meta(occ, "house").music_meta == nil
      assert Occupancy.chronicle_meta(occ, "off").music_meta == nil
    end
  end
end
