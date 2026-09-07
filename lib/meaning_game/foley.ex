defmodule MeaningGame.Foley do
  @moduledoc """
  The machine role that makes what the Room hears — the stings and the house
  loop, made once and shipped, and the music written for a Page's Gives while
  it is played.
  """

  require Logger

  @doc """
  Warns at application boot if keys for Foley's active jobs are missing.

  - Music (`:music`): missing `MUREKA_API_KEY` warns that every Page will have
    only the house loop.
  - Voice (`:voice`): missing key(s) for the configured voice provider (`HUME_API_KEY`
    and `HUME_SECRET_KEY` today, `ELEVENLABS_API_KEY` if switched) warns that
    the voice switch will do nothing.

  Emits one warning per Foley job that has no key, in the same words as `bin/deploy`,
  and silence when every key is present.
  """
  @spec warn_missing_keys() :: :ok
  def warn_missing_keys do
    warn_music_keys()
    warn_voice_keys()
    :ok
  end

  defp warn_music_keys do
    music_role = MeaningGame.Steward.role(:foley, :music)
    key = music_role[:api_key]

    if is_nil(key) or key == "" do
      Logger.warning("no MUREKA_API_KEY — every Page will have only the house loop")
    end
  end

  defp warn_voice_keys do
    voice_role = MeaningGame.Steward.role(:foley, :voice)
    provider = voice_role[:provider]

    missing =
      cond do
        provider == MeaningGame.Steward.Hume ->
          hume_api = voice_role[:hume_api_key] || voice_role[:api_key]
          hume_secret = voice_role[:hume_secret_key] || voice_role[:secret_key]

          [
            if(is_nil(hume_api) or hume_api == "", do: "HUME_API_KEY"),
            if(is_nil(hume_secret) or hume_secret == "", do: "HUME_SECRET_KEY")
          ]
          |> Enum.reject(&is_nil/1)

        provider == MeaningGame.Steward.ElevenLabs ->
          el_api = voice_role[:elevenlabs_api_key] || voice_role[:api_key]

          if is_nil(el_api) or el_api == "" do
            ["ELEVENLABS_API_KEY"]
          else
            []
          end

        true ->
          []
      end

    case missing do
      [] ->
        :ok

      keys ->
        Logger.warning("no #{Enum.join(keys, " and ")} — the voice switch will do nothing")
    end
  end
end
