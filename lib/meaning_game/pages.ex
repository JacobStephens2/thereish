defmodule MeaningGame.Pages do
  @moduledoc """
  Where a Room finds a Page.

  The Author writes Pages ahead of play against a named Chapter and fills
  a pool in Postgres. The Room draws from this pool and marks each Page played,
  ensuring no Page repeats within an evening.

  When the pool drains, it refuses to repeat a Page.
  """

  import Ecto.Query, only: [from: 2]

  alias MeaningGame.Pages.AuthoredPage
  alias MeaningGame.Repo
  alias MeaningGame.Steward

  @hand_written_pool [
    %{
      id: "hand-written-1",
      chapter: "the harbour",
      theme: "the harbour",
      give: nil,
      anchors: ["lantern", "harbour"],
      bait: "lighthouse",
      deep_bridges: ["beacon", "buoy"],
      likely_bridges: ["lighthouse", "beacon", "buoy", "foghorn", "dock"],
      why_these: "Harbour and lantern invite lighthouse as the immediate bridge.",
      band_scripts: %{
        "miss" => "Adrift in the fog.",
        "adjacent" => "Along the quay.",
        "close" => "Passable. In the harbour mouth.",
        "meld" => "Two minds at the light.",
        "deep_meld" => "Deep navigation."
      },
      meta: %{model: "hand-written", prompt_version: "v1", attempts: 1, cost_usd: 0.0}
    },
    %{
      id: "hand-written-2",
      chapter: "desert",
      theme: "desert",
      give: nil,
      anchors: ["desert", "mirror"],
      bait: "mirage",
      deep_bridges: ["shimmer", "glass"],
      likely_bridges: ["mirage", "shimmer", "glass", "oasis", "sand"],
      why_these: "Desert and mirror invite mirage as the obvious bridge.",
      band_scripts: %{
        "miss" => "Lost in the dunes.",
        "adjacent" => "On the edge of the heat.",
        "close" => "Passable. At the reflection.",
        "meld" => "You both saw the mirage.",
        "deep_meld" => "Crystalline convergence."
      },
      meta: %{model: "hand-written", prompt_version: "v1", attempts: 1, cost_usd: 0.0}
    },
    %{
      id: "hand-written-3",
      chapter: "river",
      theme: "river",
      give: nil,
      anchors: ["clock", "river"],
      bait: "flow",
      deep_bridges: ["current", "time"],
      likely_bridges: ["flow", "current", "time", "bank", "stream"],
      why_these: "Clock and river invite flow as the obvious bridge.",
      band_scripts: %{
        "miss" => "Standing on different banks.",
        "adjacent" => "Caught in the eddies.",
        "close" => "Passable. With the current.",
        "meld" => "Two minds in the flow.",
        "deep_meld" => "Timeless convergence."
      },
      meta: %{model: "hand-written", prompt_version: "v1", attempts: 1, cost_usd: 0.0}
    },
    %{
      id: "hand-written-4",
      chapter: "kitchen",
      theme: "kitchen",
      give: nil,
      anchors: ["honey", "knife"],
      bait: "spread",
      deep_bridges: ["sweet", "comb"],
      likely_bridges: ["spread", "sweet", "comb", "blade", "bread"],
      why_these: "Honey and knife invite spread as the obvious bridge.",
      band_scripts: %{
        "miss" => "Cold butter.",
        "adjacent" => "On the board.",
        "close" => "Passable. At the jar.",
        "meld" => "Two minds spread thin.",
        "deep_meld" => "Pure comb."
      },
      meta: %{model: "hand-written", prompt_version: "v1", attempts: 1, cost_usd: 0.0}
    },
    %{
      id: "hand-written-5",
      chapter: "attic",
      theme: "attic",
      give: nil,
      anchors: ["letter", "attic"],
      bait: "trunk",
      deep_bridges: ["memory", "dust"],
      likely_bridges: ["trunk", "memory", "dust", "post", "box"],
      why_these: "Letter and attic invite trunk as the obvious bridge.",
      band_scripts: %{
        "miss" => "In the rafters.",
        "adjacent" => "Under the floorboards.",
        "close" => "Passable. By the window.",
        "meld" => "You found the trunk.",
        "deep_meld" => "Shared memory."
      },
      meta: %{model: "hand-written", prompt_version: "v1", attempts: 1, cost_usd: 0.0}
    }
  ]

  @doc "Inserts an authored page into the pool."
  @spec insert_page(map()) :: {:ok, map()} | {:error, term()}
  def insert_page(attrs) do
    attrs =
      attrs
      |> normalize_keys()
      |> Map.put_new(:page_id, attrs[:id] || attrs["id"])

    %AuthoredPage{}
    |> AuthoredPage.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, page} -> {:ok, to_page_map(page)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc "Fetches an authored page from the pool by its page_id."
  @spec get_page(String.t()) :: map() | nil
  def get_page(page_id) do
    case Repo.get_by(AuthoredPage, page_id: page_id) do
      nil -> nil
      page -> to_page_map(page)
    end
  end

  @doc """
  Draws the next unplayed Page from the pool and marks it played by the given Room.

  Refuses to repeat a Page once the pool is drained.
  """
  @spec draw(Ecto.UUID.t() | nil, keyword()) :: {:ok, map()} | {:error, :pool_exhausted}
  def draw(room_id, opts \\ []) do
    chapter = Keyword.get(opts, :chapter)
    give = Keyword.get(opts, :give)

    query =
      from(p in AuthoredPage,
        where: is_nil(p.played_at),
        order_by: [asc: p.inserted_at],
        limit: 1
      )

    query =
      cond do
        give ->
          from(p in query, where: p.give == ^give)

        chapter ->
          from(p in query, where: p.chapter == ^chapter)

        true ->
          query
      end

    case Repo.one(query) do
      nil ->
        {:error, :pool_exhausted}

      page ->
        page
        |> AuthoredPage.mark_played_changeset(room_id)
        |> Repo.update!()
        |> then(&{:ok, to_page_map(&1)})
    end
  end

  @doc """
  Authors `count` Pages ahead of play against a Give (named meaning-space) and fills the pool.
  """
  @spec author_give(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def author_give(give, opts \\ []) do
    count = Keyword.get(opts, :count, 3)
    opts = Keyword.put(opts, :give, give)
    chapter = Keyword.get(opts, :chapter, give)

    author_chapter(chapter, count, opts)
  end

  @doc """
  Authors `count` Pages ahead of play against `chapter_name` and fills the pool.
  """
  @spec author_chapter(String.t(), pos_integer(), keyword()) ::
          {:ok, [map()]} | {:error, term()}
  def author_chapter(chapter_name, count \\ 5, opts \\ []) do
    results =
      Enum.reduce_while(1..count, {:ok, []}, fn _i, {:ok, acc} ->
        case Steward.author(chapter_name, opts) do
          {:ok, page} ->
            case insert_page(page) do
              {:ok, inserted} -> {:cont, {:ok, [inserted | acc]}}
              {:error, reason} -> {:halt, {:error, reason}}
            end

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)

    case results do
      {:ok, pages} -> {:ok, Enum.reverse(pages)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  The opening Page for a Room. Draws from pool if available, otherwise falls
  back to first hand-written page.
  """
  @spec first(Ecto.UUID.t() | nil, keyword()) :: MeaningGame.Game.page()
  def first(room_id \\ nil, opts \\ []) do
    case draw(room_id, opts) do
      {:ok, page} -> page
      {:error, :pool_exhausted} -> hd(@hand_written_pool)
    end
  end

  @doc """
  The Page after this one. Draws from pool if available, otherwise returns
  {:error, :pool_exhausted} when pool is active, or advances hand-written ring.
  """
  @spec next(String.t(), Ecto.UUID.t() | nil, keyword()) ::
          {:ok, MeaningGame.Game.page()} | {:error, :pool_exhausted}
  def next(page_id, room_id \\ nil, opts \\ []) do
    # If pool has been authored, draw from pool; refuse to repeat when drained
    if pool_has_pages?() do
      draw(room_id, opts)
    else
      # Hand-written fallback when pool has no pages at all
      next_page =
        case Enum.find_index(@hand_written_pool, &(&1.id == page_id)) do
          nil -> first(room_id, opts)
          index -> Enum.at(@hand_written_pool, rem(index + 1, length(@hand_written_pool)))
        end

      {:ok, next_page}
    end
  end

  @doc """
  Computes a provisional reading from the Author's likely_bridges table.
  """
  defdelegate provisional_reading(page, bridges), to: MeaningGame.Steward.Author

  defp pool_has_pages? do
    Repo.exists?(AuthoredPage)
  rescue
    _ -> false
  end

  defp to_page_map(%AuthoredPage{} = page) do
    %{
      id: page.page_id,
      chapter: page.chapter,
      give: page.give,
      theme: page.theme,
      anchors: page.anchors,
      bait: page.bait,
      deep_bridges: page.deep_bridges,
      likely_bridges: page.likely_bridges,
      why_these: page.why_these,
      band_scripts: page.band_scripts,
      meta: page.meta,
      played_at: page.played_at,
      played_room_id: page.played_room_id
    }
  end

  defp normalize_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {k, v}
      {k, v} when is_binary(k) -> {String.to_atom(k), v}
    end)
  end
end
