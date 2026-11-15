defmodule Thereish.Rooms.Pages do
  @moduledoc """
  Which Chronicle Page each result the Room is waiting on belongs to.

  It is a pure reducer in the shape of Pacing, Occupancy and Voice. The Room
  tells it that a Page was opened, that it closed, that its Chronicle Page
  was written, that the Gives were reset or the Page turned, and hands it
  each write that should land on a Page. It answers with a new Pages and the
  writes to perform now. It does no I/O, and it never looks inside a write.

  ## Two kinds of ref

  A Mask is drawn as soon as its Give lands, before the Author is asked for
  anything, so its task carries the *giving* ref: one per set of Gives, made
  fresh when they are reset or the Page turns. Occupancy asks for its Foley
  under a *Page* ref, one per Author request, so an Author retry makes a
  second. `page_opened/3` records each Page ref under the giving it was asked
  for, and `written/2` binds every one of them, and the giving ref, to the
  Chronicle Page.

  ## Where a write goes

  That rule lives in `write/3` and nowhere else:

    * a ref of a written Page writes onto that Page now;
    * a ref of the Page in play, once it has closed but before it is
      written, is held until `written/2`, which releases every held write in
      arrival order. The Chronicle Entry is built when the Page closes, and
      Pages holds it while the closing Verdict is still being spoken; a
      result that lands in that window is newer than the entry it follows;
    * any other ref is dropped. Before the Page closes, the entry it closes
      with carries what the Room knows, so an earlier write would only
      replay something older over it. A giving that was reset, or a Page
      turned without an acknowledgement, was never written, so its results
      have nowhere to go after that context is forgotten.

  ## The Entry and speech

  Voice reports pending Verdict synthesis and normalized completion metadata.
  Pages keeps the latest pending Attempt and completed metadata per Attempt.
  `page_closed/2` attaches matching metadata and submits the Entry immediately,
  unless that latest pending Verdict belongs to it. Its success or failure
  then submits the Entry once, before Voice announces its clip is ready.

  A turn flushes a held Entry with the metadata already received and starts
  fresh recording state. Only the submitted refs and deferred writes survive
  until the Room's synchronous `written/2` acknowledgement. A failed write
  has no acknowledgement and no retry; its context is forgotten on the next
  turn or close. Acknowledgement never replaces the new giving.

  ## The Assignment

  The Assignment of the Page in play is kept here too. New Gives
  keep it, so an abandoned Author request and the Page written after it share
  one Assignment; a turned Page clears it.

  ## Effects

    * `{:commit_chronicle, entry}`: insert the Entry, then answer with `written/2`
    * `{:write, page_id, write}`: perform this write onto that Chronicle Page
  """

  alias Thereish.Chronicle.Entry

  defstruct giving: nil,
            page_refs: [],
            assignment: nil,
            closed?: false,
            written: %{},
            held: [],
            pending_verdict: nil,
            voice_meta: %{},
            held_entry: nil,
            submitted: nil

  @type ref :: reference()
  @type page_id :: Ecto.UUID.t()

  @type t :: %__MODULE__{
          giving: ref(),
          page_refs: [ref()],
          assignment: Thereish.Experiments.Assignment.t() | nil,
          closed?: boolean(),
          written: %{optional(ref()) => page_id()},
          held: [term()],
          pending_verdict: integer() | nil,
          voice_meta: %{optional(integer()) => map()},
          held_entry: Entry.t() | nil,
          submitted: %{refs: [ref()], held: [term()]} | nil
        }

  @typedoc "An Entry submission or a write onto a named Page. Pages performs neither."
  @type effect :: {:commit_chronicle, Entry.t()} | {:write, page_id(), term()}

  @doc "Pages before the first Give: a fresh giving and nothing written."
  @spec new() :: t()
  def new, do: %__MODULE__{giving: make_ref()}

  @doc "The ref of the Gives in play, for a Mask task to carry."
  @spec giving(t()) :: ref()
  def giving(%__MODULE__{giving: giving}), do: giving

  @doc "The Author was asked for a Page under this ref, for this Assignment."
  @spec page_opened(t(), ref(), Thereish.Experiments.Assignment.t()) :: t()
  def page_opened(%__MODULE__{} = pages, page_ref, assignment) do
    %{pages | page_refs: [page_ref | pages.page_refs], assignment: assignment}
  end

  @doc "The Assignment of the Page in play, or nil before one is made."
  @spec assignment(t()) :: Thereish.Experiments.Assignment.t() | nil
  def assignment(%__MODULE__{assignment: assignment}), do: assignment

  @doc """
  The prepared Entry closed the Page. Attach completed speech metadata, then
  submit it once, or hold it for its latest pending Verdict's completion.
  Later writes wait for the successful Chronicle acknowledgement.
  """
  @spec page_closed(t(), Entry.t()) :: {t(), [effect()]}
  def page_closed(%__MODULE__{closed?: true} = pages, %Entry{}), do: {pages, []}

  def page_closed(%__MODULE__{} = pages, %Entry{} = entry) do
    pages = %{pages | closed?: true, submitted: nil, held_entry: entry}

    if waiting?(pages, entry), do: {pages, []}, else: submit(pages)
  end

  @doc "Voice actually requested synthesis of this Attempt's Verdict."
  @spec verdict_pending(t(), integer()) :: {t(), [effect()]}
  def verdict_pending(%__MODULE__{} = pages, attempt),
    do: {%{pages | pending_verdict: attempt}, []}

  @doc "Voice accepted success or failure metadata for this Attempt's Verdict."
  @spec verdict_spoken(t(), integer(), map()) :: {t(), [effect()]}
  def verdict_spoken(%__MODULE__{pending_verdict: nil} = pages, _attempt, _meta),
    do: {pages, []}

  def verdict_spoken(%__MODULE__{} = pages, attempt, meta) do
    matching? = pages.pending_verdict == attempt

    pages = %{pages | voice_meta: Map.put(pages.voice_meta, attempt, meta)}

    if matching?, do: submit(pages), else: {pages, []}
  end

  @doc """
  The submitted Page is in the Chronicle as `page_id`. Every ref that names it
  now writes there, and what was held for it is released, oldest first.
  """
  @spec written(t(), page_id()) :: {t(), [effect()]}
  def written(%__MODULE__{submitted: nil} = pages, _page_id), do: {pages, []}

  def written(%__MODULE__{submitted: submitted} = pages, page_id) do
    written =
      Enum.reduce(submitted.refs, pages.written, &Map.put(&2, &1, page_id))

    effects = submitted.held |> Enum.reverse() |> Enum.map(&{:write, page_id, &1})

    {%{pages | written: written, submitted: nil}, effects}
  end

  @doc "A write onto the Page `ref` names: now, once it is written, or never."
  @spec write(t(), ref(), term()) :: {t(), [effect()]}
  def write(%__MODULE__{} = pages, ref, write) do
    cond do
      Map.has_key?(pages.written, ref) ->
        {pages, [{:write, Map.fetch!(pages.written, ref), write}]}

      pages.submitted != nil and ref in pages.submitted.refs ->
        submitted = %{pages.submitted | held: [write | pages.submitted.held]}
        {%{pages | submitted: submitted}, []}

      pages.closed? and in_play?(pages, ref) ->
        {%{pages | held: [write | pages.held]}, []}

      true ->
        {pages, []}
    end
  end

  @doc "The Gives were reset before the Page was written: start a new giving."
  @spec gives_reset(t()) :: t()
  def gives_reset(%__MODULE__{} = pages), do: %{forget_giving(pages) | submitted: nil}

  @doc """
  Turn the Page, flushing a held Entry before ordinary turn effects. Keep
  only that submission's acknowledgement context while starting the next Page.
  """
  @spec page_turned(t()) :: {t(), [effect()]}
  def page_turned(%__MODULE__{} = pages) do
    {pages, effects} = submit(%{pages | submitted: nil})
    {%{forget_giving(pages) | assignment: nil}, effects}
  end

  defp in_play?(pages, ref), do: ref == pages.giving or ref in pages.page_refs

  defp forget_giving(pages) do
    %{
      pages
      | giving: make_ref(),
        page_refs: [],
        closed?: false,
        held: [],
        held_entry: nil,
        pending_verdict: nil,
        voice_meta: %{}
    }
  end

  defp waiting?(pages, entry) do
    pending = pages.pending_verdict

    pending != nil and not Map.has_key?(pages.voice_meta, pending) and
      Enum.any?(entry.attempts, &(&1.number == pending))
  end

  defp submit(%{held_entry: nil} = pages), do: {pages, []}

  defp submit(%{held_entry: entry} = pages) do
    submitted = %{refs: [pages.giving | pages.page_refs], held: pages.held}
    entry = attach_meta(entry, pages.voice_meta)
    {%{pages | held_entry: nil, held: [], submitted: submitted}, [{:commit_chronicle, entry}]}
  end

  defp attach_meta(%Entry{} = entry, meta) do
    attempts =
      Enum.map(entry.attempts, fn %Entry.Attempt{} = attempt ->
        case Map.get(meta, attempt.number) do
          nil ->
            attempt

          voice_meta ->
            %{attempt | verdicts: Enum.map(attempt.verdicts, &%{&1 | voice_meta: voice_meta})}
        end
      end)

    %{entry | attempts: attempts}
  end
end
