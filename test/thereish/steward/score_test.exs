defmodule Thereish.Steward.ScoreTest do
  use Thereish.DataCase, async: false

  @moduletag :capture_log

  alias Thereish.Steward
  alias Thereish.Steward.Live
  alias Thereish.Steward.Fake
  alias Thereish.Steward.Music
  alias Thereish.Steward.TrackCache
  alias Thereish.Steward.Lyria

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

    test "score_failure builds failure provenance with provider and model" do
      meta = Steward.score_failure(:timeout)
      assert meta.cost_usd == 0.0
      assert meta.failure == "timeout"
      assert meta.provider == "fake"
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

      # Ensure the music API key is present in live config for test
      steward_cfg = Application.get_env(:thereish, :steward, [])
      roles = Keyword.get(steward_cfg, :roles, [])
      foley_cfg = Keyword.get(roles, :foley, [])
      jobs = Keyword.get(foley_cfg, :jobs, [])
      music_cfg = Keyword.get(jobs, :music, [])

      updated_music = Keyword.put(music_cfg, :api_key, "test-music-key")
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

      # No Req.Test.stub set up for the provider - a call would crash
      assert {:ok, track} = Live.score(@gives)
      assert track.path == "/media/tracks/already-cached.mp3"
      assert track.duration == 150
    end

    test "cache miss scores the Music prompt through the configured provider, writes to media dir, and caches" do
      test_pid = self()

      Req.Test.stub(Lyria, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:lyria_generate, conn.request_path, Jason.decode!(body)})

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            "candidates" => [
              %{
                "content" => %{
                  "parts" => [
                    %{
                      "inlineData" => %{
                        "mimeType" => "audio/mpeg",
                        "data" => Base.encode64(@fake_bytes)
                      }
                    }
                  ]
                }
              }
            ]
          })
        )
      end)

      fresh_gives = ["Kiss Heavy Metal", "bossa nova"]
      assert {:ok, track} = Live.score(fresh_gives)

      assert_receive {:lyria_generate, "/v1beta/models/lyria-3.5:generateContent", body}
      assert [%{"parts" => [%{"text" => prompt}]}] = body["contents"]
      assert String.starts_with?(prompt, Music.prompt(fresh_gives))

      assert String.starts_with?(track.path, "/media/tracks/")
      assert File.read!(TrackCache.disk_path(track.path)) == @fake_bytes
      assert track.meta.provider == "lyria"
      assert track.meta.model == "lyria-3.5"
      assert track.meta.cost_usd == 0.08

      assert {:ok, cached} = TrackCache.get(fresh_gives)
      assert cached.path == track.path
    end

    test "score_failure names the provider the way a landed track does" do
      steward_cfg = Application.get_env(:thereish, :steward)
      Application.put_env(:thereish, :steward, Keyword.put(steward_cfg, :adapter, Live))

      assert %{provider: "lyria", model: "lyria-3.5"} = Steward.score_failure(:timeout)
    end

    test "a quota refusal on miss is an error and caches nothing" do
      Req.Test.stub(Lyria, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(
          429,
          Jason.encode!(%{"error" => %{"status" => "RESOURCE_EXHAUSTED"}})
        )
      end)

      fresh_gives = ["stormy sea", "lighthouse"]
      assert {:error, {:http, 429, _}} = Live.score(fresh_gives)
      assert :miss = TrackCache.get(fresh_gives)
    end
  end
end
