defmodule Thereish.Steward.TrackCache do
  @moduledoc """
  The track cache table holding scored instrumentals keyed by normalized, sorted Gives.

  Answers a hit without a provider call. On miss, Mureka writes into the app's media
  directory on the server's volume, never relying on Mureka's thirty-day URL.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Thereish.Repo
  alias Thereish.Steward.TrackCache

  @primary_key {:id, :binary_id, autogenerate: true}

  @type t :: %__MODULE__{}

  schema "track_cache" do
    field :key, :string
    field :gives, {:array, :string}
    field :title, :string
    field :path, :string
    field :duration, :integer
    field :format, :string, default: "mp3"
    field :meta, :map

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(track_cache, attrs) do
    track_cache
    |> cast(attrs, [:key, :gives, :title, :path, :duration, :format, :meta])
    |> validate_required([:key, :gives, :path])
    |> unique_constraint(:key)
  end

  @doc "Normalizes a single Give: NFC, downcase, trimmed, whitespace collapsed."
  @spec normalize_give(String.t() | map()) :: String.t()
  def normalize_give(give) do
    give
    |> Thereish.Steward.Author.give_text()
    |> :unicode.characters_to_nfc_binary()
    |> String.downcase()
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
  end

  @doc "Normalizes and sorts a list of Gives."
  @spec normalize_gives([String.t() | map()]) :: [String.t()]
  def normalize_gives(gives) when is_list(gives) do
    gives
    |> Enum.map(&normalize_give/1)
    |> Enum.sort()
  end

  @doc "Deterministic cache key for a list of Gives."
  @spec key([String.t() | map()]) :: String.t()
  def key(gives) when is_list(gives) do
    gives
    |> normalize_gives()
    |> Enum.join(":")
  end

  @doc "Fetches a track from the cache by Gives."
  @spec get([String.t() | map()]) :: {:ok, map()} | :miss
  def get(gives) when is_list(gives) do
    cache_key = key(gives)

    case Repo.one(from(t in TrackCache, where: t.key == ^cache_key)) do
      nil ->
        :miss

      row ->
        {:ok,
         %{
           title: row.title,
           path: row.path,
           duration: row.duration,
           format: format_atom(row.format),
           meta: row.meta
         }}
    end
  end

  @doc "Puts a track into the cache table."
  @spec put([String.t() | map()], map()) :: {:ok, TrackCache.t()} | {:error, term()}
  def put(gives, attrs) when is_list(gives) and is_map(attrs) do
    normalized = normalize_gives(gives)
    cache_key = key(gives)

    format =
      case Map.get(attrs, :format) || Map.get(attrs, "format") do
        f when is_atom(f) -> Atom.to_string(f)
        f when is_binary(f) -> f
        _ -> "mp3"
      end

    meta = Map.get(attrs, :meta) || Map.get(attrs, "meta") || %{}

    params = %{
      key: cache_key,
      gives: normalized,
      title: Map.get(attrs, :title) || Map.get(attrs, "title"),
      path: Map.get(attrs, :path) || Map.get(attrs, "path"),
      duration: Map.get(attrs, :duration) || Map.get(attrs, "duration"),
      format: format,
      meta: meta
    }

    on_conflict =
      if params.title do
        {:replace, [:title, :updated_at]}
      else
        :nothing
      end

    %TrackCache{}
    |> changeset(params)
    |> Repo.insert(
      on_conflict: on_conflict,
      conflict_target: :key
    )
  end

  @doc "Stores generated audio bytes into the media directory and records in cache."
  @spec store([String.t() | map()], map(), keyword()) :: {:ok, map()} | {:error, term()}
  def store(gives, mureka_result, opts \\ []) when is_list(gives) and is_map(mureka_result) do
    cache_key = key(gives)
    filename = filename_for_key(cache_key) <> ".mp3"
    dir = Path.join(media_dir(), "tracks")
    File.mkdir_p!(dir)
    file_path = Path.join(dir, filename)

    case Map.get(mureka_result, :bytes) do
      bytes when is_binary(bytes) ->
        File.write!(file_path, bytes)

      _ ->
        :ok
    end

    web_path = "/media/tracks/#{filename}"
    duration = Map.get(mureka_result, :duration, 120) || 120

    title =
      Keyword.get(opts, :title) || Map.get(mureka_result, :title) ||
        Map.get(mureka_result, "title")

    meta = %{
      provider: "mureka",
      model: Map.get(mureka_result, :model, "auto"),
      cost_usd: Map.get(mureka_result, :cost_usd, 0.04)
    }

    track_attrs = %{
      title: title,
      path: web_path,
      duration: duration,
      format: :mp3,
      meta: meta
    }

    with {:ok, _row} <- put(gives, track_attrs) do
      {:ok, track_attrs}
    end
  end

  @doc "Returns the configured media directory on the server volume."
  def media_dir do
    Application.get_env(:thereish, :media_dir) ||
      Path.join([:code.priv_dir(:thereish) || "priv", "static", "media"])
  end

  @doc "Generates a hex filename from a cache key."
  def filename_for_key(key) when is_binary(key) do
    :crypto.hash(:sha256, key)
    |> Base.encode16(case: :lower)
  end

  defp format_atom("mp3"), do: :mp3
  defp format_atom(f) when is_binary(f), do: String.to_atom(f)
  defp format_atom(f) when is_atom(f), do: f
  defp format_atom(_), do: :mp3
end
