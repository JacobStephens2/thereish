defmodule MeaningGame.Rooms.Code do
  @moduledoc """
  The word a Room is known by, and the way one is read and drawn.

  A Code is stored lowercase, shown uppercase and accepted in any case, because
  it arrives by being said across a table and typed by whoever heard it. The
  stored form is the Room's slug, so every Room that already exists has a Code
  already.

  A drawn Code is a four-letter word from the ENABLE list less the profanity
  list. They are real words on purpose: "CANE" is read aloud once and spelled by
  four people, which is not true of four random letters, and it is why there is
  no look-alike-letter rule here.
  """

  alias MeaningGame.Rooms.Room
  alias MeaningGame.Steward.Legality

  @doc """
  The Code someone typed, in the form a Room is stored under, or `nil` if it is
  not one any Room could have.

  Turning a slip of the thumb into `nil` here is what keeps a typo from
  conjuring a Room later on.
  """
  @spec normalise(term()) :: String.t() | nil
  def normalise(input) when is_binary(input) do
    code = input |> String.trim() |> String.downcase()

    if Regex.match?(Room.slug_format(), code), do: code
  end

  def normalise(_input), do: nil

  @doc "The Code as it is shown — large, on a phone, to be read aloud."
  @spec shout(String.t()) :: String.t()
  def shout(code), do: String.upcase(code)

  @doc """
  One four-letter word, at random.

  Collisions are the caller's to handle: a drawn word that is already a Room's
  Code is drawn again, which is cheaper than tracking what is taken in here.
  """
  @spec draw() :: String.t()
  def draw, do: Enum.random(words())

  @doc "Every word a Code can be drawn from."
  @spec words() :: [String.t()]
  def words do
    key = {__MODULE__, :words}

    case :persistent_term.get(key, nil) do
      nil ->
        words =
          Legality.dictionary()
          |> Enum.filter(&(String.length(&1) == 4))
          |> Enum.reject(&Legality.profane?/1)
          |> Enum.sort()

        :persistent_term.put(key, words)
        words

      words ->
        words
    end
  end
end
