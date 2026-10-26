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

  # ElevenLabs sound generation refuses a text over 450 characters, and the
  # Track's direction plus two Gives already came to 445, so the Vamp says the
  # same things in fewer words, and a table too long even for that loses the
  # tail of its Gives rather than the whole Vamp.
  @vamp_limit 450

  @vamp_composition_brief "A Give naming a genre, artist, instrument, or energy sets genre, instrumentation, and energy, loud styles included; other Gives are atmosphere only."

  @vamp_fusion_brief "Fuse differing genres."

  @vamp_mix_brief "Comfortable volume."

  @doc "House style prefix used for the Track's instrumental generation."
  @spec house_prefix([String.t() | map()]) :: String.t()
  def house_prefix(gives \\ []), do: build(@house_opener, gives)

  @doc "Prefix for the Vamp: ElevenLabs sound-generation, not the Track's provider."
  @spec vamp_prefix([String.t() | map()]) :: String.t()
  def vamp_prefix(gives \\ []),
    do: @vamp_opener <> vamp_direction(gives) <> " Gives: "

  @doc """
  Builds the Track's prompt from the given Gives.
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
    prefix = vamp_prefix(gives)
    prefix <> fit(theme(gives), @vamp_limit - String.length(prefix))
  end

  defp fit(theme, room) do
    if String.length(theme) <= room do
      theme
    else
      theme
      |> String.slice(0, room)
      |> String.replace(~r/[\s,]+\S*$/u, "")
    end
  end

  defp build(opener, gives), do: opener <> direction(gives) <> " Gives: "

  defp vamp_direction(gives) do
    [@vamp_composition_brief, several?(gives) && @vamp_fusion_brief, @vamp_mix_brief]
    |> Enum.filter(& &1)
    |> Enum.join(" ")
  end

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
