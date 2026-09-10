defmodule Thereish.Foley.ScoreQueueTest do
  use Thereish.DataCase, async: false

  @moduletag :capture_log

  alias Thereish.Foley.ScoreQueue

  setup do
    ScoreQueue.reset()
    :ok
  end

  test "enqueues a score request and delivers {:scored, page_ref, result} to the room" do
    page_ref = make_ref()
    gives = ["river", "stone"]

    assert :ok = ScoreQueue.enqueue(self(), page_ref, gives)

    assert_receive {:scored, ^page_ref, {:ok, track}}, 1_000
    assert is_binary(track.path)
  end

  test "runs score requests one at a time sequentially" do
    fake_config = Application.get_env(:thereish, :steward, [])[:fake] || []

    Application.put_env(
      :thereish,
      :steward,
      Keyword.put(
        Application.get_env(:thereish, :steward, []),
        :fake,
        Keyword.merge(fake_config, music_delay_ms: 100)
      )
    )

    on_exit(fn ->
      Application.put_env(
        :thereish,
        :steward,
        Keyword.put(Application.get_env(:thereish, :steward, []), :fake, fake_config)
      )
    end)

    page_ref1 = make_ref()
    page_ref2 = make_ref()

    ScoreQueue.enqueue(self(), page_ref1, ["first", "score"])
    ScoreQueue.enqueue(self(), page_ref2, ["second", "score"])

    # First score completes
    assert_receive {:scored, ^page_ref1, {:ok, _track1}}, 500
    # Second score has NOT completed yet at this exact moment
    refute_received {:scored, ^page_ref2, _}

    # Second score completes after its own delay
    assert_receive {:scored, ^page_ref2, {:ok, _track2}}, 500
  end

  test "a Page has at most one score in flight (duplicate enqueue is ignored)" do
    fake_config = Application.get_env(:thereish, :steward, [])[:fake] || []

    Application.put_env(
      :thereish,
      :steward,
      Keyword.put(
        Application.get_env(:thereish, :steward, []),
        :fake,
        Keyword.merge(fake_config, music_delay_ms: 100)
      )
    )

    on_exit(fn ->
      Application.put_env(
        :thereish,
        :steward,
        Keyword.put(Application.get_env(:thereish, :steward, []), :fake, fake_config)
      )
    end)

    page_ref = make_ref()

    assert :ok = ScoreQueue.enqueue(self(), page_ref, ["summer", "camp"])
    assert :ok = ScoreQueue.enqueue(self(), page_ref, ["summer", "camp"])

    assert_receive {:scored, ^page_ref, {:ok, _track}}, 500
    # Must not receive a second message for the same page_ref
    refute_receive {:scored, ^page_ref, _}, 300
  end

  test "when a score fails, delivers error to room and proceeds with next queued job" do
    fake_config = Application.get_env(:thereish, :steward, [])[:fake] || []

    Application.put_env(
      :thereish,
      :steward,
      Keyword.put(
        Application.get_env(:thereish, :steward, []),
        :fake,
        Keyword.merge(fake_config, music_mode: :unavailable)
      )
    )

    page_ref1 = make_ref()
    page_ref2 = make_ref()

    ScoreQueue.enqueue(self(), page_ref1, ["failing", "gives"])

    assert_receive {:scored, ^page_ref1, {:error, :music_unavailable}}, 1_000

    # Reset fake to ok so next job can succeed
    Application.put_env(
      :thereish,
      :steward,
      Keyword.put(Application.get_env(:thereish, :steward, []), :fake, fake_config)
    )

    ScoreQueue.enqueue(self(), page_ref2, ["working", "gives"])
    assert_receive {:scored, ^page_ref2, {:ok, _track}}, 1_000
  end

  test "prunes queued score jobs when a room process exits" do
    fake_config = Application.get_env(:thereish, :steward, [])[:fake] || []

    Application.put_env(
      :thereish,
      :steward,
      Keyword.put(
        Application.get_env(:thereish, :steward, []),
        :fake,
        Keyword.merge(fake_config, music_delay_ms: 100)
      )
    )

    on_exit(fn ->
      Application.put_env(
        :thereish,
        :steward,
        Keyword.put(Application.get_env(:thereish, :steward, []), :fake, fake_config)
      )
    end)

    # Job 1 in flight with self()
    job1_ref = make_ref()
    ScoreQueue.enqueue(self(), job1_ref, ["first", "job"])

    # Dead room enqueued behind Job 1
    dead_room = spawn(fn -> receive do: (_ -> :ok) end)
    ScoreQueue.enqueue(dead_room, make_ref(), ["dead", "room"])
    # Kill dead_room while it waits in queue
    Process.exit(dead_room, :kill)

    # Job 3 enqueued behind dead room
    job3_ref = make_ref()
    ScoreQueue.enqueue(self(), job3_ref, ["third", "job"])

    # First job completes
    assert_receive {:scored, ^job1_ref, {:ok, _track}}, 500

    # Third job runs immediately after job 1 completes, because dead_room was pruned
    assert_receive {:scored, ^job3_ref, {:ok, _track}}, 500
  end
end
