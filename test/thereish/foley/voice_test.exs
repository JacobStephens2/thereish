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

  defp table(overrides \\ %{}) do
    Map.merge(
      %{attempt: 1, phase: :bridging, bookends: @bookends, speaker?: true, quips?: true},
      Map.new(overrides)
    )
  end

  defp entry(numbers) do
    %{
      attempts: Enum.map(numbers, fn n -> %{number: n, verdicts: [%{band: :miss}]} end)
    }
  end

  defp line(voice, verdict, table) do
    {_voice, [{:speak, _n, :verdict, line}]} = Voice.verdict_received(voice, verdict, table)
    line
  end

  # A Voice that has spoken attempt 1's Verdict and is waiting for it.
  defp verdict_in_flight do
    {voice, _} = Voice.verdict_received(Voice.new(), %{band: :miss}, table(phase: :assaying))
    voice
  end

  describe "the Bookends" do
    test "are spoken when an Attempt opens with a Speaker held during bridging" do
      assert {_voice, [{:speak, 1, :bookends, "harbour. lantern"}]} =
               Voice.table_moved(Voice.new(), table())
    end

    test "are spoken once per Attempt" do
      {voice, _} = Voice.table_moved(Voice.new(), table())
      assert {voice, []} = Voice.table_moved(voice, table())

      {voice, _} = Voice.spoken(voice, 1, :bookends, {:ok, @clip}, table())
      assert {_voice, []} = Voice.table_moved(voice, table())
    end

    test "are spoken again for the next Attempt" do
      {voice, _} = Voice.table_moved(Voice.new(), table())

      assert {_voice, [{:speak, 2, :bookends, _line}]} =
               Voice.table_moved(voice, table(attempt: 2))
    end

    test "a new Attempt forgets Bookends still in flight for the last one" do
      {voice, _} = Voice.table_moved(Voice.new(), table())
      {voice, _} = Voice.table_moved(voice, table(attempt: 2, phase: :assaying))

      assert {_voice, [{:speak, 2, :bookends, _line}]} =
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

      assert {_voice, [{:speak, 1, :bookends, _line}]} =
               Voice.speaker_claimed(voice, table())
    end

    test "a landed clip is announced only while bridging" do
      {voice, _} = Voice.table_moved(Voice.new(), table())

      assert {_voice, [{:broadcast, {:bookends_ready, 1}}]} =
               Voice.spoken(voice, 1, :bookends, {:ok, @clip}, table())

      assert {_voice, []} =
               Voice.spoken(voice, 1, :bookends, {:ok, @clip}, table(phase: :assaying))
    end

    test "a failed synthesis is logged and nothing is announced" do
      {voice, _} = Voice.table_moved(Voice.new(), table())

      assert {voice, [{:log, :warning, message}]} =
               Voice.spoken(voice, 1, :bookends, {:error, @failure}, table())

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
      voice = verdict_in_flight()

      assert {voice, [{:broadcast, {:voice_ready, 1}}]} =
               Voice.spoken(voice, 1, :verdict, {:ok, @clip}, table(phase: :reveal))

      assert {:ok, "audio-bytes", :mp3} = Voice.clip(voice, 1, :verdict, table(phase: :reveal))
      assert {:ok, "audio-bytes", :mp3} = Voice.clip(voice, 1, "verdict", table(phase: :reveal))
    end

    test "arriving after the next Attempt started is dropped and logged" do
      voice = verdict_in_flight()
      {voice, _} = Voice.table_moved(voice, table(attempt: 2))

      assert {voice, [{:log, :warning, message}]} =
               Voice.spoken(voice, 1, :verdict, {:ok, @clip}, table(attempt: 2))

      assert message =~ "dropping"
      assert {:error, :not_found} = Voice.clip(voice, 1, :verdict, table(attempt: 2))
      assert {:error, :not_found} = Voice.clip(voice, 2, :verdict, table(attempt: 2))
    end
  end

  describe "clip lookup" do
    setup do
      {voice, _} = Voice.table_moved(Voice.new(), table())
      {voice, _} = Voice.spoken(voice, 1, :bookends, {:ok, @clip}, table())
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
      {voice, _} = Voice.table_moved(Voice.new(), table())
      {voice, _} = Voice.spoken(voice, 1, :bookends, {:ok, @clip}, table())

      assert {_voice, [{:broadcast, {:bookends_ready, 1}}]} =
               Voice.speaker_claimed(voice, table())
    end

    test "offers the Verdict clip already held at the reveal" do
      {voice, _} = Voice.spoken(verdict_in_flight(), 1, :verdict, {:ok, @clip}, table())

      assert {_voice, [{:broadcast, {:voice_ready, 1}}]} =
               Voice.speaker_claimed(voice, table(phase: :reveal))
    end

    test "offers nothing for a past Attempt's clips" do
      {voice, _} = Voice.table_moved(Voice.new(), table())
      {voice, _} = Voice.spoken(voice, 1, :bookends, {:ok, @clip}, table())

      assert {_voice, [{:speak, 2, :bookends, _line}]} =
               Voice.speaker_claimed(voice, table(attempt: 2))
    end
  end

  describe "the Chronicle hold" do
    test "a Page with no Verdict being spoken is committed at once" do
      assert {_voice, [{:commit_chronicle, %{attempts: [%{number: 1}]}}]} =
               Voice.page_closed(Voice.new(), entry([1]))
    end

    test "a Page whose Verdict is being spoken waits, and is committed before voice_ready" do
      {voice, effects} = Voice.page_closed(verdict_in_flight(), entry([1]))
      assert effects == []

      assert {_voice, [{:commit_chronicle, committed}, {:broadcast, {:voice_ready, 1}}]} =
               Voice.spoken(voice, 1, :verdict, {:ok, @clip}, table(phase: :closed))

      [%{verdicts: [verdict]}] = committed.attempts
      assert verdict.voice_meta["provider"] == "fake"
      assert verdict.voice_meta["voice"] == "v1"
      assert verdict.voice_meta["model"] == "v1"
    end

    test "a failed synthesis records its failure metadata on the held Page" do
      {voice, []} = Voice.page_closed(verdict_in_flight(), entry([1]))

      assert {_voice, [{:log, :warning, _message}, {:commit_chronicle, committed}]} =
               Voice.spoken(voice, 1, :verdict, {:error, @failure}, table(phase: :closed))

      [%{verdicts: [verdict]}] = committed.attempts
      assert verdict.voice_meta == @failure
    end

    test "a Page closing after its Verdict metadata landed is committed with it" do
      {voice, _} = Voice.spoken(verdict_in_flight(), 1, :verdict, {:ok, @clip}, table())

      assert {_voice, [{:commit_chronicle, committed}]} = Voice.page_closed(voice, entry([1]))
      [%{verdicts: [verdict]}] = committed.attempts
      assert verdict.voice_meta["provider"] == "fake"
    end

    test "turning the Page flushes a held Page with what has landed" do
      {voice, []} = Voice.page_closed(verdict_in_flight(), entry([1]))

      assert {voice, [{:commit_chronicle, committed}]} = Voice.page_turned(voice)
      [%{verdicts: [verdict]}] = committed.attempts
      refute Map.has_key?(verdict, :voice_meta)

      assert {_voice, []} = Voice.page_turned(voice)
    end

    test "turning the Page forgets the Verdict in flight and its clips" do
      voice = verdict_in_flight()
      {voice, []} = Voice.page_turned(voice)

      assert {_voice, [{:commit_chronicle, _entry}]} = Voice.page_closed(voice, entry([1]))
    end
  end

  describe "provider metadata" do
    test "falls back across atom and string keys" do
      raw = %{
        "provider" => "hume",
        "voice_id" => "v9",
        "cost" => 0.02,
        latency: 120
      }

      {voice, []} = Voice.page_closed(verdict_in_flight(), entry([1]))

      {_voice, [{:commit_chronicle, committed}, _ready]} =
        Voice.spoken(voice, 1, :verdict, {:ok, %{@clip | meta: raw}}, table())

      [%{verdicts: [verdict]}] = committed.attempts

      assert verdict.voice_meta == %{
               "provider" => "hume",
               "voice" => "v9",
               "model" => "v9",
               "cost_usd" => 0.02,
               "latency_ms" => 120
             }
    end

    test "defaults with none" do
      {voice, []} = Voice.page_closed(verdict_in_flight(), entry([1]))
      clip = Map.delete(@clip, :meta)

      {_voice, [{:commit_chronicle, committed}, _ready]} =
        Voice.spoken(voice, 1, :verdict, {:ok, clip}, table())

      [%{verdicts: [verdict]}] = committed.attempts

      assert %{"provider" => "hume", "voice" => "default", "model" => "default"} =
               verdict.voice_meta
    end
  end
end
