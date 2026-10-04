defmodule Thereish.Scribe do
  @moduledoc """
  The machine role that writes the Chronicle after play.

  The Room's part in this is one line — a Page closed, go and write about it —
  and everything after that line is here: which Page, what the Scribe is allowed
  to have read of the Room's history, what to do with the paragraph, and what to
  do when there is no paragraph. None of it is Room state and none of it belongs
  in a `GenServer` that has a next Page to deal.

  It writes from a task under its own supervisor rather than the Steward's,
  because the two are different lengths of thing: an assay lives and dies inside
  a reveal beat, and a recap is a model writing a paragraph after everyone has
  stood up. Nothing should have to wait on one to know about the other.

  Naming a Room is the Scribe's other job, called through the Steward seam
  (`Thereish.Steward.name_room/2`).
  """

  require Logger

  alias Thereish.Chronicle
  alias Thereish.Steward

  @doc """
  Writes about one closed Page, in the background, and tells the Room's readers
  when there is something new to read.

  Returns as soon as the work is started. Nothing is sent back: the book
  computes the recap out of its row, so a broadcast is the whole of the update,
  and there is nothing about a Room that a recap changes.
  """
  @spec write_about(Thereish.Rooms.Room.t(), Thereish.Chronicle.Page.t()) :: :ok
  def write_about(room, page) do
    {:ok, _pid} =
      Task.Supervisor.start_child(Thereish.Scribe.Tasks, fn -> recap(room, page) end)

    :ok
  end

  @doc """
  Asks for one Page's recap and files it.

  Runs where it is called, which in the game is inside `write_about/2`'s task
  and in a test is wherever the test wants it.
  """
  @spec recap(Thereish.Rooms.Room.t(), Thereish.Chronicle.Page.t()) ::
          :ok | {:error, term()}
  def recap(room, page) do
    # Both of these are read back out of the log rather than passed down from
    # the Room, so that the Page the Scribe writes about and the Chronicle it
    # reaches into cannot disagree. The Steward reads every Page before this one,
    # because this one is in the question already and what a callback reaches
    # back for is everything before tonight.
    views = Chronicle.page_views(room.id, :asc)
    view = Enum.find(views, &(&1.id == page.id))

    # In live play, this Page is already the last in the log. During a replay or
    # catch-up sync, later Pages already exist in the log; taking only the views
    # before this Page ensures later play never leaks into this Page's callback.
    prior_views = Enum.take_while(views, &(&1.id != page.id))

    case Steward.recap(view, prior_views) do
      {:ok, recap} ->
        {:ok, _row} = Chronicle.record_recap(room.id, Map.put(recap, :page_id, page.id))

        # The Chronicle changed and the Room did not, which is exactly the
        # difference between the two events: a phone in the middle of a Page has
        # nothing to redraw, and a phone reading the book has a new paragraph.
        Thereish.Rooms.broadcast(room.slug, :chronicle_changed)

        :ok

      {:error, reason} ->
        # A Page with no recap is a Page with no recap. The book says so, and
        # the couple can write their own (design law 5).
        Logger.error(
          "the Scribe wrote no recap for #{room.slug} page #{page.id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  rescue
    error ->
      Logger.error(
        "the Scribe fell over for #{room.slug} page #{page.id}: #{Exception.message(error)}"
      )

      {:error, error}
  end

  @doc """
  Finds all closed Pages without recaps, in chronological order, and writes
  recaps for them.

  If a Room Code is provided, only Pages in that Room are processed.
  """
  @spec sync(String.t() | nil) :: :ok
  def sync(code \\ nil) do
    rooms = rooms_for_sync(code)

    for room <- rooms do
      pages = Chronicle.unrecapped_pages(room.id)

      for page <- pages do
        recap(room, page)
      end
    end

    :ok
  end

  defp rooms_for_sync(nil), do: Thereish.Rooms.list_rooms()

  defp rooms_for_sync(code) when is_binary(code) do
    case Thereish.Rooms.get_room(code) do
      nil -> []
      room -> [room]
    end
  end
end
