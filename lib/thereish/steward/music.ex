defmodule Thereish.Steward.Music do
  @moduledoc """
  Prompt construction and formatting for Foley music generation.

  Explicit musical Gives determine genre, instrumentation, and energy;
  nonmusical Gives supply atmosphere. Conflicting genres invite a fusion.
  Comfortable playback volume is mix, not a requirement for gentle composition.
  """

  @give_brief "Musical Gives set genre, instrumentation, and energy — follow them strongly. " <>
                "Nonmusical Gives supply atmosphere. When several Gives name different genres, fuse them rather than a subdued style. " <>
                "Mix volume is comfortable, not a requirement for gentle composition."

  @house_prefix "Instrumental music. " <> @give_brief <> " Gives: "

  @vamp_prefix "A 30-second looping instrumental music bed. No vocals, no speech, no crowd, no talking. " <>
                 @give_brief <> " Gives: "

  @doc "House style prefix used for Mureka instrumental generation."
  def house_prefix, do: @house_prefix

  @doc "Prefix for the Vamp: ElevenLabs sound-generation, not Mureka."
  def vamp_prefix, do: @vamp_prefix

  @doc """
  Builds a prompt for Mureka from the given Gives.
  """
  @spec prompt([String.t() | map()]) :: String.t()
  def prompt(gives) when is_list(gives) do
    @house_prefix <> theme(gives)
  end

  @doc """
  Builds a prompt for the Vamp (ElevenLabs sound-generation).

  ElevenLabs sound-generation hears "conversational" and "spoken conversation"
  as people talking, so the Vamp brief must not use those words.
  """
  @spec vamp_prompt([String.t() | map()]) :: String.t()
  def vamp_prompt(gives) when is_list(gives) do
    @vamp_prefix <> theme(gives)
  end

  defp theme(gives) do
    gives
    |> Enum.map(&Thereish.Steward.Author.give_text/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(", ")
  end
end
