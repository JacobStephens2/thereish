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
  alias Thereish.Foley.Track
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
  Tracks kept in this Room's Chronicle: each Page's Track that `Track.kept?/1`.
  """
  @spec chronicle_tracks(Ecto.UUID.t() | String.t()) :: [member()]
  def chronicle_tracks(room_id) do
    from(p in Page,
      where: p.room_id == ^room_id and not is_nil(p.music_meta),
      select: p.music_meta
    )
    |> Repo.all()
    |> Enum.filter(&Track.kept?/1)
    |> Enum.map(fn %Track{path: path, title: title} -> make_member(title, path) end)
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
  Paths that this Room has marked Never.
  """
  @spec nevers(Ecto.UUID.t() | String.t() | nil) :: [String.t()]
  def nevers(nil), do: []

  def nevers(room_id) do
    Thereish.Rooms.Store.list_nevers(room_id)
  rescue
    _ -> []
  end

  @doc """
  The eligible wait music members of the Repertoire for a Room.
  - Unsettled: shipped loops + every kept Track across the game.
  - Settled: this Room's Chronicle Tracks + the five shipped loops.
  - Minus this Room's Never list.
  """
  @spec members(Ecto.UUID.t() | String.t() | [member()]) :: [member()]
  def members(room_id_or_members) when is_list(room_id_or_members), do: room_id_or_members

  def members(room_id) do
    never_paths = MapSet.new(nevers(room_id))

    raw_members =
      case chronicle_tracks(room_id) do
        [] ->
          Enum.uniq_by(shipped_loops() ++ kept_tracks(), & &1.path)

        room_tracks ->
          Enum.uniq_by(room_tracks ++ shipped_loops(), & &1.path)
      end

    Enum.reject(raw_members, fn m -> MapSet.member?(never_paths, m.path) end)
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

  @doc """
  Advances the deal after a member has been marked Never:
  - If only one eligible member remains, returns that member and an empty deal.
  - Otherwise, advances the deal or reshuffles using the remaining eligible members.
  """
  @spec advance_after_never([member()], [member()] | nil, String.t() | nil) ::
          {:ok, member(), [member()]} | {:error, :no_members}
  def advance_after_never([], _deal, _nevered_path), do: {:error, :no_members}

  def advance_after_never([single], _deal, _nevered_path) do
    {:ok, single, []}
  end

  def advance_after_never(eligible, current_deal, nevered_path) do
    next_deal(eligible, current_deal || [], nevered_path)
  end

  defp clean_title(title) when is_binary(title) and title != "", do: title
  defp clean_title(_), do: "Track"

  defp make_member(name_or_title, path) do
    title = clean_title(name_or_title)
    %{name: title, title: title, path: path}
  end
end
