defmodule Thereish.Foley.Repertoire do
  @moduledoc """
  The Repertoire: the five shipped loops plus every kept Track in the game.

  An unsettled Room (no kept Track in this Chronicle yet) shuffles the five
  shipped loops and every kept Track. A settled Room shuffles this Chronicle's
  Tracks plus the five.
  """
  import Ecto.Query

  alias Thereish.Chronicle.Page
  alias Thereish.Foley.Loops
  alias Thereish.Repo
  alias Thereish.Steward.TrackCache

  @type member :: %{
          name: String.t(),
          title: String.t(),
          path: String.t()
        }

  @doc """
  The five loops shipped with the game.
  """
  @spec shipped_loops() :: [member()]
  def shipped_loops do
    Enum.map(Loops.all(), fn loop -> make_member(loop.name, loop.path) end)
  end

  @doc """
  Every kept Track in the game from the track cache.
  """
  @spec kept_tracks() :: [member()]
  def kept_tracks do
    from(t in TrackCache,
      where: not is_nil(t.path) and t.path != "",
      select: %{title: t.title, path: t.path}
    )
    |> Repo.all()
    |> Enum.map(fn t -> make_member(t.title, t.path) end)
  end

  @doc """
  Tracks kept in this Room's Chronicle (pages whose music_meta has a playable path and no failure).
  """
  @spec chronicle_tracks(Ecto.UUID.t() | String.t()) :: [member()]
  def chronicle_tracks(room_id) do
    from(p in Page,
      where: p.room_id == ^room_id and not is_nil(p.music_meta),
      select: p.music_meta
    )
    |> Repo.all()
    |> Enum.flat_map(fn meta ->
      path = meta["path"] || meta[:path]
      title = meta["title"] || meta[:title]
      failure = meta["failure"] || meta[:failure]

      if is_binary(path) and path != "" and is_nil(failure) do
        [make_member(title, path)]
      else
        []
      end
    end)
    |> Enum.uniq_by(& &1.path)
  end

  @doc """
  Whether this Room's Chronicle holds at least one kept Track.
  """
  @spec settled?(Ecto.UUID.t() | String.t()) :: boolean()
  def settled?(room_id) do
    chronicle_tracks(room_id) != []
  end

  @doc """
  The eligible wait music members of the Repertoire for a Room.
  - Unsettled: shipped loops + every kept Track across the game.
  - Settled: this Room's Chronicle Tracks + the five shipped loops.
  """
  @spec members(Ecto.UUID.t() | String.t()) :: [member()]
  def members(room_id) do
    case chronicle_tracks(room_id) do
      [] ->
        Enum.uniq_by(shipped_loops() ++ kept_tracks(), & &1.path)

      room_tracks ->
        Enum.uniq_by(room_tracks ++ shipped_loops(), & &1.path)
    end
  end

  @doc false
  # Backward-compatible alias
  def pool(room_id), do: members(room_id)

  @doc """
  Draws a member from the eligible members for a Room or explicit member list at random.
  If a previous member is given, avoids picking it if more than one candidate exists.
  """
  @spec draw(Ecto.UUID.t() | String.t() | [member()], member() | map() | nil) :: member()
  def draw(room_id_or_members, previous \\ nil) do
    repertoire_members =
      if is_list(room_id_or_members) do
        room_id_or_members
      else
        members(room_id_or_members)
      end

    candidates =
      if is_map(previous) and length(repertoire_members) > 1 do
        prev_path = previous[:path] || previous["path"]
        Enum.reject(repertoire_members, fn m -> m.path == prev_path end)
      else
        repertoire_members
      end

    case candidates do
      [] -> hd(shipped_loops())
      [single] -> single
      multiple -> Enum.random(multiple)
    end
  end

  @doc """
  Returns a shuffled deal of eligible members for a Room or explicit member list, excluding the given member or path.
  """
  @spec deal(Ecto.UUID.t() | String.t() | [member()], String.t() | member() | map() | nil) ::
          [member()]
  def deal(room_id_or_members, exclude \\ nil) do
    eligible =
      if is_list(room_id_or_members) do
        room_id_or_members
      else
        members(room_id_or_members)
      end

    exclude_path =
      case exclude do
        nil -> nil
        path when is_binary(path) -> path
        %{path: path} -> path
        %{"path" => path} -> path
      end

    eligible
    |> Enum.reject(fn m -> m.path == exclude_path end)
    |> Enum.shuffle()
  end

  @doc """
  Advances the session deal:
  - If `deal` has remaining members, takes the next one.
  - If `deal` is exhausted or empty, reshuffles from eligible members,
    excluding `current_path` so it never repeats the thing now playing.
  - If only one playable member exists in the Repertoire, returns `{:error, :no_other_members}`.
  """
  @spec next_deal(
          Ecto.UUID.t() | String.t() | [member()],
          [member()] | nil,
          String.t() | member() | map() | nil
        ) ::
          {:ok, member(), [member()]} | {:error, :no_other_members}
  def next_deal(room_id_or_members, current_deal \\ [], current \\ nil) do
    eligible =
      if is_list(room_id_or_members) do
        room_id_or_members
      else
        members(room_id_or_members)
      end

    if length(eligible) <= 1 do
      {:error, :no_other_members}
    else
      current_path =
        case current do
          nil -> nil
          path when is_binary(path) -> path
          %{path: path} -> path
          %{"path" => path} -> path
        end

      valid_paths = MapSet.new(eligible, & &1.path)

      usable_deal =
        (current_deal || [])
        |> Enum.filter(fn m -> MapSet.member?(valid_paths, m.path) and m.path != current_path end)

      case usable_deal do
        [next_member | remaining] ->
          {:ok, next_member, remaining}

        [] ->
          [next_member | remaining] =
            eligible
            |> Enum.reject(fn m -> m.path == current_path end)
            |> Enum.shuffle()

          {:ok, next_member, remaining}
      end
    end
  end

  defp clean_title(title) when is_binary(title) and title != "", do: title
  defp clean_title(_), do: "Track"

  defp make_member(name_or_title, path) do
    title = clean_title(name_or_title)
    %{name: title, title: title, path: path}
  end
end
