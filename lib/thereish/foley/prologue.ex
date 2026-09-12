defmodule Thereish.Foley.Prologue do
  @moduledoc """
  The Prologue: a fixed three-sentence script explaining what Thereish is
  and what a Meld is, kept in three readings so a repeat hearing is not
  the same take.
  """

  @script "Welcome to Thereish. Every Page shows two words, and each of you writes the one word that sits between them. Land on the same word and that's a Meld: one mind. Start by offering a Give."

  @readings [
    "/audio/prologue-1.mp3",
    "/audio/prologue-2.mp3",
    "/audio/prologue-3.mp3"
  ]

  @filenames [
    "prologue-1.mp3",
    "prologue-2.mp3",
    "prologue-3.mp3"
  ]

  @doc "The fixed three-sentence script."
  @spec script() :: String.t()
  def script, do: @script

  @doc "All shipped reading audio paths."
  @spec readings() :: [String.t()]
  def readings, do: @readings

  @doc "All shipped reading file names."
  @spec filenames() :: [String.t()]
  def filenames, do: @filenames

  @doc "Draws one reading audio path at random."
  @spec draw() :: String.t()
  def draw, do: Enum.random(@readings)

  @doc "Draws one reading audio path at random and pairs it with the fixed script."
  @spec draw_take() :: %{reading: String.t(), text: String.t()}
  def draw_take do
    %{
      reading: draw(),
      text: @script
    }
  end
end
