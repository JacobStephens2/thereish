defmodule Thereish.Foley.Occupancy do
  @moduledoc """
  What the Speaker is playing for a Room right now: this Page's Track, its
  Vamp, a held-over Track, or a Repertoire draw.

  It is a pure reducer in the shape of the Game. The Room tells it what
  happened — a Page opened, a Foley result arrived, the Page turned, the Gives
  were reset, the music setting changed — and gets back a new Occupancy and a
  list of effects to perform. It does no I/O: a TrackCache hit and the
  Repertoire's eligible members come in as arguments, and every write goes out
  as an effect.

  It also holds the Repertoire draw, the session deal and the eligible members,
  and decides Next and Never on them (ADR-0013).

  It never stores the Page's Phase or the Room's music setting. Both are the
  caller's facts, passed in on each call that needs them, so neither can drift.

  ## Effects

    * `{:start_vamp, page_ref, gives}`
    * `{:enqueue_track, page_ref, gives, gives_landed_at}`
    * `{:start_title, page_ref, gives}`
    * `{:look_up_track, page_ref, gives}` — answer with `track_looked_up/3`
    * `{:persist_vamp_meta, page_ref, meta}` — onto the Page this ref names,
      once it is in the Chronicle
    * `{:persist_music_meta, page_ref, meta}` — likewise
    * `{:cache_track, gives, track}`
    * `{:record_never, path}` — this Room never plays `path` again
    * `{:log, page_ref, event, gives_landed_at}`

  ## Stale results

  A Vamp, Track or title is answered for the Page ref it was asked for. One
  that arrives for any other ref belongs to a superseded Page: what it carries
  is persisted to that Page and nothing is played. One that arrives after its
  own Page closed is persisted the same way. That rule lives in `arrived/4` and
  nowhere else.
  """

  alias Thereish.Foley.Repertoire
  alias Thereish.Foley.Track
  alias Thereish.Foley.Vamp

  defstruct draw: nil,
            deal: [],
            members: [],
            page_ref: nil,
            gives: nil,
            gives_landed_at: nil,
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

  @type page_ref :: term()
  @type gives :: [String.t()]

  @type t :: %__MODULE__{
          draw: Repertoire.member() | nil,
          deal: [Repertoire.member()],
          members: [Repertoire.member()],
          page_ref: page_ref() | nil,
          gives: gives() | nil,
          gives_landed_at: integer() | nil,
          track: map() | nil,
          track_page_ref: page_ref() | nil,
          vamp: map() | nil,
          vamp_meta: Vamp.t() | nil,
          title: String.t() | nil,
          title_meta: map() | nil,
          music_meta: Track.t() | nil,
          vamp_running?: boolean(),
          track_running?: boolean(),
          title_running?: boolean()
        }

  @typedoc """
  Something for the Room to do. Effects are descriptions: Occupancy performs
  none of them.
  """
  @type effect ::
          {:start_vamp, page_ref(), gives()}
          | {:enqueue_track, page_ref(), gives(), integer()}
          | {:start_title, page_ref(), gives()}
          | {:look_up_track, page_ref(), gives()}
          | {:persist_vamp_meta, page_ref(), Vamp.t()}
          | {:persist_music_meta, page_ref(), Track.t()}
          | {:cache_track, gives(), map()}
          | {:record_never, String.t()}
          | {:log, page_ref(), String.t() | {atom(), term()}, integer() | nil}

  @typedoc "The Room's facts for this call: its music setting and whether its Page has closed."
  @type table :: %{music: String.t(), closed?: boolean()}

  @doc """
  An Occupancy with no Page open, playing a Repertoire draw from `members`, the
  Room's eligible members, with the rest of them dealt.
  """
  @spec new([Repertoire.member()]) :: t()
  def new(members), do: redraw(%__MODULE__{}, members)

  @doc """
  A Page opened from these Gives. `cached` is the TrackCache's answer for them,
  or nil. Under "page" a stored Track plays at once. A title is asked for only
  when that Track has none. With nothing stored, Vamp, Track and title work is
  asked for. A Track still playing holds over.
  """
  @spec page_opened(t(), page_ref(), gives(), map() | nil, integer(), String.t()) ::
          {t(), [effect()]}
  def page_opened(%__MODULE__{} = occ, page_ref, gives, cached, now, mode) do
    occ = %{forget_page(occ) | page_ref: page_ref, gives: gives, gives_landed_at: now}
    if mode == "page", do: start_track_work(occ, cached), else: {occ, []}
  end

  @doc """
  A Foley result arrived for `page_ref`: `{:vamp | :track | :title, result}`,
  where result is `{:ok, value}` or `{:error, reason}`. `closed?` is whether the
  Room's current Page has closed.
  """
  @spec arrived(
          t(),
          page_ref(),
          {:vamp | :track | :title, {:ok, map()} | {:error, term()}},
          boolean()
        ) ::
          {t(), [effect()]}
  def arrived(%__MODULE__{} = occ, page_ref, {kind, result}, closed?) do
    arrive(occ, kind, result, current?(occ, page_ref), page_ref, closed?)
  end

  @doc """
  The Page turned. A Track still playing holds over until the next Page's
  Track lands (ADR-0013); everything else about the old Page is forgotten. A
  fresh draw, not the last one, and a fresh deal are made from `members`, the
  Room's eligible members now.
  """
  @spec page_turned(t(), [Repertoire.member()]) :: t()
  def page_turned(%__MODULE__{} = occ, members), do: occ |> forget_page() |> redraw(members)

  @doc "The Gives were reset. A held-over Track keeps the Speaker from falling silent."
  @spec gives_reset(t()) :: t()
  def gives_reset(%__MODULE__{} = occ), do: forget_page(occ)

  @doc """
  The Room's music setting changed to `mode`. Turning to "page" mid-Page starts
  Track work only when none is running and this Page's Track has not landed:
  it asks for the TrackCache to be looked up, and the answer comes back
  through `track_looked_up/3`.
  """
  @spec music_changed(t(), String.t()) :: {t(), [effect()]}
  def music_changed(%__MODULE__{} = occ, "page") do
    if not track_for_page?(occ) and not occ.track_running? and not is_nil(occ.page_ref) and
         not is_nil(occ.gives) do
      {occ, [{:look_up_track, occ.page_ref, occ.gives}]}
    else
      {occ, []}
    end
  end

  def music_changed(%__MODULE__{} = occ, _mode), do: {occ, []}

  @doc """
  The TrackCache answered a `{:look_up_track, ...}` effect with `cached`, or
  nil. A stored Track plays at once, and a title is asked for only when it has
  none; with nothing stored, Track work starts. An answer for a Page no longer
  current, or arriving once work is running, starts nothing.
  """
  @spec track_looked_up(t(), page_ref(), map() | nil) :: {t(), [effect()]}
  def track_looked_up(%__MODULE__{} = occ, page_ref, cached) do
    if current?(occ, page_ref) and not occ.track_running? and not track_for_page?(occ) do
      start_track_work(occ, cached)
    else
      {occ, []}
    end
  end

  @doc """
  Next: the Speaker moves to the next member of the deal, reshuffling when the
  deal runs out, and a held-over Track is dropped. Refused on this Page's own
  Track, and when no other member exists.
  """
  @spec next(t(), table()) :: {:ok, t(), [effect()]} | {:error, :refused}
  def next(%__MODULE__{} = occ, table) do
    %{playing: playing, next?: next?} = view(occ, table)

    with true <- next?,
         {:ok, member, deal} <- Repertoire.next_deal(occ.members, occ.deal, playing.path) do
      occ = %{occ | draw: member, deal: deal}
      {:ok, if(playing.kind == "holdover", do: drop_track(occ), else: occ), []}
    else
      _ -> {:error, :refused}
    end
  end

  @doc """
  Never: what is playing leaves the eligible members and the deal for good, the
  Speaker moves on, and a Track playing or held over is cleared. Answers a
  `{:record_never, path}` effect. Refused on the last remaining member.
  """
  @spec never(t(), table()) :: {:ok, t(), [effect()]} | {:error, :refused}
  def never(%__MODULE__{} = occ, table) do
    %{playing: playing, never?: never?} = view(occ, table)

    with true <- never?,
         path = playing.path,
         members = Enum.reject(occ.members, &(&1.path == path)),
         deal = Enum.reject(occ.deal, &(&1.path == path)),
         {:ok, member, deal} <- Repertoire.advance_after_never(members, deal, path) do
      occ = %{occ | draw: member, deal: deal, members: members}
      occ = if playing.kind in ["holdover", "track"], do: drop_track(occ), else: occ
      {:ok, occ, [{:record_never, path}]}
    else
      _ -> {:error, :refused}
    end
  end

  @doc """
  The snapshot fragment: `vamp`, `track`, `music_meta`, `loop`, `playing`,
  `next?` and `never?`.
  """
  @spec view(t(), table()) :: map()
  def view(%__MODULE__{draw: draw, members: members} = occ, %{music: mode, closed?: closed?}) do
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
  @spec chronicle_meta(t(), String.t()) :: %{
          music_meta: Track.t() | nil,
          vamp_meta: Vamp.t() | nil
        }
  def chronicle_meta(%__MODULE__{} = occ, mode) do
    music_meta =
      cond do
        mode != "page" -> nil
        not is_nil(occ.music_meta) -> occ.music_meta
        true -> Track.failed(:unfinished)
      end

    %{music_meta: music_meta, vamp_meta: occ.vamp_meta}
  end

  # -- arrivals -------------------------------------------------------------

  defp arrive(occ, :vamp, {:ok, vamp}, current?, page_ref, closed?) do
    vamp_meta = Vamp.landed(vamp)
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
    music_meta = Track.landed(track, title, occ.title_meta)
    track = if title, do: Map.put(track, :title, title), else: track
    effects = [{:persist_music_meta, page_ref, music_meta}, log(occ, page_ref, "track landed")]
    occ = %{occ | track_running?: false, vamp: nil}

    if closed? do
      {occ, effects}
    else
      {occ, cache} = put_track(occ, track, music_meta)
      {occ, effects ++ cache}
    end
  end

  defp arrive(occ, :track, {:ok, track}, false, page_ref, _closed?) do
    {occ, [{:persist_music_meta, page_ref, Track.landed(track, track[:title], %{})}]}
  end

  defp arrive(occ, :track, {:error, reason}, true, page_ref, closed?) do
    occ = %{occ | track_running?: false, vamp: nil}

    if closed? do
      {occ, []}
    else
      occ = if occ.track_page_ref == page_ref, do: drop_track(occ), else: occ

      {%{occ | music_meta: Track.failed(reason)}, [log(occ, page_ref, {:failure, reason})]}
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
          play_track(occ, title, title_meta)
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

  defp start_track_work(occ, %{path: path} = cached) when is_binary(path) and path != "" do
    title = cached[:title]
    music_meta = Track.landed(cached, title, %{})
    title_missing? = is_nil(title)

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
        title_running?: title_missing?
    }

    effects = [log(occ, occ.page_ref, "cache hit")]

    if title_missing? do
      {occ, effects ++ [{:start_title, occ.page_ref, occ.gives}]}
    else
      {occ, effects}
    end
  end

  defp start_track_work(occ, _cached) do
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

  # This Page's Track is on the Speaker, titled, and kept for the same Gives.
  defp play_track(occ, title, title_meta) do
    music_meta = Track.titled(occ.music_meta, title, title_meta)
    put_track(occ, Map.put(occ.track, :title, title), music_meta)
  end

  defp put_track(occ, track, music_meta) do
    occ = %{occ | track: track, track_page_ref: occ.page_ref, music_meta: music_meta}
    {occ, [{:cache_track, occ.gives, track}]}
  end

  defp drop_track(occ), do: %{occ | track: nil, track_page_ref: nil}

  defp redraw(occ, members) do
    draw = Repertoire.draw(members, occ.draw)
    %{occ | members: members, draw: draw, deal: Repertoire.deal(members, draw.path)}
  end

  defp forget_page(occ) do
    %{
      occ
      | page_ref: nil,
        gives: nil,
        gives_landed_at: nil,
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
