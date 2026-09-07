defmodule MeaningGame.RoomFixtures do
  @moduledoc """
  Opens a Room of its own for one test.

  Rooms are global — found by slug in a registry — so a test that reused a slug
  would inherit the previous test's Seats even after the sandbox rolled the rows
  back. Every test gets a slug nobody else has, and a Room process the test
  supervisor takes down at the end.
  """

  alias MeaningGame.Rooms
  alias MeaningGame.Rooms.Server
  alias MeaningGame.Rooms.Store

  @doc """
  Creates a Room with a Code of its own and starts it, returning the Code.

  Creating before starting is the order the game itself uses: Rooms are created
  through `MeaningGame.Rooms.create/2`, and a process is only ever started for a
  Room that already exists.
  """
  def open_room(opts \\ []) do
    slug = Keyword.get_lazy(opts, :slug, &unique_slug/0)
    seat_limit = Keyword.get(opts, :seat_limit, Rooms.default_seat_limit())

    {:ok, _room} = Store.insert_room(slug, seat_limit)

    ExUnit.Callbacks.start_supervised!(
      Supervisor.child_spec({Server, slug: slug}, id: {Server, slug})
    )

    # A Page that closes leaves the Scribe writing in a task the Room does not
    # wait for. Neither should the test — until it ends, at which point a task
    # still talking to Postgres would be talking to a sandbox connection whose
    # owner has gone.
    ExUnit.Callbacks.on_exit(&await_scribe/0)
    ExUnit.Callbacks.on_exit(&await_notice/0)

    slug
  end

  @doc """
  Takes a Room's process down again.

  For the tests that create a Room through `MeaningGame.Rooms.create/2` rather
  than through `open_room/1`: that Room is nobody's child but the dynamic
  supervisor's, so the test that made one puts it away itself.
  """
  def stop_room(code) do
    case GenServer.whereis(Server.via(code)) do
      nil -> :ok
      pid -> DynamicSupervisor.terminate_child(MeaningGame.Rooms.Supervisor, pid)
    end
  end

  @doc "A token standing in for one browser's."
  def device_token, do: "device-#{System.unique_integer([:positive])}"

  @doc """
  Turns the fake Assayer's dials for one test: `delay_ms` and `mode`.

  See `MeaningGame.Steward.Fake` for what they do. Configuration is global, so a
  test that reaches for this cannot be async — which is true of every test that
  touches a Room anyway.
  """
  def steward(opts) do
    steward = restore(:steward)
    fake = Keyword.merge(Keyword.fetch!(steward, :fake), opts)

    Application.put_env(:meaning_game, :steward, Keyword.put(steward, :fake, fake))
  end

  @doc "The reveal beat for one test, in milliseconds."
  def beat(ms) do
    restore(:reveal_beat_ms)

    Application.put_env(:meaning_game, :reveal_beat_ms, ms)
  end

  @doc """
  Where the escalation ladder's rungs sit for one test, in milliseconds from the
  moment the Assayer was asked.

  A test that watches a step go by needs a window it can catch the Room in, and
  the couch's four, eight and ten seconds are both too slow to run and — being
  evenly spaced — too tight to observe.
  """
  def escalation(opts) do
    steps = restore(:assayer_escalation_ms)

    Application.put_env(:meaning_game, :assayer_escalation_ms, Keyword.merge(steps, opts))
  end

  @doc """
  Where the Author escalation ladder's rungs sit for one test, in milliseconds from the
  moment the Author was asked.
  """
  def author_escalation(opts) do
    steps = restore(:author_escalation_ms)

    Application.put_env(:meaning_game, :author_escalation_ms, Keyword.merge(steps, opts))
  end

  @doc "How many Seats a newly opened Room holds, for one test."
  def seats_per_room(seats) do
    restore(:seats_per_room)

    Application.put_env(:meaning_game, :seats_per_room, seats)
  end

  @doc """
  How many attempts a Page gets, for one test.

  Two is usually enough to watch a Page run out of them, and five rounds of
  typing to prove the same rule is five rounds of nothing.
  """
  def attempt_cap(attempts) do
    restore(:attempts_per_page)

    Application.put_env(:meaning_game, :attempts_per_page, attempts)
  end

  @doc """
  The Room's view once it has reached `phase`.

  The Room reaches a reveal on its own time — a beat runs, a verdict arrives —
  so a test that wants to look at one waits for it the way a phone does.
  """
  def await_phase(slug, phase) do
    eventually(
      fn ->
        view = MeaningGame.Rooms.snapshot(slug, nil)
        view.phase == phase && view
      end,
      "the Room never reached #{inspect(phase)}"
    )
  end

  @doc """
  The Room's view once the reveal is up, whether or not it closed the Page.

  What a test that plays a Page is waiting for is the reveal landing; whether
  the grade also ended the Page is the thing under test rather than the thing to
  wait on.
  """
  def await_reveal(slug) do
    eventually(
      fn ->
        view = MeaningGame.Rooms.snapshot(slug, nil)
        view.reveal != nil && view
      end,
      "the reveal never landed in this Room"
    )
  end

  @doc """
  Waits until the Scribe has finished writing.

  It writes from a task the Room deliberately does not wait for, so a test that
  wants to look at what it decided — including a test that wants to see it
  decide nothing — waits for the task rather than for a row that may never
  arrive. It also keeps the sandbox honest: a task still holding a connection
  when the test's owner exits takes the connection down with it.

  The Assayer's tasks are somebody else's supervisor and are deliberately not
  waited on here: a test that wants a slow grade wants it still in flight.
  """
  def await_scribe do
    eventually(
      fn -> Task.Supervisor.children(MeaningGame.Scribe.Tasks) == [] end,
      "the Scribe was still writing"
    )

    :ok
  end

  @doc "Waits for any background notice delivery tasks to finish."
  def await_notice do
    eventually(
      fn -> Task.Supervisor.children(MeaningGame.Notice.Tasks) == [] end,
      "the notice was still delivering"
    )

    :ok
  end

  @doc """
  The first truthy thing `check` returns, or a failure saying what never
  happened.

  For the handful of things a test cannot be handed synchronously: a beat
  running out, a verdict arriving, a view catching up.
  """
  def eventually(check, what \\ "the thing being waited for never happened") do
    deadline = System.monotonic_time(:millisecond) + 2_000

    keep_trying(check, what, deadline)
  end

  defp keep_trying(check, what, deadline) do
    cond do
      result = check.() ->
        result

      System.monotonic_time(:millisecond) > deadline ->
        raise what

      true ->
        Process.sleep(5)
        keep_trying(check, what, deadline)
    end
  end

  # Hands back the current value as well as putting it back afterwards, because
  # every caller wants both.
  defp restore(key) do
    previous = Application.fetch_env!(:meaning_game, key)
    ExUnit.Callbacks.on_exit(fn -> Application.put_env(:meaning_game, key, previous) end)

    previous
  end

  defp unique_slug, do: "test-#{System.unique_integer([:positive])}"
end
