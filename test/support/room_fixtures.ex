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

  @doc "Opens a Room with a slug of its own, and returns the slug."
  def open_room(opts \\ []) do
    slug = Keyword.get_lazy(opts, :slug, &unique_slug/0)
    seat_limit = Keyword.get(opts, :seat_limit, Rooms.default_seat_limit())

    ExUnit.Callbacks.start_supervised!(
      Supervisor.child_spec({Server, slug: slug, seat_limit: seat_limit}, id: {Server, slug})
    )

    slug
  end

  @doc "A token standing in for one browser's."
  def device_token, do: "device-#{System.unique_integer([:positive])}"

  @doc """
  Turns the fake Assayer's dials for one test: `delay_ms` and `mode`.

  See `MeaningGame.Keeper.Fake` for what they do. Configuration is global, so a
  test that reaches for this cannot be async — which is true of every test that
  touches a Room anyway.
  """
  def keeper(opts) do
    keeper = restore(:keeper)
    fake = Keyword.merge(Keyword.fetch!(keeper, :fake), opts)

    Application.put_env(:meaning_game, :keeper, Keyword.put(keeper, :fake, fake))
  end

  @doc "The reveal beat for one test, in milliseconds."
  def beat(ms) do
    restore(:reveal_beat_ms)

    Application.put_env(:meaning_game, :reveal_beat_ms, ms)
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
