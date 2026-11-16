defmodule Thereish.Foley.VoiceTest do
  @moduledoc """
  Foley's Voice, driven as a list of things that happen to a Room and asserted
  on the effects it asks the Room to perform and the clips it serves.

  Everything here goes through the interface. No test reads a struct field.
  """
  use ExUnit.Case, async: true

  alias Thereish.Foley.Voice

  @bookends ["harbour", "lantern"]
  @clip %{audio: "audio-bytes", format: :mp3, meta: %{provider: "fake", voice: "v1"}}
  @failure %{
    "provider" => "fake",
    "voice" => "fake-voice",
    "cost_usd" => 0.0,
    "failure" => "unavailable"
  }

  test "a turned Page's Bookends cannot land on another Page's Attempt 1" do
    {voice, [{:speak, old_request, _}]} = Voice.table_moved(Voice.new(), table())
    {voice, []} = Voice.page_turned(voice)
    {voice, _current_request} = Voice.table_moved(voice, table())

    {voice, effects} = Voice.spoken(voice, old_request, {:ok, @clip}, table())

    refute Enum.any?(effects, &match?({:broadcast, _}, &1))
    assert {:error, :not_found} = Voice.clip(voice, 1, :bookends, table())
    assert {_voice, []} = Voice.table_moved(voice, table())
  end

  defp table(overrides \\ %{}) do
    Map.merge(
      %{attempt: 1, phase: :bridging, bookends: @bookends, speaker?: true, quips?: true},
      Map.new(overrides)
    )
  end

  defp line(voice, verdict, table) do
    {_voice, [{:verdict_pending, _n}, {:speak, _request, line}]} =
      Voice.verdict_received(voice, verdict, table)

    line
  end

  # A Voice that has spoken attempt 1's Verdict and is waiting for it.
  defp verdict_in_flight do
    {voice, [{:verdict_pending, 1}, {:speak, request, _line}]} =
      Voice.verdict_received(Voice.new(), %{band: :miss}, table(phase: :assaying))

    {voice, request}
  end

  defp request(voice, kind, table) do
    {voice, effects} =
      case kind do
        :bookends -> Voice.table_moved(voice, table)
        :verdict -> Voice.verdict_received(voice, %{band: :miss}, table)
      end

    {:speak, request, _line} = Enum.find(effects, &match?({:speak, _, _}, &1))
    assert is_reference(request)
    {voice, request}
  end

  defp ignored(voice, request, result, table) do
    assert {^voice, effects} = Voice.spoken(voice, request, result, table)
    assert Enum.all?(effects, &match?({:log, _, _}, &1))
    voice
  end

  describe "speech from a turned Page" do
    for {kind, ready, phase} <- [
          {:bookends, :bookends_ready, :bridging},
          {:verdict, :voice_ready, :assaying}
        ],
        outcome <- [:ok, :error],
        order <- [:before_current, :after_current] do
      test "#{kind} #{outcome} delivered #{order} cannot touch the next Page's Attempt 1" do
        kind = unquote(kind)
        {voice, old} = request(Voice.new(), kind, table())
        {voice, []} = Voice.page_turned(voice)
        {voice, current} = request(voice, kind, table())
        refute old == current

        stale = if unquote(outcome) == :ok, do: {:ok, @clip}, else: {:error, @failure}

        voice =
          if unquote(order) == :before_current do
            voice = ignored(voice, old, stale, table())
            assert {:error, :not_found} = Voice.clip(voice, 1, kind, table())
            assert {_voice, []} = Voice.table_moved(voice, table(phase: unquote(phase)))
            voice
          else
            voice
          end

        {voice, effects} =
          Voice.spoken(voice, current, {:ok, %{@clip | audio: "current"}}, table())

        assert {:broadcast, {unquote(ready), 1}} in effects
        assert {:ok, "current", :mp3} = Voice.clip(voice, 1, kind, table())

        if unquote(order) == :after_current do
          voice = ignored(voice, old, stale, table())
          assert {:ok, "current", :mp3} = Voice.clip(voice, 1, kind, table())
        end
      end
    end
  end

  describe "completion acceptance" do
    test "unknown successes and failures leave both pending requests and clips alone" do
      {voice, bookends} = request(Voice.new(), :bookends, table())
      {voice, verdict} = request(voice, :verdict, table())

      for result <- [{:ok, @clip}, {:error, @failure}] do
        ignored(voice, make_ref(), result, table(attempt: 2))
      end

      {voice, [{:broadcast, {:bookends_ready, 1}}]} =
        Voice.spoken(voice, bookends, {:ok, @clip}, table())

      {voice, [{:verdict_spoken, 1, _}, {:broadcast, {:voice_ready, 1}}]} =
        Voice.spoken(voice, verdict, {:ok, @clip}, table())

      for kind <- [:bookends, :verdict] do
        assert {:ok, "audio-bytes", :mp3} = Voice.clip(voice, 1, kind, table())
      end
    end

    test "replacement retires a Verdict's previous identity for either outcome" do
      {voice, old} = request(Voice.new(), :verdict, table())
      {voice, current} = request(voice, :verdict, table())
      refute old == current
      ignored(voice, old, {:ok, @clip}, table())
      ignored(voice, old, {:error, @failure}, table())
      assert {:error, :not_found} = Voice.clip(voice, 1, :verdict, table())

      assert {_voice, [{:log, :warning, _}, {:verdict_spoken, 1, meta}]} =
               Voice.spoken(voice, current, {:error, @failure}, table())

      assert meta == @failure
    end

    for kind <- [:bookends, :verdict], first <- [:ok, :error], second <- [:ok, :error] do
      test "#{kind} consumes #{first} once and ignores a following #{second}" do
        kind = unquote(kind)
        {voice, request} = request(Voice.new(), kind, table())
        result = if unquote(first) == :ok, do: {:ok, @clip}, else: {:error, @failure}
        {voice, _} = Voice.spoken(voice, request, result, table())

        result =
          if unquote(second) == :ok,
            do: {:ok, %{@clip | audio: "duplicate"}},
            else: {:error, @failure}

        ignored(voice, request, result, table())

        if unquote(first) == :ok do
          assert {:ok, "audio-bytes", :mp3} = Voice.clip(voice, 1, kind, table())
        else
          assert {:error, :not_found} = Voice.clip(voice, 1, kind, table())
        end
      end
    end

    test "an Attempt change discards both outcomes of earlier Bookends without clearing current work" do
      {voice, old} = request(Voice.new(), :bookends, table())
      {voice, current} = request(voice, :bookends, table(attempt: 2))
      refute old == current
      ignored(voice, old, {:ok, @clip}, table(attempt: 2))
      ignored(voice, old, {:error, @failure}, table(attempt: 2))
      assert {_voice, []} = Voice.table_moved(voice, table(attempt: 2))

      assert {voice, [{:broadcast, {:bookends_ready, 2}}]} =
               Voice.spoken(voice, current, {:ok, @clip}, table(attempt: 2))

      assert {:ok, "audio-bytes", :mp3} = Voice.clip(voice, 2, :bookends, table(attempt: 2))
    end

    test "earlier Verdict failures retain their Attempt and cannot consume newer work" do
      {voice, first} = request(Voice.new(), :verdict, table())
      {voice, second} = request(voice, :verdict, table(attempt: 2))
      {voice, latest} = request(voice, :verdict, table(attempt: 3))

      assert {voice, [{:log, :warning, _}, {:verdict_spoken, 1, meta}]} =
               Voice.spoken(voice, first, {:error, @failure}, table(attempt: 3))

      assert meta == @failure

      assert {:error, :not_found} = Voice.clip(voice, 3, :verdict, table(attempt: 3))
      ignored(voice, first, {:error, @failure}, table(attempt: 3))

      # Earlier successes are consumed without a clip or metadata, even if
      # a failure for the same identity follows them.
      assert {voice, [{:log, :warning, _}]} =
               Voice.spoken(voice, second, {:ok, @clip}, table(attempt: 3))

      ignored(voice, second, {:error, @failure}, table(attempt: 3))

      assert {voice, [{:verdict_spoken, 3, _}, {:broadcast, {:voice_ready, 3}}]} =
               Voice.spoken(voice, latest, {:ok, @clip}, table(attempt: 3))

      assert {:ok, "audio-bytes", :mp3} = Voice.clip(voice, 3, :verdict, table(attempt: 3))
    end
  end

  describe "the Bookends" do
    test "are spoken when an Attempt opens with a Speaker held during bridging" do
      assert {_voice, [{:speak, request, "harbour. lantern"}]} =
               Voice.table_moved(Voice.new(), table())

      assert is_reference(request)
    end

    test "are spoken once per Attempt" do
      {voice, [{:speak, request, _}]} = Voice.table_moved(Voice.new(), table())
      assert {voice, []} = Voice.table_moved(voice, table())

      {voice, _} = Voice.spoken(voice, request, {:ok, @clip}, table())
      assert {_voice, []} = Voice.table_moved(voice, table())
    end

    test "are spoken again for the next Attempt" do
      {voice, _} = Voice.table_moved(Voice.new(), table())

      assert {_voice, [{:speak, _request, _line}]} =
               Voice.table_moved(voice, table(attempt: 2))
    end

    test "a new Attempt forgets Bookends still in flight for the last one" do
      {voice, _} = Voice.table_moved(Voice.new(), table())
      {voice, _} = Voice.table_moved(voice, table(attempt: 2, phase: :assaying))

      assert {_voice, [{:speak, _request, _line}]} =
               Voice.table_moved(voice, table(attempt: 2))
    end

    test "are not spoken without a Speaker, outside bridging, or with none" do
      assert {_voice, []} = Voice.table_moved(Voice.new(), table(speaker?: false))
      assert {_voice, []} = Voice.table_moved(Voice.new(), table(phase: :reveal))
      assert {_voice, []} = Voice.table_moved(Voice.new(), table(bookends: []))
      assert {_voice, []} = Voice.table_moved(Voice.new(), table(bookends: nil))
    end

    test "are spoken when the Speaker is claimed during bridging" do
      {voice, []} = Voice.table_moved(Voice.new(), table(speaker?: false))

      assert {_voice, [{:speak, _request, _line}]} =
               Voice.speaker_claimed(voice, table())
    end

    test "a landed clip is announced only while bridging" do
      {voice, [{:speak, request, _}]} = Voice.table_moved(Voice.new(), table())

      assert {_voice, [{:broadcast, {:bookends_ready, 1}}]} =
               Voice.spoken(voice, request, {:ok, @clip}, table())

      assert {_voice, []} =
               Voice.spoken(voice, request, {:ok, @clip}, table(phase: :assaying))
    end

    test "a clip arriving after the next Attempt started is dropped and logged" do
      {voice, [{:speak, request, _}]} = Voice.table_moved(Voice.new(), table())
      {voice, _} = Voice.table_moved(voice, table(attempt: 2, phase: :assaying))

      assert {voice, [{:log, :warning, message}]} =
               Voice.spoken(
                 voice,
                 request,
                 {:ok, @clip},
                 table(attempt: 2, phase: :assaying)
               )

      assert message =~ "dropping"
      assert {:error, :not_found} = Voice.clip(voice, 1, :bookends, table(attempt: 2))
      assert {:error, :not_found} = Voice.clip(voice, 2, :bookends, table(attempt: 2))
    end

    test "a failed synthesis is logged and nothing is announced" do
      {voice, [{:speak, request, _}]} = Voice.table_moved(Voice.new(), table())

      assert {voice, [{:log, :warning, message}]} =
               Voice.spoken(voice, request, {:error, @failure}, table())

      assert message =~ "failed"
      assert {:error, :not_found} = Voice.clip(voice, 1, :bookends, table())
    end
  end

  describe "the Verdict line" do
    test "is the band word then the Quip with quips on" do
      verdict = %{band: :deep_meld, quip: "  Two minds walk into a bar.  "}
      assert line(Voice.new(), verdict, table()) == "deep meld. Two minds walk into a bar."
    end

    test "is the band word alone with quips off" do
      verdict = %{band: :deep_meld, quip: "Two minds walk into a bar."}
      assert line(Voice.new(), verdict, table(quips?: false)) == "deep meld"
    end

    test "is the band word alone when there is no Quip" do
      assert line(Voice.new(), %{"band" => "miss", "quip" => ""}, table()) == "miss"
    end

    test "reads the band from Closeness on the Ladder when the Verdict has none" do
      band = Thereish.Ladder.read(100).band |> to_string() |> String.replace("_", " ")
      assert line(Voice.new(), %{"closeness" => 100}, table(quips?: false)) == band
    end

    test "falls back to miss with neither band nor Closeness" do
      assert line(Voice.new(), %{}, table()) == "miss"
    end

    test "is not spoken without a Speaker" do
      assert {_voice, []} =
               Voice.verdict_received(Voice.new(), %{band: :miss}, table(speaker?: false))
    end
  end

  describe "a landed Verdict clip" do
    test "is announced and served for its Attempt" do
      {voice, request} = verdict_in_flight()

      assert {voice, [{:verdict_spoken, 1, meta}, {:broadcast, {:voice_ready, 1}}]} =
               Voice.spoken(voice, request, {:ok, @clip}, table(phase: :reveal))

      assert meta == %{
               "provider" => "fake",
               "voice" => "v1",
               "model" => "v1",
               "cost_usd" => nil,
               "latency_ms" => nil
             }

      assert {:ok, "audio-bytes", :mp3} = Voice.clip(voice, 1, :verdict, table(phase: :reveal))
      assert {:ok, "audio-bytes", :mp3} = Voice.clip(voice, 1, "verdict", table(phase: :reveal))
    end

    test "arriving after the next Attempt started is dropped and logged" do
      {voice, request} = verdict_in_flight()
      {voice, _} = Voice.table_moved(voice, table(attempt: 2))

      assert {voice, [{:log, :warning, message}]} =
               Voice.spoken(voice, request, {:ok, @clip}, table(attempt: 2))

      assert message =~ "dropping"
      assert {:error, :not_found} = Voice.clip(voice, 1, :verdict, table(attempt: 2))
      assert {:error, :not_found} = Voice.clip(voice, 2, :verdict, table(attempt: 2))
    end
  end

  describe "clip lookup" do
    setup do
      {voice, [{:speak, request, _}]} = Voice.table_moved(Voice.new(), table())
      {voice, _} = Voice.spoken(voice, request, {:ok, @clip}, table())
      %{voice: voice}
    end

    test "serves the current Attempt's clip by atom or string kind", %{voice: voice} do
      assert {:ok, "audio-bytes", :mp3} = Voice.clip(voice, 1, :bookends, table())
      assert {:ok, "audio-bytes", :mp3} = Voice.clip(voice, 1, "bookends", table())
    end

    test "is not found for a missing or unknown kind", %{voice: voice} do
      assert {:error, :not_found} = Voice.clip(voice, 1, :verdict, table())
      assert {:error, :not_found} = Voice.clip(voice, 1, "nonsense", table())
      assert {:error, :not_found} = Voice.clip(voice, 1, nil, table())
    end

    test "is not found for a past Attempt", %{voice: voice} do
      assert {:error, :not_found} = Voice.clip(voice, 1, :bookends, table(attempt: 2))

      {voice, _} = Voice.table_moved(voice, table(attempt: 2, phase: :assaying))
      assert {:error, :not_found} = Voice.clip(voice, 1, :bookends, table(attempt: 2))
      assert {:error, :not_found} = Voice.clip(voice, 2, :bookends, table(attempt: 2))
    end
  end

  describe "claiming the Speaker" do
    test "offers the Bookends clip already held while bridging, without speaking again" do
      {voice, [{:speak, request, _}]} = Voice.table_moved(Voice.new(), table())
      {voice, _} = Voice.spoken(voice, request, {:ok, @clip}, table())

      assert {_voice, [{:broadcast, {:bookends_ready, 1}}]} =
               Voice.speaker_claimed(voice, table())
    end

    test "offers the Verdict clip already held at the reveal" do
      {voice, request} = verdict_in_flight()
      {voice, _} = Voice.spoken(voice, request, {:ok, @clip}, table())

      assert {_voice, [{:broadcast, {:voice_ready, 1}}]} =
               Voice.speaker_claimed(voice, table(phase: :reveal))
    end

    test "offers nothing for a past Attempt's clips" do
      {voice, [{:speak, request, _}]} = Voice.table_moved(Voice.new(), table())
      {voice, _} = Voice.spoken(voice, request, {:ok, @clip}, table())

      assert {_voice, [{:speak, _request, _line}]} =
               Voice.speaker_claimed(voice, table(attempt: 2))
    end
  end

  test "failed Verdict speech reports unchanged metadata after its log" do
    {voice, request} = verdict_in_flight()

    assert {_voice, [{:log, :warning, _}, {:verdict_spoken, 1, meta}]} =
             Voice.spoken(voice, request, {:error, @failure}, table())

    assert meta == @failure
  end

  test "turning the Page forgets clips and allows fresh synthesis" do
    {voice, request} = verdict_in_flight()
    {voice, _} = Voice.spoken(voice, request, {:ok, @clip}, table())
    {voice, []} = Voice.page_turned(voice)
    assert {:error, :not_found} = Voice.clip(voice, 1, :verdict, table())

    assert {_voice, [{:verdict_pending, 1}, {:speak, _request, _}]} =
             Voice.verdict_received(voice, %{band: :miss}, table())
  end

  describe "provider metadata" do
    test "falls back across atom and string keys" do
      {voice, request} = verdict_in_flight()

      raw = %{
        "provider" => "hume",
        "voice_id" => "v9",
        "cost" => 0.02,
        latency: 120
      }

      {_voice, [{:verdict_spoken, 1, meta}, _ready]} =
        Voice.spoken(voice, request, {:ok, %{@clip | meta: raw}}, table())

      assert meta == %{
               "provider" => "hume",
               "voice" => "v9",
               "model" => "v9",
               "cost_usd" => 0.02,
               "latency_ms" => 120
             }
    end

    test "defaults with none" do
      {voice, request} = verdict_in_flight()
      clip = Map.delete(@clip, :meta)

      {_voice, [{:verdict_spoken, 1, meta}, _ready]} =
        Voice.spoken(voice, request, {:ok, clip}, table())

      assert %{"provider" => nil, "voice" => "default", "model" => "default"} =
               meta
    end
  end
end
