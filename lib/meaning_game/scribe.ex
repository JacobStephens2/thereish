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
  @spec recap(MeaningGame.Rooms.Room.t(), MeaningGame.Chronicle.Page.t()) ::
          :ok | {:error, term()}
  def recap(room, page) do
    # Both of these are read back out of the log rather than passed down from
    # the Room, so that the Page the Scribe writes about and the Chronicle it
    # reaches into cannot disagree. The digest holds every Page before this one,
    # because this one is in the question already and what a callback reaches
    # back for is everything before tonight.
    views = Chronicle.page_views(room.id, :asc)
    view = Enum.find(views, &(&1.id == page.id))

    # In live play, this Page is already the last in the log. During a replay or
    # catch-up sync, later Pages already exist in the log; taking only the views
    # before this Page ensures later play never leaks into this Page's callback.
    prior_views = Enum.take_while(views, &(&1.id != page.id))
    digest = Chronicle.scribe_digest(prior_views, nil)

    case Steward.recap(view, digest) do
      {:ok, recap} ->
        {:ok, _row} = Chronicle.record_recap(room.id, Map.put(recap, :page_id, page.id))

        # The Chronicle changed and the Room did not, which is exactly the
        # difference between the two events: a phone in the middle of a Page has
        # nothing to redraw, and a phone reading the book has a new paragraph.
        MeaningGame.Rooms.broadcast(room.slug, :chronicle_changed)

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

  If a Room slug or ID is provided, only Pages in that Room are processed.
  """
  @spec sync(String.t() | Ecto.UUID.t() | nil) :: :ok
  def sync(room_id_or_slug \\ nil) do
    rooms = rooms_for_sync(room_id_or_slug)

    for room <- rooms do
      pages = unrecapped_pages(room.id)

      for page <- pages do
        recap(room, page)
      end
    end

    :ok
  end

  defp rooms_for_sync(nil), do: MeaningGame.Repo.all(MeaningGame.Rooms.Room)

  defp rooms_for_sync(slug_or_id) when is_binary(slug_or_id) do
    room =
      MeaningGame.Repo.get_by(MeaningGame.Rooms.Room, slug: slug_or_id) ||
        case Ecto.UUID.cast(slug_or_id) do
          {:ok, uuid} -> MeaningGame.Repo.get(MeaningGame.Rooms.Room, uuid)
          :error -> nil
        end

    if room, do: [room], else: []
  end

  defp unrecapped_pages(room_id) do
    import Ecto.Query

    from(p in MeaningGame.Chronicle.Page,
      left_join: r in MeaningGame.Chronicle.Recap,
      on: r.page_id == p.id,
      where: p.room_id == ^room_id and is_nil(r.id),
      order_by: [asc: p.closed_at, asc: p.id]
    )
    |> MeaningGame.Repo.all()
  end
end
