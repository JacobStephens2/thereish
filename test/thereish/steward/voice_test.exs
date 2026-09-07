defmodule Thereish.Steward.VoiceTest do
  use ExUnit.Case, async: false

  alias Thereish.Steward.ElevenLabs
  alias Thereish.Steward.Fake
  alias Thereish.Steward.Hume
  alias Thereish.Steward.Live

  @sample_mp3 Fake.mp3_fixture()

  setup do
    steward = Application.fetch_env!(:thereish, :steward)
    on_exit(fn -> Application.put_env(:thereish, :steward, steward) end)
    :ok
  end

  describe "ElevenLabs provider" do
    test "builds a request with v3 Conversational, MP3, audio tags, and reads character-cost header" do
      Req.Test.stub(ElevenLabs, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/v1/text-to-speech/test-voice-id"
        assert ["test-eleven-key"] = Plug.Conn.get_req_header(conn, "xi-api-key")
        assert conn.query_params["output_format"] =~ "mp3"

        {:ok, body, conn} = Plug.Conn.read_body(conn)
        json = Jason.decode!(body)
        assert json["text"] == "Close. [laughs] You both saw the beach."
        assert json["model_id"] == "eleven_v3_conversational"

        conn
        |> Plug.Conn.put_resp_header("content-type", "audio/mpeg")
        |> Plug.Conn.put_resp_header("character-cost", "40")
        |> Plug.Conn.resp(200, @sample_mp3)
      end)

      opts = [
        voice_id: "test-voice-id",
        api_key: "test-eleven-key",
        timeout_ms: 3_000
      ]

      assert {:ok, result} = ElevenLabs.speak("Close. [laughs] You both saw the beach.", opts)
      assert result.audio == @sample_mp3
      assert result.format == :mp3
      assert result.meta.provider == ElevenLabs
      assert result.meta.voice_id == "test-voice-id"
      assert result.meta.model == "eleven_v3_conversational"
      assert result.meta.characters == 40
      # 40 chars * 0.00010 = 0.0040
      assert_in_delta result.meta.cost_usd, 0.0040, 0.0001
    end

    test "parses an error response" do
      Req.Test.stub(ElevenLabs, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(401, Jason.encode!(%{"detail" => %{"message" => "invalid api key"}}))
      end)

      opts = [
        voice_id: "test-voice-id",
        api_key: "bad-key",
        timeout_ms: 3_000
      ]

      assert {:error, {:eleven_labs, 401, "invalid api key"}} = ElevenLabs.speak("Miss.", opts)
    end

    test "returns error when API key is missing" do
      assert {:error, :no_api_key} = ElevenLabs.speak("Miss.", voice_id: "voice", api_key: nil)
    end
  end

  describe "Hume provider" do
    test "builds an Octave 2 request, MP3 format, and decodes base64 audio" do
      Req.Test.stub(Hume, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/v0/tts"
        assert ["test-hume-key"] = Plug.Conn.get_req_header(conn, "x-hume-api-key")

        {:ok, body, conn} = Plug.Conn.read_body(conn)
        json = Jason.decode!(body)
        assert json["version"] == "2"
        assert json["format"]["type"] == "mp3"
        [utterance] = json["utterances"]
        assert utterance["text"] == "Miss. Completely different thoughts."
        assert utterance["voice"]["id"] == "test-hume-voice"

        resp_body = %{
          "generations" => [
            %{
              "audio" => Base.encode64(@sample_mp3),
              "duration" => 2.5,
              "file_size" => byte_size(@sample_mp3)
            }
          ]
        }

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!(resp_body))
      end)

      opts = [
        voice_id: "test-hume-voice",
        api_key: "test-hume-key",
        timeout_ms: 3_000
      ]

      line = "Miss. Completely different thoughts."
      assert {:ok, result} = Hume.speak(line, opts)
      assert result.audio == @sample_mp3
      assert result.format == :mp3
      assert result.meta.provider == Hume
      assert result.meta.voice_id == "test-hume-voice"
      assert result.meta.model == "octave-2"
      assert result.meta.characters == String.length(line)
      # String.length(line) is 36. 36 * 0.00015 = 0.0054
      assert_in_delta result.meta.cost_usd, 36 * 0.00015, 0.0001
    end

    test "parses a Hume error response" do
      Req.Test.stub(Hume, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(
          400,
          Jason.encode!(%{"error" => "Bad Request", "message" => "voice not found"})
        )
      end)

      opts = [voice_id: "bad-voice", api_key: "test-key"]
      assert {:error, {:hume, 400, "voice not found"}} = Hume.speak("Miss.", opts)
    end

    test "includes x-hume-secret-key header when secret key is provided" do
      Req.Test.stub(Hume, fn conn ->
        assert ["test-hume-key"] = Plug.Conn.get_req_header(conn, "x-hume-api-key")
        assert ["test-secret-key"] = Plug.Conn.get_req_header(conn, "x-hume-secret-key")

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{
            "generations" => [
              %{"audio" => Base.encode64(@sample_mp3)}
            ]
          })
        )
      end)

      opts = [
        voice_id: "voice",
        api_key: "test-hume-key",
        secret_key: "test-secret-key"
      ]

      assert {:ok, result} = Hume.speak("Miss.", opts)
      assert result.audio == @sample_mp3
    end

    test "returns error when Hume API key is missing" do
      assert {:error, :no_api_key} = Hume.speak("Miss.", voice_id: "voice", api_key: nil)
    end
  end

  describe "Live steward voice integration" do
    test "Live.speak delegates to the configured provider in voice job" do
      Req.Test.stub(ElevenLabs, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "audio/mpeg")
        |> Plug.Conn.put_resp_header("character-cost", "25")
        |> Plug.Conn.resp(200, @sample_mp3)
      end)

      steward = Application.fetch_env!(:thereish, :steward)

      updated_roles =
        Keyword.put(steward[:roles] || [], :foley,
          jobs: [
            voice: [
              provider: ElevenLabs,
              voice_id: "test-voice",
              api_key: "test-key",
              timeout_ms: 3_000
            ]
          ]
        )

      Application.put_env(:thereish, :steward, Keyword.put(steward, :roles, updated_roles))

      assert {:ok, result} = Live.speak("Meld. Two minds at once.")
      assert result.audio == @sample_mp3
      assert result.format == :mp3
      assert result.meta.provider == ElevenLabs
    end

    test "Live.speak delegates to Hume as configured winner" do
      Req.Test.stub(Hume, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{
            "generations" => [
              %{"audio" => Base.encode64(@sample_mp3)}
            ]
          })
        )
      end)

      steward = Application.fetch_env!(:thereish, :steward)

      updated_roles =
        Keyword.put(steward[:roles] || [], :foley,
          hume_api_key: "test-hume-key",
          jobs: [
            voice: [
              provider: Hume,
              voice_id: "44cb3a51-07b4-4934-83fd-9d9e8d363ce6",
              timeout_ms: 3_000
            ]
          ]
        )

      Application.put_env(:thereish, :steward, Keyword.put(steward, :roles, updated_roles))

      assert {:ok, result} = Live.speak("Meld. Two minds at once.")
      assert result.audio == @sample_mp3
      assert result.format == :mp3
      assert result.meta.provider == Hume
    end
  end
end
