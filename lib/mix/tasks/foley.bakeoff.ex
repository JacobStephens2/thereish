defmodule Mix.Tasks.Foley.Bakeoff do
  @moduledoc """
  Renders quips from a Room's Chronicle through ElevenLabs and Hume Octave 2 for blind evaluation.

  Reads the last N quips (default: 5 from Room DUST), renders each through ElevenLabs v3
  Conversational and Hume Octave 2, writes blind paired audio files (`01-a.mp3`, `01-b.mp3`, …),
  and writes a sealed key file (`key.txt` and `key.json`) mapping blind letters to providers.

  ## Options

    * `--room`, `-r` - Room Code (default: "DUST")
    * `--count`, `-n` - Number of recent quips to render (default: 5)
    * `--dir`, `-d` - Scratch directory to write files to (default: ".scratch/foley/bakeoff")
    * `--eleven-voice` - Voice ID for ElevenLabs (default: "JBFqnCBsd6RMkjVDRZzb", George)
    * `--hume-voice` - Voice ID for Hume (default: "44cb3a51-07b4-4934-83fd-9d9e8d363ce6", Dungeon Master)
    * `--seed` - Integer seed for deterministic letter assignment (optional)

  ## Examples

      $ mix foley.bakeoff
      $ mix foley.bakeoff DUST 5
      $ mix foley.bakeoff --room DUST --count 5 --dir .scratch/foley/bakeoff
  """
  use Mix.Task

  @shortdoc "Renders recent quips through ElevenLabs and Hume for blind listening"

  @switches [
    room: :string,
    count: :integer,
    dir: :string,
    eleven_voice: :string,
    hume_voice: :string,
    seed: :integer
  ]

  @aliases [
    r: :room,
    n: :count,
    d: :dir
  ]

  @default_room "DUST"
  @default_count 5
  @default_dir ".scratch/foley/bakeoff"
  @default_eleven_voice "JBFqnCBsd6RMkjVDRZzb"
  @default_hume_voice "44cb3a51-07b4-4934-83fd-9d9e8d363ce6"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, argv} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)

    room =
      opts[:room] ||
        Enum.at(argv, 0) ||
        @default_room

    count =
      case {opts[:count], Enum.at(argv, 1)} do
        {count, _} when is_integer(count) -> count
        {nil, count_str} when is_binary(count_str) -> String.to_integer(count_str)
        _ -> @default_count
      end

    dir = opts[:dir] || @default_dir
    eleven_voice = opts[:eleven_voice] || @default_eleven_voice
    hume_voice = opts[:hume_voice] || @default_hume_voice

    if seed = opts[:seed] do
      :rand.seed(:exsss, {seed, seed, seed})
    end

    quips = Thereish.Chronicle.recent_quips(room, count)

    if quips == [] do
      Mix.raise("No quips found in Chronicle for room #{inspect(room)}.")
    end

    File.mkdir_p!(dir)

    # Blind assignment: randomly assign letters "a" and "b" to the two providers
    candidates = [
      %{
        provider: "ElevenLabs",
        provider_module: Thereish.Steward.ElevenLabs,
        voice_id: eleven_voice,
        voice_name: "George"
      },
      %{
        provider: "Hume",
        provider_module: Thereish.Steward.Hume,
        voice_id: hume_voice,
        voice_name: "Dungeon Master"
      }
    ]

    [provider_a, provider_b] = Enum.shuffle(candidates)

    key = %{
      "a" => %{
        "provider" => provider_a.provider,
        "voice_id" => provider_a.voice_id,
        "voice_name" => provider_a.voice_name
      },
      "b" => %{
        "provider" => provider_b.provider,
        "voice_id" => provider_b.voice_id,
        "voice_name" => provider_b.voice_name
      }
    }

    Mix.shell().info("Rendering #{length(quips)} quip(s) for Room #{room} into #{dir}...")

    quips_text =
      quips
      |> Enum.with_index(1)
      |> Enum.map(fn {quip, idx} ->
        num = String.pad_leading("#{idx}", 2, "0")
        "#{num}: #{quip}"
      end)
      |> Enum.join("\n")

    File.write!(Path.join(dir, "quips.txt"), quips_text <> "\n")

    Enum.each(Enum.with_index(quips, 1), fn {quip, idx} ->
      num = String.pad_leading("#{idx}", 2, "0")

      Mix.shell().info("  [#{num}/#{String.pad_leading("#{length(quips)}", 2, "0")}] #{quip}")

      render_variant(dir, num, "a", quip, provider_a)
      render_variant(dir, num, "b", quip, provider_b)
    end)

    # Write sealed key files
    key_json_path = Path.join(dir, "key.json")
    key_txt_path = Path.join(dir, "key.txt")

    File.write!(key_json_path, Jason.encode!(key, pretty: true) <> "\n")

    key_txt = """
    =======================================================
    SEALED BAKE-OFF KEY (Do not inspect until after listening!)
    =======================================================
    Room: #{room}
    Quips rendered: #{length(quips)}

    Letter A: #{provider_a.provider} (#{provider_a.voice_name}, ID: #{provider_a.voice_id})
    Letter B: #{provider_b.provider} (#{provider_b.voice_name}, ID: #{provider_b.voice_id})
    =======================================================
    """

    File.write!(key_txt_path, key_txt)

    abs_dir = Path.expand(dir)

    pairs_list =
      Enum.map(1..length(quips), fn i ->
        n = String.pad_leading("#{i}", 2, "0")
        "  #{n}-a.mp3 / #{n}-b.mp3"
      end)
      |> Enum.join("\n")

    Mix.shell().info("""

    Baked off #{length(quips)} quip(s) to:
    #{abs_dir}

    Audio pairs written:
    #{pairs_list}

    Sealed key written to:
      #{Path.join(abs_dir, "key.txt")}
      #{Path.join(abs_dir, "key.json")}

    Listen to both letters across the quips, note your preference, and unseal key.txt to reveal the winner!
    """)
  end

  defp render_variant(dir, num, letter, quip, candidate) do
    audio = speak!(quip, candidate.provider_module, candidate.voice_id)
    File.write!(Path.join(dir, "#{num}-#{letter}.mp3"), audio)
  end

  defp speak!(quip, provider_module, voice_id) do
    case Thereish.Steward.speak(quip, provider: provider_module, voice_id: voice_id) do
      {:ok, %{audio: audio}} when is_binary(audio) ->
        audio

      {:error, reason} ->
        Mix.raise("TTS synthesis failed for #{inspect(provider_module)}: #{inspect(reason)}")
    end
  end
end
