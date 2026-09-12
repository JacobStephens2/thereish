defmodule Thereish.Steward.VampTest do
  use Thereish.DataCase, async: false

  @moduletag :capture_log

  alias Thereish.Steward
  alias Thereish.Steward.Fake
  alias Thereish.Steward.Live
  alias Thereish.Steward.ElevenLabs
  alias Thereish.Steward.TrackCache

  @gives ["summer camp", "viking beaches"]
  @fake_mp3 <<255, 251, 144, 100, 1, 2, 3, 4, 5, 6>>

  describe "Steward.vamp with Fake adapter" do
    test "answers a short looping instrumental with path, duration 30, format, loop: true, and meta" do
      assert {:ok, vamp} = Fake.vamp(@gives)
      assert is_binary(vamp.path)
      assert vamp.format == :mp3
      assert vamp.duration == 30
      assert vamp.loop == true
      assert vamp.meta.provider == "fake"
    end

    test "measures latency through Steward.vamp" do
      assert {:ok, vamp} = Steward.vamp(@gives)
      assert is_integer(vamp.meta.latency_ms)
      assert vamp.meta.latency_ms >= 0
    end

    test "respects fake dials" do
      fake_config = Application.get_env(:thereish, :steward, [])[:fake] || []

      Application.put_env(
        :thereish,
        :steward,
        Keyword.put(
          Application.get_env(:thereish, :steward, []),
          :fake,
          Keyword.put(fake_config, :vamp_mode, :unavailable)
        )
      )

      on_exit(fn ->
        Application.put_env(
          :thereish,
          :steward,
          Keyword.put(Application.get_env(:thereish, :steward, []), :fake, fake_config)
        )
      end)

      assert {:error, :vamp_unavailable} = Fake.vamp(@gives)
    end
  end

  describe "Steward.vamp with Live adapter" do
    setup do
      test_pid = self()

      test_dir =
        Path.join(
          System.tmp_dir!(),
          "vamp_test_media_#{System.unique_integer([:positive])}"
        )

      File.mkdir_p!(test_dir)
      Application.put_env(:thereish, :media_dir, test_dir)

      on_exit(fn ->
        Application.delete_env(:thereish, :media_dir)
        File.rm_rf!(test_dir)
      end)

      Req.Test.stub(ElevenLabs, fn conn ->
        case {conn.method, conn.request_path} do
          {"POST", "/v1/sound-generation"} ->
            {:ok, body, conn} = Plug.Conn.read_body(conn)
            decoded = Jason.decode!(body)
            send(test_pid, {:eleven_labs_generate_called, conn.req_headers, decoded})

            conn
            |> Plug.Conn.put_resp_header("content-type", "audio/mpeg")
            |> Plug.Conn.put_resp_header("character-cost", "120")
            |> Plug.Conn.send_resp(200, @fake_mp3)
        end
      end)

      :ok
    end

    test "generates thirty-second looping sound via ElevenLabs with vamp prefix plus gives and writes to disk" do
      role = [
        provider: Thereish.Steward.ElevenLabs,
        model: "eleven_text_to_sound_v2",
        format: "mp3_44100_128",
        timeout_ms: 30_000,
        api_key: "test-eleven-key"
      ]

      assert {:ok, vamp} = Live.vamp(@gives, role)

      assert vamp.duration == 30
      assert vamp.format == :mp3
      assert vamp.loop == true
      assert String.starts_with?(vamp.path, "/media/vamps/")

      # Verify the file was written to disk
      disk_path = TrackCache.disk_path(vamp.path)
      assert File.exists?(disk_path)
      assert File.read!(disk_path) == @fake_mp3

      # Verify ElevenLabs request parameters
      assert_receive {:eleven_labs_generate_called, headers, body}
      assert {"xi-api-key", "test-eleven-key"} in headers
      assert body["duration_seconds"] == 30.0 or body["duration_seconds"] == 30
      assert body["loop"] == true

      text = body["text"]
      assert text == Thereish.Steward.Music.vamp_prompt(@gives)
      refute String.contains?(text, "conversational")
      refute String.contains?(text, "spoken conversation")

      # Verify Vamp is never cached in TrackCache
      assert :miss = TrackCache.get(@gives)
    end
  end
end
