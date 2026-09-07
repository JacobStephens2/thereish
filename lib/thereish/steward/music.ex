defmodule Thereish.Steward.Music do
  @moduledoc """
  Prompt construction and formatting for Foley music generation.
  """

  @house_prefix "Gentle, conversational background instrumental music that sits comfortably under spoken conversation. Atmosphere and theme: "

  @doc "House style prefix used for Mureka instrumental generation."
  def house_prefix, do: @house_prefix

  @doc """
  Builds a prompt for Mureka from the given Gives.
  """
  @spec prompt([String.t() | map()]) :: String.t()
  def prompt(gives) when is_list(gives) do
    theme =
      gives
      |> Enum.map(&Thereish.Steward.Author.give_text/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(", ")

    @house_prefix <> theme
  end
end
