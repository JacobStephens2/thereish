defmodule Thereish.Steward.ScoreTest do
  use Thereish.DataCase, async: false

  @moduletag :capture_log

  alias Thereish.Steward
  alias Thereish.Steward.Live
  alias Thereish.Steward.Fake
  alias Thereish.Steward.TrackCache
  alias Thereish.Steward.Mureka

  @gives ["summer camp", "viking beaches"]
  @fake_bytes <<255, 251, 144, 100, 11, 22, 33>>

  describe "Steward.score with Fake adapter" do
    test "answers a track with path, duration, format and meta" do
      assert {:ok, track} = Fake.score(@gives)
      assert is_binary(track.path)
      assert track.format == :mp3
      assert track.meta.provider == "fake"
    end

    test "measures latency through Steward.score" do
      assert {:ok, track} = Steward.score(@gives)
      assert is_integer(track.meta.latency_ms)
      assert track.meta.latency_ms >= 0
    end

    test "respects fake dials" do
      fake_config = Application.get_env(:thereish, :steward, [])[:fake] || []

      Application.put_env(
        :thereish,
        :steward,
        Keyword.put(
          Application.get_env(:thereish, :steward, []),
          :fake,
          Keyword.put(fake_config, :music_mode, :unavailable)
        )
      )

      on_exit(fn ->
        Application.put_env(
          :thereish,
          :steward,
          Keyword.put(Application.get_env(:thereish, :steward, []), :fake, fake_config)
        )
      end)

      assert {:error, :music_unavailable} = Fake.score(@gives)
    end

    test "music_mode: :stream calls on_playable callback with stream track, then returns final track" do
      fake_config = Application.get_env(:thereish, :steward, [])[:fake] || []

      Application.put_env(
        :thereish,
        :steward,
        Keyword.put(
          Application.get_env(:thereish, :steward, []),
          :fake,
          Keyword.merge(fake_config, music_mode: :stream)
        )
      )

      on_exit(fn ->
        Application.put_env(
          :thereish,
          :steward,
          Keyword.put(Application.get_env(:thereish, :steward, []), :fake, fake_config)
        )
      end)

      test_pid = self()
      on_playable = fn track -> send(test_pid, {:playable_received, track}) end

      assert {:ok, final_track} = Fake.score(@gives, on_playable: on_playable)
      assert final_track.format == :mp3
      assert String.ends_with?(final_track.path, ".mp3")

      assert_receive {:playable_received, stream_track}
      assert stream_track.format == :aac
      assert stream_track.stream == true
      assert String.starts_with?(stream_track.path, "https://stream.mureka.ai/live/fake-")
    end

    test "music_mode: :stream with music_fail_after_stream: true calls on_playable and fails" do
      fake_config = Application.get_env(:thereish, :steward, [])[:fake] || []

      Application.put_env(
        :thereish,
        :steward,
        Keyword.put(
          Application.get_env(:thereish, :steward, []),
          :fake,
          Keyword.merge(fake_config, music_mode: :stream, music_fail_after_stream: true)
        )
      )

      on_exit(fn ->
        Application.put_env(
          :thereish,
          :steward,
          Keyword.put(Application.get_env(:thereish, :steward, []), :fake, fake_config)
        )
      end)

      test_pid = self()
      on_playable = fn track -> send(test_pid, {:playable_received, track}) end

      assert {:error, :stream_generation_failed} = Fake.score(@gives, on_playable: on_playable)
      assert_receive {:playable_received, stream_track}
      assert stream_track.stream == true
    end

    test "score_failure builds failure provenance with provider and model" do
      meta = Steward.score_failure(:timeout)
      assert meta.cost_usd == 0.0
      assert meta.failure == "timeout"
      assert meta.provider in ["fake", "mureka"]
      assert is_binary(meta.model)
    end

    test "score_failure handles non-binary and tuple failure reasons safely" do
      meta = Steward.score_failure({:http, 429, "rate limit"})
      assert meta.failure == "{:http, 429, \"rate limit\"}"

      meta_str = Steward.score_failure("upstream error")
      assert meta_str.failure == "upstream error"
    end
  end

  describe "Steward.Live.score" do
    setup do
      test_dir = Path.join(System.tmp_dir!(), "score_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(test_dir)
      Application.put_env(:thereish, :media_dir, test_dir)

      # Ensure Mureka API key is present in live config for test
      steward_cfg = Application.get_env(:thereish, :steward, [])
      roles = Keyword.get(steward_cfg, :roles, [])
      foley_cfg = Keyword.get(roles, :foley, [])
      jobs = Keyword.get(foley_cfg, :jobs, [])
      music_cfg = Keyword.get(jobs, :music, [])

      updated_music = Keyword.put(music_cfg, :api_key, "test-mureka-key")
      updated_jobs = Keyword.put(jobs, :music, updated_music)
      updated_foley = Keyword.put(foley_cfg, :jobs, updated_jobs)
      updated_roles = Keyword.put(roles, :foley, updated_foley)

      Application.put_env(
        :thereish,
        :steward,
        Keyword.put(steward_cfg, :roles, updated_roles)
      )

      on_exit(fn ->
        File.rm_rf(test_dir)
        Application.delete_env(:thereish, :media_dir)
        Application.put_env(:thereish, :steward, steward_cfg)
      end)

      :ok
    end

    test "cache hit answers without a provider call" do
      cached_path = "/media/tracks/already-cached.mp3"
      file_path = TrackCache.disk_path(cached_path)
      File.mkdir_p!(Path.dirname(file_path))
      File.write!(file_path, "audio-bytes")

      TrackCache.put(@gives, %{
        path: cached_path,
        duration: 150,
        format: :mp3,
        meta: %{"provider" => "mureka", "cost_usd" => 0.04}
      })

      # No Req.Test.stub set up for Mureka - if it calls Mureka, it will crash
      assert {:ok, track} = Live.score(@gives)
      assert track.path == "/media/tracks/already-cached.mp3"
      assert track.duration == 150
    end

    test "cache miss calls Mureka with house prefix, n: 1, downloads to media dir, and caches" do
      test_pid = self()

      Req.Test.stub(Mureka, fn conn ->
        case {conn.method, conn.request_path} do
          {"POST", "/v1/instrumental/generate"} ->
            {:ok, body, conn} = Plug.Conn.read_body(conn)
            decoded = Jason.decode!(body)
            send(test_pid, {:mureka_generate, decoded})

            conn
            |> Plug.Conn.put_resp_header("content-type", "application/json")
            |> Plug.Conn.send_resp(200, Jason.encode!(%{"id" => "task_scored_123"}))

          {"GET", "/v1/instrumental/query/task_scored_123"} ->
            conn
            |> Plug.Conn.put_resp_header("content-type", "application/json")
            |> Plug.Conn.send_resp(
              200,
              Jason.encode!(%{
                "id" => "task_scored_123",
                "status" => "succeeded",
                "choices" => [%{"url" => "https://cdn.mureka.ai/audio/score.mp3"}]
              })
            )

          {"GET", "/audio/score.mp3"} ->
            conn
            |> Plug.Conn.put_resp_header("content-type", "audio/mpeg")
            |> Plug.Conn.send_resp(200, @fake_bytes)
        end
      end)

      fresh_gives = ["alpine meadow", "deep space"]
      assert {:ok, track} = Live.score(fresh_gives)

      assert_receive {:mureka_generate, body}
      assert body["n"] == 1
      assert body["prompt"] =~ "conversation"
      assert body["prompt"] =~ "alpine meadow"
      assert body["prompt"] =~ "deep space"

      assert String.starts_with?(track.path, "/media/tracks/")
      assert track.meta.cost_usd == 0.04

      # Verify cached
      assert {:ok, cached} = TrackCache.get(fresh_gives)
      assert cached.path == track.path
    end

    test "handles provider error on miss" do
      Req.Test.stub(Mureka, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(500, Jason.encode!(%{"error" => "internal error"}))
      end)

      fresh_gives = ["stormy sea", "lighthouse"]
      assert {:error, _} = Live.score(fresh_gives)
    end

    test "cache miss invokes on_playable callback when Mureka stream_url arrives, then caches final MP3" do
      poll_count = Agent.start_link(fn -> 0 end) |> elem(1)
      test_pid = self()

      Req.Test.stub(Mureka, fn conn ->
        case {conn.method, conn.request_path} do
          {"POST", "/v1/instrumental/generate"} ->
            conn
            |> Plug.Conn.put_resp_header("content-type", "application/json")
            |> Plug.Conn.send_resp(200, Jason.encode!(%{"id" => "task_live_stream_1"}))

          {"GET", "/v1/instrumental/query/task_live_stream_1"} ->
            step = Agent.get_and_update(poll_count, &{&1 + 1, &1 + 1})

            response_data =
              case step do
                1 ->
                  %{
                    "id" => "task_live_stream_1",
                    "status" => "streaming",
                    "stream_url" => "https://stream.mureka.ai/live/live1.aac",
                    "choices" => [%{"stream_url" => "https://stream.mureka.ai/live/live1.aac"}]
                  }

                _ ->
                  %{
                    "id" => "task_live_stream_1",
                    "status" => "succeeded",
                    "choices" => [%{"url" => "https://cdn.mureka.ai/audio/live1_final.mp3"}]
                  }
              end

            conn
            |> Plug.Conn.put_resp_header("content-type", "application/json")
            |> Plug.Conn.send_resp(200, Jason.encode!(response_data))

          {"GET", "/audio/live1_final.mp3"} ->
            conn
            |> Plug.Conn.put_resp_header("content-type", "audio/mpeg")
            |> Plug.Conn.send_resp(200, @fake_bytes)
        end
      end)

      gives = ["crystal cave", "ancient flute"]
      on_playable = fn playable -> send(test_pid, {:playable_received, playable}) end

      assert {:ok, track} = Live.score(gives, on_playable: on_playable)
      assert String.starts_with?(track.path, "/media/tracks/")
      assert track.format == :mp3

      assert_receive {:playable_received, playable}
      assert playable.path == "https://stream.mureka.ai/live/live1.aac"
      assert playable.format == :aac
      assert playable.stream == true

      # Verified final file cached
      assert {:ok, cached} = TrackCache.get(gives)
      assert cached.path == track.path
    end
  end
end
