defmodule Mix.Tasks.Foley.Listen do
  @moduledoc """
  Measures wall-clock time to first audible sample across three audio beds for Foley music:

    1. Control: Current Mureka poll-then-download path (full mix generation).
    2. Mureka Stream: Mureka with `stream: true`, polling for `stream_url` during generation.
    3. ElevenLabs Loop: ElevenLabs Sound Generation (≤30 s seamless loop) with `loop: true`.

  Outputs audio files, `report.json`, and `report.txt` into the destination directory.

  ## Options

    * `--gives`, `-g` - Comma-separated gives (default: "pine, cold river")
    * `--room`, `-r` - Room Code to draw recent gives from (optional)
    * `--dir`, `-d` - Destination directory (default: ".scratch/nights-music/listen")
    * `--live` - Force live provider calls using environment API keys
    * `--fake` - Force fake/fixture responses without network calls
    * `--probe` - Probe live streaming URL for first audio chunk TTFB (default: true)
    * `--deadline` - Generation deadline in milliseconds (default: 180_000)

  ## Examples

      $ mix foley.listen
      $ mix foley.listen --gives "cabin, blizzard" --dir .scratch/nights-music/listen
      $ mix foley.listen pine "cold river"
      $ mix foley.listen --live
  """
  use Mix.Task

  alias Thereish.Steward
  alias Thereish.Steward.ElevenLabs
  alias Thereish.Steward.Music
  alias Thereish.Steward.Mureka

  @shortdoc "Measures time to first audible audio for Foley music across three candidate beds"

  @switches [
    gives: :string,
    room: :string,
    dir: :string,
    live: :boolean,
    fake: :boolean,
    probe: :boolean,
    deadline: :integer
  ]

  @aliases [
    g: :gives,
    r: :room,
    d: :dir
  ]

  @default_gives ["pine", "cold river"]
  @default_dir ".scratch/nights-music/listen"
  @default_deadline_ms 180_000

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, argv} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)

    dir = opts[:dir] || @default_dir
    File.mkdir_p!(dir)

    gives = resolve_gives(opts, argv)
    prompt = Music.prompt(gives)
    deadline_ms = opts[:deadline] || @default_deadline_ms

    fake? =
      cond do
        opts[:fake] -> true
        opts[:live] -> false
        Steward.adapter() == Thereish.Steward.Fake -> true
        true -> false
      end

    Mix.shell().info("""
    ================================================================================
    FIRST AUDIBLE LISTEN: MEASURING THREE BEDS FROM THE SAME GIVES
    ================================================================================
    Mode: #{if fake?, do: "Fake / Fixture (offline)", else: "LIVE (calling providers)"}
    Gives: #{inspect(gives)}
    Prompt: #{prompt}
    Output dir: #{Path.expand(dir)}
    """)

    results =
      if fake? do
        run_fake_beds(dir, gives, prompt)
      else
        run_live_beds(dir, gives, prompt, deadline_ms, Keyword.get(opts, :probe, true))
      end

    write_reports(dir, gives, prompt, fake?, results)
    print_summary(results)
  end

  defp resolve_gives(opts, argv) do
    cond do
      opts[:gives] ->
        opts[:gives]
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      argv != [] ->
        argv
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      opts[:room] ->
        case find_room_gives(opts[:room]) do
          {:ok, room_gives} when is_list(room_gives) and room_gives != [] -> room_gives
          _ -> @default_gives
        end

      true ->
        @default_gives
    end
  end

  defp find_room_gives(room_code) do
    try do
      case Thereish.Chronicle.book(room_code) do
        [%{gives: gives} | _] when is_list(gives) and length(gives) >= 2 -> {:ok, gives}
        _ -> :none
      end
    rescue
      _ -> :none
    end
  end

  # ---------------------------------------------------------------------------
  # Fake execution
  # ---------------------------------------------------------------------------

  defp run_fake_beds(dir, _gives, _prompt) do
    fixture = Thereish.Steward.Fake.mp3_fixture()

    Mix.shell().info("--> [1/3] Measuring Bed 1: Control (poll-then-download)...")
    control_file = "01-control.mp3"
    File.write!(Path.join(dir, control_file), fixture)

    control_bed = %{
      name: "Control (poll-then-download)",
      provider: "Mureka",
      model: "auto",
      status: "succeeded",
      time_to_first_audible_ms: 54_200,
      music_meta_latency_ms: 54_200,
      format: "audio/mpeg",
      codec: "MP3 (44.1 kHz, 128 kbps)",
      playable: true,
      cost_usd: 0.045,
      bytes: byte_size(fixture),
      file: control_file,
      notes: "Full track downloaded after job succeeded."
    }

    Mix.shell().info("--> [2/3] Measuring Bed 2: Mureka stream (stream: true / stream_url)...")
    stream_file = "02-mureka-stream.aac"
    stream_url = "https://stream.mureka.ai/live/fake_stream_sample.aac"
    File.write!(Path.join(dir, stream_file), fixture)
    File.write!(Path.join(dir, "02-mureka-stream.url"), stream_url <> "\n")

    stream_bed = %{
      name: "Mureka stream (stream: true)",
      provider: "Mureka",
      model: "auto",
      status: "streaming",
      stream_url: stream_url,
      time_to_stream_url_ms: 18_400,
      time_to_first_audible_ms: 19_100,
      music_meta_latency_ms: 18_400,
      format: "audio/mpeg",
      codec: "MP3 stream (browser playable)",
      playable: true,
      cost_usd: 0.045,
      bytes: byte_size(fixture),
      file: stream_file,
      notes: "stream_url available at 18.4 s during streaming status; first byte at 19.1 s."
    }

    Mix.shell().info("--> [3/3] Measuring Bed 3: ElevenLabs Sound Generation (≤30 s loop)...")
    eleven_file = "03-elevenlabs-30s-loop.mp3"
    File.write!(Path.join(dir, eleven_file), fixture)

    eleven_bed = %{
      name: "ElevenLabs SFX loop (≤30 s)",
      provider: "ElevenLabs",
      model: "eleven_text_to_sound_v2",
      status: "succeeded",
      time_to_first_audible_ms: 2_650,
      music_meta_latency_ms: 2_650,
      format: "audio/mpeg",
      codec: "MP3 (44.1 kHz, seamless loop)",
      playable: true,
      loop: true,
      cost_usd: 0.06,
      bytes: byte_size(fixture),
      file: eleven_file,
      notes: "Generated 30 s seamless audio loop under 3 seconds."
    }

    %{
      control: control_bed,
      mureka_stream: stream_bed,
      eleven_loop: eleven_bed
    }
  end

  # ---------------------------------------------------------------------------
  # Live execution
  # ---------------------------------------------------------------------------

  defp run_live_beds(dir, _gives, prompt, deadline_ms, probe?) do
    # Bed 1: Control
    Mix.shell().info("--> [1/3] Running Bed 1: Control (Mureka poll-then-download)...")
    control_bed = measure_live_control(dir, prompt, deadline_ms)

    # Bed 2: Mureka stream
    Mix.shell().info("--> [2/3] Running Bed 2: Mureka stream (stream: true / stream_url)...")
    stream_bed = measure_live_stream(dir, prompt, deadline_ms, probe?)

    # Bed 3: ElevenLabs SFX loop
    Mix.shell().info("--> [3/3] Running Bed 3: ElevenLabs Sound Generation (≤30 s loop)...")
    eleven_bed = measure_live_eleven(dir, prompt)

    %{
      control: control_bed,
      mureka_stream: stream_bed,
      eleven_loop: eleven_bed
    }
  end

  defp measure_live_control(dir, prompt, deadline_ms) do
    key = System.get_env("MUREKA_API_KEY")

    if is_nil(key) or key == "" do
      Mix.shell().error("  Missing MUREKA_API_KEY; skipping control bed")
      %{error: "Missing MUREKA_API_KEY", time_to_first_audible_ms: nil}
    else
      start_time = System.monotonic_time(:millisecond)

      case Mureka.generate(%{
             prompt: prompt,
             model: "auto",
             n: 1,
             api_key: key,
             deadline_ms: deadline_ms
           }) do
        {:ok, res} ->
          elapsed = System.monotonic_time(:millisecond) - start_time
          filename = "01-control.mp3"
          File.write!(Path.join(dir, filename), res.bytes)

          Mix.shell().info("  Succeeded in #{elapsed} ms (#{byte_size(res.bytes)} bytes)")

          %{
            name: "Control (poll-then-download)",
            provider: "Mureka",
            model: res.model,
            status: "succeeded",
            time_to_first_audible_ms: elapsed,
            music_meta_latency_ms: elapsed,
            format: "audio/mpeg",
            codec: "MP3",
            playable: true,
            cost_usd: res.cost_usd,
            bytes: byte_size(res.bytes),
            url: res.url,
            duration: res.duration,
            file: filename,
            notes: "Downloaded complete MP3 after succeeded status."
          }

        {:error, reason} ->
          Mix.shell().error("  Control generation failed: #{inspect(reason)}")

          %{
            name: "Control (poll-then-download)",
            provider: "Mureka",
            status: "failed",
            error: inspect(reason),
            time_to_first_audible_ms: nil,
            playable: false
          }
      end
    end
  end

  defp measure_live_stream(_dir, _prompt, _deadline_ms, _probe?) do
    Mix.shell().info("  Mureka stream removed in favor of ElevenLabs vamp")
    %{skipped: "Mureka stream removed in favor of ElevenLabs vamp", time_to_first_audible_ms: nil}
  end

  defp measure_live_eleven(dir, prompt) do
    key = System.get_env("ELEVENLABS_API_KEY")

    if is_nil(key) or key == "" do
      Mix.shell().error("  Missing ELEVENLABS_API_KEY; skipping ElevenLabs Vamp")
      %{error: "Missing ELEVENLABS_API_KEY", time_to_first_audible_ms: nil}
    else
      start_time = System.monotonic_time(:millisecond)

      case ElevenLabs.generate(%{
             text: prompt,
             duration_seconds: 30.0,
             loop: true,
             api_key: key
           }) do
        {:ok, res} ->
          elapsed = System.monotonic_time(:millisecond) - start_time
          filename = "03-elevenlabs-30s-loop.mp3"
          File.write!(Path.join(dir, filename), res.bytes)

          Mix.shell().info("  Succeeded in #{elapsed} ms (#{byte_size(res.bytes)} bytes)")

          %{
            name: "ElevenLabs SFX loop (≤30 s)",
            provider: "ElevenLabs",
            model: res.model,
            status: "succeeded",
            time_to_first_audible_ms: elapsed,
            music_meta_latency_ms: elapsed,
            format: "audio/mpeg",
            codec: "MP3 (44.1 kHz, seamless loop)",
            playable: true,
            loop: true,
            cost_usd: res.cost_usd,
            bytes: byte_size(res.bytes),
            character_cost: Map.get(res, :character_cost),
            file: filename,
            notes: "Generated 30 s seamless audio loop."
          }

        {:error, reason} ->
          Mix.shell().error("  ElevenLabs generation failed: #{inspect(reason)}")

          %{
            name: "ElevenLabs SFX loop (≤30 s)",
            provider: "ElevenLabs",
            status: "failed",
            error: inspect(reason),
            time_to_first_audible_ms: nil,
            playable: false
          }
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Reporting
  # ---------------------------------------------------------------------------

  defp write_reports(dir, gives, prompt, fake?, results) do
    report_data = %{
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      fake: fake?,
      gives: gives,
      prompt: prompt,
      beds: results
    }

    File.write!(Path.join(dir, "report.json"), Jason.encode!(report_data, pretty: true) <> "\n")

    summary_txt = """
    ================================================================================
    FIRST AUDIBLE LISTEN REPORT
    ================================================================================
    Timestamp: #{report_data.timestamp}
    Mode: #{if fake?, do: "Fake / Fixture", else: "Live Providers"}
    Gives: #{Enum.join(gives, ", ")}
    Prompt: #{prompt}

    --------------------------------------------------------------------------------
    MEASUREMENTS
    --------------------------------------------------------------------------------
    #{format_bed_txt("1. Control (poll-then-download)", results[:control])}

    #{format_bed_txt("2. Mureka Stream (stream: true)", results[:mureka_stream])}

    #{format_bed_txt("3. ElevenLabs Loop (≤30 s)", results[:eleven_loop])}

    ================================================================================
    ATTEMPT 1 TIMING BAR:
    Bar: During Attempt 1, before the second Attempt's Bridges (~20–45 s).
    ================================================================================
    """

    File.write!(Path.join(dir, "report.txt"), summary_txt)
  end

  defp format_bed_txt(label, nil), do: "#{label}: No data"
  defp format_bed_txt(label, %{error: err}), do: "#{label}: FAILED (#{err})"

  defp format_bed_txt(label, bed) do
    """
    #{label}:
      Provider: #{bed[:provider]} (#{bed[:model]})
      Status: #{bed[:status]}
      Time to first audible audio: #{bed[:time_to_first_audible_ms]} ms
      Chronicle music_meta.latency: #{bed[:music_meta_latency_ms]} ms
      Format / Codec: #{bed[:format]} (#{bed[:codec]})
      Browser Playable: #{bed[:playable]}
      Cost: $#{bed[:cost_usd]}
      File: #{bed[:file]}
      Notes: #{bed[:notes]}
    """
  end

  defp print_summary(results) do
    Mix.shell().info("""
    --------------------------------------------------------------------------------
    FIRST AUDIBLE LATENCY COMPARISON
    --------------------------------------------------------------------------------
    Bed                             | Wall-clock (ms) | Codec               | Playable | Cost
    --------------------------------+-----------------+---------------------+----------+--------
    Control (Mureka poll-download)  | #{pad_time(results[:control])} | MP3                 | #{pad_bool(results[:control])} | $#{get_in(results, [:control, :cost_usd]) || 0.045}
    Mureka Stream (stream: true)    | #{pad_time(results[:mureka_stream])} | #{pad_str(get_in(results, [:mureka_stream, :codec]) || "MP3", 19)} | #{pad_bool(results[:mureka_stream])} | $#{get_in(results, [:mureka_stream, :cost_usd]) || 0.045}
    ElevenLabs Loop (≤30 s)         | #{pad_time(results[:eleven_loop])} | MP3 (seamless loop) | #{pad_bool(results[:eleven_loop])} | $#{get_in(results, [:eleven_loop, :cost_usd]) || 0.06}
    --------------------------------------------------------------------------------
    """)
  end

  defp pad_time(%{time_to_first_audible_ms: ms}) when is_number(ms) do
    "#{ms} ms" |> String.pad_trailing(15)
  end

  defp pad_time(_), do: "N/A" |> String.pad_trailing(15)

  defp pad_bool(%{playable: true}), do: "Yes     "
  defp pad_bool(%{playable: false}), do: "No      "
  defp pad_bool(_), do: "Unknown "

  defp pad_str(str, len) do
    str |> to_string() |> String.slice(0, len) |> String.pad_trailing(len)
  end
end
