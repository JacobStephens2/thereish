defmodule Thereish.Steward.Music do
  @moduledoc """
  Prompt construction and formatting for Foley music generation.

  A Give that names a genre, artist, instrument, or energy determines
  genre, instrumentation, and energy; every other Give supplies atmosphere.
  Conflicting genres invite a fusion. Mix volume is not a requirement for
  gentle composition.
  """

  @composition_brief "A Give that names a genre, artist, instrument, or energy sets genre, instrumentation, and energy — follow it strongly, including loud or driving styles. Every other Give supplies atmosphere only."

  @fusion_brief "When several Gives name different genres, fuse them rather than a subdued style."

  @mix_brief "Mix volume is comfortable, not a requirement for gentle composition."

  @house_opener "Instrumental music. "

  @vamp_opener "A 30-second looping instrumental music bed. No vocals, no speech, no crowd, no talking. "

  @doc "House style prefix used for Mureka instrumental generation."
  @spec house_prefix([String.t() | map()]) :: String.t()
  def house_prefix(gives \\ []), do: build(@house_opener, gives)

  @doc "Prefix for the Vamp: ElevenLabs sound-generation, not Mureka."
  @spec vamp_prefix([String.t() | map()]) :: String.t()
  def vamp_prefix(gives \\ []), do: build(@vamp_opener, gives)

  @doc """
  Builds a prompt for Mureka from the given Gives.
  """
  @spec prompt([String.t() | map()]) :: String.t()
  def prompt(gives) when is_list(gives) do
    house_prefix(gives) <> theme(gives)
  end

  @doc """
  Builds a prompt for the Vamp (ElevenLabs sound-generation).

  ElevenLabs sound-generation hears "conversational" and "spoken conversation"
  as people talking, so the Vamp brief must not use those words.
  """
  @spec vamp_prompt([String.t() | map()]) :: String.t()
  def vamp_prompt(gives) when is_list(gives) do
    vamp_prefix(gives) <> theme(gives)
  end

  defp build(opener, gives), do: opener <> direction(gives) <> " Gives: "

  defp direction(gives) do
    [
      @composition_brief,
      several?(gives) && @fusion_brief,
      @mix_brief
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" ")
  end

  defp several?(gives) do
    gives
    |> theme_parts()
    |> length() >= 2
  end

  defp theme(gives), do: gives |> theme_parts() |> Enum.join(", ")

  defp theme_parts(gives) do
    gives
    |> Enum.map(&Thereish.Steward.Author.give_text/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end
end
