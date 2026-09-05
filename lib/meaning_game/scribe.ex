defmodule MeaningGame.Scribe do
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

  Naming a Room is the Scribe's other job and is not here yet
  (`.scratch/group-play/issues/04`).
  """

  require Logger

  alias MeaningGame.Chronicle
  alias MeaningGame.Steward

  @doc """
  Writes about one closed Page, in the background, and tells the Room's readers
  when there is something new to read.

  Returns as soon as the work is started. Nothing is sent back: the book
  computes the recap out of its row, so a broadcast is the whole of the update,
  and there is nothing about a Room that a recap changes.
  """
  @spec write_about(MeaningGame.Rooms.Room.t(), MeaningGame.Chronicle.Page.t()) :: :ok
  def write_about(room, page) do
    {:ok, _pid} =
      Task.Supervisor.start_child(MeaningGame.Scribe.Tasks, fn -> recap(room, page) end)

    :ok
  end

  @doc """
  Asks for one Page's recap and files it.

  Runs where it is called, which in the game is inside `write_about/2`'s task
  and in a test is wherever the test wants it.
  """
  @spec recap(MeaningGame.Rooms.Room.t(), MeaningGame.Chronicle.Page.t()) :: :ok
  def recap(room, page) do
    # Both of these are read back out of the log rather than passed down from
    # the Room, so that the Page the Scribe writes about and the Chronicle it
    # reaches into cannot disagree. The digest holds every Page but this one,
    # because this one is in the question already and what a callback reaches
    # back for is everything before tonight.
    views = Chronicle.page_views(room.id, :asc)
    view = Enum.find(views, &(&1.id == page.id))
    digest = Chronicle.scribe_digest(views, page.id)

    case Steward.recap(view, digest) do
      {:ok, recap} ->
        {:ok, _row} = Chronicle.record_recap(room.id, Map.put(recap, :page_id, page.id))

        # The Chronicle changed and the Room did not, which is exactly the
        # difference between the two events: a phone in the middle of a Page has
        # nothing to redraw, and a phone reading the book has a new paragraph.
        MeaningGame.Rooms.broadcast(room.slug, :chronicle_changed)

      {:error, reason} ->
        # A Page with no recap is a Page with no recap. The book says so, and
        # the couple can write their own (design law 5).
        Logger.warning("the Scribe wrote no recap for #{room.slug}: #{inspect(reason)}")
    end

    :ok
  rescue
    error ->
      Logger.error("the Scribe fell over: #{Exception.message(error)}")

      :ok
  end
end
