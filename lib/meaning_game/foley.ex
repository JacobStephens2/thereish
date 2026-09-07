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
    case MeaningGame.Steward.missing_keys(:foley, :music) do
      [] ->
        :ok

      [key | _] ->
        Logger.warning("no #{key} — every Page will have only the house loop")
    end
  end

  defp warn_voice_keys do
    case MeaningGame.Steward.missing_keys(:foley, :voice) do
      [] ->
        :ok

      keys ->
        Logger.warning("no #{Enum.join(keys, " and ")} — the voice switch will do nothing")
    end
  end
end
