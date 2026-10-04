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
      arrival order. The Chronicle entry is built when the Page closes, and
      Voice may hold its write while the Verdict is still being spoken; a
      result that lands in that window is newer than the entry it follows;
    * any other ref is dropped. Before the Page closes, the entry it closes
      with carries what the Room knows, so an earlier write would only
      replay something older over it. A giving that was reset, or a Page
      turned before its write landed, was never written, so its results
      have nowhere to go.

  ## The arm

  The experiment arm of the Page in play is kept here too. New Gives keep it,
  so an abandoned Author request and the Page written after it share one
  assignment; a turned Page clears it.

  ## Effects

    * `{:write, page_id, write}`: perform this write onto that Chronicle Page
  """

  defstruct giving: nil, page_refs: [], arm: nil, closed?: false, written: %{}, held: []

  @type ref :: reference()
  @type page_id :: Ecto.UUID.t()

  @type t :: %__MODULE__{
          giving: ref(),
          page_refs: [ref()],
          arm: atom() | nil,
          closed?: boolean(),
          written: %{optional(ref()) => page_id()},
          held: [term()]
        }

  @typedoc "A write onto a named Chronicle Page. Pages performs none of them."
  @type effect :: {:write, page_id(), term()}

  @doc "Pages before the first Give: a fresh giving and nothing written."
  @spec new() :: t()
  def new, do: %__MODULE__{giving: make_ref()}

  @doc "The ref of the Gives in play, for a Mask task to carry."
  @spec giving(t()) :: ref()
  def giving(%__MODULE__{giving: giving}), do: giving

  @doc "The Author was asked for a Page under this ref, for this arm."
  @spec page_opened(t(), ref(), atom()) :: t()
  def page_opened(%__MODULE__{} = pages, page_ref, arm) do
    %{pages | page_refs: [page_ref | pages.page_refs], arm: arm}
  end

  @doc "The experiment arm of the Page in play, or nil before one is assigned."
  @spec arm(t()) :: atom() | nil
  def arm(%__MODULE__{arm: arm}), do: arm

  @doc """
  The Page in play closed and its Chronicle entry is built. Writes for it are
  held from now until it is written.
  """
  @spec page_closed(t()) :: t()
  def page_closed(%__MODULE__{} = pages), do: %{pages | closed?: true}

  @doc """
  The Page in play is in the Chronicle as `page_id`. Every ref that names it
  now writes there, and what was held for it is released, oldest first.
  """
  @spec written(t(), page_id()) :: {t(), [effect()]}
  def written(%__MODULE__{} = pages, page_id) do
    written =
      Enum.reduce([pages.giving | pages.page_refs], pages.written, &Map.put(&2, &1, page_id))

    effects = pages.held |> Enum.reverse() |> Enum.map(&{:write, page_id, &1})

    {%{pages | written: written, held: []}, effects}
  end

  @doc "A write onto the Page `ref` names: now, once it is written, or never."
  @spec write(t(), ref(), term()) :: {t(), [effect()]}
  def write(%__MODULE__{} = pages, ref, write) do
    cond do
      Map.has_key?(pages.written, ref) ->
        {pages, [{:write, Map.fetch!(pages.written, ref), write}]}

      pages.closed? and in_play?(pages, ref) ->
        {%{pages | held: [write | pages.held]}, []}

      true ->
        {pages, []}
    end
  end

  @doc "The Gives were reset before the Page was written: start a new giving."
  @spec gives_reset(t()) :: t()
  def gives_reset(%__MODULE__{} = pages), do: forget_giving(pages)

  @doc """
  The Page turned. Call it after Voice has released any Page it was holding,
  so that Page's write, and the writes held for it, have already landed.
  """
  @spec page_turned(t()) :: t()
  def page_turned(%__MODULE__{} = pages), do: %{forget_giving(pages) | arm: nil}

  defp in_play?(pages, ref), do: ref == pages.giving or ref in pages.page_refs

  defp forget_giving(pages),
    do: %{pages | giving: make_ref(), page_refs: [], closed?: false, held: []}
end
