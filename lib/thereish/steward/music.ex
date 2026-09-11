defmodule Thereish.Steward.Music do
  @moduledoc """
  Prompt construction and formatting for Foley music generation.
  """

  @house_prefix "Gentle, conversational background instrumental music that sits comfortably under spoken conversation. Atmosphere and theme: "

  @vamp_prefix "A 30-second looping instrumental music bed. No vocals, no speech, no crowd, no talking. Soft and gentle, sitting under conversation. Atmosphere and theme: "

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

  The Mureka house prefix says "conversational" and "spoken conversation" so
  a Track sits under talk. The same words sent to a sound-effect model come
  back as people talking.
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
