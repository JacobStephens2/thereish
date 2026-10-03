defmodule Thereish.Foley.Occupancy do
  @moduledoc """
  What the Speaker is playing for a Room right now: this Page's Track, its
  Vamp, a held-over Track, or a Repertoire draw.

  It is a pure reducer in the shape of the Game. The Room tells it what
  happened — a Page opened, a Foley result arrived, the Page turned, the Gives
  were reset, the music setting changed — and gets back a new Occupancy and a
  list of effects to perform. It does no I/O: a TrackCache hit comes in as an
  argument, and every write goes out as an effect.

  It never stores the Page's Phase or the Room's music setting. Both are the
  caller's facts, passed in on each call that needs them, so neither can drift.

  ## Effects

    * `{:start_vamp, page_ref, gives}`
    * `{:enqueue_track, page_ref, gives, gives_landed_at}`
    * `{:start_title, page_ref, gives}`
    * `{:persist_vamp_meta, page_ref, meta}` — onto the Page this ref names,
      once it is in the Chronicle
    * `{:persist_music_meta, page_ref, meta}` — likewise
    * `{:cache_track, gives, track}`
    * `{:log, page_ref, event, gives_landed_at}`

  ## Stale results

  A Vamp, Track or title is answered for the Page ref it was asked for. One
  that arrives for any other ref belongs to a superseded Page: what it carries
  is persisted to that Page and nothing is played. One that arrives after its
  own Page closed is persisted the same way. That rule lives in `arrived/4` and
  nowhere else.
  """

  alias Thereish.Steward

  defstruct page_ref: nil,
            gives: nil,
            gives_landed_at: nil,
            cached: nil,
            track: nil,
            track_page_ref: nil,
            vamp: nil,
            vamp_meta: nil,
            title: nil,
            title_meta: nil,
            music_meta: nil,
            vamp_running?: false,
            track_running?: false,
            title_running?: false

  @type t :: %__MODULE__{}
  @type effect :: tuple()

  @typedoc """
  The Room's facts for this call. Until Next and Never move here, the
  Repertoire draw and its eligible members are the Room's too.
  """
  @type table :: %{music: String.t(), closed?: boolean(), draw: map(), members: [map()]}

  @doc "An Occupancy with no Page open and nothing of its own to play."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  A Page opened from these Gives. `cached` is the TrackCache's answer for them,
  or nil. Under "page" a titled cache hit plays at once; otherwise Vamp, Track
  and title work is asked for. A Track still playing holds over.
  """
  @spec page_opened(t(), term(), [String.t()], map() | nil, integer(), String.t()) ::
          {t(), [effect()]}
  def page_opened(%__MODULE__{} = occ, page_ref, gives, cached, now, mode) do
    occ =
      %{
        occ
        | page_ref: page_ref,
          gives: gives,
          gives_landed_at: now,
          cached: cached,
          vamp: nil,
          vamp_meta: nil,
          title: nil,
          title_meta: nil,
          music_meta: nil,
          vamp_running?: false,
          track_running?: false,
          title_running?: false
      }

    if mode == "page", do: start_track_work(occ), else: {occ, []}
  end

  @doc """
  A Foley result arrived for `page_ref`: `{:vamp | :track | :title, result}`,
  where result is `{:ok, value}` or `{:error, reason}`. `closed?` is whether the
  Room's current Page has closed.
  """
  @spec arrived(
          t(),
          term(),
          {:vamp | :track | :title, {:ok, map()} | {:error, term()}},
          boolean()
        ) ::
          {t(), [effect()]}
  def arrived(%__MODULE__{} = occ, page_ref, {kind, result}, closed?) do
    arrive(occ, kind, result, current?(occ, page_ref), page_ref, closed?)
  end

  @doc """
  The Page turned. A Track still playing holds over until the next Page's
  Track lands (ADR-0013); everything else about the old Page is forgotten.
  """
  @spec page_turned(t()) :: t()
  def page_turned(%__MODULE__{} = occ), do: forget_page(occ)

  @doc "The Gives were reset. A held-over Track keeps the Speaker from falling silent."
  @spec gives_reset(t()) :: t()
  def gives_reset(%__MODULE__{} = occ), do: forget_page(occ)

  @doc """
  The Room's music setting changed to `mode`. Turning to "page" mid-Page starts
  Track work only when none is running and this Page's Track has not landed.
  """
  @spec music_changed(t(), String.t()) :: {t(), [effect()]}
  def music_changed(%__MODULE__{} = occ, "page") do
    if not track_for_page?(occ) and not occ.track_running? and not is_nil(occ.page_ref) and
         not is_nil(occ.gives) do
      start_track_work(occ)
    else
      {occ, []}
    end
  end

  def music_changed(%__MODULE__{} = occ, _mode), do: {occ, []}

  @doc """
  Takes the Track off the Speaker, whether it is this Page's or held over.
  Transitional: Next and Never use it until they move here.
  """
  @spec drop_track(t()) :: t()
  def drop_track(%__MODULE__{} = occ), do: %{occ | track: nil, track_page_ref: nil}

  @doc """
  The snapshot fragment: `vamp`, `track`, `music_meta`, `loop`, `playing`,
  `next?` and `never?`.
  """
  @spec view(t(), table()) :: map()
  def view(%__MODULE__{} = occ, %{music: mode, closed?: closed?, draw: draw, members: members}) do
    playing = playing(occ, mode, closed?, draw)

    %{
      vamp: if(mode == "page" and not track_for_page?(occ) and not closed?, do: occ.vamp),
      track: if(mode == "page", do: occ.track),
      music_meta: occ.music_meta,
      loop: if(mode != "off", do: draw),
      playing: playing,
      next?: next_offered?(playing, members),
      never?: never_offered?(playing, members)
    }
  end

  @doc """
  The `music_meta` and `vamp_meta` the Chronicle records for a closing Page.
  Under "page", a Page whose Track never landed records an "unfinished" failure.
  """
  @spec chronicle_meta(t(), String.t()) :: %{music_meta: map() | nil, vamp_meta: map() | nil}
  def chronicle_meta(%__MODULE__{} = occ, mode) do
    music_meta =
      cond do
        mode != "page" -> nil
        not is_nil(occ.music_meta) -> occ.music_meta
        true -> Steward.score_failure(:unfinished)
      end

    %{music_meta: music_meta, vamp_meta: occ.vamp_meta}
  end

  # -- arrivals -------------------------------------------------------------

  defp arrive(occ, :vamp, {:ok, vamp}, current?, page_ref, closed?) do
    vamp_meta = vamp_meta(vamp)
    persist = {:persist_vamp_meta, page_ref, vamp_meta}

    cond do
      current? and not closed? and occ.track_running? ->
        {%{occ | vamp_running?: false, vamp: vamp, vamp_meta: vamp_meta},
         [persist, log(occ, page_ref, "vamp landed")]}

      current? ->
        {%{occ | vamp_running?: false, vamp_meta: vamp_meta},
         [persist, log(occ, page_ref, "vamp landed")]}

      true ->
        {occ, [persist]}
    end
  end

  defp arrive(occ, :vamp, {:error, reason}, true, page_ref, _closed?) do
    {%{occ | vamp_running?: false}, [log(occ, page_ref, {:vamp_failure, reason})]}
  end

  defp arrive(occ, :track, {:ok, track}, true, page_ref, closed?) do
    title = track[:title] || occ.title
    {_track, music_meta} = merge_track_meta(occ.music_meta, track, title, occ.title_meta)
    effects = [{:persist_music_meta, page_ref, music_meta}, log(occ, page_ref, "track landed")]
    occ = %{occ | track_running?: false, vamp: nil}

    if closed? do
      {occ, effects}
    else
      {occ, cache} = play_track(occ, track, title, occ.title_meta)
      {occ, effects ++ cache}
    end
  end

  defp arrive(occ, :track, {:ok, track}, false, page_ref, _closed?) do
    {_track, music_meta} = merge_track_meta(nil, track, track[:title], %{})
    {occ, [{:persist_music_meta, page_ref, music_meta}]}
  end

  defp arrive(occ, :track, {:error, reason}, true, page_ref, closed?) do
    occ = %{occ | track_running?: false, vamp: nil}

    if closed? do
      {occ, []}
    else
      occ = if occ.track_page_ref == page_ref, do: drop_track(occ), else: occ

      {%{occ | music_meta: Steward.score_failure(reason)},
       [log(occ, page_ref, {:failure, reason})]}
    end
  end

  defp arrive(occ, :title, result, true, page_ref, closed?) do
    occ = %{occ | title_running?: false}

    case {closed?, result} do
      {true, _} ->
        {occ, []}

      {false, {:ok, %{title: title} = answer}} ->
        title_meta = answer[:meta] || %{}
        occ = %{occ | title: title, title_meta: title_meta}

        if track_for_page?(occ) do
          play_track(occ, occ.track, title, title_meta)
        else
          {occ, []}
        end

      {false, {:error, reason}} ->
        {occ, [log(occ, page_ref, {:title_failure, reason})]}
    end
  end

  # Anything else is a failure or a title for a Page that is no longer current:
  # it has nothing to persist and nothing to play.
  defp arrive(occ, _kind, _result, _current?, _page_ref, _closed?), do: {occ, []}

  # -- the Page's own Track ---------------------------------------------------

  defp start_track_work(occ) do
    case occ.cached do
      %{title: title} = cached when not is_nil(title) ->
        {_cached, music_meta} = merge_track_meta(nil, cached, title, %{})

        occ = %{
          occ
          | track: cached,
            track_page_ref: occ.page_ref,
            title: title,
            music_meta: music_meta,
            vamp: nil,
            vamp_meta: nil,
            vamp_running?: false,
            track_running?: false,
            title_running?: false
        }

        {occ, [log(occ, occ.page_ref, "cache hit")]}

      _ ->
        %{page_ref: ref, gives: gives, gives_landed_at: landed_at} = occ

        {%{occ | vamp_running?: true, track_running?: true, title_running?: true},
         [
           log(occ, ref, "cache miss"),
           log(occ, ref, "vamp started"),
           {:start_vamp, ref, gives},
           log(occ, ref, "score queued"),
           {:enqueue_track, ref, gives, landed_at},
           {:start_title, ref, gives}
         ]}
    end
  end

  # This Page's Track is on the Speaker, titled, and kept for the same Gives.
  defp play_track(occ, track, title, title_meta) do
    {track, music_meta} = merge_track_meta(occ.music_meta, track, title, title_meta)
    occ = %{occ | track: track, track_page_ref: occ.page_ref, music_meta: music_meta}
    {occ, [{:cache_track, occ.gives, track}]}
  end

  # Title, path and title cost go onto the meta already recorded for this
  # Page, unless that meta records a failure; then the Track's own meta is the
  # base. Returns the Track carrying its title, and the merged meta.
  defp merge_track_meta(existing, track, title, title_meta) do
    title_meta = title_meta || %{}
    title_cost = title_meta[:cost_usd] || title_meta["cost_usd"] || 0.0
    track = if title, do: Map.put(track, :title, title), else: track

    base =
      case existing do
        %{} = meta when not is_map_key(meta, :failure) and not is_map_key(meta, "failure") ->
          meta

        _ ->
          Map.get(track, :meta) || %{}
      end

    attrs =
      [path: track.path] ++ if(title, do: [title: title, title_cost_usd: title_cost], else: [])

    {track, put_meta(base, attrs)}
  end

  defp vamp_meta(vamp) when is_map(vamp) do
    base = vamp[:meta] || vamp["meta"] || %{}

    put_meta(base,
      path: vamp[:path] || vamp["path"],
      duration: vamp[:duration] || vamp["duration"],
      format: vamp[:format] || vamp["format"],
      loop: Map.get(vamp, :loop, Map.get(vamp, "loop", true))
    )
  end

  defp put_meta(base, pairs) do
    Enum.reduce(pairs, base || %{}, fn {key, val}, acc ->
      acc
      |> Map.put(key, val)
      |> Map.put(to_string(key), val)
    end)
  end

  defp forget_page(occ) do
    %{
      occ
      | page_ref: nil,
        gives: nil,
        gives_landed_at: nil,
        cached: nil,
        vamp: nil,
        vamp_meta: nil,
        title: nil,
        title_meta: nil,
        music_meta: nil,
        vamp_running?: false,
        track_running?: false,
        title_running?: false
    }
  end

  defp current?(%{page_ref: nil}, _page_ref), do: false
  defp current?(%{page_ref: ref}, page_ref), do: ref == page_ref

  defp track_for_page?(occ) do
    not is_nil(occ.track) and not is_nil(occ.page_ref) and occ.track_page_ref == occ.page_ref
  end

  defp log(occ, page_ref, event), do: {:log, page_ref, event, occ.gives_landed_at}

  # -- what is playing ---------------------------------------------------------

  defp playing(_occ, "off", _closed?, _draw), do: nil
  defp playing(_occ, "house", _closed?, draw), do: repertoire_playing(draw)

  defp playing(occ, "page", closed?, draw) do
    cond do
      track_for_page?(occ) and occ.track[:path] ->
        track_playing(occ, if(closed?, do: "holdover", else: "track"))

      (not closed? and occ.vamp) && occ.vamp[:path] ->
        %{path: occ.vamp.path, title: nil, kind: "vamp"}

      occ.track && occ.track[:path] ->
        track_playing(occ, "holdover")

      true ->
        repertoire_playing(draw)
    end
  end

  defp track_playing(occ, kind) do
    %{path: occ.track.path, title: occ.track[:title] || occ.title || "Track", kind: kind}
  end

  defp repertoire_playing(draw) do
    %{path: draw.path, title: draw[:title] || draw[:name] || "Track", kind: "repertoire"}
  end

  defp next_offered?(playing, members) do
    playing != nil and playing.kind in ["repertoire", "holdover"] and length(members) > 1
  end

  defp never_offered?(playing, members) do
    playing != nil and playing.kind in ["repertoire", "holdover", "track"] and
      not last_member?(playing, members)
  end

  defp last_member?(_playing, []), do: true
  defp last_member?(playing, [only]), do: only.path == playing.path
  defp last_member?(_playing, _members), do: false
end
