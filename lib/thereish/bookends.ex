defmodule Thereish.Bookends do
  @moduledoc """
  Which Bridges a miss carries forward as the next Attempt's Bookends, whose
  each one is, and how a set of Bookends dresses as chips.

  One rule, read the same at the table and in the Chronicle: the Game applies
  it as an Attempt is played and `Thereish.Chronicle.PageView` applies it again
  to the rows a closed Page left, so the book says what the table saw
  (ADR-0016).

  Pure. "Bridges" here are a list of `%{seat_id, bridge}` in roster order,
  holding only the Bridges that were written. Whether an Attempt melded, and so
  carries nothing at all, is the caller's concern.
  """

  alias Thereish.Mask

  @typedoc "One written Bridge and the Seat that wrote it, in roster order."
  @type bridge :: %{required(:seat_id) => term(), required(:bridge) => String.t()}

  @typedoc "One word and the Seat whose Bridge it is, or nil when none wrote it."
  @type claimed :: %{word: String.t(), seat_id: term() | nil}

  @typedoc """
  What the Assayer said, as far as the carry reads it. `furthest` is the pair
  it named as landing furthest apart.
  """
  @type verdict :: %{optional(atom()) => term(), graded?: boolean(), furthest: [String.t()] | nil}

  @typedoc "Where one opening Bookend came from, when a Give dealt it."
  @type origin :: %{
          word: String.t() | nil,
          seat_id: term() | nil,
          seat_name: String.t() | nil,
          give: String.t() | nil
        }

  @typedoc "One Bookend as a chip."
  @type chip :: %{
          word: String.t(),
          seat_id: term() | nil,
          seat_name: String.t() | nil,
          give: String.t() | nil,
          mask: Mask.t() | :dot | nil
        }

  @doc """
  The Bridges a missed Attempt carries forward, and whether they were chosen.

  At a Full table every Bridge carries, each with its Seat. Otherwise the
  Verdict's furthest pair carries when the Verdict was graded and both words
  can be claimed from the Bridges: a pair the roster cannot account for, such
  as a paraphrase, is no choice at all. Failing that the first two Bridges
  carry, and `chosen?` is false so the screens can say the game fell back.
  """
  @spec carry([bridge()], verdict() | nil, boolean()) :: %{
          carried: [claimed()],
          chosen?: boolean()
        }
  def carry(bridges, _verdict, true), do: %{carried: Enum.map(bridges, &carried/1), chosen?: true}

  def carry(bridges, verdict, _full_table?) do
    case furthest(verdict, bridges) do
      nil -> %{carried: bridges |> Enum.take(2) |> Enum.map(&carried/1), chosen?: false}
      pair -> %{carried: pair, chosen?: true}
    end
  end

  defp carried(bridge), do: %{word: bridge.bridge, seat_id: bridge.seat_id}

  defp furthest(%{graded?: true, furthest: [_, _] = words}, bridges) do
    claims = claims(words, bridges)
    if Enum.all?(claims, fn {_word, bridge} -> bridge end), do: Enum.map(claims, &claimed/1)
  end

  defp furthest(_verdict, _bridges), do: nil

  @doc """
  Each word with the Seat whose Bridge wrote it. Each Bridge is claimed at most
  once, in roster order, so a table that wrote one word twice does not read as
  one Seat writing it twice; a word no unclaimed Bridge wrote names no Seat.
  """
  @spec claim([String.t()], [bridge()]) :: [claimed()]
  def claim(words, bridges), do: words |> claims(bridges) |> Enum.map(&claimed/1)

  defp claims(words, bridges) do
    {claims, _unclaimed} =
      Enum.map_reduce(words, bridges, fn word, unclaimed ->
        case Enum.split_while(unclaimed, &(&1.bridge != word)) do
          {passed, [bridge | rest]} -> {{word, bridge}, passed ++ rest}
          {_all, []} -> {{word, nil}, unclaimed}
        end
      end)

    claims
  end

  defp claimed({word, bridge}), do: %{word: word, seat_id: bridge && bridge.seat_id}

  @doc """
  One chip per word, padding missing origins with nils.

  A first-Attempt chip names the Give and Seat its word came from and never
  wears a Mask. A later chip names the Seat whose Bridge it carried and wears
  that Seat's Mask from `masks` when there is one.
  """
  @spec chips([String.t()], [map()], pos_integer(), %{optional(term()) => Mask.t() | :dot}) ::
          [chip()]
  def chips(words, origins, attempt_number, masks) do
    padded = Stream.concat(origins, Stream.repeatedly(fn -> %{} end))

    Enum.zip_with(words, padded, fn word, origin ->
      seat_id = origin[:seat_id]

      %{
        word: word,
        seat_id: seat_id,
        seat_name: origin[:seat_name],
        give: origin[:give],
        mask: if(attempt_number > 1 and seat_id != nil, do: Map.get(masks, seat_id))
      }
    end)
  end
end
